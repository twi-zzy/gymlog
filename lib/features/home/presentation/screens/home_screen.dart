import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/features/routines/presentation/widgets/routine_detail_styles.dart';
import 'package:gymlog/shared/widgets/ui/tracker_card.dart';
import 'package:gymlog/shared/widgets/ui/primary_button.dart';
import 'package:gymlog/shared/widgets/ui/action_bottom_sheet.dart';
import 'package:gymlog/shared/widgets/ui/app_dialog.dart';
import 'package:gymlog/shared/widgets/ui/skeleton.dart';
import 'package:gymlog/features/workout/presentation/providers/active_workout_provider.dart';
import 'package:gymlog/features/workout/presentation/providers/workout_actions_provider.dart';
import 'package:gymlog/features/home/presentation/providers/home_provider.dart';
import 'package:gymlog/features/home/presentation/widgets/workout_history_card.dart';
import 'package:gymlog/features/profile/presentation/providers/profile_stats_provider.dart';
import 'package:gymlog/core/utils/formatters.dart';
import 'package:gymlog/core/database/database.dart';
import 'package:gymlog/core/providers/database_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(workoutHistoryProvider);
    final notifier = ref.read(workoutHistoryProvider.notifier);
    final totalItems = historyState.items.length;

    // ── Initial load: skeleton feed (no spinner, no layout jump) ─────────
    if (historyState.isInitialLoad) {
      return Scaffold(
        backgroundColor: AppColors.bgBase,
        appBar: _appBar(),
        body: SkeletonPulse(
          child: ListView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: const [
              SkeletonBox(height: 124, radius: 12),
              SizedBox(height: 16),
              SkeletonBox(width: 150, height: 18),
              SizedBox(height: 12),
              WorkoutHistoryCardSkeleton(),
              SizedBox(height: 8),
              WorkoutHistoryCardSkeleton(),
              SizedBox(height: 8),
              WorkoutHistoryCardSkeleton(),
            ],
          ),
        ),
      );
    }

    // itemCount: [QuickStart] + [Header+WeekStrip] + [N cards] + [footer]
    final itemCount = 2 + totalItems + 1;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: _appBar(),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          // ── 0: Quick Start card ──────────────────────────────────────────
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: RDStyles.cardGradient,
                  borderRadius: BorderRadius.circular(12),
                  border: RDStyles.hairlineBorder,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Start',
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    PrimaryButton(
                      label: 'Start Empty Workout',
                      onPressed: () {
                        ref.read(activeWorkoutProvider.notifier).startWorkout();
                        context.push('/workout/active');
                      },
                      icon: Icons.add_circle_outline,
                    ),
                  ],
                ),
              ),
            );
          }

          // ── 1: Section header + week-at-a-glance ─────────────────────────
          if (index == 1) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'Workout History',
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const _WeekStrip(),
                ],
              ),
            );
          }

          final historyIndex = index - 2;

          // ── 3..N+2: History cards ────────────────────────────────────────
          if (historyIndex < totalItems) {
            // Trigger next-page fetch when within 3 items of the end
            if (historyIndex >= totalItems - 3 &&
                historyState.hasMore &&
                !historyState.isLoadingMore) {
              Future.microtask(() => notifier.fetchNextPage());
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: WorkoutHistoryCard(
                key: ValueKey(historyState.items[historyIndex].session.id),
                preview: historyState.items[historyIndex],
                onMenuPressed: () => _showWorkoutCardMenu(
                  context,
                  ref,
                  historyState.items[historyIndex].session,
                ),
              ),
            );
          }

          // ── Footer (loading | empty | all caught up) ─────────────────────
          if (historyState.isLoadingMore) {
            return const Padding(
              padding: EdgeInsets.only(top: 4),
              child: SkeletonPulse(child: WorkoutHistoryCardSkeleton()),
            );
          }

          if (totalItems == 0) {
            return TrackerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No workouts yet',
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Your history lives here. Start your first workout above.',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'All caught up',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  AppBar _appBar() => AppBar(
        title: Text(
          'Home',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 28,
            letterSpacing: -0.5,
          ),
        ),
      );

  void _showWorkoutCardMenu(
    BuildContext context,
    WidgetRef ref,
    WorkoutSession session,
  ) {
    final name = getWorkoutNameFallback(session.startedAt, session.name);

    showActionBottomSheet(
      context: context,
      title: name,
      items: [
        ActionSheetItem(
          icon: Icons.edit_outlined,
          iconColor: AppColors.textSecondary,
          iconBackground: AppColors.bgBase,
          title: 'Edit Workout',
          onTap: (sheetContext) async {
            Navigator.of(sheetContext).pop();
            final db = ref.read(databaseProvider);
            final hydrated =
                await db.workoutsDao.getHydratedWorkout(session.id);
            if (hydrated == null) return;
            if (!context.mounted) return;
            HapticFeedback.selectionClick();
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
          onTap: (sheetContext) async {
            Navigator.of(sheetContext).pop();
            final confirmed = await showAppConfirmDialog(
              context: context,
              title: 'Delete Workout?',
              message:
                  'This workout will be permanently removed from your history.',
              confirmLabel: 'Delete',
              isDestructive: true,
            );
            if (confirmed) {
              await ref
                  .read(workoutActionsProvider.notifier)
                  .deleteSession(session.id);
            }
          },
        ),
      ],
    );
  }
}

/// Week-at-a-glance chip living inside the Workout History header — clear
/// hierarchy, no orphaned strips. Hidden until the first completed workout.
class _WeekStrip extends ConsumerWidget {
  const _WeekStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakStatsProvider);
    final goal = ref.watch(weeklyGoalProvider);

    if (streak.currentStreak == 0 && streak.workoutsThisWeek == 0) {
      return const SizedBox.shrink();
    }

    final goalMet = streak.workoutsThisWeek >= goal;

    // Goal-met is shown on screen by icon COLOR alone; give screen readers a
    // single spoken summary and hide the fragmented row pieces.
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'This week: ${streak.workoutsThisWeek} of $goal workouts'
          '${goalMet ? ', goal met' : ''}'
          '${streak.currentStreak > 0 ? '. ${streak.currentStreak} day streak' : ''}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
        if (streak.currentStreak > 0) ...[
          const Icon(Icons.local_fire_department_rounded,
              size: 14, color: Color(0xFFFF9F0A)),
          const SizedBox(width: 3),
          Text(
            '${streak.currentStreak}',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            '  ·  ',
            style:
                GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
        Icon(
          goalMet ? Icons.check_circle_rounded : Icons.flag_rounded,
          size: 13,
          color: goalMet ? AppColors.success : AppColors.textSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          '${streak.workoutsThisWeek}/$goal',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: goalMet ? AppColors.success : AppColors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        ],
      ),
    );
  }
}
