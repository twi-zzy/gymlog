import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymlog/core/providers/database_provider.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/database/database.dart';
import 'package:gymlog/features/auth/presentation/providers/auth_provider.dart';
import 'package:gymlog/shared/widgets/exercise_gif_widget.dart';
import '../providers/exercises_provider.dart';
import '../widgets/create_exercise_dialog.dart';

/// Live recent-exercise ids from workout history.
final _recentExerciseIdsProvider = StreamProvider.autoDispose<List<int>>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return Stream.value(const []);
  final db = ref.watch(databaseProvider);
  return db.workoutsDao.watchRecentExerciseIds(user.id);
});

/// Muscle-group buckets → exercise.bodyPart (region) values.
///
/// Keys map to the coarse regions stored in the unified catalog
/// (assets/db/exercises.json): chest, back, shoulders, arms, forearms, legs,
/// core, neck, full body. Arms folds in forearms; Legs covers quads/hams/
/// glutes/calves/adductors. The richer parent→child muscle taxonomy lives in
/// lib/core/exercises/muscle_taxonomy.dart.
const _muscleGroups = <String, List<String>>{
  'Chest': ['chest'],
  'Back': ['back'],
  'Shoulders': ['shoulders'],
  'Arms': ['arms', 'forearms'],
  'Legs': ['legs'],
  'Core': ['core'],
};

/// Equipment buckets → matcher over exercise.equipment (lower-cased).
/// Catalog equipment values: Barbell, Dumbbell, Cable, Machine, Smith Machine,
/// Bodyweight, Kettlebell, Resistance Band, EZ Bar, Trap Bar, Weight Plate, etc.
final _equipmentGroups = <String, bool Function(String)>{
  'Barbell': (e) =>
      e.contains('barbell') || e.contains('ez bar') || e.contains('trap bar'),
  'Dumbbell': (e) => e.contains('dumbbell'),
  'Machine': (e) => e.contains('machine'), // matches 'machine' + 'smith machine'
  'Cable': (e) => e.contains('cable'),
  'Bodyweight': (e) => e.contains('bodyweight') || e.contains('body weight'),
  'Kettlebell': (e) => e.contains('kettlebell'),
  'Band': (e) => e.contains('band'),
};

/// Exercise list with live search, Recent section, and combinable
/// Muscle / Equipment filters.
///
/// Two modes, one screen:
///  * Selection (default): tapping pops with the chosen [Exercise].
///  * Browse (`browse: true`, route `/exercises/library`): tapping opens
///    the exercise detail with charts, records and form instructions.
class ExerciseSelectionScreen extends ConsumerStatefulWidget {
  final bool browse;

  const ExerciseSelectionScreen({super.key, this.browse = false});

  @override
  ConsumerState<ExerciseSelectionScreen> createState() =>
      _ExerciseSelectionScreenState();
}

class _ExerciseSelectionScreenState
    extends ConsumerState<ExerciseSelectionScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  String? _muscleFilter;
  String? _equipmentFilter;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Debounce the DB query by 150ms so a fast typist triggers one search after
  /// they pause, not one per keystroke. The provider's epoch guard already
  /// drops stale results; this also cuts redundant query + rebuild churn.
  void _onSearchChanged(String query) {
    setState(() {}); // refresh `isSearching` (Recent section) immediately
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      ref.read(exerciseListProvider.notifier).search(query);
    });
  }

  /// Opens the manual "create custom exercise" flow. Pre-fills the name with
  /// the current search so a no-results search converts straight into a new
  /// exercise. In selection mode, picking succeeds by popping with the new
  /// exercise; in browse mode the list just refreshes (handled by the dialog).
  Future<void> _createCustom() async {
    final seed = _searchController.text.trim();
    final created = await showCreateExerciseDialog(
      context: context,
      initialName: seed.isEmpty ? null : seed,
    );
    if (created == null || !mounted) return;
    if (!widget.browse) Navigator.pop(context, created);
  }

  bool _matchesFilters(Exercise e) {
    if (_muscleFilter != null &&
        !_muscleGroups[_muscleFilter]!.contains(e.bodyPart)) {
      return false;
    }
    if (_equipmentFilter != null &&
        !_equipmentGroups[_equipmentFilter]!(e.equipment.toLowerCase())) {
      return false;
    }
    return true;
  }

  Future<void> _pickFilter({
    required String title,
    required List<String> options,
    required String? current,
    required ValueChanged<String?> onSelected,
  }) async {
    HapticFeedback.lightImpact();
    final result = await showModalBottomSheet<String?>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A6A6A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                for (final option in ['All', ...options])
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(sheetCtx)
                          .pop(option == 'All' ? '__all__' : option);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color:
                                AppColors.textSecondary.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              option,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: (option == current ||
                                        (option == 'All' && current == null))
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: (option == current ||
                                        (option == 'All' && current == null))
                                    ? AppColors.accentPrimary
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (option == current ||
                              (option == 'All' && current == null))
                            const Icon(Icons.check_rounded,
                                size: 18, color: AppColors.accentPrimary),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null) {
      onSelected(result == '__all__' ? null : result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercisesAsync = ref.watch(exerciseListProvider);
    final recentIds = ref.watch(_recentExerciseIdsProvider).valueOrNull ?? [];
    final isSearching = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        title: Text(
          widget.browse ? 'Exercise Library' : 'Select Exercise',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.bgBase,
        scrolledUnderElevation: 0,
        titleSpacing: 0, // title hugs the back button on every sub-screen
        actions: [
          IconButton(
            tooltip: 'Create custom exercise',
            icon: const Icon(Icons.add_rounded, color: AppColors.textPrimary),
            onPressed: () => _createCustom(),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              controller: _searchController,
              style: GoogleFonts.inter(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search exercises...',
                hintStyle: GoogleFonts.inter(color: AppColors.textSecondary),
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // ── Filters ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                _FilterChipButton(
                  label: _muscleFilter ?? 'Muscle',
                  active: _muscleFilter != null,
                  onTap: () => _pickFilter(
                    title: 'Muscle Group',
                    options: _muscleGroups.keys.toList(),
                    current: _muscleFilter,
                    onSelected: (v) => setState(() => _muscleFilter = v),
                  ),
                ),
                const SizedBox(width: 8),
                _FilterChipButton(
                  label: _equipmentFilter ?? 'Equipment',
                  active: _equipmentFilter != null,
                  onTap: () => _pickFilter(
                    title: 'Equipment',
                    options: _equipmentGroups.keys.toList(),
                    current: _equipmentFilter,
                    onSelected: (v) => setState(() => _equipmentFilter = v),
                  ),
                ),
              ],
            ),
          ),

          // ── List ───────────────────────────────────────────────────────
          Expanded(
            child: exercisesAsync.when(
              data: (exercises) {
                final filtered = exercises.where(_matchesFilters).toList();

                // Recent section: only without an active search; respects
                // filters; excluded from the alphabetical catalog below.
                final recent = <Exercise>[];
                if (!isSearching && recentIds.isNotEmpty) {
                  final byId = {for (final e in filtered) e.id: e};
                  for (final id in recentIds) {
                    final e = byId[id];
                    if (e != null) recent.add(e);
                  }
                }
                final recentIdSet = {for (final e in recent) e.id};
                final catalog = filtered
                    .where((e) => !recentIdSet.contains(e.id))
                    .toList()
                  ..sort((a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()));

                if (recent.isEmpty && catalog.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 30,
                            color: Colors.white.withValues(alpha: 0.25)),
                        const SizedBox(height: 10),
                        Text(
                          'No exercises match',
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isSearching
                              ? "Not in the library? Add it yourself."
                              : 'Try clearing a filter or changing the search.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextButton.icon(
                          onPressed: _createCustom,
                          icon: const Icon(Icons.add_rounded,
                              size: 18, color: AppColors.accentText),
                          label: Text(
                            'Create custom exercise',
                            style: GoogleFonts.inter(
                              color: AppColors.accentText,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final items = <_ListItem>[
                  if (recent.isNotEmpty) ...[
                    const _ListItem.header('RECENT'),
                    ...recent.map(_ListItem.exercise),
                    const _ListItem.header('ALL EXERCISES'),
                  ],
                  ...catalog.map(_ListItem.exercise),
                ];

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    if (item.headerLabel != null) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                        child: Text(
                          item.headerLabel!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      );
                    }
                    final exercise = item.exerciseValue!;
                    return ListTile(
                      key:
                          ValueKey('${item.headerLabel}_${exercise.id}_$index'),
                      leading: RepaintBoundary(
                        child: ExerciseGifWidget(
                          gifUrl: exercise.gifUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          animate: false,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                      title: Text(
                        exercise.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${exercise.target} • ${exercise.equipment}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                      trailing: widget.browse
                          ? Icon(Icons.chevron_right_rounded,
                              size: 20,
                              color: Colors.white.withValues(alpha: 0.25))
                          : null,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        if (widget.browse) {
                          context.push('/exercise/detail/${exercise.id}',
                              extra: exercise);
                        } else {
                          Navigator.pop(context, exercise);
                        }
                      },
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(
                    color: AppColors.accentPrimary, strokeWidth: 2),
              ),
              error: (e, _) => Center(
                child: Text(
                  'Failed to load exercises',
                  style: GoogleFonts.inter(color: AppColors.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListItem {
  final String? headerLabel;
  final Exercise? exerciseValue;

  const _ListItem.header(this.headerLabel) : exerciseValue = null;
  const _ListItem.exercise(this.exerciseValue) : headerLabel = null;
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label filter${active ? ', active' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accentPrimary.withValues(alpha: 0.14)
                : AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(999),
            border: active
                ? Border.all(
                    color: AppColors.accentPrimary.withValues(alpha: 0.45))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      active ? const Color(0xFFCBB2FF) : AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color:
                    active ? const Color(0xFFCBB2FF) : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
