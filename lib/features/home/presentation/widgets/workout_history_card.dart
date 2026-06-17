import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:gymlog/core/database/daos/workouts_dao.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/utils/formatters.dart';
import 'package:gymlog/features/routines/presentation/widgets/routine_detail_styles.dart';
import 'package:gymlog/shared/providers/gif_last_frame_provider.dart';

/// [workout_history_card.dart]
/// Purpose: Data-dense workout history card for the HomeScreen feed.
///
/// Layout:
///   Row: workout name (bold) + date · duration (secondary)
///   Row × 2: [52×52 GIF] exercise name (bold)  N sets
///   Text: "+ N more exercises"  (if totalExerciseCount > 2)
///   Divider
///   Stats row: volume  duration  [🏆 N PRs]  (PRs only rendered if prCount > 0)

class WorkoutHistoryCard extends StatelessWidget {
  final WorkoutSessionPreview preview;
  final VoidCallback? onMenuPressed;

  const WorkoutHistoryCard({
    super.key,
    required this.preview,
    this.onMenuPressed,
  });

  @override
  Widget build(BuildContext context) {
    final session = preview.session;
    final name = getWorkoutNameFallback(session.startedAt, session.name);
    final dateStr = DateFormat('MMM d').format(session.startedAt);
    final durationStr =
        formatWorkoutDuration(session.startedAt, session.endedAt);

    return Container(
      decoration: BoxDecoration(
        gradient: RDStyles.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: RDStyles.hairlineBorder,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/workout/detail/${session.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Row 1: Column(Name, Date) + Three-dots icon ─────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.inter(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateStr,
                            style: GoogleFonts.inter(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onMenuPressed != null)
                      IconButton(
                        tooltip: 'Workout options',
                        icon: const Icon(
                          Icons.more_horiz,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: onMenuPressed,
                      ),
                  ],
                ),

                // ── Exercise preview rows ────────────────────────────────────────
                if (preview.topExercises.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...preview.topExercises.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ExerciseRow(item: item),
                    ),
                  ),
                  if (preview.totalExerciseCount > 2)
                    Text(
                      '+ ${preview.totalExerciseCount - 2} more '
                      'exercise${preview.totalExerciseCount - 2 > 1 ? 's' : ''}',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                ],

                const SizedBox(height: 11),
                Container(height: 1, color: RDStyles.hairline),
                const SizedBox(height: 11),

                // ── Stats row ────────────────────────────────────────────────────
                _StatsRow(preview: preview, durationStr: durationStr),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

// _ExerciseRow is a ConsumerWidget so it can watch the Riverpod
// gifLastFrameProvider, which decodes + caches the GIF's last frame globally.
// The cached MemoryImage survives all navigation — no widget state involved.
class _ExerciseRow extends ConsumerWidget {
  final ExercisePreviewItem item;

  const _ExerciseRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        _buildThumbnail(ref),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            item.exerciseName,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '${item.setCount} set${item.setCount != 1 ? 's' : ''}',
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnail(WidgetRef ref) {
    final url = item.gifUrl;

    // No URL — render the icon fallback immediately, no async needed.
    if (url == null || url.isEmpty) return _iconFallback();

    // Watch the globally-cached last-frame provider.
    // AsyncValue handles loading / error / data states cleanly.
    final frameAsync = ref.watch(gifLastFrameProvider(url));

    return _wrapBoundary(frameAsync.when(
      // ── Loading: subtle shimmer container while the codec runs ────────────
      loading: () => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      // ── Error / null: icon fallback ───────────────────────────────────────
      error: (_, __) => _iconFallback(),
      // ── Data: render the decoded MemoryImage (last frame) ────────────────
      data: (memoryImage) {
        if (memoryImage == null) return _iconFallback();
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image(
            image: memoryImage,
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            // gaplessPlayback prevents a blank flash when the list cell is
            // recycled and rebuilt with the same (already-cached) provider.
            gaplessPlayback: true,
          ),
        );
      },
    ));
  }

  /// Isolates thumbnail repaints from the scrolling list layer.
  Widget _wrapBoundary(Widget child) => RepaintBoundary(child: child);

  Widget _iconFallback() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(
          Icons.fitness_center_rounded,
          color: AppColors.textSecondary,
          size: 20,
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final WorkoutSessionPreview preview;
  final String durationStr;

  const _StatsRow({required this.preview, required this.durationStr});

  @override
  Widget build(BuildContext context) {
    final hasPrs = preview.prCount > 0;

    final volumeChip = _StatChip(
      icon: Icons.inventory_2_outlined,
      label: _formatVolume(preview.totalVolumeKg),
    );
    final durationChip = _StatChip(
      icon: Icons.timer_outlined,
      label: durationStr,
    );

    if (hasPrs) {
      // 3 stats — evenly spaced
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          volumeChip,
          durationChip,
          _StatChip(
            icon: Icons.emoji_events_rounded,
            label: '${preview.prCount} PR${preview.prCount > 1 ? 's' : ''}',
            color: AppColors.warning,
          ),
        ],
      );
    }

    // 2 stats — fixed gap
    return Row(
      children: [
        volumeChip,
        const SizedBox(width: 24),
        durationChip,
      ],
    );
  }

  /// Formats kg with thousands comma: 1488 → "1,488 kg", 980 → "980 kg"
  static String _formatVolume(double kg) {
    final rounded = kg.round();
    if (rounded >= 1000) {
      final thousands = rounded ~/ 1000;
      final hundreds = (rounded % 1000).toString().padLeft(3, '0');
      return '$thousands,$hundreds kg';
    }
    return '$rounded kg';
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    this.color = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.inter(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
