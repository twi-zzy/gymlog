import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_text.dart';

/// [app_theme.dart]
/// Purpose: "Clinical Void" — cool GitHub/Linear dark canvas, teal action accent,
/// data over decoration. Every theme text style carries Inter tabular figures so
/// theme-driven numbers never jitter.

// Inter with tabular figures baked in. `color` is nullable so button text styles
// can defer to their foregroundColor while still gaining tabular figures.
TextStyle _ct({
  required double fontSize,
  required FontWeight fontWeight,
  Color? color,
  double? letterSpacing,
}) =>
    GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      fontFeatures: kInterFeatures,
    );

final appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: GoogleFonts.inter().fontFamily,

  colorScheme: const ColorScheme.dark(
    surface: AppColors.bgBase,
    surfaceContainerHighest: AppColors.bgSurface,
    primary: AppColors.accentPrimary,
    // Dark text on the teal CTA: canvas-on-teal ~8.4:1. (White-on-teal was ~2:1.)
    onPrimary: AppColors.bgBase,
    secondary: AppColors.bgSurface,
    onSecondary: AppColors.textPrimary,
    error: AppColors.error,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    outline: AppColors.borderSubtle,
  ),

  scaffoldBackgroundColor: AppColors.bgBase,
  cardColor: AppColors.bgSurface,
  dividerColor: AppColors.borderSubtle,

  appBarTheme: AppBarTheme(
    backgroundColor: AppColors.bgBase,
    elevation: 0,
    // Kill M3's scroll-under tint: on the dark canvas it renders as a faint
    // tinted band behind the title the moment content scrolls under.
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    titleTextStyle: _ct(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
      letterSpacing: -0.5,
    ),
  ),

  // Bottom sheets float above content → Round (20).
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: AppColors.elevated,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: AppRadius.roundTop),
  ),

  // Cards → Soft (12).
  cardTheme: const CardThemeData(
    elevation: 0,
    color: AppColors.bgSurface,
    shadowColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: AppRadius.softAll),
  ),

  // Inputs → Sharp (4), 1px Border, teal focus ring.
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.bgSurface,
    border: const OutlineInputBorder(
      borderRadius: AppRadius.sharpAll,
      borderSide: BorderSide(color: AppColors.borderSubtle),
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: AppRadius.sharpAll,
      borderSide: BorderSide(color: AppColors.borderSubtle),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: AppRadius.sharpAll,
      borderSide: BorderSide(color: AppColors.borderFocus, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    hintStyle: _ct(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AppColors.textSecondary,
    ),
  ),

  // Primary CTA → pill, teal fill, dark text.
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.accentPrimary,
      foregroundColor: AppColors.bgBase,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      textStyle: _ct(fontWeight: FontWeight.w700, fontSize: 16),
    ),
  ),

  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.accentPrimary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: _ct(fontWeight: FontWeight.w600, fontSize: 16),
    ),
  ),

  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(foregroundColor: AppColors.textPrimary),
  ),

  textTheme: TextTheme(
    // Headers
    displayLarge: _ct(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.5),
    headlineLarge: _ct(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.5),
    headlineMedium: _ct(
        fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    titleLarge: _ct(
        fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),

    // Data points
    titleMedium: _ct(
        fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    titleSmall: _ct(
        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),

    // Body
    bodyLarge: _ct(
        fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textPrimary),
    bodyMedium: _ct(
        fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textPrimary),

    // Subtext
    bodySmall: _ct(
        fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
    labelLarge: _ct(
        fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
    labelMedium: _ct(
        fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
    labelSmall: _ct(
        fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
  ),
);

// ── High-contrast variant ───────────────────────────────────────────────────
// Selected automatically by MaterialApp when the OS "increase contrast" setting
// is on. Brightens secondary text and makes dividers/borders clearly visible.
//
// COVERAGE NOTE: this reaches theme-derived widgets (default Text via the text
// theme, dividers, input borders, the color scheme). Screens that hardcode
// `AppColors.textSecondary` / inline `GoogleFonts.inter(color: ...)` bypass the
// theme and are NOT recolored by this — a full migration of those call sites is
// the remaining work (see the PR notes).
const _hcSecondary = Color(0xFFD2D2D7); // very high contrast on the dark canvas
const _hcBorder = Color(0xFF8A8A8E); // clearly visible divider/border

final appHighContrastTheme = appTheme.copyWith(
  dividerColor: _hcBorder,
  colorScheme: appTheme.colorScheme.copyWith(
    onSurfaceVariant: _hcSecondary,
    outline: _hcBorder,
  ),
  textTheme: appTheme.textTheme.copyWith(
    bodySmall: appTheme.textTheme.bodySmall?.copyWith(color: _hcSecondary),
    labelLarge: appTheme.textTheme.labelLarge?.copyWith(color: _hcSecondary),
    labelMedium: appTheme.textTheme.labelMedium?.copyWith(color: _hcSecondary),
    labelSmall: appTheme.textTheme.labelSmall?.copyWith(color: _hcSecondary),
  ),
);
