import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/dynamic_accent_theme.dart';
import 'muscle_summary.dart';

/// [muscle_load_bar.dart]
/// LAYER 1 (redesigned, ship-readiness #7): the muscle load bar.
///
/// What it replaces: a 44dp horizontally-scrolling chip strip. A summary you
/// must scroll is not a summary — and the scroll edge hard-clipped the next
/// chip mid-glyph with no fade, which read as "text being cut off".
///
/// What this is: ONE stacked proportional bar — each segment's width is that
/// muscle group's share of the routine's working sets — plus an inline
/// legend of up to three named groups with percentages. No scroll, ONE
/// overflow mechanism ("+n"), deterministic height. A user opening Push Day
/// for the 40th time already knows it hits chest; what they do NOT know at a
/// glance is the balance — show proportion, not membership.
///
/// Tap anywhere → the full muscle map (Layer 3, unchanged).
class MuscleLoadBar extends StatelessWidget {
  /// Ranked groups (dominant first) with their share of total load.
  final List<MuscleLoadEntry> entries;
  final Set<String> primaryGroups;
  final Set<String> secondaryGroups;
  final String gender;

  /// Optional override for the tap action. Defaults to opening the map sheet.
  final VoidCallback? onTap;

  const MuscleLoadBar({
    super.key,
    required this.entries,
    required this.primaryGroups,
    required this.secondaryGroups,
    required this.gender,
    this.onTap,
  });

  static const int _kMaxLegendItems = 3;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final surface = context.surface;
    final visible = entries.take(_kMaxLegendItems).toList();
    final overflow = entries.length - visible.length;
    final palette = AppColors.muscleSplitPalette;

    final semanticsLabel =
        'Muscles worked: ${entries.map((e) => '${muscleGroupTitleCase(e.group)} ${(e.share * 100).round()}%').join(', ')}. '
        'Opens the full muscle map.';

    void handleTap() {
      HapticFeedback.selectionClick();
      if (onTap != null) {
        onTap!();
        return;
      }
      showMuscleMapSheet(
        context: context,
        primaryGroups: primaryGroups,
        secondaryGroups: secondaryGroups,
        gender: gender,
      );
    }

    return Semantics(
      container: true,
      button: true,
      // Wrapper owns the summary label; the legend Texts must not publish
      // their own duplicate nodes (docs/a11y-semantics-checklist.md §2).
      excludeSemantics: true,
      onTap: handleTap,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: handleTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 8,
                width: double.infinity,
                child: CustomPaint(
                  painter: _LoadBarPainter(
                    shares: [for (final e in entries) e.share],
                    colors: [
                      for (var i = 0; i < entries.length; i++)
                        palette[i.clamp(0, palette.length - 1)],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < visible.length; i++)
                    _LegendItem(
                      color: palette[i.clamp(0, palette.length - 1)],
                      label:
                          '${muscleGroupTitleCase(visible[i].group)} ${(visible[i].share * 100).round()}%',
                    ),
                  if (overflow > 0)
                    Text('+$overflow',
                        style:
                            AppText.statLabel(color: surface.textTertiary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One ranked muscle group and its share (0..1) of the routine's total load.
class MuscleLoadEntry {
  final String group;
  final double share;
  const MuscleLoadEntry(this.group, this.share);
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: AppText.statLabel(color: context.surface.textSecondary)),
      ],
    );
  }
}

/// Stacked proportional bar. Outer ends get the rounded caps; inner seams
/// are square with a 2dp gap. Rounding error is absorbed into the last
/// segment so the bar always spans exactly the full width.
class _LoadBarPainter extends CustomPainter {
  final List<double> shares;
  final List<Color> colors;
  final double gap;
  final double radius;

  _LoadBarPainter({
    required this.shares,
    required this.colors,
    this.gap = 2,
    this.radius = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var x = 0.0;
    final usable = size.width - gap * (shares.length - 1);
    for (var i = 0; i < shares.length; i++) {
      var w = usable * shares[i];
      if (i == shares.length - 1) {
        w = size.width - x; // absorb rounding into the last segment
      }
      if (w <= 0) continue;
      final isFirst = i == 0;
      final isLast = i == shares.length - 1;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, 0, w, size.height),
          topLeft: isFirst ? Radius.circular(radius) : Radius.zero,
          bottomLeft: isFirst ? Radius.circular(radius) : Radius.zero,
          topRight: isLast ? Radius.circular(radius) : Radius.zero,
          bottomRight: isLast ? Radius.circular(radius) : Radius.zero,
        ),
        Paint()..color = colors[i],
      );
      x += w + gap;
    }
  }

  @override
  bool shouldRepaint(_LoadBarPainter old) =>
      !_listEquals(old.shares, shares) || !_listEquals(old.colors, colors);

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
