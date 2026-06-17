import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/exercises/muscle_taxonomy.dart';
import 'package:gymlog/core/database/database.dart';
import 'package:gymlog/core/database/daos/workouts_dao.dart';
import 'package:gymlog/core/providers/premium_provider.dart';
import 'package:gymlog/core/utils/units.dart';
import 'package:gymlog/features/routines/presentation/widgets/routine_detail_styles.dart';
import 'package:gymlog/shared/widgets/async_error_state.dart';
import 'package:gymlog/shared/widgets/branded_line_chart.dart';
import 'package:gymlog/shared/widgets/exercise_gif_widget.dart';
import 'package:gymlog/shared/widgets/premium_paywall.dart';
import 'package:gymlog/shared/widgets/ui/time_range_filter.dart';
import 'package:gymlog/core/providers/database_provider.dart';
import '../providers/exercise_analytics_provider.dart';

class ExerciseDetailScreen extends ConsumerStatefulWidget {
  final int exerciseId;
  final Exercise? exercise;

  const ExerciseDetailScreen(
      {super.key, required this.exerciseId, this.exercise});

  @override
  ConsumerState<ExerciseDetailScreen> createState() =>
      _ExerciseDetailScreenState();
}

final _exerciseFallbackProvider =
    FutureProvider.autoDispose.family<Exercise, int>((ref, id) {
  final db = ref.watch(databaseProvider);
  return db.exercisesDao.getExerciseById(id);
});

class _ExerciseDetailScreenState extends ConsumerState<ExerciseDetailScreen> {
  int _activeToggleIndex = 0;
  String _selectedTimeRange = 'All Time';

  static const _toggleLabels = [
    'Heaviest Weight',
    'One Rep Max',
    'Best Set',
    'Session Volume',
  ];

  double _metricForToggle(ExerciseHistoryData e, int index) {
    switch (index) {
      case 0:
        return e.weight;
      case 1:
        return e.estimated1RM;
      case 2:
        return e.weight;
      case 3:
        return e.volume;
      default:
        return e.weight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(
        exerciseAnalyticsProvider((widget.exerciseId, _selectedTimeRange)));

    final exerciseAsync = widget.exercise != null
        ? AsyncValue.data(widget.exercise!)
        : ref.watch(_exerciseFallbackProvider(widget.exerciseId));

    return exerciseAsync.when(
      loading: () => const Scaffold(
          backgroundColor: AppColors.bgBase,
          body: Center(
              child:
                  CircularProgressIndicator(color: AppColors.accentPrimary))),
      error: (e, st) => Scaffold(
        backgroundColor: AppColors.bgBase,
        appBar: AppBar(
          backgroundColor: AppColors.bgBase,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
        ),
        body: AsyncErrorState(
          message: "Couldn't load this exercise.",
          onRetry: () =>
              ref.invalidate(_exerciseFallbackProvider(widget.exerciseId)),
        ),
      ),
      data: (exercise) {
        return Scaffold(
          backgroundColor: AppColors.bgBase,
          appBar: AppBar(
            title: Text(
              exercise.name,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: AppColors.bgBase,
            scrolledUnderElevation: 0,
            titleSpacing: 0, // title hugs the back button on every sub-screen
            iconTheme: const IconThemeData(color: AppColors.textPrimary),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Exercise GIF — loads from Supabase, cached permanently offline
              ExerciseGifWidget(
                gifUrl: exercise.gifUrl,
                width: double.infinity,
                height: 220,
                fit: BoxFit.contain,
              ),

              const SizedBox(height: 16),

              // Exercise Name & Metadata
              Text(
                exercise.name,
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                () {
                  final parent = MuscleTaxonomy.parentOf(exercise.target);
                  return parent == exercise.target || parent == 'Other'
                      ? exercise.equipment
                      : '$parent  •  ${exercise.equipment}';
                }(),
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 14),
              // Worked muscles: primary (accent) + secondary (muted) chips.
              Builder(
                builder: (_) {
                  final chips = <(String, bool)>[(exercise.target, true)];
                  try {
                    final sec = (jsonDecode(exercise.secondaryMuscles ?? '[]')
                            as List)
                        .cast<String>();
                    for (final m in sec) {
                      if (m.trim().isNotEmpty) chips.add((m, false));
                    }
                  } catch (_) {/* malformed JSON — show primary only */}
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (label, primary) in chips)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 6),
                          decoration: BoxDecoration(
                            color: primary
                                ? AppColors.accentPrimary.withValues(alpha: 0.14)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: primary
                                  ? AppColors.accentPrimary
                                      .withValues(alpha: 0.34)
                                  : Colors.white.withValues(alpha: 0.08),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            label,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight:
                                  primary ? FontWeight.w600 : FontWeight.w500,
                              color: primary
                                  ? const Color(0xFFCBB2FF)
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),

              historyAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: CircularProgressIndicator(
                      color: AppColors.accentPrimary,
                    ),
                  ),
                ),
                error: (err, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Text(
                      'Failed to load analytics',
                      style: GoogleFonts.inter(color: AppColors.error),
                    ),
                  ),
                ),
                data: (history) {
                  // Free tier: 3 most recent sessions in the chart as a
                  // teaser. PR aggregates stay free — they're core
                  // motivation, not deep analytics.
                  final isPremium = ref.watch(isPremiumProvider);
                  final visible = gateChartSamples(history, isPremium);
                  return Column(
                    children: [
                      _buildGraphSection(visible,
                          showProPill: !isPremium && history.length > 3),
                      const SizedBox(height: 24),
                      _buildStatToggles(),
                      if (history.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildPersonalRecords(history),
                      ],
                      const SizedBox(height: 24),
                      _buildInstructions(exercise),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGraphSection(List<ExerciseHistoryData> history,
      {bool showProPill = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _toggleLabels[_activeToggleIndex],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RDStyles.sectionLabel,
              ),
            ),
            if (showProPill)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: ProLockPill(label: 'FULL HISTORY'),
              ),
            TimeRangeFilter(
              value: _selectedTimeRange,
              onChanged: (range) => setState(() => _selectedTimeRange = range),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // The same chart component as Routine Detail and Profile — same
        // touch-to-inspect header, dots, axis density and animations.
        BrandedLineChart(
          key: ValueKey(
              '$_activeToggleIndex|$_selectedTimeRange|${history.length}'),
          data: [
            for (final e in history)
              ChartPoint(e.date, _metricForToggle(e, _activeToggleIndex)),
          ],
          valueFormatter: (v) => _activeToggleIndex == 3
              ? '${groupThousands(v)} kg'
              : '${v == v.truncateToDouble() ? v.toInt() : v.toStringAsFixed(1)} kg',
          emptyTitle: 'No data yet',
          emptySubtitle: 'Log this exercise to see your progress',
        ),
      ],
    );
  }

  Widget _buildStatToggles() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _toggleLabels.asMap().entries.map((entry) {
          final isActive = entry.key == _activeToggleIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              button: true,
              selected: isActive,
              child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _activeToggleIndex = entry.key);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      isActive ? AppColors.accentPrimary : AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  entry.value,
                  style: GoogleFonts.inter(
                    color: isActive ? Colors.white : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPersonalRecords(List<ExerciseHistoryData> history) {
    final maxWeight = history.isEmpty
        ? 0.0
        : history.map((e) => e.weight).reduce((a, b) => a > b ? a : b);
    final max1RM = history.isEmpty
        ? 0.0
        : history.map((e) => e.estimated1RM).reduce((a, b) => a > b ? a : b);
    final maxVolume = history.isEmpty
        ? 0.0
        : history.map((e) => e.volume).reduce((a, b) => a > b ? a : b);
    final maxReps = history.isEmpty
        ? 0
        : history.map((e) => e.reps).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.emoji_events, color: AppColors.warning, size: 20),
            const SizedBox(width: 8),
            Text(
              'Personal Records',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _prRow('Heaviest Weight', '${maxWeight.toStringAsFixed(1)} kg'),
              _prDivider(),
              _prRow('Best 1RM', '${max1RM.toStringAsFixed(2)} kg'),
              _prDivider(),
              _prRow(
                  'Max Session Volume', '${maxVolume.toStringAsFixed(0)} kg'),
              _prDivider(),
              _prRow('Max Reps', '$maxReps reps'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _prRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _prDivider() {
    return const Divider(
      color: AppColors.borderSubtle,
      height: 1,
      indent: 16,
      endIndent: 16,
    );
  }

  Widget _buildInstructions(Exercise exercise) {
    if (exercise.instructions == null || exercise.instructions!.isEmpty) {
      return const SizedBox.shrink();
    }

    List<String> steps;
    try {
      steps =
          (jsonDecode(exercise.instructions!) as List<dynamic>).cast<String>();
    } catch (_) {
      return const SizedBox.shrink();
    }

    if (steps.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.list_alt_rounded,
                color: AppColors.accentPrimary, size: 20),
            const SizedBox(width: 8),
            Text(
              'How to Perform',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: steps.asMap().entries.map((entry) {
              final isLast = entry.key == steps.length - 1;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color:
                                AppColors.accentPrimary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: Text(
                              '${entry.key + 1}',
                              style: GoogleFonts.inter(
                                color: AppColors.accentPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: GoogleFonts.inter(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    const Divider(
                      color: AppColors.borderSubtle,
                      height: 1,
                      indent: 52,
                      endIndent: 16,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
