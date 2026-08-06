import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/theme/app_text.dart';
import 'package:gymlog/core/theme/dynamic_accent_theme.dart';
import 'package:gymlog/features/workout/presentation/providers/rest_timer_provider.dart';
import 'package:gymlog/features/workout/presentation/widgets/rest_timer_bar.dart';
import 'package:gymlog/shared/widgets/feedback/undoable_delete.dart';

/// Semantic meaning of a snackbar. Feedback color is information, not
/// decoration: success and failure must never render in the same neutral
/// grey as a purely informational note.
enum AppSnackBarVariant { neutral, success, error }

/// Resolved visuals for an [AppSnackBarVariant]. Shape-first: the icon
/// carries the meaning so the signal survives colour-blindness and the
/// light theme; the tint and hairline are reinforcement, not the message.
class _SnackBarStyle {
  final Color background;
  final Color border;
  final IconData? icon;
  final Color? iconColor;

  const _SnackBarStyle({
    required this.background,
    required this.border,
    this.icon,
    this.iconColor,
  });
}

/// Global snackbar helper providing standardized floating snackbar alerts.
///
/// Features:
/// - Floating behavior with 16dp horizontal margins and 14dp radius
/// - Semantic variants: success (accent tint + check glyph) and error
///   (error tint + error glyph) layered on the neutral default
/// - Maximum two lines of text with ellipsis
/// - Auto-adjusting bottom offset so it clears the active rest timer bar
///   (read from [restTimerProvider] via the optional [ref])
/// - Accent-tinted action button
/// - Does not dismiss a showing undoable-delete snackbar, so a rapid
///   double-action can never silently finalize a pending deletion
void showAppSnackBar(
  BuildContext context, {
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
  WidgetRef? ref,
  Color? backgroundColor,
  AppSnackBarVariant variant = AppSnackBarVariant.neutral,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.of(context);
  // An active undo snackbar must survive until its window elapses or the
  // user presses Undo — clearing it would finalize the pending deletion.
  if (!hasActiveUndoSnackBar) {
    messenger.clearSnackBars();
  }

  final accent = context.accent;
  final surface = context.surface;
  final restBarVisible = ref?.read(restTimerProvider) != null;
  final restBarOffset = restBarVisible ? kRestTileHeight + 18 : 0;
  final bottomPadding =
      MediaQuery.viewPaddingOf(context).bottom + restBarOffset + 12;

  final style = switch (variant) {
    // Saturation ladder: large tinted fills at 14%/12%, borders at 35%/45%,
    // small marks at 100% — mirrors the opacity policy in app_colors.dart.
    AppSnackBarVariant.success => _SnackBarStyle(
        background: Color.alphaBlend(
          accent.base.withValues(alpha: 0.14),
          surface.surface3,
        ),
        border: accent.base.withValues(alpha: 0.35),
        icon: Icons.check_circle_rounded,
        iconColor: accent.base,
      ),
    AppSnackBarVariant.error => _SnackBarStyle(
        background: Color.alphaBlend(
          AppColors.error.withValues(alpha: 0.12),
          surface.surface3,
        ),
        border: AppColors.error.withValues(alpha: 0.45),
        icon: Icons.error_rounded,
        iconColor: AppColors.error,
      ),
    AppSnackBarVariant.neutral => _SnackBarStyle(
        background: surface.surface3,
        border: surface.borderSubtle,
      ),
  };
  final icon = style.icon;

  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: duration,
      elevation: 4,
      backgroundColor: backgroundColor ?? style.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.snackbar),
        side: BorderSide(color: style.border, width: 1.0),
      ),
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
      content: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: style.iconColor),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(color: surface.textPrimary),
            ),
          ),
        ],
      ),
      action: actionLabel != null
          ? SnackBarAction(
              label: actionLabel,
              textColor: accent.light,
              onPressed: onAction ?? () {},
            )
          : null,
    ),
  );
}
