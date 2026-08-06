import 'package:flutter/material.dart';

/// [app_button_shell.dart]
/// The one layout contract for button content rows.
///
/// Root cause it kills (ship-readiness #3 / D2): a fixed `height:` on a
/// button is a promise about text metrics the app does not control — OS text
/// scale, bold-text, and localisation all change intrinsic label height, so a
/// fixed-height button converts a resize into a clip. Here an invisible
/// [SizedBox] enforces the minimum tap height *as a row child*, so the row
/// can always GROW past the floor, and the label lives inside [Flexible]
/// with ellipsis so horizontal pressure truncates gracefully instead of
/// overflowing the Row.
///
/// Colour, shape and press physics stay with the caller; this owns geometry.
class AppButtonShell extends StatelessWidget {
  final String label;
  final TextStyle style;
  final IconData? icon;
  final double iconSize;

  /// Defaults to [style]'s color. StartButton passes the accent here because
  /// its glyph is the only accent carrier on a neutral-raised button.
  final Color? iconColor;

  /// Minimum tap height — enforced as a floor, never a ceiling.
  final double minHeight;

  /// true → row fills available width (full-width CTAs);
  /// false → row hugs its content (compact inline buttons).
  final bool expand;

  const AppButtonShell({
    super.key,
    required this.label,
    required this.style,
    this.icon,
    this.iconSize = 20,
    this.iconColor,
    this.minHeight = 48,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Invisible min-height child: sets the row's floor while allowing
        // growth — the fixed-`height:` replacement.
        SizedBox(height: minHeight),
        if (icon != null) ...[
          Icon(icon, size: iconSize, color: iconColor ?? style.color),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}
