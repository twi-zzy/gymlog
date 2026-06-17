import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/database/database.dart';
import 'package:gymlog/features/routines/presentation/widgets/routine_detail_styles.dart';
import 'package:gymlog/features/workout/domain/active_workout_state.dart';
import 'package:gymlog/shared/widgets/exercise_gif_widget.dart';
import 'package:gymlog/shared/widgets/ui/secondary_button.dart';
import 'package:gymlog/shared/widgets/ui/action_bottom_sheet.dart';
import 'set_row.dart';

/// One exercise inside the active workout. North-star surfaces: gradient
/// card + hairline, white heading (the accent is for actions, not titles),
/// swipe-to-delete sets, and the signature branded three-dot sheet with
/// reorder / replace / remove.
class ExerciseBlock extends StatelessWidget {
  final int exerciseIndex;
  final WorkoutExerciseState exercise;
  final Exercise? driftExercise;
  final String unit;

  /// Previous-session sets for this exercise, ordered by set index. Drives
  /// the PREVIOUS column. Empty when the exercise has no prior history.
  final List<WorkoutSet> previousSets;

  /// Opens the focus-safe reorder sheet. Null when there's only one
  /// exercise (nothing to reorder).
  final VoidCallback? onReorderExercises;
  final VoidCallback onRemove;
  final VoidCallback onReplace;

  /// Toggles kg/lbs for this exercise — invoked from the tappable unit in
  /// the column header (Hevy puts the unit in the header, not inline).
  final VoidCallback? onUnitTap;
  final VoidCallback onAddSet;
  final void Function(int setIndex) onRemoveSet;
  final ValueChanged<WorkoutSetState> onSetChanged;
  final void Function(int setIndex) onToggleSetCompletion;

  const ExerciseBlock({
    super.key,
    required this.exerciseIndex,
    required this.exercise,
    this.driftExercise,
    this.unit = 'kg',
    this.previousSets = const [],
    this.onReorderExercises,
    required this.onRemove,
    required this.onReplace,
    this.onUnitTap,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onSetChanged,
    required this.onToggleSetCompletion,
  });

  void _showMenu(BuildContext context) {
    showActionBottomSheet(
      context: context,
      title: exercise.name,
      items: [
        ActionSheetItem(
          icon: Icons.swap_horiz_rounded,
          iconColor: AppColors.textSecondary,
          iconBackground: AppColors.bgBase,
          title: 'Replace Exercise',
          onTap: (sheetContext) {
            Navigator.pop(sheetContext);
            onReplace();
          },
        ),
        if (onReorderExercises != null)
          ActionSheetItem(
            icon: Icons.swap_vert_rounded,
            iconColor: AppColors.textSecondary,
            iconBackground: AppColors.bgBase,
            title: 'Reorder Exercises',
            onTap: (sheetContext) {
              Navigator.pop(sheetContext);
              onReorderExercises!();
            },
          ),
        ActionSheetItem(
          icon: Icons.delete_outline_rounded,
          iconColor: AppColors.error,
          iconBackground: AppColors.error.withValues(alpha: 0.12),
          title: 'Remove Exercise',
          titleColor: AppColors.error,
          onTap: (sheetContext) {
            Navigator.pop(sheetContext);
            HapticFeedback.heavyImpact();
            onRemove();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final de = driftExercise;
    final gifUrl = de?.gifUrl;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        gradient: RDStyles.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: RDStyles.hairlineBorder,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 4, 0),
            child: Row(
              children: [
                if (gifUrl != null && gifUrl.isNotEmpty) ...[
                  RepaintBoundary(
                    child: ExerciseGifWidget(
                      gifUrl: gifUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      animate: false,
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: GestureDetector(
                    onTap: de != null
                        ? () =>
                            context.push('/exercise/detail/${de.id}', extra: de)
                        : null,
                    child: Text(
                      exercise.name,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Exercise options',
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(
                    Icons.more_horiz,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () => _showMenu(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Column labels — share SetRow's exact column geometry ─────
          // SET · PREVIOUS · KG · REPS · ✓. The unit lives HERE (Hevy
          // pattern), and the KG/LBS caption is the tappable per-exercise
          // unit toggle — there is no inline unit on the rows anymore.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                    width: kSetColW,
                    child: Text('SET', style: RDStyles.tableHeader)),
                Expanded(
                  flex: kPrevFlex,
                  child: Text('PREVIOUS', style: RDStyles.tableHeader),
                ),
                Expanded(
                  flex: kWeightFlex,
                  child: Center(
                    child: Semantics(
                      button: onUnitTap != null,
                      label: 'Weight unit ${unit.toUpperCase()}, tap to change',
                      child: GestureDetector(
                        onTap: onUnitTap == null
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                onUnitTap!();
                              },
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fitness_center_rounded,
                                size: 11, color: AppColors.chartAxisLabel),
                            const SizedBox(width: 3),
                            Text(unit.toUpperCase(),
                                style: RDStyles.tableHeader),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: kRepsFlex,
                  child:
                      Center(child: Text('REPS', style: RDStyles.tableHeader)),
                ),
                const SizedBox(
                  width: kCheckColW,
                  child: Center(
                    child: Icon(Icons.check_rounded,
                        size: 13, color: AppColors.chartAxisLabel),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // ── Sets — swipe left to delete (locked once completed) ──────
          ...exercise.sets.asMap().entries.map((entry) {
            final setIndex = entry.key;
            final setData = entry.value;
            // Previous-session baseline for this exact set index (if any).
            final prevSet =
                setIndex < previousSets.length ? previousSets[setIndex] : null;
            final row = SetRow(
              key: ValueKey(setData.id),
              setIndex: setIndex,
              setData: setData,
              previousWeight: prevSet?.weightKg,
              previousReps: prevSet?.reps,
              unit: unit,
              onChanged: onSetChanged,
              onToggleComplete: () => onToggleSetCompletion(setIndex),
            );
            // A completed set is a committed record — no accidental
            // swipe-away. Uncheck it first to delete or edit.
            if (setData.isCompleted) {
              return KeyedSubtree(
                  key: ValueKey('locked_${setData.id}'), child: row);
            }
            return Dismissible(
              key: ValueKey('dismiss_${setData.id}'),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) async {
                HapticFeedback.heavyImpact(); // feel the danger first
                return true;
              },
              onDismissed: (_) => onRemoveSet(setIndex),
              background: Container(
                color: AppColors.error.withValues(alpha: 0.85),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 22),
                child: const Icon(Icons.delete_outline_rounded,
                    color: Colors.white, size: 20),
              ),
              child: row,
            );
          }),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: SecondaryButton(
              label: '+ Add Set',
              onPressed: () {
                HapticFeedback.lightImpact();
                onAddSet();
              },
            ),
          ),
        ],
      ),
    );
  }
}
