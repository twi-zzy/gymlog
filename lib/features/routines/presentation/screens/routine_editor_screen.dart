import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymlog/core/database/daos/routines_dao.dart';
import 'package:gymlog/core/database/database.dart';
import 'package:gymlog/core/providers/database_provider.dart';
import 'package:gymlog/core/providers/premium_provider.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/shared/widgets/premium_paywall.dart';
import 'package:gymlog/features/auth/presentation/providers/auth_provider.dart';
import 'package:gymlog/features/exercises/presentation/screens/exercise_selection_screen.dart';
import 'package:gymlog/shared/widgets/exercise_gif_widget.dart';
import 'package:gymlog/shared/widgets/ui/app_dialog.dart';
import 'package:gymlog/features/routines/presentation/widgets/routine_detail_styles.dart';
import 'package:uuid/uuid.dart';

/// Real routine builder — replaces the old "Coming Soon" stub.
///
/// Create mode: `/routines/edit`
/// Edit mode:   `/routines/edit?id=<routineId>`
///
/// Name + ordered exercise list with per-exercise set count, drag-to-reorder,
/// swipe-free removal, and atomic save through RoutinesDao.
class RoutineEditorScreen extends ConsumerStatefulWidget {
  final String? routineId;

  const RoutineEditorScreen({super.key, this.routineId});

  @override
  ConsumerState<RoutineEditorScreen> createState() =>
      _RoutineEditorScreenState();
}

class _EditorExercise {
  /// Stable, guaranteed-unique identity for the reorderable list key.
  ///
  /// The same exercise can legitimately appear twice in a routine, so
  /// `exerciseId` is NOT unique. The previous key blended in
  /// `identityHashCode`, which is neither guaranteed-unique nor a documented
  /// stable key — exactly the "keyed list rebuild" fragility that breaks
  /// `ReorderableListView` mid-drag. A per-instance UUID is unambiguous.
  final String uid = const Uuid().v4();

  final int exerciseId;
  final String name;
  final String? gifUrl;
  final String? equipment;
  int sets;
  final int? defaultReps;
  final double? defaultWeightKg;

  _EditorExercise({
    required this.exerciseId,
    required this.name,
    this.gifUrl,
    this.equipment,
    this.sets = 3,
    this.defaultReps,
    this.defaultWeightKg,
  });
}

class _RoutineEditorScreenState extends ConsumerState<RoutineEditorScreen> {
  final _nameController = TextEditingController();
  final List<_EditorExercise> _exercises = [];

  bool get _isEditMode => widget.routineId != null;
  bool _loading = false;
  bool _saving = false;
  bool _dirty = false;

  bool get _canSave =>
      _nameController.text.trim().isNotEmpty && _exercises.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      _dirty = true;
      setState(() {}); // refresh Save enabled state
    });
    if (_isEditMode) _loadExisting();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    final detail = await ref
        .read(databaseProvider)
        .routinesDao
        .getHydratedRoutineDetail(widget.routineId!);
    if (!mounted) return;

    if (detail != null) {
      _nameController.text = detail.routine.name;
      _exercises.addAll(detail.exercises.map((he) => _EditorExercise(
            exerciseId: he.exercise.id,
            name: he.exercise.name,
            gifUrl: he.exercise.gifUrl,
            equipment: he.exercise.equipment,
            sets: he.config.defaultSets,
            defaultReps: he.config.defaultReps,
            defaultWeightKg: he.config.defaultWeightKg,
          )));
    }
    _dirty = false;
    setState(() => _loading = false);
  }

  Future<void> _addExercises() async {
    HapticFeedback.lightImpact();
    final selected = await Navigator.push<Exercise>(
      context,
      MaterialPageRoute(builder: (_) => const ExerciseSelectionScreen()),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _dirty = true;
      _exercises.add(_EditorExercise(
        exerciseId: selected.id,
        name: selected.name,
        gifUrl: selected.gifUrl,
        equipment: selected.equipment,
      ));
    });
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);

    try {
      final dao = ref.read(databaseProvider).routinesDao;
      final draft = [
        for (final e in _exercises)
          RoutineDraftExercise(
            exerciseId: e.exerciseId,
            defaultSets: e.sets,
            defaultReps: e.defaultReps,
            defaultWeightKg: e.defaultWeightKg,
          ),
      ];

      if (_isEditMode) {
        await dao.replaceRoutineStructure(
          routineId: widget.routineId!,
          name: _nameController.text.trim(),
          exercises: draft,
        );
      } else {
        final user = ref.read(authProvider);
        if (user == null) return;

        // Free-tier routine cap. Editing an existing routine is never gated —
        // only creating a NEW one past the limit. Free users keep every
        // routine they already have (grandfathered); they just can't add more.
        final isPremium = ref.read(isPremiumProvider);
        final count = await dao.countRoutinesForUser(user.id);
        if (isAtFreeRoutineLimit(isPremium: isPremium, routineCount: count)) {
          if (mounted) await showRoutineLimitUpsell(context);
          return; // draft stays on screen; nothing saved
        }

        await dao.createRoutine(
          userId: user.id,
          name: _nameController.text.trim(),
          exercises: draft,
        );
      }

      if (mounted) {
        _dirty = false;
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLeave() async {
    if (!_dirty) {
      context.pop();
      return;
    }
    final discard = await showAppConfirmDialog(
      context: context,
      title: 'Discard changes?',
      message: 'Your edits to this routine will be lost.',
      confirmLabel: 'Discard',
      isDestructive: true,
    );
    if (discard && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgBase,
        appBar: AppBar(
          backgroundColor: AppColors.bgBase,
          scrolledUnderElevation: 0,
          elevation: 0,
          titleSpacing: 0, // title hugs the close button on every sub-screen
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close, color: AppColors.textPrimary),
            onPressed: _confirmLeave,
          ),
          title: Text(
            _isEditMode ? 'Edit Routine' : 'New Routine',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: AppColors.textPrimary,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _canSave && !_saving ? _save : null,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accentPrimary),
                      )
                    : Text(
                        'Save',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _canSave
                              ? AppColors.accentPrimary
                              : AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                      ),
              ),
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(
                    color: AppColors.accentPrimary, strokeWidth: 2),
              )
            : Column(
                children: [
                  // ── Routine name ──────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: TextField(
                      controller: _nameController,
                      maxLength: 50,
                      textCapitalization: TextCapitalization.words,
                      cursorColor: AppColors.accentPrimary,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Routine name',
                        counterText: '',
                        hintStyle: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceRaised,
                      ),
                    ),
                  ),

                  // ── Exercise list ─────────────────────────────────────
                  Expanded(
                    child: _exercises.isEmpty
                        ? _EmptyEditorState(onAdd: _addExercises)
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                            itemCount: _exercises.length,
                            // The card supplies its own drag handle
                            // (ReorderableDragStartListener). Leaving the
                            // default handles on too gives every item TWO
                            // competing drag listeners — the source of the
                            // mid-drag index confusion. Exactly one handle.
                            buildDefaultDragHandles: false,
                            onReorderStart: (_) =>
                                HapticFeedback.selectionClick(),
                            proxyDecorator: (child, index, animation) =>
                                AnimatedBuilder(
                              animation: animation,
                              child: child,
                              builder: (context, child) {
                                // Lift the dragged card: subtle scale + shadow
                                // so it visibly detaches from the list.
                                final t =
                                    Curves.easeInOut.transform(animation.value);
                                return Transform.scale(
                                  scale: 1.0 + 0.03 * t,
                                  child: Material(
                                    color: Colors.transparent,
                                    elevation: 10 * t,
                                    shadowColor:
                                        Colors.black.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(12),
                                    child: child,
                                  ),
                                );
                              },
                            ),
                            // onReorderItem (Flutter 3.44+) pre-adjusts
                            // newIndex for the removed item — no manual
                            // decrement needed.
                            onReorderItem: (oldIndex, newIndex) {
                              HapticFeedback.mediumImpact(); // satisfying drop
                              setState(() {
                                _dirty = true;
                                final item = _exercises.removeAt(oldIndex);
                                _exercises.insert(newIndex, item);
                              });
                            },
                            itemBuilder: (context, index) {
                              final e = _exercises[index];
                              return Padding(
                                key: ValueKey(e.uid),
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _EditorExerciseCard(
                                  exercise: e,
                                  index: index,
                                  onSetsChanged: (sets) => setState(() {
                                    _dirty = true;
                                    e.sets = sets;
                                  }),
                                  onRemove: () {
                                    HapticFeedback.lightImpact();
                                    setState(() {
                                      _dirty = true;
                                      _exercises.removeAt(index);
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
        bottomNavigationBar: _exercises.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Material(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _addExercises,
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
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _EmptyEditorState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyEditorState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fitness_center_rounded,
                size: 34, color: Colors.white.withValues(alpha: 0.25)),
            const SizedBox(height: 14),
            Text(
              'Build your routine',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add exercises from the library, set your\ntargets, and start training in one tap.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
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
                onTap: onAdd,
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded,
                          size: 18, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        'Add Exercise',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorExerciseCard extends StatelessWidget {
  final _EditorExercise exercise;
  final int index;
  final ValueChanged<int> onSetsChanged;
  final VoidCallback onRemove;

  const _EditorExerciseCard({
    required this.exercise,
    required this.index,
    required this.onSetsChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RDStyles.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: RDStyles.hairlineBorder,
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              label: 'Reorder ${exercise.name}',
              child: Container(
                width: 32,
                height: 48,
                alignment: Alignment.center,
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.30),
                ),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ExerciseGifWidget(
              gifUrl: exercise.gifUrl,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              animate: false,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.name,
                  // Two lines before truncating — the trailing stepper + remove
                  // controls squeeze this column hard, and "Barbell Ben…" at
                  // ~12 chars made rows ambiguous (three barbell presses in a
                  // row were indistinguishable).
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${exercise.sets} set${exercise.sets != 1 ? 's' : ''}'
                  '${(exercise.equipment ?? '').isNotEmpty ? ' · ${exercise.equipment}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Sets stepper
          _StepperButton(
            icon: Icons.remove_rounded,
            label: 'Decrease sets',
            enabled: exercise.sets > 1,
            onTap: () => onSetsChanged(exercise.sets - 1),
          ),
          SizedBox(
            width: 22,
            child: Text(
              '${exercise.sets}',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.add_rounded,
            label: 'Increase sets',
            enabled: exercise.sets < 10,
            onTap: () => onSetsChanged(exercise.sets + 1),
          ),
          IconButton(
            tooltip: 'Remove ${exercise.name}',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(Icons.close_rounded,
                size: 18, color: Colors.white.withValues(alpha: 0.4)),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _StepperButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onTap();
              }
            : null,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 48,
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 16,
                color: enabled
                    ? AppColors.textPrimary
                    : AppColors.textSecondary.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
