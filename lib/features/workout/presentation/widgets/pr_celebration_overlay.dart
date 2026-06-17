import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymlog/core/database/daos/workouts_dao.dart';
import 'package:gymlog/core/theme/app_colors.dart';

/// Full-screen celebration shown when a finished workout contains PRs.
/// Turns a silent `is_pr = 1` database write into the app's best moment:
/// strong haptic, purple confetti, and the actual numbers that were beaten.
///
/// Dependency-free — confetti is a lightweight CustomPainter, not a package.
Future<void> showPrCelebration(
  BuildContext context,
  List<PrRecord> prs,
) {
  if (prs.isEmpty) return Future.value();
  HapticFeedback.heavyImpact();

  // Honor OS reduce-motion: no scale/fade entrance, no confetti.
  final reduceMotion = MediaQuery.disableAnimationsOf(context);

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Personal record celebration',
    barrierColor: Colors.black.withValues(alpha: 0.82),
    transitionDuration:
        reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
    transitionBuilder: reduceMotion
        ? (_, __, ___, child) => child
        : (_, animation, __, child) {
            final curved =
                CurvedAnimation(parent: animation, curve: Curves.easeOutBack);
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: curved, child: child),
            );
          },
    pageBuilder: (dialogCtx, _, __) =>
        _PrCelebration(prs: prs, reduceMotion: reduceMotion),
  );
}

class _PrCelebration extends StatefulWidget {
  final List<PrRecord> prs;
  final bool reduceMotion;
  const _PrCelebration({required this.prs, this.reduceMotion = false});

  @override
  State<_PrCelebration> createState() => _PrCelebrationState();
}

class _PrCelebrationState extends State<_PrCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _confetti = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    // Reduce-motion: skip the confetti animation entirely.
    if (!widget.reduceMotion) _confetti.forward();
    // Double-pulse: the entry heavy impact is followed by a medium tap as
    // the card settles — the "rep lockout" feel.
    Future.delayed(const Duration(milliseconds: 240), () {
      if (mounted) HapticFeedback.mediumImpact();
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  String _fmtKg(double kg) => kg == kg.truncateToDouble()
      ? kg.toInt().toString()
      : kg.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final prs = widget.prs;
    final title = prs.length == 1
        ? 'New Personal Record!'
        : '${prs.length} New Personal Records!';

    return Stack(
      children: [
        // ── Confetti layer (skipped entirely under reduce-motion) ──────────
        if (!widget.reduceMotion)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _confetti,
                builder: (_, __) => CustomPaint(
                  painter: _ConfettiPainter(progress: _confetti.value),
                ),
              ),
            ),
          ),

        // ── Card ──────────────────────────────────────────────────────────
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 380),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF15101D), Color(0xFF0B0B0D)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.accentPrimary.withValues(alpha: 0.35),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentPrimary.withValues(alpha: 0.25),
                      blurRadius: 48,
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accentPrimary.withValues(alpha: 0.16),
                        border: Border.all(
                          color: AppColors.accentPrimary.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        color: Color(0xFFCBB2FF),
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Stronger than every session before it.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── PR rows (max 4 visible, scrolls beyond) ───────────
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final pr in prs)
                              Semantics(
                                label: '${pr.exerciseName}: '
                                    '${_fmtKg(pr.weightKg)} kilograms for ${pr.reps} reps, '
                                    'estimated one-rep max ${_fmtKg(pr.estimated1rm)} kilograms'
                                    '${pr.previousBest1rm > 0 ? ', up from ${_fmtKg(pr.previousBest1rm)} kilograms' : ', first record'}',
                                excludeSemantics: true,
                                child: Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.04),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              pr.exerciseName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${_fmtKg(pr.weightKg)} kg × ${pr.reps} reps',
                                              style: GoogleFonts.inter(
                                                fontSize: 12.5,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '${_fmtKg(pr.estimated1rm)} kg',
                                            style: GoogleFonts.inter(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFFCBB2FF),
                                            ),
                                          ),
                                          Text(
                                            pr.previousBest1rm > 0
                                                ? 'prev ${_fmtKg(pr.previousBest1rm)} kg'
                                                : 'first 1RM',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Keep Going',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Confetti ──────────────────────────────────────────────────────────────────

class _ConfettiPainter extends CustomPainter {
  final double progress;

  _ConfettiPainter({required this.progress});

  // Deterministic particle field — same seed every build, zero allocations
  // beyond the paint object per frame.
  static final List<_Particle> _particles = _generate();

  static List<_Particle> _generate() {
    final rng = math.Random(7);
    const palette = [
      Color(0xFFE6C84A),
      Color(0xFFE6C84A),
      Color(0xFFCBB2FF),
      Color(0xFFE6C84A),
      Color(0xFFFFFFFF),
      Color(0xFFFFCC00),
    ];
    return List.generate(64, (i) {
      return _Particle(
        x: rng.nextDouble(),
        delay: rng.nextDouble() * 0.35,
        speed: 0.65 + rng.nextDouble() * 0.55,
        drift: (rng.nextDouble() - 0.5) * 0.22,
        size: 4 + rng.nextDouble() * 5,
        spin: (rng.nextDouble() - 0.5) * 14,
        color: palette[i % palette.length],
        isCircle: i % 4 == 0,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in _particles) {
      final t = ((progress - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final opacity = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
      final dy = -0.05 + t * p.speed * 1.15;
      if (dy > 1.05) continue;

      final dx = p.x + math.sin(t * math.pi * 2) * p.drift;
      paint.color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(dx * size.width, dy * size.height);
      canvas.rotate(t * p.spin);
      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset.zero, width: p.size, height: p.size * 0.62),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _Particle {
  final double x, delay, speed, drift, size, spin;
  final Color color;
  final bool isCircle;

  const _Particle({
    required this.x,
    required this.delay,
    required this.speed,
    required this.drift,
    required this.size,
    required this.spin,
    required this.color,
    required this.isCircle,
  });
}
