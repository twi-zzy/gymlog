import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymlog/core/providers/premium_provider.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/features/routines/presentation/widgets/routine_detail_styles.dart';
import 'package:gymlog/shared/widgets/premium_paywall.dart';

const kTimeRangeOptions = ['1M', '3M', '6M', '1Y', 'All Time'];

/// Ranges deeper than 6 months are a Pro feature, identically everywhere.
const kProTimeRanges = {'1Y', 'All Time'};

/// THE time-range filter — one chip, one sheet, one lock behavior, shared
/// by Routine Detail, Exercise Detail, and any future chart screen.
class TimeRangeFilter extends ConsumerWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const TimeRangeFilter({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      label: 'Time range filter, currently $value',
      button: true,
      child: GestureDetector(
        onTap: () => _showSheet(context, ref),
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: RDStyles.rangePill),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: Color(0xFF9CA3AF),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref) {
    HapticFeedback.lightImpact();
    final isPremium = ref.read(isPremiumProvider);

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface.withValues(alpha: 0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Time Range',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...kTimeRangeOptions.map((range) {
                    final isSelected = range == value;
                    final isLocked =
                        !isPremium && kProTimeRanges.contains(range);
                    return Semantics(
                      button: true,
                      selected: isSelected && !isLocked,
                      label: isLocked
                          ? '$range, premium, locked'
                          : isSelected
                              ? '$range, selected'
                              : range,
                      child: InkWell(
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        if (isLocked) {
                          showPremiumPaywall(context);
                          return;
                        }
                        HapticFeedback.lightImpact();
                        onChanged(range);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: AppColors.textSecondary
                                  .withValues(alpha: 0.08),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                range,
                                // A locked row must never read as "active" —
                                // showing the accent color AND a lock on the
                                // same row is a contradictory affordance.
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  fontWeight: isSelected && !isLocked
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isLocked
                                      ? AppColors.textSecondary
                                      : isSelected
                                          ? AppColors.accentPrimary
                                          : AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (isLocked)
                              const Icon(
                                Icons.lock_rounded,
                                size: 14,
                                color: Color(0xFFCBB2FF),
                              )
                            else if (isSelected)
                              const Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: AppColors.accentPrimary,
                              ),
                          ],
                        ),
                      ),
                    ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Branded picker sheet for simple option lists (set type, units, filters).
/// Same surface, handle, and row language as every other sheet in the app.
Future<T?> showBrandedPickerSheet<T>({
  required BuildContext context,
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF6A6A6A),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              // Flexible + scroll so long option lists (e.g. 7 rest
              // durations) never overflow on short screens.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: options.map((opt) {
                      final isSelected =
                          selected != null && opt.value == selected;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.of(sheetCtx).pop(opt.value);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 13),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: opt.color.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(opt.icon,
                                      size: 18, color: opt.color),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        opt.label,
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      if (opt.subtitle != null)
                                        Text(
                                          opt.subtitle!,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_rounded,
                                      size: 18, color: AppColors.accentPrimary),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PickerOption<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData icon;
  final Color color;

  const PickerOption({
    required this.value,
    required this.label,
    this.subtitle,
    required this.icon,
    this.color = AppColors.textSecondary,
  });
}
