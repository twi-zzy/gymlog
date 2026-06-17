import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_text.dart';

/// [app_theme.dart]
/// Purpose: The Copper Void — OLED-first, data over decoration.
/// Every theme text style carries Inter's tabular figures + alternate g
/// (see [AppText.kInterFeatures]) so theme-driven numbers never jitter.

// Inter with the Copper Void numeric features baked in. `color` is nullable so
// button text styles can defer to their foregroundColor (matching the prior
// behavior) while still gaining tabular figures.
TextStyle _ctext({
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
      fontFeatures: AppText.kInterFeatures,
    );

final appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: GoogleFonts.inter().fontFamily,

  colorScheme: const ColorScheme.dark(
    surface: AppColors.bgBase,
    surfaceContainerHighest: AppColors.bgSurface,
    primary: AppColors.accentPrimary,
    // Black text on the copper CTA: ~6.4:1. Warm-white on copper was ~2.6:1
    // and failed AA — this is the accessible pairing.
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
    // Kill M3's scroll-under tint: on OLED black it renders as a faint band
    // behind the title the moment content scrolls under.
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    titleTextStyle: _ctext(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
      letterSpacing: -0.5,
    ),
  ),

  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: AppColors.bgSurface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
  ),

  cardTheme: const CardThemeData(
    elevation: 0,
    color: AppColors.bgSurface,
    shadowColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.bgSurface,
    border: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide.none,
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide.none,
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      // Focused input is an active state (Context 2) → copper.
      borderSide: BorderSide(color: AppColors.accentPrimary, width: 2),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    hintStyle: _ctext(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AppColors.textSecondary,
    ),
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.accentPrimary,
      foregroundColor: AppColors.bgBase, // black on copper (see onPrimary note)
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      textStyle: _ctext(
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
    ),
  ),

  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.accentPrimary,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: _ctext(
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    ),
  ),

  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      foregroundColor: AppColors.textPrimary,
    ),
  ),

  textTheme: TextTheme(
    // Headers
    displayLarge: _ctext(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.5),
    headlineLarge: _ctext(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.5),
    headlineMedium: _ctext(
        fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    titleLarge: _ctext(
        fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),

    // Data points
    titleMedium: _ctext(
        fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    titleSmall: _ctext(
        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),

    // Body
    bodyLarge: _ctext(
        fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textPrimary),
    bodyMedium: _ctext(
        fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textPrimary),

    // Subtext
    bodySmall: _ctext(
        fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
    labelLarge: _ctext(
        fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
    labelMedium: _ctext(
        fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
    labelSmall: _ctext(
        fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
  ),
);
