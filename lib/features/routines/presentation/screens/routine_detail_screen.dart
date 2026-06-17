import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/daos/routines_dao.dart';
import '../../../../core/database/daos/workouts_dao.dart';
import '../../../../core/database/database.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/premium_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../features/exercises/presentation/screens/exercise_selection_screen.dart';
import '../../../../features/workout/domain/active_workout_state.dart';
import '../../../../features/workout/presentation/providers/active_workout_provider.dart';
import '../../../../shared/widgets/async_error_state.dart';
import '../../../../shared/widgets/premium_paywall.dart';
import '../../../../shared/widgets/ui/app_dialog.dart';
import '../../../../shared/widgets/ui/time_range_filter.dart';
import '../providers/routines_provider.dart';
import '../widgets/routine_detail_styles.dart';
import '../widgets/routine_exercise_block.dart';
import '../widgets/routine_volume_graph.dart';

/// Premium RoutineDetailScreen — matches the approved mockup.
///   - SliverAppBar, animated entry
///   - Hevy-style volume chart (the graph owns its own gradient card)
///   - Exercise blocks on pure black, no gray slab
///   - Purple-tint progress pill
class RoutineDetailScreen extends ConsumerStatefulWidget {
  final String routineId;

  const RoutineDetailScreen({super.key, required this.routineId});

  @override
  ConsumerState<RoutineDetailScreen> createState() =>
      _RoutineDetailScreenState();
}

class _RoutineDetailScreenState extends ConsumerState<RoutineDetailScreen>
    with TickerProviderStateMixin {
  String _selectedTimeRange = 'All Time';

  late final AnimationController _entryController;

  bool _entryStarted = false;

  @override
  void initState() {
    super.initState();
    // Responsive, not theatrical: 280ms total, stagger capped below.
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    // Forward is armed in didChangeDependencies, where MediaQuery (and thus the
    // reduce-motion flag) is safe to read.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entryStarted) return;
    _entryStarted = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _entryController.value = 1.0; // reduce-motion: show final state instantly
    } else {
      _entryController.forward();
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  String _relativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays < 1) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 14) return '1 week ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
    if (diff.inDays < 60) return '1 month ago';
    return '${(diff.inDays / 30).floor()} months ago';
  }

  void _startRoutine(HydratedRoutineDetail routine) {
    final exercises = routine.exercises.map((he) {
      final config = he.config;
      final sets = List.generate(
        config.defaultSets,
        (_) => WorkoutSetState(
          id: const Uuid().v4(),
          weightKg: config.defaultWeightKg ?? 0.0,
          reps: config.defaultReps ?? 0,
        ),
      );
      return WorkoutExerciseState(
        id: const Uuid().v4(),
        exerciseId: he.exercise.id,
        name: he.exercise.name,
        sets: sets.isEmpty ? [WorkoutSetState.create()] : sets,
      );
    }).toList();

    ref.read(activeWorkoutProvider.notifier).startWorkout(
          routineId: routine.routine.id,
          name: routine.routine.name,
          initialExercises: exercises,
        );
    context.push('/workout/active');
  }

  Future<void> _deleteRoutine(String routineId) async {
    final db = ref.read(databaseProvider);
    await db.routinesDao.deleteRoutine(routineId);
    if (!mounted) return;
    context.pop();
  }

  /// Opens the full routine editor (rename, add/remove/reorder exercises).
  void _openEditor() {
    HapticFeedback.selectionClick();
    context.push('/routines/edit?id=${widget.routineId}');
  }

  /// Appends an exercise to this routine in place — no editor round-trip.
  Future<void> _addExercise() async {
    HapticFeedback.lightImpact();
    final selected = await Navigator.push<Exercise>(
      context,
      MaterialPageRoute(builder: (_) => const ExerciseSelectionScreen()),
    );
    if (selected == null || !mounted) return;
    await ref
        .read(databaseProvider)
        .routinesDao
        .addExerciseToRoutine(widget.routineId, selected.id);
  }

  void _showActionsSheet(HydratedRoutineDetail routine) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A6A6A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      routine.routine.name,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(
                  color: Color(0x0DFFFFFF),
                  height: 1,
                  indent: 24,
                  endIndent: 24,
                ),
                _SheetActionRow(
                  icon: Icons.edit_outlined,
                  iconColor: const Color(0xFFB3B3B3),
                  iconBackground: AppColors.bgBase,
                  title: 'Edit Routine',
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _openEditor();
                  },
                ),
                const Divider(
                  color: Color(0x0DFFFFFF),
                  height: 1,
                  indent: 80,
                  endIndent: 24,
                ),
                _SheetActionRow(
                  icon: Icons.delete_outline_rounded,
                  iconColor: AppColors.error,
                  iconBackground: AppColors.error.withValues(alpha: 0.12),
                  title: 'Delete Routine',
                  titleColor: AppColors.error,
                  subtitle: 'This cannot be undone',
                  subtitleColor: AppColors.error.withValues(alpha: 0.7),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _confirmDelete(context, routine.routine.id);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String routineId) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Delete Routine?',
      message:
          'This routine will be permanently deleted. Your workout history stays.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirmed) await _deleteRoutine(routineId);
  }

  Future<void> _onRefresh() async {
    ref.invalidate(routineDetailProvider(widget.routineId));
    ref.invalidate(
        routineDailyVolumeProvider((widget.routineId, _selectedTimeRange)));
    ref.invalidate(routineLastSetsProvider(widget.routineId));
  }

  @override
  Widget build(BuildContext context) {
    final routineAsync = ref.watch(routineDetailProvider(widget.routineId));
    final volumeAsync = ref.watch(
      routineDailyVolumeProvider((widget.routineId, _selectedTimeRange)),
    );
    final lastSetsAsync = ref.watch(routineLastSetsProvider(widget.routineId));

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: routineAsync.when(
        loading: () => _buildSkeleton(),
        error: (_, __) => _buildError(),
        data: (routine) {
          if (routine == null) {
            return _buildNotFound();
          }
          return _buildScrollView(
            routine,
            volumeAsync,
            lastSetsAsync.valueOrNull ?? {},
            lastSetsAsync.isLoading && lastSetsAsync.valueOrNull == null,
          );
        },
      ),
    );
  }

  Widget _buildScrollView(
    HydratedRoutineDetail routine,
    AsyncValue<List<DailyVolumeSample>> volumeAsync,
    Map<String, List<LastSessionSetData>> lastSetsMap,
    bool isLoadingHistory,
  ) {
    final isPremium = ref.watch(isPremiumProvider);
    final lastDate = volumeAsync.valueOrNull?.isNotEmpty == true
        ? volumeAsync.valueOrNull!.last.day
        : null;
    final exerciseCount = routine.exercises.length;

    return NotificationListener<ScrollNotification>(
      onNotification: (_) => false,
      child: RefreshIndicator(
        color: AppColors.accentPrimary,
        backgroundColor: const Color(0xFF121212),
        onRefresh: _onRefresh,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── SliverAppBar ─────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              floating: false,
              snap: false,
              toolbarHeight: 56,
              backgroundColor: AppColors.bgBase,
              scrolledUnderElevation: 0,
              elevation: 0,
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              centerTitle: false,
              title: Text(
                routine.routine.name,
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              leading: SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(Icons.arrow_back_ios_new),
                  color: AppColors.textPrimary,
                  onPressed: () => context.pop(),
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Routine options',
                  icon: const Icon(Icons.more_vert_rounded, size: 24),
                  color: AppColors.textPrimary,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  splashRadius: 24,
                  onPressed: () => _showActionsSheet(routine),
                ),
              ],
            ),

            // ── Attribution + CTA ────────────────────────────────────────
            SliverToBoxAdapter(
              child: _entryFade(
                interval: const Interval(0.0, 0.3, curve: Curves.easeOutExpo),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$exerciseCount exercise${exerciseCount != 1 ? 's' : ''}${lastDate != null ? ' · Last performed ${_relativeTime(lastDate)}' : ''}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Singular, dominant primary action — editing lives
                      // in the three-dot sheet where it belongs.
                      Semantics(
                        button: true,
                        label: 'Start Routine',
                        child: _StartRoutineButton(
                          onTap: () => _startRoutine(routine),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),

            // ── Graph Section ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _entryFade(
                interval: const Interval(0.2, 0.45, curve: Curves.easeOutExpo),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text.rich(TextSpan(children: [
                            TextSpan(
                                text: 'Total Volume ',
                                style: RDStyles.sectionLabel),
                            TextSpan(text: '(kg)', style: RDStyles.sectionUnit),
                          ])),
                          Row(
                            children: [
                              if (!isPremium &&
                                  (volumeAsync.valueOrNull?.length ?? 0) > 3)
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
                      volumeAsync.when(
                        loading: () => Container(
                          height: 198,
                          decoration: BoxDecoration(
                            gradient: RDStyles.cardGradient,
                            borderRadius: BorderRadius.circular(20),
                            border: RDStyles.hairlineBorder,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.accentPrimary,
                            ),
                          ),
                        ),
                        error: (_, __) => const RoutineVolumeGraph(data: []),
                        data: (data) {
                          // Free tier: 3 most recent sessions as a teaser.
                          final visible = gateChartSamples(data, isPremium);
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: RoutineVolumeGraph(
                              key: ValueKey(
                                  '$_selectedTimeRange${visible.length}'),
                              data: visible,
                            ),
                          );
                        },
                      ),
                      volumeAsync.maybeWhen(
                        data: (data) => _RoutineProgressPill(
                            samples: gateChartSamples(data, isPremium)),
                        orElse: () => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),

            // ── Exercise List ────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final exercise = routine.exercises[index];
                    final exKey = exercise.exercise.id.toString();
                    final sets = lastSetsMap[exKey];
                    // Stagger only the first 3 items, capped — entry must
                    // feel responsive, not theatrical.
                    final delay = index.clamp(0, 3) * 0.05;
                    return _entryFade(
                      interval: Interval(
                        (0.35 + delay).clamp(0.0, 0.9),
                        (0.55 + delay).clamp(0.0, 1.0),
                        curve: Curves.easeOutExpo,
                      ),
                      child: RoutineExerciseBlock(
                        hydratedExercise: exercise,
                        lastSets: sets,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          context.push(
                            '/exercise/detail/${exercise.exercise.id}',
                            extra: exercise.exercise,
                          );
                        },
                        isLoadingHistory: isLoadingHistory,
                        isLast: index == routine.exercises.length - 1,
                      ),
                    );
                  },
                  childCount: routine.exercises.length,
                ),
              ),
            ),

            // ── Add Exercise ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Material(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _addExercise,
                    child: Container(
                      height: 50,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded,
                              color: Colors.white.withValues(alpha: 0.9),
                              size: 16),
                          const SizedBox(width: 9),
                          Text('Add Exercise', style: RDStyles.addBtn),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  /// Shared fade+slide entry transition wrapper.
  Widget _entryFade({required Interval interval, required Widget child}) {
    final curved = CurvedAnimation(parent: _entryController, curve: interval);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  Widget _buildSkeleton() {
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        const SliverAppBar(
          pinned: true,
          toolbarHeight: 56,
          backgroundColor: AppColors.bgBase,
          scrolledUnderElevation: 0,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          centerTitle: false,
          title: SizedBox.shrink(),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _skel(width: 200, height: 16, radius: 8),
                const SizedBox(height: 16),
                _skel(height: 56, radius: 16),
                const SizedBox(height: 24),
                _skel(height: 198, radius: 20),
                const SizedBox(height: 24),
                ...List.generate(
                  3,
                  (i) => const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: _SkelBox(height: 120, radius: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _skel({double? width, required double height, double radius = 12}) =>
      _SkelBox(width: width, height: height, radius: radius);

  Widget _buildError() {
    // A bare Center used to strand the user (no back button, "pull down to
    // retry" where pull didn't work). Now: an app bar back + a real retry.
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        scrolledUnderElevation: 0,
        leading: const BackButton(color: AppColors.textPrimary),
      ),
      body: AsyncErrorState(
        message: "Couldn't load this routine.",
        onRetry: _onRefresh,
      ),
    );
  }

  Widget _buildNotFound() {
    return const AppNotFoundScreen(
      title: 'Routine not found',
      message: 'It may have been deleted.',
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Sub-widgets
// ══════════════════════════════════════════════════════════════════════════════

class _SkelBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const _SkelBox({this.width, required this.height, this.radius = 12});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

class _StartRoutineButton extends StatefulWidget {
  final VoidCallback onTap;

  const _StartRoutineButton({required this.onTap});

  @override
  State<_StartRoutineButton> createState() => _StartRoutineButtonState();
}

class _StartRoutineButtonState extends State<_StartRoutineButton> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails _) => setState(() => _scale = 0.97);
  void _onTapUp(TapUpDetails _) => setState(() => _scale = 1.0);
  void _onTapCancel() => setState(() => _scale = 1.0);

  void _onTap() {
    HapticFeedback.mediumImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: _onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutQuint,
        child: Container(
          height: 54,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.accentPrimary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentPrimary.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
                spreadRadius: -6,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            // Tap is handled by the ancestor GestureDetector (which also drives
            // the press-scale). This InkWell previously ALSO had onTap: _onTap,
            // so a single tap fired the handler — and the haptic, and the
            // navigation — twice. With no callbacks the tap falls through to
            // the GestureDetector: exactly one fire. AnimatedScale is the press
            // feedback, so losing the ripple is intentional.
            child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                    Text('Start Routine', style: RDStyles.startBtn),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }
}

class _SheetActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final Color? titleColor;
  final String? subtitle;
  final Color? subtitleColor;
  final VoidCallback onTap;

  const _SheetActionRow({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    this.titleColor,
    this.subtitle,
    this.subtitleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: titleColor ?? AppColors.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: subtitleColor ?? const Color(0xFF6A6A6A),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
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

    final delta = ((latest - first) / first * 100).round();
    final isUp = delta >= 0;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accentPrimary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.accentPrimary.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 14,
                color: const Color(0xFFCBB2FF),
              ),
              const SizedBox(width: 6),
              Text(
                isUp
                    ? 'Volume up $delta% since ${DateFormat('MMM d').format(samples.first.day)}'
                    : 'Volume down ${-delta}% since ${DateFormat('MMM d').format(samples.first.day)}',
                style: RDStyles.deltaPill,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
