import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/router/router.dart';
import '../../core/theme/app_colors.dart';

/// Branded replacement for Flutter's red/grey error screen in release mode.
/// Wired up via `ErrorWidget.builder` in main.dart.
///
/// Deliberately dependency-free and layout-safe: it can be inflated outside
/// a MaterialApp (no Directionality / Theme / Material above it), so everything
/// is self-contained — the recovery buttons are plain tappables (NOT Material
/// buttons, which would require a Material ancestor) and navigation is routed
/// through the global [rootNavigatorKey] with graceful fallbacks.
class AppErrorScreen extends StatelessWidget {
  const AppErrorScreen({super.key});

  /// Navigate via the root navigator if it's alive; if the navigator itself is
  /// corrupted, fall back to closing the app (a clean relaunch re-runs init).
  void _navigateOrFallback(String route) {
    try {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) {
        GoRouter.of(ctx).go(route);
        return;
      }
    } catch (_) {
      // Router/navigator unavailable — fall through.
    }
    // Last resort. On Android this closes the app for a clean relaunch; on iOS
    // it's a no-op, but the visible buttons mean the screen is never a silent
    // dead end.
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AppColors.bgBase,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accentPrimary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.fitness_center_rounded,
                    color: Color(0xFF00C4A0),
                    size: 26,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Something went wrong',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your workout data is safe on this device.\n'
                  'Restart GymLog or head back home.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 24),
                _ErrorAction(
                  label: 'Restart GymLog',
                  primary: true,
                  onTap: () => _navigateOrFallback('/splash'),
                ),
                const SizedBox(height: 10),
                _ErrorAction(
                  label: 'Go Home',
                  primary: false,
                  onTap: () => _navigateOrFallback('/'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Material-free, screen-reader-reachable action button. Avoids ElevatedButton/
/// InkWell because those require a Material ancestor this screen may not have.
class _ErrorAction extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _ErrorAction({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 240,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary
                ? AppColors.accentPrimary
                : AppColors.accentPrimary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: primary
                ? null
                : Border.all(
                    color: AppColors.accentPrimary.withValues(alpha: 0.40)),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: primary ? Colors.white : const Color(0xFFCBB2FF),
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
