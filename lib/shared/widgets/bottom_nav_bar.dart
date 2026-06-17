import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';

/// [bottom_nav_bar.dart]
/// Purpose: High-Density Tracker - 3-tab navigation (Home, Workout, Profile)
/// Dependencies: flutter/material.dart, go_router, google_fonts, app_colors.dart
///
/// Active-tab indicator: a small accent underline drawn INSIDE each tab
/// cell, directly under its label. Per-cell rendering means the indicator
/// is centered under the active tab by construction — there is no
/// cross-bar alignment math that can drift. (A previous experiment with a
/// bar-wide animated indicator produced an underline that was visibly
/// off-center under Home/Routines; do not reintroduce one.)

class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key});

  static const _tabs = [
    _NavItem(icon: Icons.home_filled, label: 'Home', path: '/'),
    _NavItem(icon: Icons.fitness_center, label: 'Routines', path: '/workout'),
    _NavItem(icon: Icons.person, label: 'Profile', path: '/profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgBase,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: _tabs.map((tab) {
              final isActive = location == tab.path;
              // Expanded cells: three equal thirds, edge-to-edge tap
              // targets (full cell height — comfortably ≥48dp).
              return Expanded(
                child: _NavButton(
                  item: tab,
                  isActive: isActive,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.go(tab.path);
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String path;
  const _NavItem({required this.icon, required this.label, required this.path});
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isActive,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              color:
                  isActive ? AppColors.accentPrimary : AppColors.textSecondary,
              size: 26,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: GoogleFonts.inter(
                color: isActive
                    ? AppColors.accentPrimary
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 3),
            // Reward-moment underline — grows in under the active label,
            // collapses to nothing when inactive. Centered by the Column,
            // never positioned by hand.
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              height: 2,
              width: isActive ? 16 : 0,
              decoration: BoxDecoration(
                color: AppColors.accentPrimary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
