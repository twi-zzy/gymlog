import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gymlog/core/services/exercise_media_cache_manager.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/theme/app_text.dart';
import 'package:gymlog/shared/providers/gif_last_frame_provider.dart';
import 'package:gymlog/shared/widgets/ui/skeleton.dart';

class ExerciseGifWidget extends StatelessWidget {
  final String? gifUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final bool animate;

  /// What a screen reader should call this animation. Optional and added last
  /// so no existing call site changes; when null the generic label is used.
  final String? semanticLabel;

  const ExerciseGifWidget({
    super.key,
    required this.gifUrl,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.thumbnail)),
    this.animate = true,
    this.semanticLabel,
  });

  String get _label => semanticLabel ?? 'Exercise demonstration';

  @override
  Widget build(BuildContext context) {
    if (gifUrl == null || gifUrl!.isEmpty) {
      // No media in the catalog for this exercise. Permanent, not a failure.
      return _buildFallback(failed: false);
    }

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shouldAnimate = animate && !reduceMotion;

    // Decode at the exact device-pixel size the widget paints at — never
    // logicalWidth*2 and never the 512px blanket fallback. A 512px animated
    // GIF decodes EVERY frame at 512² on the UI isolate; a 44dp thumbnail on
    // a 3× device needs 132 (ship-readiness #1).
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth =
        width != null && width! > 0 ? (width! * dpr).round() : 512;

    // Scroll-aware decode gate (P2 deferred item, now landed): while a
    // surrounding Scrollable is flinging hard enough that Flutter itself
    // recommends deferred loading, hold the skeleton and do not start a
    // new fetch/decode. No device-tuned constants — uses the framework
    // signal directly. When the fling settles the next build resumes.
    final deferDecode =
        Scrollable.recommendDeferredLoadingForContext(context);
    if (deferDecode) {
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: borderRadius,
          child: _buildPlaceholder(),
        ),
      );
    }

    if (shouldAnimate) {
      // RepaintBoundary: an animating GIF repaints every frame — it must not
      // dirty its ancestors' layers with it.
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: borderRadius,
          child: CachedNetworkImage(
            cacheManager: ExerciseMediaCacheManager(),
            imageUrl: gifUrl!,
            width: width,
            height: height,
            fit: fit,
            memCacheWidth: decodeWidth,
            imageBuilder: (context, imageProvider) => Semantics(
              image: true,
              label: _label,
              // Fade the arrival — a hard spinner→image pop reads as "slow"
              // even when the decode was fast.
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                builder: (context, t, child) =>
                    Opacity(opacity: t, child: child),
                child: Image(
                  image: imageProvider,
                  width: width,
                  height: height,
                  fit: fit,
                ),
              ),
            ),
            placeholder: (context, url) => _buildPlaceholder(),
            errorWidget: (context, url, error) {
              debugPrint(
                '[ExerciseGifWidget] Failed to load GIF.\n'
                '  URL  : $url\n'
                '  Error: $error',
              );
              return _buildFallback(failed: true);
            },
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: Consumer(
        builder: (context, ref, child) {
          // FIRST frame, not last: the last-frame path looped
          // codec.getNextFrame() over EVERY frame to reach the end — a
          // 40-frame GIF cost 40 decodes to show one image. The first frame
          // is the start-position pose (semantically the better thumbnail)
          // and costs exactly one decode (ship-readiness #1).
          final frameAsync = ref.watch(gifFirstFrameProvider((
            url: gifUrl!,
            targetWidth: decodeWidth,
          )));

          return ClipRRect(
            borderRadius: borderRadius,
            child: frameAsync.when(
              loading: () => _buildPlaceholder(),
              error: (_, __) => _buildFallback(failed: true),
              data: (img) {
                // A null frame means the fetch or decode gave up — that is a
                // failure, not an exercise without media (B19-F4).
                if (img == null) return _buildFallback(failed: true);
                return Semantics(
                  image: true,
                  label: _label,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    builder: (context, t, child) =>
                        Opacity(opacity: t, child: child),
                    child: RawImage(
                      // Borrowed from the shared bounded frame cache; never
                      // disposed here (see gif_last_frame_provider).
                      image: img,
                      width: width,
                      height: height,
                      fit: fit,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder() {
    final w = width;
    final h = height;
    // Skeleton at the EXACT final size: no spinner, zero layout shift when
    // the frame arrives (the old bare CircularProgressIndicator on bgSurface
    // hard-popped into the image).
    if (w != null && h != null) {
      return Semantics(
        label: 'Loading exercise demonstration',
        child: ExcludeSemantics(
          child: SkeletonPulse(
            label: 'Loading exercise demonstration',
            child: SkeletonBox(
              width: w,
              height: h,
              radius: borderRadius.topLeft.x,
            ),
          ),
        ),
      );
    }
    // Intrinsic-size contexts (hero/detail): no exact skeleton possible —
    // hold the quiet surface so arrival is still shift-free.
    return Semantics(
      label: 'Loading exercise demonstration',
      child: ExcludeSemantics(
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: borderRadius,
          ),
        ),
      ),
    );
  }

  /// [failed] false = this exercise has no animation at all (nothing is wrong).
  /// [failed] true  = an animation exists but could not be fetched or decoded.
  /// These used to render identically, which left the user unable to tell a
  /// gap in the catalog from a dropped network request.
  Widget _buildFallback({required bool failed}) {
    return Semantics(
      label: failed
          ? 'Exercise demonstration could not be loaded'
          : 'No demonstration available for this exercise',
      child: ExcludeSemantics(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: borderRadius,
          ),
          child: Center(
            child: Icon(
              failed
                  ? Icons.broken_image_rounded
                  : Icons.fitness_center_rounded,
              color: AppColors.textSecondary,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}
