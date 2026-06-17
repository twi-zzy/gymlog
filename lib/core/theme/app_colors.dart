import 'package:flutter/material.dart';

/// [app_colors.dart]
/// Purpose: "Clinical Void" design system — GitHub/Linear dark canvas with a
/// cool teal action accent and a single warm gold reward accent.
///
/// IMPLEMENTATION NOTE (Clinical Void · Commit 1):
/// Token NAMES are preserved from the previous (purple) system so NO call site
/// breaks — only VALUES are re-pointed. New tokens (elevated, borderFocus,
/// primaryMuted, reward, rewardMuted) are additive.
/// Off-system semantics are folded onto the two accents:
///   success → teal  (completed / positive = the action color, per the spec)
///   warning → gold  (warmup / trophy = reward-adjacent)
/// muscleSplitPalette is re-pointed to a teal ramp (no purple); treat as
/// provisional pending the screenshot pass.
abstract class AppColors {
  // ── The Void (cool dark base) ───────────────────────────────────────────
  static const bgBase    = Color(0xFF0D1117); // Canvas — root background
  static const bgSurface = Color(0xFF161B22); // Surface — cards, list rows, inputs
  static const elevated  = Color(0xFF1F2937); // Elevated — modals, sheets, menus

  // Legacy surface aliases re-pointed onto the new steps.
  static const surfaceCard   = Color(0xFF161B22); // == Surface
  static const surfaceRaised = Color(0xFF1F2937); // == Elevated
  static const bgSheet       = Color(0xFF1F2937); // == Elevated

  // ── Structure ───────────────────────────────────────────────────────────
  static const borderSubtle = Color(0xFF30363D); // Border — 1px dividers, outlines, inputs
  static const borderFocus  = Color(0xFF00C4A0); // Border Focus — 2px focus ring (teal)

  // ── Accents (two colors, two jobs) ──────────────────────────────────────
  // Teal = ACTION ("do this"). accentPrimary IS teal (re-pointed from purple).
  static const accentPrimary = Color(0xFF00C4A0); // Primary — CTA fill, active, focus, completed-set
  static const primaryMuted  = Color(0x2600C4A0); // teal @ ~15% — pressed / active-row backdrop
  static const accentText    = Color(0xFF00C4A0); // accent text/icons on canvas (~8.4:1)

  // Gold = REWARD ("you did this"). The only warm element.
  static const reward       = Color(0xFFE6C84A); // PR badge, streak, goal completion
  static const rewardMuted  = Color(0x26E6C84A); // gold @ ~15% — reward glow / backdrop

  // ── Text hierarchy (GitHub tokens; checked on canvas) ───────────────────
  static const textPrimary   = Color(0xFFF0F6FC); // crisp cool white — headlines, numbers, body
  static const textSecondary = Color(0xFF8B949E); // ~5.7:1 — labels, captions, metadata, placeholders
  static const textDisabled  = Color(0xFF484F58); // disabled controls ONLY (WCAG-exempt)

  // ── Semantic ────────────────────────────────────────────────────────────
  static const error   = Color(0xFFF85149); // Destructive — delete / discard / remove (NOT the brand)
  static const success = Color(0xFF00C4A0); // folded → teal (completed/positive = action)
  static const warning = Color(0xFFE6C84A); // folded → gold (reward-adjacent)

  // ── Charts ──────────────────────────────────────────────────────────────
  static const chartAxisLabel = Color(0xFF8B949E); // == Text Secondary

  // Provisional teal ramp (replaces the purple palette; no purple remains).
  // Categorical muscle slices — revisit during the screenshot pass.
  static const muscleSplitPalette = [
    Color(0xFF00C4A0), // teal (primary)
    Color(0xFF4FD1B5),
    Color(0xFF7FDEC8),
    Color(0xFF2C8C77),
    Color(0xFF1F6B5B),
    Color(0xFF8B949E), // grey fallback
  ];
}
