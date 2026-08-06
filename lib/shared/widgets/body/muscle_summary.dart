import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/dynamic_accent_theme.dart';
import 'muscle_map.dart';

/// [muscle_summary.dart]
/// Progressive disclosure for "what does this routine train".
///
/// LAYER 1 — `MuscleLoadBar` (muscle_load_bar.dart): always-visible stacked
/// proportional bar — each segment's width is that group's share of working
/// sets. No scroll, deterministic height (ship-readiness #7).
/// LAYER 3 — [showMuscleMapSheet]: the anatomical figure, on demand, full size.
///
/// Rationale: the muscle map is reference information with a very low re-read
/// rate. A user opening their Push day for the 40th time already knows it hits
/// chest and triceps; what they actually came for is the exercise list and last
/// session's numbers. Reference content that is re-read rarely should not hold
/// prime vertical real estate above the primary content — it should be one tap
/// away and bigger when you get there.
///
/// (The old LAYER 1 chip strip was retired: a summary you must scroll is not
/// a summary, and its scroll edge clipped chips mid-glyph.)

/// Full-size muscle map in a 92%-height sheet.
///
/// The map is unchanged — the win is purely that it is no longer squeezed into
/// a scroll position it has to share with a stat strip, a chart, and a list.
Future<void> showMuscleMapSheet({
  required BuildContext context,
  required Set<String> primaryGroups,
  required Set<String> secondaryGroups,
  required String gender,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) {
      final surface = sheetCtx.surface;
      return FractionallySizedBox(
        heightFactor: 0.92,
        child: Container(
          decoration: BoxDecoration(
            color: surface.surface2,
            borderRadius: AppRadius.sheetTop,
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: surface.borderEmphasis,
                  borderRadius: BorderRadius.circular(AppRadius.badge),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text('Muscles Worked',
                            style:
                                AppText.sheetTitle(color: surface.textPrimary)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: Icon(Icons.close_rounded,
                          size: 22, color: surface.textSecondary),
                      onPressed: () => Navigator.of(sheetCtx).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MuscleMap(
                        primaryGroups: primaryGroups,
                        secondaryGroups: secondaryGroups,
                        gender: gender,
                        showBack: true,
                        showLegend: true,
                      ),
                      const SizedBox(height: 20),
                      if (primaryGroups.isNotEmpty)
                        _GroupList(
                          title: 'PRIMARY',
                          groups: primaryGroups,
                          color: AppColors.textPrimary,
                        ),
                      if (secondaryGroups.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _GroupList(
                          title: 'SECONDARY',
                          groups: secondaryGroups,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _GroupList extends StatelessWidget {
  final String title;
  final Set<String> groups;
  final Color color;

  const _GroupList({
    required this.title,
    required this.groups,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = groups.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: AppText.columnHeader(color: context.surface.textTertiary)),
        const SizedBox(height: 6),
        Text(
          sorted.map(_titleCase).join('  \u00b7  '),
          style: AppText.body(color: color),
        ),
      ],
    );
  }
}

/// Public wrapper so sibling widgets (the load bar's legend) title-case group
/// keys identically to the map sheet.
String muscleGroupTitleCase(String input) => _titleCase(input);

/// `'lower back' -> 'Lower Back'`. Body-map group keys are lowercase, and
/// title-casing at the presentation layer keeps the data layer canonical.
String _titleCase(String input) {
  if (input.isEmpty) return input;
  return input
      .split(' ')
      .map((w) => w.isEmpty
          ? w
          : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');
}
