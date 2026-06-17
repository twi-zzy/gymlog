import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/database/daos/routines_dao.dart';
import 'package:gymlog/core/database/daos/workouts_dao.dart';
import 'routine_detail_styles.dart';

/// Exercise block — sits directly on the black background (no gray card).
/// Grouping comes from spacing + the set-table hairlines only.
class RoutineExerciseBlock extends StatelessWidget {
  final HydratedRoutineExercise hydratedExercise;
  final List<LastSessionSetData>? lastSets;
  final VoidCallback? onTap;
  final bool isLoadingHistory;
  final bool isLast;

  const RoutineExerciseBlock({
    super.key,
    required this.hydratedExercise,
    this.lastSets,
    this.onTap,
    this.isLoadingHistory = false,
    this.isLast = false,
  });

  String _fmtKg(double? w) => w == null
      ? '–'
      : (w % 1 == 0 ? w.toInt().toString() : w.toStringAsFixed(1));

  String _summary(List<LastSessionSetData> sets) {
    if (sets.isEmpty) return 'No history yet';
    final top =
        sets.reduce((a, b) => (a.weightKg ?? 0) >= (b.weightKg ?? 0) ? a : b);
    final r = top.reps?.toString() ?? '–';
    return 'Last: ${_fmtKg(top.weightKg)} kg × $r reps · ${sets.length} sets';
  }

  @override
  Widget build(BuildContext context) {
    final sets = [...?lastSets]
      ..sort((a, b) => a.setNumber.compareTo(b.setNumber));

    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: RDStyles.hairlineBorder,
                      ),
                      child: CachedNetworkImage(
                        imageUrl: hydratedExercise.exercise.gifUrl ?? '',
                        fit: BoxFit.cover,
                        // List thumbnail: cap decode size — a 52dp cell must
                        // not hold a full-resolution animated GIF in memory.
                        memCacheWidth: 200,
                        maxHeightDiskCache: 400,
                        placeholder: (_, __) =>
                            Container(color: const Color(0xFF1A1A1D)),
                        errorWidget: (_, __, ___) =>
                            Container(color: const Color(0xFF1A1A1D)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hydratedExercise.exercise.name,
                        style: RDStyles.exName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLoadingHistory
                            ? 'Loading last session…'
                            : _summary(sets),
                        style: RDStyles.exLast,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (isLoadingHistory)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accentPrimary,
                ),
              ),
            )
          else if (sets.isNotEmpty)
            _SetTable(sets: sets),
        ],
      ),
    );
  }
}

class _SetTable extends StatelessWidget {
  final List<LastSessionSetData> sets;
  const _SetTable({required this.sets});

  /// Right gutter so the numeric columns sit inboard of the screen edge
  /// instead of terminating exactly where the screen ends.
  static const double _numGutter = 20;

  String _fmtKg(double? w) => w == null
      ? '–'
      : (w % 1 == 0 ? w.toInt().toString() : w.toStringAsFixed(1));

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                  flex: 5, child: Text('SET', style: RDStyles.tableHeader)),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(right: _numGutter),
                  child: Text('KG',
                      style: RDStyles.tableHeader, textAlign: TextAlign.right),
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(right: _numGutter),
                  child: Text('REPS',
                      style: RDStyles.tableHeader, textAlign: TextAlign.right),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < sets.length; i++)
          Container(
            decoration: BoxDecoration(
              border: i == 0
                  ? null
                  : Border(top: BorderSide(color: RDStyles.hairline, width: 1)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        child:
                            Text('${sets[i].setNumber}', style: RDStyles.setNo),
                      ),
                      const SizedBox(width: 10),
                      if (_chipFor(sets[i].setType) != null)
                        _chipFor(sets[i].setType)!,
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(right: _numGutter),
                    child: Text(_fmtKg(sets[i].weightKg),
                        style: RDStyles.numCell, textAlign: TextAlign.right),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(right: _numGutter),
                    child: Text(sets[i].reps?.toString() ?? '–',
                        style: RDStyles.numCell, textAlign: TextAlign.right),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget? _chipFor(String? type) {
    switch (type) {
      case 'warmup':
        return const _SetTypeChip(
            label: 'Warm',
            fg: Color(0xFFE0A422),
            icon: Icons.local_fire_department_rounded);
      case 'dropset':
      case 'drop':
        return const _SetTypeChip(
            label: 'Drop',
            fg: Color(0xFF00C4A0),
            icon: Icons.trending_down_rounded);
      case 'failure':
        return const _SetTypeChip(
            label: 'Fail',
            fg: Color(0xFFFF6B70),
            icon: Icons.warning_amber_rounded);
      default:
        return null; // 'normal' / null → no chip
    }
  }
}

class _SetTypeChip extends StatelessWidget {
  final String label;
  final Color fg;
  final IconData icon;

  const _SetTypeChip(
      {required this.label, required this.fg, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 5),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
          ],
        ),
      );
}
