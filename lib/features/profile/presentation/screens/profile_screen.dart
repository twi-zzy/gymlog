import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../core/providers/premium_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/units.dart';
import '../../../../features/routines/presentation/widgets/routine_detail_styles.dart';
import '../../../../shared/widgets/branded_line_chart.dart';
import '../../../../shared/widgets/premium_paywall.dart';
import '../../../../shared/widgets/ui/toggle_pill.dart';
import '../providers/profile_provider.dart';
import '../providers/profile_stats_provider.dart';
import 'settings_screen.dart';

/// Athlete dashboard — identity, streak, weekly goal ring, and the same
/// chart component every other screen uses. Settings lives one tap away.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _selectedMetric = 'Volume';

  @override
  Widget build(BuildContext context) {
    final workoutCount = ref.watch(workoutCountProvider).valueOrNull ?? 0;
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final streak = ref.watch(streakStatsProvider);
    final goal = ref.watch(weeklyGoalProvider);
    final isPremium = ref.watch(isPremiumProvider);

    final displayName = profile?.displayName ?? 'Athlete';

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        scrolledUnderElevation: 0,
        title: Text(
          'Profile',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 28,
            letterSpacing: -0.5,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.settings_outlined,
                size: 22, color: AppColors.textPrimary),
            onPressed: () {
              HapticFeedback.selectionClick();
              context.push('/settings');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          // ── Identity ────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentPrimary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF00C4A0),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile?.email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isPremium)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentPrimary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.accentPrimary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'PRO',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: const Color(0xFFCBB2FF),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Stats strip: streak · weekly ring · total ───────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
            decoration: BoxDecoration(
              gradient: RDStyles.cardGradient,
              borderRadius: BorderRadius.circular(12),
              border: RDStyles.hairlineBorder,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _StatCell(
                    value: streak.currentStreak > 0
                        ? '${streak.currentStreak}'
                        : '—',
                    label: 'DAY STREAK',
                    leading: Icon(
                      Icons.local_fire_department_rounded,
                      size: 17,
                      color: streak.currentStreak > 0
                          ? const Color(0xFFFF9F0A)
                          : AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                _statDivider(),
                Expanded(
                  child: Semantics(
                    button: true,
                    label:
                        'Weekly goal: ${streak.workoutsThisWeek} of $goal workouts. Tap to change goal.',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => showWeeklyGoalSheet(context, ref),
                      child: _StatCell(
                        value: '${streak.workoutsThisWeek}/$goal',
                        label: 'THIS WEEK',
                        leading: GoalRing(
                          progress: goal == 0
                              ? 0
                              : (streak.workoutsThisWeek / goal)
                                  .clamp(0.0, 1.0),
                        ),
                      ),
                    ),
                  ),
                ),
                _statDivider(),
                Expanded(
                  child: _StatCell(
                    value: '$workoutCount',
                    label: 'WORKOUTS',
                    leading: const Icon(
                      Icons.fitness_center_rounded,
                      size: 16,
                      color: Color(0xFF00C4A0),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (!streak.trainedToday && streak.currentStreak > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 4),
              child: Text(
                'Train today to keep your ${streak.currentStreak}-day streak alive.',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          const SizedBox(height: 28),

          // ── Training chart (shared component) ───────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: 'Training ', style: RDStyles.sectionLabel),
                TextSpan(
                    text: '(weekly ${_unitFor(_selectedMetric)})',
                    style: RDStyles.sectionUnit),
              ])),
              if (!isPremium) const ProLockPill(label: 'FULL HISTORY'),
            ],
          ),
          const SizedBox(height: 12),
          _WeeklyChart(metric: _selectedMetric, isPremium: isPremium),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final metric in const ['Volume', 'Duration', 'Reps']) ...[
                TogglePill(
                  label: metric,
                  isActive: _selectedMetric == metric,
                  onTap: () => setState(() => _selectedMetric = metric),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 28),

          // ── Quick links ─────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: RDStyles.cardGradient,
              borderRadius: BorderRadius.circular(12),
              border: RDStyles.hairlineBorder,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _ActionRow(
                  icon: Icons.workspace_premium_rounded,
                  iconColor: const Color(0xFFCBB2FF),
                  title: isPremium ? 'GymLog Pro' : 'Upgrade to Pro',
                  subtitle: isPremium
                      ? 'Active — full history unlocked'
                      : 'Full analytics history & more',
                  onTap: () {
                    if (isPremium) {
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          'You are on GymLog Pro. Thanks for the support!',
                          style:
                              GoogleFonts.inter(color: AppColors.textPrimary),
                        ),
                        backgroundColor: AppColors.bgSurface,
                        behavior: SnackBarBehavior.floating,
                      ));
                    } else {
                      showPremiumPaywall(context);
                    }
                  },
                ),
                _rowDivider(),
                _ActionRow(
                  icon: Icons.fitness_center_rounded,
                  iconColor: AppColors.textSecondary,
                  title: 'Exercise Library',
                  subtitle: 'Browse exercises, form guides & records',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/exercises/library');
                  },
                ),
                _rowDivider(),
                _ActionRow(
                  icon: Icons.settings_outlined,
                  iconColor: AppColors.textSecondary,
                  title: 'Settings',
                  subtitle: 'Units, goals, rest timer, account',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.push('/settings');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _unitFor(String metric) => switch (metric) {
        'Duration' => 'min',
        'Reps' => 'reps',
        _ => 'kg',
      };

  Widget _statDivider() => Container(
        width: 1,
        height: 36,
        color: Colors.white.withValues(alpha: 0.06),
      );

  Widget _rowDivider() => Padding(
        padding: const EdgeInsets.only(left: 56),
        child: Container(height: 1, color: RDStyles.hairline),
      );
}

// ── Stats strip pieces ────────────────────────────────────────────────────────

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final Widget leading;

  const _StatCell({
    required this.value,
    required this.label,
    required this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 6),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Animated weekly-goal ring — fills smoothly as workouts land, turns
/// success-green the moment the goal completes.
class GoalRing extends StatelessWidget {
  final double progress;
  final double size;

  const GoalRing({super.key, required this.progress, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (_, animated, __) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(progress: animated, complete: progress >= 1),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final bool complete;
  _RingPainter({required this.progress, required this.complete});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5;

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
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color =
              complete ? const Color(0xFF34C759) : AppColors.accentPrimary,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.complete != complete;
}

// ── Weekly training chart — delegates to the shared component ────────────────

class _WeeklyChart extends ConsumerWidget {
  final String metric;
  final bool isPremium;

  const _WeeklyChart({required this.metric, required this.isPremium});

  double _valueOf(WeeklyMetricPoint p) => switch (metric) {
        'Duration' => p.duration,
        'Reps' => p.reps,
        _ => p.volume,
      };

  String _formatValue(double v) => switch (metric) {
        // Full notation + unit — never "3.0k kg" double-unit nonsense.
        'Duration' => '${groupThousands(v)} min',
        'Reps' => '${groupThousands(v)} reps',
        _ => '${groupThousands(v)} kg',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allPoints = ref.watch(weeklyMetricsProvider);
    final points = gateChartSamples(allPoints, isPremium);

    return BrandedLineChart(
      key: ValueKey('$metric${points.length}'),
      data: [for (final p in points) ChartPoint(p.weekStart, _valueOf(p))],
      valueFormatter: _formatValue,
      dateFormatter: (d) => 'week of ${DateFormat('MMM d').format(d)}',
      height: 150,
      emptyTitle: 'No training data yet',
      emptySubtitle: 'Finish a workout to see your weekly trend',
    );
  }
}

// ── Action rows ───────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: Colors.white.withValues(alpha: 0.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
