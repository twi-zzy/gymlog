import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// [app_text.dart]
/// Clinical Void design tokens: typography (one Inter scale, six roles) and the
/// four-radius shape law. `FontFeature` resolves via material (used the same way
/// elsewhere in this codebase), so no `dart:ui` import is needed.

/// Inter numeric features — tabular figures so numbers never jitter.
const List<FontFeature> kInterFeatures = <FontFeature>[
  FontFeature.tabularFigures(),
];

abstract class AppText {
  /// Hero — rest timer, PR number. One per screen, max. (Center where used.)
  static TextStyle hero({Color color = AppColors.textPrimary}) =>
      GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: color,
        fontFeatures: kInterFeatures,
      );

  /// Title — screen titles. Left-aligned, never centered.
  static TextStyle title({Color color = AppColors.textPrimary}) =>
      GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: color,
        fontFeatures: kInterFeatures,
      );

  /// Body — exercise names, descriptions.
  static TextStyle body({Color color = AppColors.textPrimary}) =>
      GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: color,
        fontFeatures: kInterFeatures,
      );

  /// Value — weights, reps, volume. Tabular; right-align in rows.
  static TextStyle value({Color color = AppColors.textPrimary}) =>
      GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w500,
        color: color,
        fontFeatures: kInterFeatures,
      );

  /// Label — units, metadata. UPPERCASE, 0.05em tracking.
  static TextStyle label({Color color = AppColors.textSecondary}) =>
      GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.6, // ~0.05em at 12px
        color: color,
        fontFeatures: kInterFeatures,
      );

  /// Caption — timestamps, hints.
  static TextStyle caption({Color color = AppColors.textSecondary}) =>
      GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: color,
        fontFeatures: kInterFeatures,
      );
}

/// The four-radius "Slightly Rounded" law. Pill = `StadiumBorder()`.
abstract class AppRadius {
  static const double sharp = 4; // data rows, inputs, secondary buttons, chips
  static const double soft = 12; // cards, list containers, sheets-as-cards
  static const double round = 20; // modals, bottom sheets, dialogs

  static const BorderRadius sharpAll = BorderRadius.all(Radius.circular(sharp));
  static const BorderRadius softAll = BorderRadius.all(Radius.circular(soft));
  static const BorderRadius roundAll = BorderRadius.all(Radius.circular(round));
  static const BorderRadius roundTop =
      BorderRadius.vertical(top: Radius.circular(round));
}
