import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gymlog/core/exercises/body_map.dart';
import 'package:gymlog/features/auth/presentation/providers/tour_provider.dart';
import 'package:gymlog/features/profile/presentation/providers/profile_provider.dart';
import 'package:gymlog/shared/widgets/body/muscle_load_bar.dart';
import 'package:gymlog/shared/widgets/tour/spotlight_tour_overlay.dart';

import 'package:gymlog/core/database/daos/routines_dao.dart';
import 'package:gymlog/core/database/daos/workouts_dao.dart';
import 'package:gymlog/core/database/database.dart';
import 'package:gymlog/core/providers/database_provider.dart';
import 'package:gymlog/core/providers/premium_provider.dart';
import 'package:gymlog/core/providers/settings_provider.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/theme/app_text.dart';
import 'package:gymlog/core/theme/dynamic_accent_theme.dart';
import 'package:gymlog/core/utils/relative_time.dart';
import 'package:gymlog/core/utils/tap_guard.dart';
import 'package:gymlog/core/utils/units.dart';
import 'package:gymlog/features/workout/domain/active_workout_state.dart';
import 'package:gymlog/features/workout/presentation/providers/active_workout_provider.dart';
import 'package:gymlog/shared/widgets/async_error_state.dart';
import 'package:gymlog/shared/widgets/premium_paywall.dart';
import 'package:gymlog/shared/widgets/ui/action_bottom_sheet.dart';
import 'package:gymlog/shared/widgets/ui/app_button_shell.dart';
import 'package:gymlog/shared/widgets/ui/app_dialog.dart';
import 'package:gymlog/shared/widgets/ui/app_snack_bar.dart';
import 'package:gymlog/shared/widgets/ui/app_refresh_indicator.dart';
import 'package:gymlog/shared/widgets/feedback/undoable_delete.dart';
import 'package:gymlog/shared/widgets/ui/secondary_button.dart';
import 'package:gymlog/shared/widgets/ui/skeleton.dart';
import 'package:gymlog/shared/widgets/motion/pressable_scale.dart';
import 'package:gymlog/shared/widgets/ui/time_range_filter.dart';
import 'package:gymlog/shared/layout/adaptive.dart';
import '../providers/routines_provider.dart';
import '../widgets/routine_exercise_block.dart';
import '../widgets/routine_volume_graph.dart';

/// Hoisted once — constructing a [DateFormat] parses its pattern, so it must not
/// be rebuilt per frame.
final DateFormat _monthDay = DateFormat('MMM d');

/// RoutineDetailScreen — the launchpad for a saved routine: one dominant Start
/// CTA, a personal stat line, a volume trend, and the exercise set tables.
///
/// Muscle coverage is shown as a one-line [MuscleLoadBar] — a stacked
/// proportional bar rather than an inline anatomical map or a scrolling chip
/// strip. See muscle_load_bar.dart / muscle_summary.dart for why: the map is
/// low re-read-rate reference content and was consuming the space where the
/// exercise list should start.
class RoutineDetailScreen extends ConsumerStatefulWidget {
  final String routineId;

  const RoutineDetailScreen({super.key, required this.routineId});

  @override
  ConsumerState<RoutineDetailScreen> createState() =>
      _RoutineDetailScreenState();
}

class _RoutineDetailScreenState extends ConsumerState<RoutineDetailScreen> {
  final GlobalKey _startRoutineButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
  }

  // ── Actions ────────────────────────

  void _startRoutine(HydratedRoutineDetail routine) {
    if (!tapGuard()) return;
    if (routine.exercises.isEmpty) {
      context.push('/routines/edit?id=${widget.routineId}');
      return;
    }

    if (ref.read(firstRunTourProvider) == 2) {
      ref.read(firstRunTourProvider.notifier).skipOrEnd();
    }

    ref.read(activeWorkoutProvider.notifier).startWorkout(
          routineId: routine.routine.id,
          name: routine.routine.name,
          initialExercises: seedExercisesFromRoutine(routine),
        );
    context.push('/workout/active');
  }

  void _openEditor() {
    if (!tapGuard()) return;
    HapticFeedback.selectionClick();
    context.push('/routines/edit?id=${widget.routineId}');
  }

  Future<void> _addExercise() async {
    if (!tapGuard()) return;
    HapticFeedback.lightImpact();
    final selected = await context.push<Exercise>('/exercises/select');
    if (selected == null || !mounted) return;
    await ref
        .read(databaseProvider)
        .routinesDao
        .addExerciseToRoutine(widget.routineId, selected.id);
  }

  Future<void> _shareRoutine(HydratedRoutineDetail routine) async {
    final b = StringBuffer()
      ..writeln(routine.routine.name)
      ..writeln();
    for (final he in routine.exercises) {
      final c = he.config;
      final reps = c.defaultReps != null ? ' × ${c.defaultReps}' : '';
      b.writeln('• ${he.exercise.name} — ${c.defaultSets} sets$reps');
    }
    b
      ..writeln()
      ..write('Shared from GymLog');
    await SharePlus.instance.share(
      ShareParams(text: b.toString(), subject: routine.routine.name),
    );
  }

  void _showActions(HydratedRoutineDetail routine) {
    final surface = context.surface;
    showActionBottomSheet(
      context: context,
      title: routine.routine.name,
      items: [
        ActionSheetItem(
          icon: Icons.edit_rounded,
          iconColor: surface.textSecondary,
          iconBackground: surface.bgBase,
          title: 'Edit Routine',
          onTap: (ctx) {
            Navigator.of(ctx).pop();
            _openEditor();
          },
        ),
        ActionSheetItem(
          icon: Icons.share_rounded,
          iconColor: surface.textSecondary,
          iconBackground: surface.bgBase,
          title: 'Share Routine',
          onTap: (ctx) {
            Navigator.of(ctx).pop();
            _shareRoutine(routine);
          },
        ),
        ActionSheetItem(
          icon: Icons.delete_outline_rounded,
          iconColor: AppColors.error,
          iconBackground: AppColors.error.withValues(alpha: 0.12),
          title: 'Delete Routine',
          titleColor: AppColors.error,
          subtitle: 'Remove from list',
          subtitleColor: AppColors.error.withValues(alpha: 0.7),
          onTap: (ctx) {
            Navigator.of(ctx).pop();
            _confirmDelete(routine.routine.id);
          },
        ),
      ],
    );
  }

  Future<void> _confirmDelete(String routineId) async {
    if (!tapGuard()) return;
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Delete Routine?',
      message:
          'This routine will be removed from your list. Your workout history stays.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final db = ref.read(databaseProvider);

    // Capture the JSON representation of the routine before delete
    final data = await db.routinesDao.exportRoutineJson(routineId);
    if (data == null) return;

    if (!mounted) return;

    // RD-4 discipline: capture messenger and router BEFORE popping
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    HapticFeedback.mediumImpact();

    var deleted = true;
    try {
      await db.routinesDao.deleteRoutine(routineId);
    } catch (_) {
      deleted = false;
    }
    if (!deleted) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: "Couldn't delete that routine. Try again.",
      );
      return;
    }
    router.pop();

    showUndoableDelete(
      messenger: messenger,
      label: 'Routine deleted',
      onUndo: () async {
        await db.routinesDao.restoreRoutine(data);
      },
    );
  }

  Future<void> _onRefresh() async {
    ref.invalidate(routineDetailProvider(widget.routineId));
    ref.invalidate(routineDailyVolumeProvider);
    ref.invalidate(routineLastSetsProvider(widget.routineId));
  }

  // ── Build ────────────────────────

  @override
  Widget build(BuildContext context) {
    final routineAsync = ref.watch(routineDetailProvider(widget.routineId));
    return routineAsync.when(
      loading: _buildSkeleton,
      error: (_, __) => _buildError(),
      data: (routine) =>
          routine == null ? _buildNotFound() : _buildLoaded(routine),
    );
  }

  Widget _buildLoaded(HydratedRoutineDetail routine) {
    final lastSetsAsync = ref.watch(routineLastSetsProvider(widget.routineId));
    final isPremium = ref.watch(isPremiumProvider);
    final unit = ref.watch(weightUnitProvider);
    final sessionStats =
        ref.watch(routineSessionStatsProvider(widget.routineId)).valueOrNull;

    final lastSetsMap =
        lastSetsAsync.valueOrNull ?? const <String, List<LastSessionSetData>>{};
    final isLoadingHistory =
        lastSetsAsync.isLoading && lastSetsAsync.valueOrNull == null;

    final exerciseCount = routine.exercises.length;
    final lastDate = ref.watch(
        routineDailyVolumeProvider((widget.routineId, '6M')).select(
            (asyncVal) =>
                asyncVal.valueOrNull == null || asyncVal.valueOrNull!.isEmpty
                    ? null
                    : asyncVal.valueOrNull!.last.day));
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final surface = context.surface;

    final seen = <int>{};
    final heroEnabledList = <bool>[];
    for (final exercise in routine.exercises) {
      heroEnabledList.add(seen.add(exercise.exercise.id));
    }

    final tourStep = ref.watch(firstRunTourProvider);

    final scaffold = Scaffold(
      backgroundColor: surface.bgBase,
      body: AdaptiveContent(
          child: AppRefreshIndicator(
        onRefresh: _onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _appBar(routine),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$exerciseCount exercise${exerciseCount != 1 ? 's' : ''}'
                      '${lastDate != null ? ' · Last performed ${relativeDay(lastDate)}' : ''}',
                      style: AppText.meta(),
                    ),
                    if (sessionStats != null && sessionStats.count > 0) ...[
                      const SizedBox(height: 16),
                      _HeroStatStrip(stats: sessionStats, unit: unit),
                    ],
                    const SizedBox(height: 12),
                    _MusclesWorkedStrip(routine: routine),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _RoutineVolumeSection(
                  routineId: widget.routineId,
                  isPremium: isPremium,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final exercise = routine.exercises[index];
                    final sets = lastSetsMap[exercise.exercise.id.toString()];
                    return RoutineExerciseBlock(
                      hydratedExercise: exercise,
                      lastSets: sets,
                      unit: unit,
                      onTap: () {
                        if (!tapGuard()) return;
                        HapticFeedback.selectionClick();
                        context.push(
                          '/exercise/detail/${exercise.exercise.id}',
                          extra: exercise.exercise,
                        );
                      },
                      isLoadingHistory: isLoadingHistory,
                      isLast: index == routine.exercises.length - 1,
                      enableHero: heroEnabledList[index],
                    );
                  },
                  childCount: routine.exercises.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: SecondaryButton(
                  label: 'Add Exercise',
                  icon: Icons.add_rounded,
                  onPressed: _addExercise,
                ),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: 80 + bottomInset)),
          ],
        ),
      )),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Semantics(
            button: true,
            label: routine.exercises.isEmpty
                ? 'Add an exercise to start'
                : 'Start Routine',
            child: _StartRoutineButton(
              key: _startRoutineButtonKey,
              empty: routine.exercises.isEmpty,
              onTap: () => _startRoutine(routine),
            ),
          ),
        ),
      ),
    );

    if (tourStep == 2) {
      return Stack(
        children: [
          scaffold,
          SpotlightTourOverlay(
            targetKey: _startRoutineButtonKey,
            title: 'Your program',
            description:
                'This is your training hub — exercises, sets, and your personal '
                'records all live here. Tap Next to finish setup.',
            step: 2,
          ),
        ],
      );
    }

    return scaffold;
  }

  Widget _appBar(HydratedRoutineDetail routine) {
    final surface = context.surface;
    return SliverAppBar(
      pinned: true,
      toolbarHeight: 56,
      backgroundColor: surface.bgBase,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      centerTitle: false,
      title: Text(
        routine.routine.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // S3: text-depth shadow on routine detail title
        style: AppText.sectionHeading(shadows: AppText.depthFor(context)),
      ),
      leading: IconButton(
        tooltip: 'Back',
        icon: Icon(Icons.arrow_back_rounded,
            size: 24, color: surface.textPrimary),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: () => context.pop(),
      ),
      actions: [
        // S13: standardized to more_horiz_rounded + showActionBottomSheet
        IconButton(
          tooltip: 'More options',
          icon: Icon(Icons.more_horiz_rounded,
              size: 24, color: surface.textPrimary),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => _showActions(routine),
        ),
      ],
    );
  }

  // ── Loading / error / not-found ────────────────────────

  Widget _buildSkeleton() {
    final surface = context.surface;
    return SkeletonPulse(
      label: 'Loading this routine',
      child: Scaffold(
        backgroundColor: surface.bgBase,
        body: AdaptiveContent(
            child: CustomScrollView(
          physics: const NeverScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              toolbarHeight: 56,
              backgroundColor: surface.bgBase,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              elevation: 0,
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              title: const SizedBox.shrink(),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SkeletonBox(width: 200, height: 16),
                    const SizedBox(height: 16),
                    // Matches the ~46dp muscle load bar (8 bar + legend),
                    // not the old 44dp chip strip or the ~400dp inline map.
                    const SkeletonBox(height: 46, radius: AppRadius.badge),
                    const SizedBox(height: 24),
                    const SkeletonBox(height: 198, radius: AppRadius.card),
                    const SizedBox(height: 24),
                    ...List.generate(
                      3,
                      (i) => const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: SkeletonBox(height: 120, radius: AppRadius.card),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        )),
        bottomNavigationBar: const SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: SkeletonBox(height: 52, radius: AppRadius.buttonPrimary),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    final surface = context.surface;
    return Scaffold(
      backgroundColor: surface.bgBase,
      appBar: AppBar(
        backgroundColor: surface.bgBase,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: surface.textPrimary),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => context.pop(),
        ),
      ),
      body: AdaptiveContent(
          child: AsyncErrorState(
        message: "Couldn't load this routine.",
        onRetry: _onRefresh,
      )),
    );
  }

  Widget _buildNotFound() {
    return const AppNotFoundScreen(
      title: 'Routine not found',
      message: 'It may have been deleted.',
    );
  }
}

({Set<String> primary, Set<String> secondary}) _workedGroupsForRoutine(
    HydratedRoutineDetail routine) {
  final primary = <String>{};
  final secondary = <String>{};
  for (final he in routine.exercises) {
    final ex = he.exercise;
    final sec =
        (jsonDecode(ex.secondaryMuscles ?? '[]') as List).cast<String>();
    final groups = workedGroupsFor(target: ex.target, secondary: sec);
    primary.addAll(groups.primary);
    secondary.addAll(groups.secondary);
  }
  secondary.removeAll(primary);
  return (primary: primary, secondary: secondary);
}

/// Ranked load shares for the [MuscleLoadBar]: each group's share of the
/// routine's working sets. Primary groups score full set count, secondaries
/// half (assistance work is real but not equal) — deterministic, so the bar
/// never reshuffles between builds.
List<MuscleLoadEntry> _loadEntriesForRoutine(HydratedRoutineDetail routine) {
  final groups = _workedGroupsForRoutine(routine);
  final load = <String, double>{};
  for (final he in routine.exercises) {
    final ex = he.exercise;
    final sec =
        (jsonDecode(ex.secondaryMuscles ?? '[]') as List).cast<String>();
    final worked = workedGroupsFor(target: ex.target, secondary: sec);
    final setCount = he.config.defaultSets.toDouble();
    for (final g in worked.primary) {
      load[g] = (load[g] ?? 0) + setCount;
    }
    for (final g in worked.secondary) {
      if (!groups.primary.contains(g)) {
        load[g] = (load[g] ?? 0) + setCount * 0.5;
      }
    }
  }
  final total = load.values.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return const [];
  final sorted = load.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final e in sorted) MuscleLoadEntry(e.key, e.value / total),
  ];
}

/// Muscle coverage as one glanceable [MuscleLoadBar]: proportion of working
/// sets per group, not a scrolling membership list. Tap → full map sheet.
class _MusclesWorkedStrip extends ConsumerWidget {
  final HydratedRoutineDetail routine;
  const _MusclesWorkedStrip({required this.routine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = _workedGroupsForRoutine(routine);
    final entries = _loadEntriesForRoutine(routine);
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final gender =
        ref.watch(currentUserProfileProvider).valueOrNull?.gender ?? 'male';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MuscleLoadBar(
        entries: entries,
        primaryGroups: groups.primary,
        secondaryGroups: groups.secondary,
        gender: gender,
      ),
    );
  }
}

class _RoutineVolumeSection extends ConsumerStatefulWidget {
  final String routineId;
  final bool isPremium;

  const _RoutineVolumeSection({
    required this.routineId,
    required this.isPremium,
  });

  @override
  ConsumerState<_RoutineVolumeSection> createState() =>
      _RoutineVolumeSectionState();
}

class _RoutineVolumeSectionState extends ConsumerState<_RoutineVolumeSection> {
  String _selectedTimeRange = '6M';

  @override
  Widget build(BuildContext context) {
    final volumeAsync = ref.watch(
        routineDailyVolumeProvider((widget.routineId, _selectedTimeRange)));
    final allSamples = volumeAsync.valueOrNull ?? const <DailyVolumeSample>[];
    final visible = gateChartSamples(allSamples, widget.isPremium);
    final hasTrend = allSamples.length >= 2;
    // Volume is stored in kg; the chart and this header must both speak the
    // user's unit. Watched here rather than passed down because this section
    // is already a ConsumerStatefulWidget.
    final unit = ref.watch(weightUnitProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Semantics(
                header: true,
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Total Volume ', style: AppText.cardTitle()),
                    TextSpan(
                        text: '(${unitLabel(unit)})', style: AppText.meta()),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (hasTrend)
              Row(
                children: [
                  if (!widget.isPremium && allSamples.length > 3)
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: ProLockPill(label: 'FULL HISTORY'),
                    ),
                  TimeRangeFilter(
                    value: _selectedTimeRange,
                    onChanged: (range) =>
                        setState(() => _selectedTimeRange = range),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        RepaintBoundary(
          child: volumeAsync.when(
            loading: () => const SkeletonPulse(
              label: 'Loading volume chart',
              child: SkeletonBox(
                height: 198,
                radius: AppRadius.card,
              ),
            ),
            // A failed load must never render as a zeroed chart — that looks
            // identical to "you did nothing this period" and lies about the
            // user's data. Show an error state with a real retry instead.
            error: (_, __) => AsyncErrorState(
              message: "Couldn't load your volume history. Your data is safe.",
              onRetry: () => ref.invalidate(routineDailyVolumeProvider(
                  (widget.routineId, _selectedTimeRange))),
            ),
            data: (_) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: RoutineVolumeGraph(
                key: ValueKey('$_selectedTimeRange${visible.length}'),
                data: visible,
                unit: unit,
              ),
            ),
          ),
        ),
        _RoutineProgressPill(samples: visible),
        const SizedBox(height: 28),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
// Sub-widgets
// ═══════════════════════════════════════════════

class _HeroStatStrip extends StatelessWidget {
  final RoutineSessionStats stats;

  /// Active weight unit ('kg' | 'lbs'). BEST/AVG are aggregate volumes stored
  /// in kilograms, so both the value and the column label depend on it.
  final String unit;

  const _HeroStatStrip({required this.stats, required this.unit});

  @override
  Widget build(BuildContext context) {
    // .toDouble() so this is correct whether RoutineSessionStats exposes the
    // aggregates as int or double.
    final label = unitLabel(unit).toUpperCase();
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
              child: _HeroStat(
                  value: '${stats.count}',
                  label: 'SESSIONS',
                  shadows: AppText.depthFor(context))),
          const _StatDivider(),
          Expanded(
              child: _HeroStat(
                  value: groupThousands(
                      kgToDisplay(stats.bestVolumeKg.toDouble(), unit)),
                  label: 'BEST $label',
                  shadows: AppText.depthFor(context))),
          const _StatDivider(),
          Expanded(
              child: _HeroStat(
                  value: groupThousands(
                      kgToDisplay(stats.avgVolumeKg.toDouble(), unit)),
                  label: 'AVG $label',
                  shadows: AppText.depthFor(context))),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 26, color: context.surface.borderSubtle);
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  final List<Shadow>? shadows;
  const _HeroStat({required this.value, required this.label, this.shadows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: AppText.heroStat(shadows: shadows), maxLines: 1),
        ),
        const SizedBox(height: 3),
        Text(label,
            style: AppText.columnHeader(color: context.surface.textSecondary)),
      ],
    );
  }
}

class _StartRoutineButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool empty;

  const _StartRoutineButton({
    super.key,
    required this.onTap,
    required this.empty,
  });

  void _onTap() {
    // Dominant launchpad CTA → heavy impact for the real start; light when the
    // routine is empty (the tap just routes to the editor).
    if (empty) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    final accent = context.accent;
    return PressableScale(
      child: GestureDetector(
        onTap: _onTap,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: empty ? surface.surface3 : accent.base,
            borderRadius: AppRadius.buttonPrimaryAll,
          ),
          // TEXT SCALING: no fixed `height:` — the shell enforces the 52dp
          // floor as a row child that can grow, and the label sits in
          // Flexible+ellipsis (ship-readiness #3).
          child: AppButtonShell(
            label: empty ? 'Add an exercise' : 'Start Routine',
            style: AppText.button(
                color: empty ? surface.textSecondary : accent.onAccent),
            icon: empty ? Icons.add_rounded : Icons.play_arrow_rounded,
            iconSize: 22,
            iconColor: empty ? surface.textSecondary : accent.onAccent,
            minHeight: 52,
          ),
        ),
      ),
    );
  }
}

class _RoutineProgressPill extends StatelessWidget {
  final List<DailyVolumeSample> samples;

  const _RoutineProgressPill({required this.samples});

  @override
  Widget build(BuildContext context) {
    if (samples.length < 2) return const SizedBox.shrink();

    final first = samples.first.volume;
    final latest = samples.last.volume;
    if (first == 0) return const SizedBox.shrink();

    // Percentage delta — unit-invariant by construction, so no conversion is
    // needed here even though the underlying samples are in kilograms.
    final delta = ((latest - first) / first * 100).round();
    final isUp = delta >= 0;
    final surface = context.surface;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: surface.surface3,
            borderRadius: AppRadius.badgeAll,
            border: Border.all(
              color: surface.borderSubtle,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 14,
                color: surface.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                isUp
                    ? 'Volume up $delta% since ${_monthDay.format(samples.first.day)}'
                    : 'Volume down ${-delta}% since ${_monthDay.format(samples.first.day)}',
                style: AppText.statLabel(color: surface.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
