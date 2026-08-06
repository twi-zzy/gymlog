import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gymlog/core/services/exercise_media_cache_manager.dart';

/// Bounded concurrency semaphore to limit concurrent cache-fetch and decode.
class _SimpleSemaphore {
  final int maxConcurrency;
  int _activeCount = 0;
  final List<Completer<void>> _queue = [];

  _SimpleSemaphore(this.maxConcurrency);

  Future<void> acquire() async {
    if (_activeCount < maxConcurrency) {
      _activeCount++;
      return;
    }
    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      next.complete();
    } else {
      _activeCount--;
    }
  }
}

// Two, not four: four concurrent whole-file fetch+decode jobs contended
// with the 16.6ms frame budget during a fling — the scroll jitter was felt,
// not imagined (ship-readiness #1). Two keeps fetch and decode overlapped
// without saturating the UI isolate.
final _gifConcurrencySemaphore = _SimpleSemaphore(2);

/// Thumbnail decode width cap. Thumbnails are 44–52 dp, so decoding at 2×
/// logical pixels (104px on a 2× device) is plenty — keeps RAM low and decode
/// fast. Full-res decodes are used for the hero/detail view.
const kGifThumbnailDecodeWidth = 128;

/// Maximum number of decoded frames held in memory at once.
///
/// Why a ceiling exists at all: these frames are handed to [RawImage], which
/// paints a `ui.Image` directly and therefore **bypasses Flutter's
/// `ImageCache` entirely**. `imageCacheSize` / `imageCacheMaxBytes` do not see
/// them and cannot bound them. Without an explicit cap, scrolling the ~400
/// entry exercise library retains one decoded frame per exercise touched.
///
/// The arithmetic behind 48: list thumbnails decode at
/// [kGifThumbnailDecodeWidth] (128 px) and these GIFs are roughly square, so
/// one thumbnail costs about 128 * 128 * 4 B = 64 KB — 48 of them is ~3 MB.
/// The detail-screen poster decodes at native resolution; at a 480 px source
/// that is ~920 KB, so the pathological all-poster case lands near 15 MB. A
/// realistic mix sits far below that, and the working set of a scrolling list
/// is a screenful plus prefetch, which is well under 48.
///
/// BLOCKED ON ARTIFACT: this number is derived, not measured. Confirming it
/// needs a DevTools memory profile of a full Exercise Library scroll on a real
/// device. It is a bound where previously there was none, not a tuned value.
const int kMaxDecodedFrameCacheEntries = 48;

class _FrameCacheEntry {
  _FrameCacheEntry(this.image);

  final ui.Image image;

  /// Number of live providers currently handing this image to widgets.
  /// An entry with leases > 0 is on screen (or within its keepAlive window)
  /// and must never be disposed.
  int leases = 0;
}

/// The single owner of every decoded GIF frame in the app.
///
/// The rule this class exists to enforce (B19-F1): **whatever hands a
/// `ui.Image` to a widget must not also dispose it.** Previously each provider
/// disposed the very image it had returned, so a `RawImage` could be asked to
/// paint a disposed handle — reachable in practice through the tap-to-retry
/// `ref.invalidate(...)` in `ExerciseThumbnail`, which disposes the old
/// provider synchronously mid-frame.
///
/// Here, providers only ever *borrow*:
///  - [acquire] / [put] take a lease for the lifetime of the provider,
///  - [release] gives the lease back and **never disposes anything**; it only
///    makes the entry eligible for eviction,
///  - eviction is LRU and skips leased entries, so disposal can only happen
///    once nothing is watching the image.
class _DecodedFrameCache {
  _DecodedFrameCache._();

  static final _DecodedFrameCache instance = _DecodedFrameCache._();

  /// Insertion-ordered: first key is least-recently-used.
  final LinkedHashMap<String, _FrameCacheEntry> _entries =
      LinkedHashMap<String, _FrameCacheEntry>();

  /// Returns a cached frame and takes a lease on it, or null on a miss.
  ui.Image? acquire(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry; // re-insert at the MRU end
    entry.leases++;
    return entry.image;
  }

  /// Stores a freshly decoded [image] under [key], takes a lease, and returns
  /// the image the caller should actually use.
  ///
  /// If a concurrent decode of the same key already landed, the incumbent wins
  /// and [image] is disposed here — disposing the loser is safe precisely
  /// because it has not been handed to a widget yet, which is the distinction
  /// this whole class is about.
  ui.Image put(String key, ui.Image image) {
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing;
      existing.leases++;
      image.dispose();
      return existing.image;
    }
    _entries[key] = _FrameCacheEntry(image)..leases = 1;
    _evictIfNeeded();
    return image;
  }

  /// Gives back a lease. Deliberately does not dispose: the widget that was
  /// painting this image may still be doing so for the remainder of the frame.
  void release(String key) {
    final entry = _entries[key];
    if (entry == null) return;
    if (entry.leases > 0) entry.leases--;
    _evictIfNeeded();
  }

  void _evictIfNeeded() {
    if (_entries.length <= kMaxDecodedFrameCacheEntries) return;
    // Oldest first; skip anything still leased.
    for (final key in _entries.keys.toList(growable: false)) {
      if (_entries.length <= kMaxDecodedFrameCacheEntries) break;
      final entry = _entries[key];
      if (entry == null || entry.leases > 0) continue;
      _entries.remove(key);
      entry.image.dispose();
    }
    // If every entry is leased the cache is allowed to exceed its ceiling
    // rather than dispose an image that is on screen. That can only happen
    // when more than kMaxDecodedFrameCacheEntries frames are genuinely being
    // displayed at once, which no layout in this app produces.
  }

  @visibleForTesting
  int get debugLength => _entries.length;

  @visibleForTesting
  int debugLeaseCount(String key) => _entries[key]?.leases ?? 0;
}

/// Keeps the provider alive for 60 s after its last subscriber detaches.
/// IMPORTANT: call this eagerly (before any awaits) so the provider is never
/// auto-disposed mid-decode. Without eager keepAlive, the provider is
/// cancelled the moment a list thumbnail scrolls off-screen, which means
/// `isDisposed` becomes true inside the frame-loop and the provider returns
/// null — giving a fallback icon even though the GIF downloaded fine.
void _keepAliveEager(Ref ref) {
  final link = ref.keepAlive();
  Timer? releaseTimer;
  ref.onDispose(() => releaseTimer?.cancel());
  ref.onCancel(
      () => releaseTimer = Timer(const Duration(seconds: 60), link.close));
  ref.onResume(() => releaseTimer?.cancel());
}

/// Shared implementation behind [gifLastFrameProvider] and
/// [gifFirstFrameProvider].
///
/// These were previously two near-identical copies of a subtle lifetime
/// protocol (eager keepAlive → semaphore → cache fetch → decode → dispose
/// bookkeeping). One copy is enough: the protocol is the risky part, and two
/// copies of it drift.
Future<ui.Image?> _decodeFrame({
  required Ref ref,
  required String url,
  required int? targetWidth,
  required bool lastFrame,
}) async {
  // Must happen BEFORE the first await so that Riverpod never auto-disposes
  // this provider while it is still downloading / decoding.
  _keepAliveEager(ref);

  final String cacheKey =
      '${lastFrame ? 'last' : 'first'}|${targetWidth ?? 'full'}|$url';

  bool isDisposed = false;
  bool holdsLease = false;

  // Single dispose hook, registered before any await. It releases the lease
  // (which never disposes the image) instead of disposing the image directly —
  // that inversion is the whole of B19-F1.
  ref.onDispose(() {
    isDisposed = true;
    if (holdsLease) {
      holdsLease = false;
      _DecodedFrameCache.instance.release(cacheKey);
    }
  });

  final ui.Image? alreadyDecoded =
      _DecodedFrameCache.instance.acquire(cacheKey);
  if (alreadyDecoded != null) {
    holdsLease = true;
    if (isDisposed) {
      holdsLease = false;
      _DecodedFrameCache.instance.release(cacheKey);
      return null;
    }
    return alreadyDecoded;
  }

  await _gifConcurrencySemaphore.acquire();
  ui.Codec? codec;
  ui.Image? frame;

  try {
    if (isDisposed) return null;

    final cacheInfo = await ExerciseMediaCacheManager().getFileFromCache(url);
    final File file;
    if (cacheInfo != null) {
      file = cacheInfo.file;
    } else {
      file = await ExerciseMediaCacheManager()
          .getSingleFile(url)
          .timeout(const Duration(seconds: 12));
    }
    if (isDisposed) return null;

    final Uint8List bytes = await file.readAsBytes();
    if (isDisposed) return null;

    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      allowUpscaling: false,
    );
    if (isDisposed) return null;

    if (codec.frameCount == 0) return null;

    if (lastFrame) {
      for (int i = 0; i < codec.frameCount; i++) {
        // Intermediate frames were never handed to a widget, so disposing them
        // here is safe and necessary.
        frame?.dispose();
        if (isDisposed) return null;
        final ui.FrameInfo frameInfo = await codec.getNextFrame();
        frame = frameInfo.image;
      }
    } else {
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      frame = frameInfo.image;
    }

    final ui.Image? decoded = frame;
    if (decoded == null) return null;

    if (isDisposed) {
      decoded.dispose();
      return null;
    }

    // Hand ownership to the cache and keep only a lease. From here on this
    // function must not dispose the image under any circumstances.
    final ui.Image owned = _DecodedFrameCache.instance.put(cacheKey, decoded);
    holdsLease = true;

    if (isDisposed) {
      holdsLease = false;
      _DecodedFrameCache.instance.release(cacheKey);
      return null;
    }

    return owned;
  } catch (e, st) {
    debugPrint(
      '[gifFrameProvider] Failed to extract ${lastFrame ? 'last' : 'first'} frame.\n'
      '  URL  : $url\n'
      '  Error: $e\n$st',
    );
    if (!holdsLease) {
      // Only safe to dispose while the frame is still private to this decode.
      frame?.dispose();
    }
    return null;
  } finally {
    codec?.dispose();
    _gifConcurrencySemaphore.release();
  }
}

/// Decodes the LAST frame of the GIF at [gifUrl] as a static [ui.Image].
///
/// [targetWidth] caps the decode resolution. Pass [kGifThumbnailDecodeWidth]
/// for list thumbnails, or `null` for full-resolution decodes (e.g. the hero
/// poster on the detail screen).
///
/// The returned image is **borrowed, not owned** — it belongs to the shared
/// bounded frame cache. Do not dispose it.
final gifLastFrameProvider = FutureProvider.autoDispose
    .family<ui.Image?, ({String url, int? targetWidth})>(
  (ref, args) => _decodeFrame(
    ref: ref,
    url: args.url,
    targetWidth: args.targetWidth,
    lastFrame: true,
  ),
);

/// Decodes the FIRST frame of the GIF at [gifUrl] as a static [ui.Image].
/// Cheaper than [gifLastFrameProvider] — only reads one frame.
///
/// The returned image is **borrowed, not owned** — it belongs to the shared
/// bounded frame cache. Do not dispose it.
final gifFirstFrameProvider = FutureProvider.autoDispose
    .family<ui.Image?, ({String url, int? targetWidth})>(
  (ref, args) => _decodeFrame(
    ref: ref,
    url: args.url,
    targetWidth: args.targetWidth,
    lastFrame: false,
  ),
);
