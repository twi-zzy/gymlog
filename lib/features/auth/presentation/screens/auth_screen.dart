import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/config/legal_links.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/theme/dynamic_accent_theme.dart';
import '../../../../shared/layout/adaptive.dart';
import '../../../../shared/widgets/motion/pressable_scale.dart';
import '../../../../shared/widgets/ui/app_snack_bar.dart';
import '../../data/auth_repository.dart';
import '../providers/auth_provider.dart';

const String _googleIconSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <path fill="#EA4335" d="M20.33 3.34c-2.16-2-4.99-2.84-8.33-2.84-4.67 0-8.7 2.68-10.67 6.58l4.12 3.19c.97-2.92 3.7-5.23 6.55-5.23 1.83 0 3.48.63 4.77 1.86l3.56-3.56z"/>
  <path fill="#4285F4" d="M23.45 11.3c0-.83-.07-1.63-.2-2.41h-11.25v4.62h6.43c-.28 1.46-1.1 2.7-2.34 3.53l3.95 3.07c2.31-2.13 3.41-5.28 3.41-8.81z"/>
  <path fill="#34A853" d="M12 18.96c-2.85 0-5.58-2.31-6.55-5.23L1.33 16.92C3.3 20.82 7.33 23.5 12 23.5c3.23 0 6.13-1.07 8.21-2.93l-3.95-3.07c-1.13.76-2.6 1.46-4.26 1.46z"/>
  <path fill="#FBBC05" d="M5.45 13.73c-.25-.76-.4-1.57-.4-2.43s.15-1.67.4-2.43L1.33 5.68C.48 7.38 0 9.27 0 11.3s.48 3.92 1.33 5.62l4.12-3.19z"/>
</svg>
''';

final Widget _googleIcon = SvgPicture.string(
  _googleIconSvg,
  width: 20,
  height: 20,
);

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isSigningIn = false;

  Future<void> _signIn() async {
    if (_isSigningIn) {
      // Never a dead tap: a second press while an attempt runs gives
      // immediate feedback instead of silently dropping the gesture.
      HapticFeedback.lightImpact();
      _snack('Sign-in is already in progress.');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _isSigningIn = true);

    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (e) {
      if (e is AuthCancelled) {
        return;
      }

      String message = "Couldn’t sign in. Please try again.";
      String failure = 'unknown';
      String? code;

      if (e is AuthNetworkFailure) {
        message = 'You’re offline. Check your connection and try again.';
        failure = 'network';
      } else if (e is AuthConfigurationFailure) {
        message =
            'Google sign-in isn’t available in this build. Please update the app or contact support.';
        failure = 'configuration';
        code = e.diagnosticCode;
      } else if (e is AuthProviderFailure) {
        message =
            'Google sign-in is temporarily unavailable. Try again in a moment.';
        failure = 'provider';
      } else if (e is AuthTimeoutFailure) {
        message = 'Sign-in timed out. Please try again.';
        failure = 'timeout';
      }

      // Sanitized debug output
      debugPrint('[Auth] failure=$failure${code != null ? " code=$code" : ""}');

      if (!mounted) return;
      _snack(message);
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  void _snack(String message) {
    showAppSnackBar(context, message: message);
  }

  void _cancelSignIn() {
    HapticFeedback.lightImpact();
    ref.read(authRepositoryProvider).cancelGoogleSignIn();
  }

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) _snack("Couldn't open the link.");
      }
    } catch (_) {
      if (mounted) _snack("Couldn't open the link.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    final accent = context.accent;

    final overlay = (surface.isLight
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light)
        .copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: surface.bgBase,
      systemNavigationBarIconBrightness:
          surface.isLight ? Brightness.dark : Brightness.light,
    );

    final textScale = context.adaptive.textScaleFactor;
    // COMPACT MODE (ship-readiness #10): the phantom few-px scroll came from
    // the Column's minimum intrinsic height exceeding SliverFillRemaining's
    // remaining extent on short viewports / large text scales — the Spacer
    // can only distribute surplus, never deficit. Compressing the fixed gaps
    // brings the minimum back under the extent; ClampingScrollPhysics below
    // means even a device-specific edge case can never bounce-reveal itself.
    final compact =
        textScale >= 1.6 || MediaQuery.sizeOf(context).height < 640;
    final double topPadding = compact ? 12 : 24;
    final double gapAfterBrand = compact ? 12 : 24;
    final double gapBeforeButton = compact ? 12 : 24;
    final double gapBeforeLegal = compact ? 9 : 18;

    final secondaryColor =
        surface.isLight ? const Color(0xFF555555) : surface.textSecondary;

    final brandBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: topPadding),
        ExcludeSemantics(
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              color: surface.surface3,
              border: Border.all(
                color: accent.selectionBorder,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.glow.withValues(alpha: 0.12),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.fitness_center_rounded,
                color: accent.base,
                size: 27,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(
            'GymLog',
            style: AppText.screenTitle(color: surface.textPrimary).copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          child: Text(
            'Track every workout.\nKeep your history.',
            style: AppText.screenTitle(color: surface.textPrimary).copyWith(
              fontSize: 27,
              fontWeight: FontWeight.w700,
              height: 1.12,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          child: Text(
            'Sign in with Google to get started.\nYour workouts are stored on your device and synced securely when you sign in.',
            style: AppText.body(color: secondaryColor).copyWith(
              fontSize: 15,
              height: 1.45,
            ),
          ),
        ),
      ],
    );

    final trustBlock = Semantics(
      child: Row(
        children: [
          Icon(
            Icons.shield_outlined,
            size: 16,
            color: secondaryColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your data is stored on your device first and synced with your Google account. Google is used for secure sign-in and sync.',
              style: AppText.caption(color: secondaryColor).copyWith(
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );

    final signInButton = Semantics(
      container: true,
      button: true,
      enabled: true,
      // Wrapper owns the name; the ElevatedButton's child Text must not
      // publish a second node (docs/a11y-semantics-checklist.md §2).
      // excludeSemantics discards the button's tap action, hence the
      // explicit onTap kept in sync with onPressed.
      excludeSemantics: true,
      onTap: _signIn,
      label: _isSigningIn ? 'Signing in with Google' : 'Continue with Google',
      value: _isSigningIn ? 'In progress' : null,
      child: PressableScale(
        pressedScale: 0.985,
        child: ElevatedButton(
          onPressed: _signIn,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF111111),
            elevation: 0,
            minimumSize: const Size.fromHeight(56),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            side: surface.isLight
                ? BorderSide(color: surface.borderDefault, width: 1.0)
                : BorderSide.none,
          ),
          child: _isSigningIn
              ? Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  children: [
                    const ExcludeSemantics(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF111111),
                        ),
                      ),
                    ),
                    Text(
                      'Signing in…',
                      style: AppText.button(
                        color: const Color(0xFF111111).withValues(alpha: 0.72),
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                )
              : Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    _googleIcon,
                    Text(
                      'Continue with Google',
                      style: AppText.button(
                        color: const Color(0xFF111111),
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
        ),
      ),
    );

    final cancelButton = Semantics(
      container: true,
      button: true,
      label: 'Cancel sign-in',
      excludeSemantics: true,
      onTap: _isSigningIn ? _cancelSignIn : null,
      child: PressableScale(
        pressedScale: 0.985,
        child: TextButton(
          onPressed: _isSigningIn ? _cancelSignIn : null,
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: secondaryColor,
            textStyle: AppText.button(),
          ),
          child: const Text('Cancel'),
        ),
      ),
    );

    final legalBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          child: Text(
            'By continuing, you agree to:',
            style: AppText.caption(color: secondaryColor).copyWith(
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 0,
          children: [
            _LegalLink(
              label: 'Terms of Service',
              onPressed: () => _openUrl(kTermsOfServiceUrl),
            ),
            _LegalLink(
              label: 'Privacy Policy',
              onPressed: () => _openUrl(kPrivacyPolicyUrl),
            ),
          ],
        ),
      ],
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: surface.bgBase,
        body: Stack(
          children: [
            const Positioned.fill(
              child: _AuthAtmosphere(),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: context.adaptive.contentMaxWidth,
                  ),
                  child: CustomScrollView(
                    // No bounce: the residual few-px overflow on odd viewports
                    // can never reveal itself by rubber-banding (see compact
                    // mode above for the actual overflow fix).
                    physics: const ClampingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        sliver: SliverFillRemaining(
                          hasScrollBody: false,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _EntranceFade(child: brandBlock),
                              SizedBox(height: gapAfterBrand),
                              const Spacer(),
                              _EntranceFade(
                                delay: const Duration(milliseconds: 80),
                                child: trustBlock,
                              ),
                              SizedBox(height: gapBeforeButton),
                              _EntranceFade(
                                delay: const Duration(milliseconds: 160),
                                child: signInButton,
                              ),
                              const SizedBox(height: 4),
                              if (_isSigningIn) cancelButton,
                              SizedBox(height: gapBeforeLegal),
                              _EntranceFade(
                                delay: const Duration(milliseconds: 220),
                                child: legalBlock,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-shot fade + 12dp rise for the auth screen's staggered entrance.
/// Runs once on mount; skipped entirely under reduce-motion.
class _EntranceFade extends StatelessWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  const _EntranceFade({
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 500),
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final total = duration + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(
        delay.inMilliseconds / total.inMilliseconds,
        1.0,
        curve: Curves.easeOutCubic,
      ),
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

/// The ambient auth backdrop: two accent blobs on a slow Lissajous drift,
/// opacity breathing out of phase with position so the loop never reads as
/// a loop. One [CustomPainter], one layer — no widget-tree rebuilds. The
/// controller stops when the app is backgrounded (a running animation
/// behind a paused app is a battery bug) and freezes under reduce-motion.
class _AuthAtmosphere extends StatefulWidget {
  const _AuthAtmosphere();

  @override
  State<_AuthAtmosphere> createState() => _AuthAtmosphereState();
}

class _AuthAtmosphereState extends State<_AuthAtmosphere>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  void _syncMotion() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat(reverse: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _drift.stop();
    } else if (state == AppLifecycleState.resumed) {
      _syncMotion();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    final accent = context.accent;

    return IgnorePointer(
      child: RepaintBoundary(
        child: ColoredBox(
          color: surface.bgBase,
          child: CustomPaint(
            painter: _AtmospherePainter(
              animation: _drift,
              glowColor: accent.glow,
              mutedColor: accent.muted,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _AtmospherePainter extends CustomPainter {
  final Animation<double> animation;
  final Color glowColor;
  final Color mutedColor;

  _AtmospherePainter({
    required this.animation,
    required this.glowColor,
    required this.mutedColor,
  }) : super(repaint: animation);

  void _blob(
    Canvas canvas,
    Size size,
    Alignment align,
    double w,
    double h,
    Color color,
    double alpha,
  ) {
    final center = align.withinRect(Offset.zero & size);
    final rect = Rect.fromCenter(center: center, width: w, height: h);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final phase = 2 * math.pi * animation.value;
    // Same positions as the old static blobs, plus a small closed-loop drift.
    _blob(
      canvas,
      size,
      Alignment(0.10 * math.sin(phase), -0.72 + 0.06 * math.cos(phase)),
      260,
      260,
      glowColor,
      0.65 + 0.10 * math.sin(phase + 1.7),
    );
    _blob(
      canvas,
      size,
      Alignment(
        -0.9 + 0.08 * math.cos(phase * 0.5 + 1.3),
        0.95 + 0.05 * math.sin(phase * 0.5 + 1.3),
      ),
      320,
      220,
      mutedColor,
      0.45 + 0.08 * math.sin(phase + 3.4),
    );
  }

  @override
  bool shouldRepaint(_AtmospherePainter oldDelegate) =>
      oldDelegate.glowColor != glowColor ||
      oldDelegate.mutedColor != mutedColor;
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;

    return Semantics(
      link: true,
      label: label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 8,
            ),
            child: Text(
              label,
              style: AppText.caption().copyWith(
                fontSize: 13,
                color: surface.textSecondary,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: surface.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
