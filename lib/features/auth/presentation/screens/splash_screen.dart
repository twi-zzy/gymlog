import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/services/profile_sync_service.dart';
import '../../../../core/services/sync_engine.dart';
import '../providers/auth_provider.dart';

/// [splash_screen.dart]
/// Purpose: ~1-second brand screen. Resolves auth state + profile existence to
/// decide the initial route: /auth → /onboarding → /
///
/// Copper Void (Commit 8): warm-white wordmark + a single copper ember that
/// breathes beneath it. No spinner, no "Loading…" — the pulse implies life.
/// Respects reduce-motion (a static mark with one slow opacity fade instead).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _motionResolved = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _resolveInitialRoute();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is available here; decide the motion behavior exactly once.
    if (_motionResolved) return;
    _motionResolved = true;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _pulse.animateTo(1.0); // a single, slow fade-in (eased in the builder)
    } else {
      _pulse.repeat(reverse: true); // gentle breathing
    }
  }

  Future<void> _resolveInitialRoute() async {
    // Brand pause, not a toll booth — long enough to register, short enough to
    // never feel like loading.
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    final user = ref.read(authProvider);

    // Not logged in → auth screen.
    if (user == null) {
      context.go('/auth');
      return;
    }

    // Start the sync engine for this session, then restore cloud data and
    // snapshot preferences — all non-blocking; navigation never waits on it.
    final engine = ref.read(syncEngineProvider);
    engine.startAutoSync(user.id);
    engine.startConnectivityWatch(user.id);
    unawaited(engine.pull(user.id));
    unawaited(engine.loadLastSynced());
    unawaited(engine.enqueuePreferences(user.id));

    // Make the backend authoritative: fetch the stored profile and hydrate
    // local, or fall back to local if offline. First-ever users go to welcome.
    final resolution = await ref.read(profileSyncProvider).resolveOnLogin(
          userId: user.id,
          email: user.email ?? '',
        );

    if (!mounted) return;

    if (resolution == ProfileResolution.needsOnboarding) {
      context.go('/onboarding');
    } else {
      context.go('/');
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Spec calls for Title weight; kept a restrained 28px for splash
            // presence (down from 32px). Drop to 20px for strict Title voice.
            Text(
              'GymLog',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                fontFeatures: AppText.kInterFeatures,
              ),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_pulse.value);
                final double scale = reduceMotion ? 1.0 : (0.8 + 0.2 * t);
                final double opacity = reduceMotion ? (0.5 + 0.5 * t) : 1.0;
                return Opacity(
                  opacity: opacity,
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.accentPrimary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
