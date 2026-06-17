import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// [app_text.dart]
/// The Copper Void typography system — one font (Inter), six voices.
///
/// Inter is configured with tabular figures ("tnum") so numbers never jitter
/// when values change, and the alternate single-story g ("ss03") to give it a
/// quiet, intentional character distinct from default Inter.
///
/// MIGRATION (Commit 2/3 — deferred to the local SDK run): ~38 files still call
/// `GoogleFonts.inter(...)` inline (tabular figures applied piecemeal, ss03
/// nowhere). Migrate each to the nearest voice below; no text size should exist
/// outside these six voices.
///
/// `FontFeature` resolves via `package:flutter/material.dart` (it is used the
/// same way elsewhere in this codebase, e.g. set_row.dart), so no `dart:ui`
/// import is needed.
abstract class AppText {
  /// Inter numeric/character features — tabular figures + the alternate g.
  static const List<FontFeature> kInterFeatures = <FontFeature>[
    FontFeature.tabularFigures(),
    FontFeature.stylisticSet(3), // ss03 — alternate single-story g
  ];

  /// Display — the single largest number on screen (rest timer, PR number).
  /// Used sparingly, only where glance-from-arm's-length is real.
  static TextStyle display({Color color = AppColors.textPrimary}) =>
      GoogleFonts.inter(
        fontSize: 26,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.5,
        color: color,
        fontFeatures: kInterFeatures,
      );

  /// Title — screen titles. Left-aligned, never centered.
  static TextStyle title({Color color = AppColors.textPrimary}) =>
      GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: color,
        fontFeatures: kInterFeatures,
      );

  /// Body — exercise names, routine titles, descriptions.
  static TextStyle body({Color color = AppColors.textPrimary}) =>
      GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: color,
        fontFeatures: kInterFeatures,
      );

  /// Value — the bread-and-butter number: weights, reps, volume in rows.
  /// Tabular; right-align in rows, left-align set indices.
  static TextStyle value({Color color = AppColors.textPrimary}) =>
      GoogleFonts.inter(
        fontSize: 17,
        fontWeight: FontWeight.w500,
        color: color,
        fontFeatures: kInterFeatures,
      );

  /// Label — set numbers, units, metadata. UPPERCASE, generous tracking.
  static TextStyle label({Color color = AppColors.textLabel}) =>
      GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.6, // ~0.05em at 12px
        color: color,
        fontFeatures: kInterFeatures,
      );

  /// Caption — timestamps, hints, secondary metadata.
  static TextStyle caption({Color color = AppColors.textGhost}) =>
      GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: color,
        fontFeatures: kInterFeatures,
      );
}
