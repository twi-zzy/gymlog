import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gymlog/core/models/measurement_type.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/theme/app_text.dart';
import 'package:gymlog/features/workout/domain/active_workout_state.dart';
import 'package:gymlog/shared/widgets/ui/exercise_thumbnail.dart';
import 'package:gymlog/shared/widgets/exercise_hero_thumb.dart';
import 'package:gymlog/shared/widgets/ui/secondary_button.dart';
import 'package:gymlog/shared/widgets/ui/action_bottom_sheet.dart';
import 'package:gymlog/core/providers/settings_provider.dart';
import 'package:gymlog/features/workout/presentation/providers/active_workout_provider.dart';
import 'package:gymlog/features/workout/presentation/providers/previous_session_provider.dart';
import 'package:gymlog/features/exercises/presentation/providers/exercises_provider.dart';
import 'compact_rest_chip.dart';
import 'set_row.dart';
import 'set_table_layout.dart';

/// One exercise inside the active workout. Shared card surface (gradient +
/// hairline via AppCard), white heading (accent is for actions, not titles),
/// swipe-to-delete sets, and the branded three-dot sheet.
class ExerciseBlock extends ConsumerWidget {
  final int exerciseIndex;

  /// Opens the focus-safe reorder sheet. Null when there's only one exercise.
  final VoidCallback? onReorderExercises;
  final VoidCallback onRemove;
  final VoidCallback onReplace;

  /// Toggles kg/lbs for this exercise — invoked from the tappable column header.
  final VoidCallback? onUnitTap;
  final VoidCallback onAddSet;
  final void Function(int setIndex) onRemoveSet;
  final ValueChanged<WorkoutSetState> onSetChanged;
  final void Function(int setIndex) onToggleSetCompletion;
  final bool enableHero;

  const ExerciseBlock({
    super.key,
    required this.exerciseIndex,
    this.onReorderExercises,
    required this.onRemove,
    required this.onReplace,
    this.onUnitTap,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onSetChanged,
    required this.onToggleSetCompletion,
    this.enableHero = true,
  });

  void _showMenu(BuildContext context, String exerciseName) {
    final surface = context.surface;
    showActionBottomSheet(
      context: context,
      title: exerciseName,
      items: [
        ActionSheetItem(
          icon: Icons.swap_horiz_rounded,
          iconColor: surface.textSecondary,
          iconBackground: surface.bgBase,
          title: 'Replace Exercise',
          onTap: (sheetContext) {
            Navigator.pop(sheetContext);
            onReplace();
          },
        ),
        if (onReorderExercises != null)
          ActionSheetItem(
            icon: Icons.swap_vert_rounded,
            iconColor: surface.textSecondary,
            iconBackground: surface.bgBase,
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
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseMeta = ref.watch(activeWorkoutProvider.select((state) {
      if (state == null || exerciseIndex >= state.exercises.length) return null;
      final ex = state.exercises[exerciseIndex];
      // Include measurementType in the tuple so the column headers are always
      // accurate even before the catalog resolves (de == null).
      return (
        ex.exerciseId,
        ex.name,
        ex.sets.map((s) => s.id).join(','),
        ex.resolvedMeasurementType, // $4 — authoritative source
      );
    }));

    if (exerciseMeta == null) return const SizedBox.shrink();
    final surface = context.surface;

    final exerciseId = exerciseMeta.$1;
    final exerciseName = exerciseMeta.$2;
    final setIds =
        exerciseMeta.$3.isEmpty ? const <String>[] : exerciseMeta.$3.split(',');
    final MeasurementType mType = exerciseMeta.$4;

    final catalogById =
        ref.watch(exerciseCatalogByIdProvider).valueOrNull ?? {};
    final de = catalogById[exerciseId];

    final unit = ref.watch(exerciseUnitProvider(exerciseId));
    final previousSets =
        ref.watch(previousSessionSetsProvider(exerciseId)).valueOrNull ??
            const [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Container(
        decoration: BoxDecoration(
          color: surface.surface2,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.07),
            width: 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.fromLTRB(15, 15, 15, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: 48,
                  child: de != null
                      ? ExerciseHeroThumb(
                          exercise: de,
                          size: 48,
                          enableHero: enableHero,
                        )
                      : const ExerciseThumbnail(gifUrl: null, size: 48),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: de != null
                            ? () => context.push('/exercise/detail/${de.id}',
                                extra: de)
                            : null,
                        child: Text(
                          exerciseName,
                          style: AppText.sheetTitle(color: surface.textPrimary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: CompactRestChip(
                          exerciseIndex: exerciseIndex,
                          exerciseName: exerciseName,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox.square(
                  dimension: 48,
                  child: IconButton(
                    tooltip: 'Exercise options',
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_horiz_rounded,
                        color: surface.textSecondary, size: 20),
                    onPressed: () => _showMenu(context, exerciseName),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Column labels — the header is a SetTableRow, so its centre
            // lines are the data rows' centre lines BY CONSTRUCTION (they
            // share inset, widths and flex via set_table_layout.dart). The
            // 22dp minHeight stays a minimum: AppText.columnHeader (11sp)
            // needs ~29px at the 200% accessibility budget, so the strip
            // grows there instead of overflowing (do not pin to a fixed
            // height — see ship-readiness #6).
            SetTableRow(
              minHeight: 22,
              setSlot: Text('SET',
                  style: AppText.columnHeader(color: surface.textSecondary)),
              previousSlot: Text('PREVIOUS',
                  style: AppText.columnHeader(color: surface.textSecondary)),
              weightSlot: !mType.showsWeightColumn
                  ? const SizedBox.shrink()
                  : Center(
                      child: Semantics(
                        button: onUnitTap != null && mType.requiresWeight,
                        label: mType.requiresWeight
                            ? 'Weight unit ${unit.toUpperCase()}, tap to change'
                            : 'Distance column',
                        child: GestureDetector(
                          onTap: (mType.requiresWeight && onUnitTap != null)
                              ? () {
                                  HapticFeedback.selectionClick();
                                  onUnitTap!();
                                }
                              : null,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  mType.isDistance
                                      ? Icons.straighten_rounded
                                      : Icons.fitness_center_rounded,
                                  size: 11,
                                  color: surface.textSecondary,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    mType.fixedWeightColumnLabel ??
                                        unit.toUpperCase(),
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.columnHeader(
                                        color: surface.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
              repsSlot: Center(
                child: Text(
                  mType.repsColumnLabel,
                  style: AppText.columnHeader(color: surface.textSecondary),
                ),
              ),
              checkSlot: Center(
                child: Icon(Icons.check_rounded,
                    size: 16, color: surface.textSecondary),
              ),
            ),
            const SizedBox(height: 4),

            // ── Sets ──
            ...setIds.asMap().entries.map((entry) {
              final setIndex = entry.key;
              final setId = entry.value;
              return Consumer(
                key: ValueKey(setId),
                builder: (context, ref, child) {
                  final setData =
                      ref.watch(activeWorkoutProvider.select((state) {
                    if (state == null ||
                        exerciseIndex >= state.exercises.length) {
                      return null;
                    }
                    final ex = state.exercises[exerciseIndex];
                    if (setIndex >= ex.sets.length) return null;
                    return ex.sets[setIndex];
                  }));
                  if (setData == null) return const SizedBox.shrink();

                  final prevSet = setIndex < previousSets.length
                      ? previousSets[setIndex]
                      : null;

                  final row = SetRow(
                    key: ValueKey(setData.id),
                    setIndex: setIndex,
                    setData: setData,
                    measurementType: mType,
                    previousWeight: prevSet?.weightKg,
                    previousReps: prevSet?.reps,
                    unit: unit,
                    onChanged: onSetChanged,
                    onToggleComplete: () => onToggleSetCompletion(setIndex),
                  );

                  return Dismissible(
                    key: ValueKey(setData.id),
                    direction: setData.isCompleted
                        ? DismissDirection.none
                        : DismissDirection.endToStart,
                    dismissThresholds: const {
                      DismissDirection.endToStart: 0.55,
                    },
                    confirmDismiss: (_) async {
                      HapticFeedback.heavyImpact(); // feel the danger first
                      return true;
                    },
                    onDismissed: (_) => onRemoveSet(setIndex),
                    background: Container(
                      color: AppColors.error.withValues(alpha: 0.85),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 22),
                      child: Icon(Icons.delete_outline_rounded,
                          color: surface.textPrimary, size: 20),
                    ),
                    child: row,
                  );
                },
              );
            }),

            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 50,
                child: SecondaryButton(
                  label: '+ Add Set',
                  accent: true,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onAddSet();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
