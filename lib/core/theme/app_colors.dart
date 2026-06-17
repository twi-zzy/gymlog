import 'package:flutter/material.dart';

/// [app_colors.dart]
/// Purpose: The Copper Void design system — a monochrome void base with ONE
/// disciplined copper accent ("the ember"). OLED-first, dark only.
///
/// IMPLEMENTATION NOTE (Copper Void v1.0 · Commit 1):
/// Token NAMES are preserved from the previous purple system so that NO call
/// site breaks — only their VALUES are re-pointed. New tokens (copper*,
/// textGhost, textLabel, hairline, elevated, *HighContrast) are purely
/// additive. `muscleSplitPalette` is intentionally left purple here; it is
/// recolored in place during Commit 4 (the accent-demotion audit), NOT now,
/// so the muscle-split bar keeps compiling between commits.
abstract class AppColors {
  // ── The Void (monochrome base) ──────────────────────────────────────────
  static const bgBase    = Color(0xFF000000); // Void — root canvas
  static const bgSurface = Color(0xFF0A0A0A); // Surface — cards, inputs, sheets, rows
  static const elevated  = Color(0xFF111111); // Elevated — pressed / active / focused surfaces

  // Legacy surface aliases, re-pointed onto the new luminance steps so existing
  // call sites land on-system without edits.
  static const surfaceCard   = Color(0xFF0A0A0A); // == Surface
  static const surfaceRaised = Color(0xFF111111); // == Elevated
  static const bgSheet       = Color(0xFF111111); // sheets / dialogs sit one step above the void

  // ── Structure ───────────────────────────────────────────────────────────
  // Default separation is "felt-not-seen": a 6% white hairline + the luminance
  // step. `borderSubtle` is the STRONG edge, used only where the hairline alone
  // is insufficient.
  static const hairline     = Color(0x0FFFFFFF); // white @ ~6% — default divider / border
  static const borderSubtle = Color(0xFF1C1C1C); // Border Strong — optional stronger edge

  // ── Copper (the single accent) ──────────────────────────────────────────
  // The only color in the UI chrome. Allowed in EXACTLY three contexts:
  // (1) the primary action, (2) the active/selected state, (3) the reward.
  // `accentPrimary` IS copper — re-pointed from electric purple #8A2BE2.
  static const accentPrimary = Color(0xFFC67C3B); // Copper Primary — CTA fill, active, PR fill (~6.4:1 on black)
  static const copperLight   = Color(0xFFE8A87C); // accent text on black, thin lines, glows (~10:1)
  static const copperDark    = Color(0xFF8B5A2B); // pressed / disabled accent
  static const copperGlow    = Color(0x26C67C3B); // copper @ ~15% — ambient glow behind reward moments

  // Legacy alias: `accentText` was the on-black accent-text tint (was purple
  // #B98CFF). Re-pointed to Copper Light so existing link/label call sites
  // become copper automatically.
  static const accentText = copperLight;

  // ── Text hierarchy (all WCAG-checked on #000) ───────────────────────────
  static const textPrimary   = Color(0xFFE8E6E3); // warm white — headlines, numbers, primary actions
  static const textSecondary = Color(0xFF808080); // ~5.3:1 — body/descriptions (>=16px) & muted text
  static const textLabel     = Color(0xFF808080); // ~5.3:1 — 12px uppercase labels / units / metadata
  static const textGhost     = Color(0xFF7A7A7A); // ~4.9:1 — previous-set values, timestamps, hints, placeholders
  static const textDisabled  = Color(0xFF3D3D3D); // ~1.9:1 — GENUINELY disabled chrome ONLY (WCAG-exempt)

  // High-contrast overrides (wired by a high-contrast theme; see report).
  static const textSecondaryHighContrast = Color(0xFF8A8A8A); // ~6.1:1
  static const textGhostHighContrast     = Color(0xFF9A9A9A); // ~7.4:1

  // ── Semantic ────────────────────────────────────────────────────────────
  static const error = Color(0xFFFF5449); // Destructive — destructive actions ONLY (delete account)

  // NOTE: success/warning are RETAINED so existing call sites compile, but they
  // are OFF-SYSTEM for the Copper Void and must be DEMOTED in Commit 4:
  //   success → completed/active state becomes Copper (Context 2)
  //   warning → monochrome (textGhost), or Copper for a reward (Context 3)
  static const success = Color(0xFF34C759); // DEMOTE in Commit 4
  static const warning = Color(0xFFFFCC00); // DEMOTE in Commit 4

  // ── Charts ──────────────────────────────────────────────────────────────
  static const chartAxisLabel = Color(0xFF7A7A7A); // == textGhost (Caption voice on axes)

  // PURPLE ON PURPOSE — recolored to white-at-varying-opacity in Commit 4.
  // Do NOT delete: the muscle-split bar references this and must keep compiling.
  static const muscleSplitPalette = [
    Color(0xFF8A2BE2),
    Color(0xFF7B68EE),
    Color(0xFFB19CD9),
    Color(0xFF4B0082),
    Color(0xFF9932CC),
    Color(0xFF5D3FD3),
  ];
}
