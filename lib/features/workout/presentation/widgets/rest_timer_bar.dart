import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/features/workout/presentation/providers/rest_timer_provider.dart';

/// Floating rest-timer tile shown in the Active Workout's
/// `bottomNavigationBar`. It does NOT take over the screen — the content
/// height is HARD-BOUNDED to [kRestTileHeight] so it can never stretch,
/// no matter what constraints an ancestor passes down.
///
/// Sized for GLANCEABILITY: large tabular numerals + an ambient accent glow so
/// a lifter can read remaining rest from arm's length without focusing. The
/// active-workout list reserves enough bottom padding to clear this height.
const double kRestTileHeight = 84;

class RestTimerBar extends ConsumerWidget {
  final RestTimerState state;

  const RestTimerBar({super.key, required this.state});

  String get _label {
    final m = state.remainingSeconds ~/ 60;
    final s = state.remainingSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(restTimerProvider.notifier);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        // Fixed height — the single guarantee that this tile stays a tile.
        // Screen-reader: announce the remaining time, not just the visual ring.
        child: Semantics(
          container: true,
          label: 'Rest timer, $_label remaining',
          child: _AmbientPulse(
            radius: BorderRadius.circular(12),
            child: SizedBox(
              height: kRestTileHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1B1226), Color(0xFF0B0B0D)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.accentPrimary.withValues(alpha: 0.40),
                    width: 1.2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: CustomPaint(
                          painter: _RestRingPainter(progress: state.progress),
                          child: const Center(
                            child: Icon(Icons.timer_outlined,
                                size: 18, color: Color(0xFFCBB2FF)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'REST',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          // Large + tabular so digits don't jitter as seconds tick.
                          Text(
                            _label,
                            style: GoogleFonts.inter(
                              fontSize: 36,
                              height: 1.0,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _RestAction(
                        label: '+15s',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          notifier.addSeconds(15);
                        },
                      ),
                      const SizedBox(width: 8),
                      _RestAction(
                        label: 'Skip',
                        emphasized: true,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          notifier.skip();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RestAction extends StatelessWidget {
  final String label;
  final bool emphasized;
  final VoidCallback onTap;

  const _RestAction({
    required this.label,
    this.emphasized = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: emphasized
          ? AppColors.accentPrimary.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color:
                  emphasized ? const Color(0xFFCBB2FF) : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A slow accent glow around the rest tile, visible in peripheral vision so a
/// lifter can tell at a glance whether rest is still running. Honors OS
/// reduce-motion by holding a steady (non-pulsing) glow instead.
class _AmbientPulse extends StatefulWidget {
  final Widget child;
  final BorderRadius radius;
  const _AmbientPulse({required this.child, required this.radius});

  @override
  State<_AmbientPulse> createState() => _AmbientPulseState();
}

class _AmbientPulseState extends State<_AmbientPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      // Reduce-motion: a steady glow, no pulsing.
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: widget.radius,
          boxShadow: [
            BoxShadow(
              color: AppColors.accentPrimary.withValues(alpha: 0.28),
              blurRadius: 18,
              spreadRadius: -2,
            ),
          ],
        ),
        child: widget.child,
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.radius,
            boxShadow: [
              BoxShadow(
                color: AppColors.accentPrimary.withValues(alpha: 0.18 + 0.30 * t),
                blurRadius: 14 + 16 * t,
                spreadRadius: -2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _RestRingPainter extends CustomPainter {
  final double progress;
  _RestRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.10),
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = AppColors.accentPrimary,
      );
    }
  }

  @override
  bool shouldRepaint(_RestRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
