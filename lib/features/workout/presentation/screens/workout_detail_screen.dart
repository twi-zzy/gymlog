import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/utils/formatters.dart';
import 'package:gymlog/core/database/daos/workouts_dao.dart';
import 'package:gymlog/core/database/database.dart';
import 'package:gymlog/core/providers/database_provider.dart';
import 'package:gymlog/shared/widgets/async_error_state.dart';
import 'package:gymlog/shared/widgets/exercise_gif_widget.dart';
import 'package:gymlog/features/routines/presentation/widgets/routine_detail_styles.dart';
import 'package:gymlog/shared/widgets/ui/action_bottom_sheet.dart';
import 'package:gymlog/shared/widgets/ui/app_dialog.dart';
import '../providers/workout_detail_provider.dart';
import '../providers/workout_actions_provider.dart';
import '../providers/active_workout_provider.dart';

// ── Local design tokens (strictly mirrors AppColors) ─────────────────────────
const _kAccentPos = AppColors.success;

/// [workout_detail_screen.dart]
/// Premium OLED workout detail screen.
///
/// Component tree (top → bottom):
///   SliverAppBar          → Hero Zone: name + 3-pip metrics strip
///   SliverToBoxAdapter    → Muscle Split progress bar
///   SliverList            → Exercise cards with animated GIFs + set rows
class WorkoutDetailScreen extends ConsumerWidget {
  final String sessionId;
  const WorkoutDetailScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workoutAsync = ref.watch(workoutDetailProvider(sessionId));

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: workoutAsync.when(
        loading: _buildLoading,
        error: (e, _) => _buildError(context, ref),
        data: (workout) {
          if (workout == null) return _buildNotFound();
          return _buildScrollView(context, ref, workout);
        },
      ),
    );
  }

  // ── State shells ─────────────────────────────────────────────────────────────

  Widget _buildLoading() => const Scaffold(
        backgroundColor: AppColors.bgBase,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.accentPrimary,
            strokeWidth: 2,
          ),
        ),
      );

  Widget _buildError(BuildContext context, WidgetRef ref) => Scaffold(
        backgroundColor: AppColors.bgBase,
        appBar: AppBar(
          backgroundColor: AppColors.bgBase,
          scrolledUnderElevation: 0,
          leading: const BackButton(color: AppColors.textPrimary),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accentPrimary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cloud_off_rounded,
                      color: Color(0xFF00C4A0), size: 24),
                ),
                const SizedBox(height: 16),
                Text(
                  "Couldn't load this workout",
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your data is safe on this device. Give it another try.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                Material(
                  color: AppColors.accentPrimary,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref.invalidate(workoutDetailProvider(sessionId));
                    },
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      alignment: Alignment.center,
                      child: Text(
                        'Retry',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildNotFound() => const AppNotFoundScreen(
        title: 'Workout not found',
        message: 'It may have been deleted.',
      );

  // ── Main scroll view ─────────────────────────────────────────────────────────

  Widget _buildScrollView(
    BuildContext context,
    WidgetRef ref,
    HydratedWorkout workout,
  ) {
    final session = workout.session;
    final name = getWorkoutNameFallback(session.startedAt, session.name);
    final durationStr =
        formatWorkoutDuration(session.startedAt, session.endedAt);
    final totalSets =
        workout.exercises.fold<int>(0, (s, e) => s + e.sets.length);
    final volumeStr = _formatVolume(session.totalVolumeKg);

    // Format date string: "Mon, 5 Jun 2026"
    final dt = session.startedAt;
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final dateStr =
        '${weekdays[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';

    // Muscle split — sets-per-target share, sums to 100%
    final muscleSetCounts = <String, int>{};
    for (final ex in workout.exercises) {
      final target = ex.exerciseMetadata.target;
      muscleSetCounts[target] = (muscleSetCounts[target] ?? 0) + ex.sets.length;
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // 1 ── Hero Zone ──────────────────────────────────────────────────────
        _HeroSliver(
          name: name,
          dateStr: dateStr,
          durationStr: durationStr,
          volumeStr: volumeStr,
          totalSets: totalSets,
          onMoreTap: () => _showActions(context, ref, workout),
        ),

        // 2 ── Muscle Split ───────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _MuscleSplitSection(
            muscleSetCounts: muscleSetCounts,
          ),
        ),

        // Spacer before list
        const SliverToBoxAdapter(child: SizedBox(height: 12)),

        // 3 ── Exercise List ──────────────────────────────────────────────────
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _DetailExerciseCard(
              key: ValueKey(workout.exercises[i].workoutExercise.id),
              hydratedExercise: workout.exercises[i],
            ),
            childCount: workout.exercises.length,
          ),
        ),

        // Bottom safe-area padding
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  static String _formatVolume(double kg) {
    final rounded = kg.round();
    if (rounded >= 1000) {
      final t = rounded ~/ 1000;
      final h = (rounded % 1000).toString().padLeft(3, '0');
      return '$t,$h kg';
    }
    return '$rounded kg';
  }

  void _saveAsRoutine(
    BuildContext context,
    WidgetRef ref,
    HydratedWorkout workout,
  ) async {
    final defaultName = '${workout.session.name ?? 'Custom'} Routine';
    await ref
        .read(workoutActionsProvider.notifier)
        .saveWorkoutAsRoutine(workout, defaultName);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved as "$defaultName"',
            style: GoogleFonts.inter(color: AppColors.textPrimary),
          ),
          backgroundColor: AppColors.bgSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showActions(
    BuildContext context,
    WidgetRef ref,
    HydratedWorkout workout,
  ) {
    final title = getWorkoutNameFallback(
      workout.session.startedAt,
      workout.session.name,
    );

    showActionBottomSheet(
      context: context,
      title: title,
      items: [
        ActionSheetItem(
          icon: Icons.bookmark_outline_rounded,
          iconColor: AppColors.accentPrimary,
          iconBackground: AppColors.accentPrimary.withValues(alpha: 0.12),
          title: 'Save as Template',
          subtitle: 'Add to your routine library',
          onTap: (sheetContext) {
            Navigator.of(sheetContext).pop();
            _saveAsRoutine(context, ref, workout);
          },
        ),
        ActionSheetItem(
          icon: Icons.edit_outlined,
          iconColor: AppColors.textSecondary,
          iconBackground: AppColors.bgBase,
          title: 'Edit Workout',
          subtitle: 'Rename or adjust notes',
          onTap: (sheetContext) async {
            Navigator.of(sheetContext).pop();
            final db = ref.read(databaseProvider);
            final hydrated =
                await db.workoutsDao.getHydratedWorkout(workout.session.id);
            if (hydrated == null) return;
            if (!context.mounted) return;
            HapticFeedback.lightImpact();
            ref.read(activeWorkoutProvider.notifier).loadForEdit(hydrated);
            context.push('/workout/active');
          },
        ),
        ActionSheetItem(
          icon: Icons.delete_outline_rounded,
          iconColor: AppColors.error,
          iconBackground: AppColors.error.withValues(alpha: 0.12),
          title: 'Delete Workout',
          titleColor: AppColors.error,
          subtitle: 'This cannot be undone',
          subtitleColor: AppColors.error.withValues(alpha: 0.7),
          onTap: (sheetContext) {
            Navigator.of(sheetContext).pop();
            _confirmDelete(context, ref);
          },
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Delete Workout?',
      message: 'This workout will be permanently removed from your history.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await ref.read(workoutActionsProvider.notifier).deleteSession(sessionId);
    if (context.mounted) context.pop();
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 1. Hero Sliver — Architectural Two-Stage Header
// ══════════════════════════════════════════════════════════════════════════════
//
// Tree structure (strict):
//   SliverAppBar [NO title prop]
//   └─ FlexibleSpaceBar [CollapseMode.parallax, centerTitle: false]
//      ├─ title  → Text(name) — THE ONLY INSTANCE. Flutter animates this alone.
//      └─ background → metrics Row at Align.bottomLeft. No name widget here.
// ══════════════════════════════════════════════════════════════════════════════

class _HeroSliver extends StatelessWidget {
  final String name;
  final String dateStr;
  final String durationStr;
  final String volumeStr;
  final int totalSets;
  final VoidCallback onMoreTap;

  const _HeroSliver({
    required this.name,
    required this.dateStr,
    required this.durationStr,
    required this.volumeStr,
    required this.totalSets,
    required this.onMoreTap,
  });

  // Expanded height — toolbar + avatar row (52px) + metrics row (32px)
  // + top/bottom padding (20px each). Total: ~180.
  static const _kExpandedHeight = 180.0;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      stretch: false,
      forceElevated: true,
      scrolledUnderElevation: 0.8,
      backgroundColor: AppColors.bgBase,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      expandedHeight: _kExpandedHeight,
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(
          Icons.arrow_back_ios_new,
          size: 18,
          color: AppColors.textPrimary,
        ),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      // Three-dots lives in actions: so it stays reachable when the bar
      // COLLAPSES. It used to sit in the flexibleSpace background, which is
      // clipped on scroll — making the overflow menu unreachable once pinned.
      actions: [
        IconButton(
          tooltip: 'Workout options',
          icon: const Icon(Icons.more_horiz,
              size: 22, color: AppColors.textPrimary),
          onPressed: onMoreTap,
        ),
      ],
      flexibleSpace: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final top = constraints.maxHeight;
          final collapsedHeight =
              MediaQuery.paddingOf(context).top + kToolbarHeight;
          final isCollapsed = top <= collapsedHeight + 20;

          return FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            centerTitle: true,
            // ── SMALL TITLE (fades in when bar is fully collapsed) ────────────
            titlePadding: const EdgeInsetsDirectional.only(bottom: 16),
            title: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: isCollapsed ? 1.0 : 0.0,
              child: Text(
                name,
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // ── LARGE TITLE AREA (parallaxes up, never bleeds through top bar) ─
            background: Container(
              color: AppColors.bgBase,
              foregroundDecoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.borderSubtle),
                ),
              ),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Row: Avatar | Column(Title, Date) | Spacer | ThreeDots ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Avatar initial circle
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.accentPrimary
                                  .withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'W',
                                style: GoogleFonts.inter(
                                  color: AppColors.accentPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Column: Workout name + Date
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.inter(
                                    color: AppColors.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.4,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dateStr,
                                  style: GoogleFonts.inter(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // ── Metrics strip ─────────────────────────────────────────
                      Row(
                        children: [
                          Flexible(
                            child:
                                _HeroPip(value: durationStr, label: 'DURATION'),
                          ),
                          _HeroPip.dot,
                          Flexible(
                            // Disclosure: volume sums ALL completed sets,
                            // warm-ups included. Tap to reveal (tooltip).
                            child: Tooltip(
                              triggerMode: TooltipTriggerMode.tap,
                              showDuration: const Duration(seconds: 3),
                              message:
                                  'Volume = weight × reps across all completed '
                                  'sets, warm-ups included.',
                              child:
                                  _HeroPip(value: volumeStr, label: 'VOLUME'),
                            ),
                          ),
                          _HeroPip.dot,
                          Flexible(
                            child: _HeroPip(value: '$totalSets', label: 'SETS'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A single value + label pip used in the expanded hero background.
class _HeroPip extends StatelessWidget {
  final String value;
  final String label;

  const _HeroPip({required this.value, required this.label});

  // Reusable separator — kept const so it never allocates at runtime.
  static const dot = Padding(
    padding: EdgeInsets.symmetric(horizontal: 16),
    child: Text(
      '·',
      style: TextStyle(color: AppColors.borderSubtle, fontSize: 24),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 2. Muscle Split Section — single-line segmented proportional bar
// ══════════════════════════════════════════════════════════════════════════════
//
// One thin bar split into segments, one per target muscle. Each segment's
// width is its share of the session's total LOGGED sets (Expanded flex = set
// count), so the bar is exactly proportional to the real data — and the dot
// legend's % is computed from the same counts. (Reverted from the per-row
// card, whose bars were normalised to the leading muscle and therefore did
// not match their own percentages.)
// ══════════════════════════════════════════════════════════════════════════════

class _MuscleSplitSection extends StatelessWidget {
  /// Map of target muscle name → set count for this session.
  final Map<String, int> muscleSetCounts;

  const _MuscleSplitSection({required this.muscleSetCounts});

  @override
  Widget build(BuildContext context) {
    if (muscleSetCounts.isEmpty) return const SizedBox.shrink();

    // Dominant muscle leftmost.
    final sorted = muscleSetCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalSets = sorted.fold<int>(0, (s, e) => s + e.value);
    if (totalSets == 0) return const SizedBox.shrink();

    Color colorFor(int rank) => AppColors.muscleSplitPalette[
        rank.clamp(0, AppColors.muscleSplitPalette.length - 1)];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section label ─────────────────────────────────────────────────
          Text(
            'MUSCLE SPLIT',
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),

          // ── Legend: dot · muscle · % of total sets (Wrap never overflows) ──
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (var i = 0; i < sorted.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colorFor(i),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${sorted[i].key}  ${((sorted[i].value / totalSets) * 100).round()}%',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Single-line segmented bar — widths ∝ logged set counts ─────────
          // Color-only on screen → attach a spoken summary and hide the
          // decorative segments from screen readers (the text legend above
          // already carries the per-muscle breakdown visually).
          Semantics(
            label: 'Muscle split: '
                '${sorted.map((e) => '${e.key} ${((e.value / totalSets) * 100).round()} percent').join(', ')}',
            child: ExcludeSemantics(
              child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (var i = 0; i < sorted.length; i++)
                    Expanded(
                      // flex must be ≥ 1; stored set counts always are.
                      flex: sorted[i].value < 1 ? 1 : sorted[i].value,
                      child: Container(
                        margin: i < sorted.length - 1
                            ? const EdgeInsets.only(right: 1)
                            : EdgeInsets.zero,
                        color: colorFor(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 3. Exercise Card
// ══════════════════════════════════════════════════════════════════════════════

class _DetailExerciseCard extends StatelessWidget {
  final HydratedWorkoutExercise hydratedExercise;

  const _DetailExerciseCard({super.key, required this.hydratedExercise});

  @override
  Widget build(BuildContext context) {
    final exercise = hydratedExercise.exerciseMetadata;
    final sets = hydratedExercise.sets;
    final previousSets = hydratedExercise.previousSets;

    // Show VS PREV column only when this exercise has been logged before.
    // previousSets is empty on first appearance — column is hidden entirely.
    final hasPrevHistory = previousSets.isNotEmpty;

    return GestureDetector(
      onTap: () =>
          context.push('/exercise/detail/${exercise.id}', extra: exercise),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          // North-star surface: gradient + hairline, matching Routine cards.
          gradient: RDStyles.cardGradient,
          borderRadius: BorderRadius.circular(12),
          border: RDStyles.hairlineBorder,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card Header ────────────────────────────────────────────────
            _ExerciseCardHeader(exercise: exercise),

            const SizedBox(height: 12),

            // ── Column Labels ──────────────────────────────────────────────
            _SetTableHeader(hasPrevHistory: hasPrevHistory),

            const SizedBox(height: 4),

            // ── Set Rows ───────────────────────────────────────────────────
            ...sets.asMap().entries.map((entry) {
              final idx = entry.key;
              final set = entry.value;

              // Cross-session VS PREV: compare this set against the same set
              // index from the previous session. If the previous session had
              // fewer sets, prevSet is null and the row renders a dash.
              final prevSet =
                  idx < previousSets.length ? previousSets[idx] : null;

              return _DetailSetRow(
                setNumber: idx + 1,
                set: set,
                isAlternate: idx.isOdd,
                prevSet: prevSet,
                hasPrevHistory: hasPrevHistory,
                equipment: exercise.equipment,
              );
            }),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ── Card header with auto-playing GIF ────────────────────────────────────────

class _ExerciseCardHeader extends StatelessWidget {
  final Exercise exercise;

  const _ExerciseCardHeader({required this.exercise});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          // 52 × 52 animated GIF — ExerciseGifWidget handles caching,
          // placeholder, and fallback. Fully animated on detail screen.
          ExerciseGifWidget(
            gifUrl: exercise.gifUrl,
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.name,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (exercise.equipment.isNotEmpty)
                  Text(
                    exercise.equipment,
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Column label header ───────────────────────────────────────────────────────

class _SetTableHeader extends StatelessWidget {
  /// When true (exercise has prior history), the VS PREV column header is shown.
  /// When false (first-ever appearance), the column is hidden entirely.
  final bool hasPrevHistory;

  const _SetTableHeader({required this.hasPrevHistory});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _headerCell('SET', width: 64),
          const SizedBox(width: 12),
          _headerCell('WEIGHT & REPS'),
          const Spacer(),
          if (hasPrevHistory) _headerCell('VS PREV', align: TextAlign.right),
        ],
      ),
    );
  }

  static Widget _headerCell(
    String text, {
    double? width,
    TextAlign align = TextAlign.left,
  }) {
    final t = Text(
      text,
      textAlign: align,
      style: GoogleFonts.inter(
        color: AppColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
    return width != null ? SizedBox(width: width, child: t) : t;
  }
}

// ── Individual set row ────────────────────────────────────────────────────────

class _DetailSetRow extends StatelessWidget {
  final int setNumber;
  final WorkoutSet set;
  final bool isAlternate;

  /// The matching set from the most recent prior session.
  /// Null when the previous session had fewer sets than the current one.
  final WorkoutSet? prevSet;

  /// When true the VS PREV column space is reserved. When false the column
  /// is hidden (first-ever appearance of this exercise).
  final bool hasPrevHistory;
  final String? equipment;

  const _DetailSetRow({
    required this.setNumber,
    required this.set,
    required this.isAlternate,
    this.prevSet,
    required this.hasPrevHistory,
    this.equipment,
  });

  Widget _buildSetTypeIndicator() {
    final setType = set.setType.toLowerCase();

    switch (setType) {
      case 'warmup':
        return _buildPill(
          icon: Icons.local_fire_department,
          label: 'Warm',
          color: Colors.amber,
        );
      case 'dropset':
      case 'drop':
        return _buildPill(
          icon: Icons.trending_down,
          label: 'Drop',
          color: AppColors.accentPrimary,
        );
      case 'failure':
        return _buildPill(
          icon: Icons.warning_amber_rounded,
          label: 'Fail',
          color: AppColors.error,
        );
      case 'normal':
      default:
        return Text(
          '$setNumber',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: AppColors.textPrimary,
          ),
        );
    }
  }

  Widget _buildPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// Cross-session weight delta: positive = heavier than last time.
  /// Returns null when prevSet is absent or either weight is 0.
  double? get _crossSessionDelta {
    if (prevSet == null) return null;
    if (set.weightKg <= 0 || prevSet!.weightKg <= 0) return null;
    final d = set.weightKg - prevSet!.weightKg;
    return d == 0 ? null : d; // null suppresses the chip on equal weight
  }

  @override
  Widget build(BuildContext context) {
    // Alternate rows use bgSurface tinted slightly — achieved by painting
    // a low-opacity white overlay on top of the card's bgSurface base.
    final bg = isAlternate
        ? AppColors.textPrimary.withValues(alpha: 0.03)
        : Colors.transparent;

    final delta = _crossSessionDelta;

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          // ── Set identifier ───────────────────────────────────────────────
          SizedBox(
            width: 64,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildSetTypeIndicator(),
            ),
          ),
          const SizedBox(width: 12),

          // ── Weight × reps ────────────────────────────────────────────────
          Expanded(
            child: Row(
              children: [
                Text(
                  _formatWeight(set.weightKg, equipment),
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  ' × ',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${set.reps} reps',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (set.isPr) ...[
                  const SizedBox(width: 8),
                  const _PrBadge(),
                ],
              ],
            ),
          ),

          // ── VS PREV (cross-session) ───────────────────────────────────────
          // Column is fully absent when hasPrevHistory is false (first time).
          // When the previous session had fewer sets, prevSet is null →
          // render a dash so the column stays aligned.
          if (hasPrevHistory)
            delta != null
                ? _DeltaChip(delta: delta)
                : Text(
                    '—',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
        ],
      ),
    );
  }

  static String _formatWeight(double kg, String? equipment) {
    final isBw = equipment?.toLowerCase() == 'body weight';
    final prefix = (isBw && kg > 0) ? '+' : '';
    if (kg == kg.truncateToDouble()) return '$prefix${kg.toInt()} kg';
    return '$prefix${kg.toStringAsFixed(1)} kg';
  }
}

/// Muted tinted chip: `+2.5 kg` in green, `−2.5 kg` in secondary grey.
/// The sign is ALWAYS rendered — an unsigned grey "8 kg" reads as an
/// absolute value, not as the 8 kg regression it actually is.
class _DeltaChip extends StatelessWidget {
  final double delta;
  const _DeltaChip({required this.delta});

  @override
  Widget build(BuildContext context) {
    final isPositive = delta > 0;
    // Was grey-on-grey for negatives (~1.5:1, unreadable). Negative now uses
    // the warning token (a drop isn't an "error" — could be a deload — so amber,
    // not red); both states carry a directional arrow so the meaning survives
    // for color-blind users and a screen-reader label is attached.
    final color = isPositive ? _kAccentPos : AppColors.warning;
    final icon =
        isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
    final abs = delta.abs();
    final num = abs == abs.truncateToDouble()
        ? abs.toInt().toString()
        : abs.toStringAsFixed(1);

    return Semantics(
      label: '${isPositive ? 'Up' : 'Down'} $num kilograms from last time',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 2),
            Text(
              '$num kg',
              style: GoogleFonts.inter(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Amber trophy badge inline with PR sets.
class _PrBadge extends StatelessWidget {
  const _PrBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_rounded,
              size: 11, color: AppColors.warning),
          const SizedBox(width: 3),
          Text(
            'PR',
            style: GoogleFonts.inter(
              color: AppColors.warning,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
