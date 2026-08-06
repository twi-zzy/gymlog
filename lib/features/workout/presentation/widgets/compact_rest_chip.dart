import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gymlog/core/models/rest_preference.dart';
import 'package:gymlog/core/providers/settings_provider.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/theme/app_text.dart';
import 'package:gymlog/core/theme/dynamic_accent_theme.dart';
import 'package:gymlog/features/workout/domain/active_workout_state.dart';
import 'package:gymlog/features/workout/presentation/providers/active_workout_provider.dart';
import 'rest_time_sheet.dart';

/// Compact rest-duration override chip for exercise card headers.
///
/// Specs:
/// - Visual height: 34
/// - Intrinsic width (horizontal padding: 10)
/// - Icon size: 16
/// - Text size: 13
/// - Radius: AppRadius.badge (closed radius set — was literal 11)
/// - Touch target: minimum 48×48
///
/// Labels:
/// - Default -> `Rest 1:30`
/// - Custom -> `Rest 0:45`
/// - Disabled -> `Rest Off`
class CompactRestChip extends ConsumerWidget {
  final int exerciseIndex;
  final String exerciseName;

  const CompactRestChip({
    super.key,
    required this.exerciseIndex,
    required this.exerciseName,
  });

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return 'Off';
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _handleTap(
    BuildContext context,
    WidgetRef ref,
    RestPreference currentPreference,
    int defaultRest,
  ) async {
    final result = await showRestTimeSheet(
      context: context,
      exerciseName: exerciseName,
      currentPreference: currentPreference,
      globalSeconds: defaultRest,
    );

    if (result != null) {
      ref
          .read(activeWorkoutProvider.notifier)
          .setRestPreference(exerciseIndex, result);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workout = ref.watch(activeWorkoutProvider);
    if (workout == null || exerciseIndex >= workout.exercises.length) {
      return const SizedBox.shrink();
    }
    final exercise = workout.exercises[exerciseIndex];
    final defaultRest = ref.watch(defaultRestSecondsProvider);
    final preference = normalizeRestPreference(
      preference: exercise.restPreference,
      globalSeconds: defaultRest,
    );

    final accent = context.accent;
    final isCustom = preference is RestPreferenceCustomDuration;
    final isDisabled = isOff(preference);

    String labelText;
    if (isDisabled) {
      labelText = 'Rest Off';
    } else if (preference is RestPreferenceCustomDuration) {
      labelText = 'Rest ${_formatDuration(preference.seconds)}';
    } else {
      labelText = 'Rest ${_formatDuration(defaultRest)}';
    }

    final IconData iconData =
        isDisabled ? Icons.timer_off_rounded : Icons.timer_rounded;

    final surface = context.surface;
    final Color bgColor = isDisabled
        ? surface.surface3.withValues(alpha: 0.5)
        : (isCustom ? accent.base.withValues(alpha: 0.16) : surface.surface3);

    final Color iconColor = isCustom && !isDisabled
        ? accent.light
        : (isDisabled ? surface.textTertiary : surface.textSecondary);

    final Color textColor = isCustom && !isDisabled
        ? accent.light
        : (isDisabled ? surface.textTertiary : surface.textSecondary);

    return Semantics(
      button: true,
      label:
          'Set rest duration override for $exerciseName. Currently set to $labelText.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.badgeAll,
          onTap: () => _handleTap(context, ref, preference, defaultRest),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            alignment: Alignment.centerLeft,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: AppRadius.badgeAll,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    iconData,
                    size: 16,
                    color: iconColor,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      labelText,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.statLabel(color: textColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
