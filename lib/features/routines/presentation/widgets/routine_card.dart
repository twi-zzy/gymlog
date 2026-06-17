import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../shared/widgets/ui/action_bottom_sheet.dart';
import '../../../../shared/widgets/ui/app_dialog.dart';
import 'routine_detail_styles.dart';

/// Premium routine card for the Routines list.
/// - Tapping the body opens the routine detail (`/routines/:id`).
/// - The compact "Start" pill fires [onStartTap] (and won't trigger the body tap).
/// - Renders muscle tags, exercise count, last-trained, and a 1-line preview.
class RoutineCard extends ConsumerWidget {
  final String routineId;
  final String routineName;
  final List<String> exerciseNames;
  final List<String> muscleTags;
  final DateTime? lastTrained;
  final VoidCallback onStartTap;

  const RoutineCard({
    super.key,
    required this.routineId,
    required this.routineName,
    required this.exerciseNames,
    required this.onStartTap,
    this.muscleTags = const [],
    this.lastTrained,
  });

  /// Stable accent derived from the routine's primary muscle group, so
  /// "Push Day" and "Leg Day" are tinted differently forever.
  Color get _glyphColor {
    if (muscleTags.isEmpty) return const Color(0xFF00C4A0);
    final index =
        muscleTags.first.hashCode.abs() % AppColors.muscleSplitPalette.length;
    final base = AppColors.muscleSplitPalette[index];
    // Lighten dark palette entries for legibility on near-black.
    return Color.lerp(base, Colors.white, 0.35)!;
  }

  String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays < 1) return 'today';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 14) return '1 week ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
    if (diff.inDays < 60) return '1 month ago';
    return '${(diff.inDays / 30).floor()} months ago';
  }

  Widget _tag(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: const Color(0xFFB8B8BD),
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = exerciseNames.length;
    final exLabel = count == 1 ? 'exercise' : 'exercises';
    // Compact meta — "4 exercises · 5 days ago". The verbose
    // "Last trained …" prefix truncated mid-word next to the card menu on
    // 360dp screens ("Last trained 5 days a…"); under a routine name the
    // bare relative date is self-evident. The list header keeps the long
    // form where there is room for it.
    final meta = lastTrained == null
        ? '$count $exLabel'
        : '$count $exLabel · ${_relative(lastTrained!)}';

    final preview = exerciseNames.isEmpty
        ? 'No exercises yet'
        : exerciseNames.take(3).join(', ') +
            (count > 3 ? '  +${count - 3}' : '');

    final tags = muscleTags.take(3).toList();
    final extraTags = muscleTags.length - tags.length;

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
          onTap: () => context.push('/routines/$routineId'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 10, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header: glyph + name/meta + menu ─────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Differentiated glyph: routine initial tinted by its
                    // primary muscle group — every card identifiable at a
                    // glance, no generic dumbbell noise.
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _glyphColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        routineName.isNotEmpty
                            ? routineName[0].toUpperCase()
                            : 'R',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _glyphColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              routineName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Routine options',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      iconSize: 20,
                      splashRadius: 22,
                      icon: const Icon(Icons.more_horiz,
                          color: AppColors.textSecondary),
                      onPressed: () => _showOptions(context, ref),
                    ),
                  ],
                ),

                // ── Muscle tags (aligned under the text column) ──────────
                if (tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 57, top: 11),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in tags) _tag(t),
                        if (extraTags > 0) _tag('+$extraTags'),
                      ],
                    ),
                  ),

                // ── Divider ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(top: 13),
                  child: Container(height: 1, color: RDStyles.hairline),
                ),

                // ── Footer: preview + compact Start pill ─────────────────
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _StartPill(onTap: onStartTap),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOptions(BuildContext context, WidgetRef ref) {
    showActionBottomSheet(
      context: context,
      title: routineName,
      items: [
        ActionSheetItem(
          icon: Icons.edit_outlined,
          iconColor: AppColors.textSecondary,
          iconBackground: AppColors.bgBase,
          title: 'Edit Routine',
          onTap: (sheetContext) {
            Navigator.of(sheetContext).pop();
            HapticFeedback.selectionClick();
            context.push('/routines/edit?id=$routineId');
          },
        ),
        ActionSheetItem(
          icon: Icons.delete_outline_rounded,
          iconColor: AppColors.error,
          iconBackground: AppColors.error.withValues(alpha: 0.12),
          title: 'Delete Routine',
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
      title: 'Delete Routine?',
      message:
          'This routine will be permanently deleted. Your workout history stays.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirmed) {
      await ref.read(databaseProvider).routinesDao.deleteRoutine(routineId);
    }
  }
}

class _StartPill extends StatelessWidget {
  final VoidCallback onTap;
  const _StartPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accentPrimary,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow_rounded,
                  size: 16, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                'Start',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
