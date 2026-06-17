import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui/tracker_card.dart';
import '../../../routines/presentation/widgets/routine_card.dart';
import '../../../routines/presentation/providers/routines_provider.dart';
import 'package:uuid/uuid.dart';
import '../../domain/active_workout_state.dart';
import '../providers/active_workout_provider.dart';
import 'package:gymlog/core/database/daos/routines_dao.dart';

/// [workout_screen.dart]
/// Purpose: Routines tab — premium list of the user's saved routines.
/// State: hydratedRoutinesProvider (StreamProvider) — auto-refreshes on DB writes.
class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key});

  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  bool _routinesExpanded = true;

  void _startRoutine(HydratedRoutine routine) {
    if (routine.exerciseIds.isEmpty) return;
    HapticFeedback.mediumImpact();

    final exercises = routine.exerciseIds.asMap().entries.map((e) {
      return WorkoutExerciseState(
        id: const Uuid().v4(),
        exerciseId: e.value,
        name: routine.exerciseNames[e.key],
        sets: [WorkoutSetState.create()],
      );
    }).toList();

    ref.read(activeWorkoutProvider.notifier).startWorkout(
          routineId: routine.routine.id,
          name: routine.routine.name,
          initialExercises: exercises,
        );
    context.push('/workout/active');
  }

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays < 1) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
    return '${(diff.inDays / 30).floor()} months ago';
  }

  String _summaryLine(List<HydratedRoutine> routines) {
    final count = routines.length;
    final label = count == 1 ? 'routine' : 'routines';
    DateTime? maxLast;
    for (final r in routines) {
      final d = r.lastTrained;
      if (d != null && (maxLast == null || d.isAfter(maxLast))) maxLast = d;
    }
    return maxLast == null
        ? '$count $label'
        : '$count $label  ·  Last trained ${_relative(maxLast)}';
  }

  @override
  Widget build(BuildContext context) {
    final routinesAsync = ref.watch(hydratedRoutinesProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: AppColors.bgBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Routines',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 28,
            letterSpacing: -0.5,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Recency summary ──────────────────────────────────────────
            routinesAsync.maybeWhen(
              data: (routines) => routines.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _summaryLine(routines),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),

            // ── Action row: New (primary) + Explore (catalog) ────────────
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'New Routine',
                    icon: Icons.add_rounded,
                    primary: true,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.push('/routines/edit');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    label: 'Explore',
                    icon: Icons.explore_outlined,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.push('/routines/explore');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // ── Collapsible section header ───────────────────────────────
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _routinesExpanded = !_routinesExpanded);
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _routinesExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    routinesAsync.maybeWhen(
                      data: (routines) => Text(
                        'My Routines (${routines.length})',
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      orElse: () => Text(
                        'My Routines',
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ── Routine list ─────────────────────────────────────────────
            if (_routinesExpanded)
              routinesAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(
                        color: AppColors.accentPrimary),
                  ),
                ),
                error: (e, _) => TrackerCard(
                  child: Text(
                    'Failed to load routines',
                    style: GoogleFonts.inter(color: AppColors.error),
                  ),
                ),
                data: (routines) {
                  if (routines.isEmpty) {
                    return TrackerCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No routines yet',
                            style: GoogleFonts.inter(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Save a workout as a routine, or create one above.',
                            style: GoogleFonts.inter(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: routines.map((routine) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: RoutineCard(
                          routineId: routine.routine.id,
                          routineName: routine.routine.name,
                          exerciseNames: routine.exerciseNames,
                          muscleTags: routine.muscleTags,
                          lastTrained: routine.lastTrained,
                          onStartTap: () => _startRoutine(routine),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Top action button. `primary` = accent-outline (New Routine);
/// otherwise a neutral raised surface (Explore).
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = primary
        ? const Color(0xFF00C4A0)
        : Colors.white.withValues(alpha: 0.86);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: primary
            ? AppColors.accentPrimary.withValues(alpha: 0.12)
            : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: primary
            ? Border.all(
                color: AppColors.accentPrimary.withValues(alpha: 0.45),
                width: 1)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: fg,
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
