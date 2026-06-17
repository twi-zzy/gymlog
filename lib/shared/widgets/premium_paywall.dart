import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show IntroductoryPrice, Offerings, Package, PackageType, PeriodUnit;

import '../../core/providers/premium_provider.dart';
import '../../core/theme/app_colors.dart';

/// Opens the Premium paywall as a modal bottom sheet.
/// Safe to call when RevenueCat is unconfigured — it renders a graceful
/// "pricing unavailable" state instead of crashing.
Future<void> showPremiumPaywall(BuildContext context) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PaywallSheet(),
  );
}

/// Upsell shown when a free user hits the routine cap ([kFreeRoutineLimit]).
/// States the limit honestly and routes straight to the paywall — one flow,
/// shared tokens. Free users keep every routine they already have.
Future<void> showRoutineLimitUpsell(BuildContext context) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => Container(
      decoration: const BoxDecoration(
        color: AppColors.bgSheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A6A6A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentPrimary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.workspace_premium_rounded,
                    color: Color(0xFFCBB2FF), size: 24),
              ),
              const SizedBox(height: 14),
              Text(
                'Routine limit reached',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The free plan includes up to $kFreeRoutineLimit routines — '
                'enough for a Push / Pull / Legs / Full-Body split. Upgrade to '
                'Pro for unlimited routines and full analytics history.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(sheetCtx).pop();
                    showPremiumPaywall(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Unlock Unlimited Routines',
                    style: GoogleFonts.inter(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                  child: Text(
                    'Not now',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
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

/// Small "PRO" lock pill used next to gated features.
/// Subtle by design — a hint, not a banner. Tapping opens the paywall.
class ProLockPill extends StatelessWidget {
  final String label;

  const ProLockPill({super.key, this.label = 'PRO'});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Premium feature. Double tap to learn more.',
      child: GestureDetector(
        onTap: () => showPremiumPaywall(context),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accentPrimary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.accentPrimary.withValues(alpha: 0.30),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded,
                  size: 10, color: Color(0xFFCBB2FF)),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: const Color(0xFFCBB2FF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaywallSheet extends ConsumerStatefulWidget {
  const _PaywallSheet();

  @override
  ConsumerState<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<_PaywallSheet> {
  Offerings? _offerings;
  bool _loading = true;
  bool _purchasing = false;
  Package? _selected;

  // HONESTY RULE: this list may only name things that exist in the app
  // today. Advertising unbuilt features in a paid subscription is a
  // Play/App Store rejection risk and a user-trust killer. The first row
  // deliberately reaffirms what stays free.
  static const _features = [
    (Icons.all_inclusive_rounded, 'Unlimited workouts', 'Free, forever'),
    (Icons.insights_rounded, 'Full analytics history', 'Every chart, all of it'),
    (Icons.date_range_rounded, 'All time ranges', '1Y and All Time unlocked'),
  ];

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    final offerings = await ref.read(premiumServiceProvider).offerings();
    if (!mounted) return;
    setState(() {
      _offerings = offerings;
      _loading = false;
      _selected = _annual ?? _monthly;
    });
  }

  Package? get _monthly => _offerings?.current?.availablePackages
      .where((p) => p.packageType == PackageType.monthly)
      .firstOrNull;

  Package? get _annual => _offerings?.current?.availablePackages
      .where((p) => p.packageType == PackageType.annual)
      .firstOrNull;

  bool get _storeReady => _monthly != null || _annual != null;

  /// Free-trial intro offer on the selected package, or null. A paid intro
  /// price (e.g. discounted first month) is NOT a free trial — claiming
  /// "free" for it would be a store-policy violation.
  IntroductoryPrice? get _freeTrial {
    final intro = _selected?.storeProduct.introductoryPrice;
    if (intro == null || intro.price > 0) return null;
    return intro;
  }

  /// CTA + caption derive from the live offering — never hardcode trial
  /// terms the store may not actually grant.
  String get _ctaLabel =>
      _freeTrial != null ? 'Start Free Trial' : 'Upgrade to Pro';

  String get _ctaCaption {
    final trial = _freeTrial;
    if (trial == null) return 'Cancel anytime.';
    return '${_trialLength(trial)} free, cancel anytime.';
  }

  static String _trialLength(IntroductoryPrice intro) {
    final n = intro.periodNumberOfUnits;
    return switch (intro.periodUnit) {
      PeriodUnit.day => n == 1 ? '1 day' : '$n days',
      PeriodUnit.week => '${n * 7} days',
      PeriodUnit.month => n == 1 ? '1 month' : '$n months',
      PeriodUnit.year => n == 1 ? '1 year' : '$n years',
      _ => '$n days',
    };
  }

  Future<void> _purchase() async {
    final package = _selected;
    if (package == null || _purchasing) return;
    HapticFeedback.mediumImpact();
    setState(() => _purchasing = true);

    try {
      final info =
          await ref.read(premiumServiceProvider).purchasePackage(package);
      if (!mounted) return;
      if (info != null && info.entitlements.active.isNotEmpty) {
        HapticFeedback.heavyImpact();
        Navigator.of(context).pop();
        _snack('Welcome to GymLog Pro — everything is unlocked.');
      }
    } catch (e) {
      if (mounted) _snack('Purchase failed. You were not charged.');
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restore() async {
    HapticFeedback.lightImpact();
    try {
      final info = await ref.read(premiumServiceProvider).restorePurchases();
      if (!mounted) return;
      if (info != null && info.entitlements.active.isNotEmpty) {
        HapticFeedback.heavyImpact();
        Navigator.of(context).pop();
        _snack('Pro restored. Welcome back.');
      } else {
        _snack('No previous purchases found.');
      }
    } catch (_) {
      if (mounted) _snack('Restore failed. Try again later.');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(message, style: GoogleFonts.inter(color: AppColors.textPrimary)),
      backgroundColor: AppColors.bgSurface,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A6A6A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Header ────────────────────────────────────────────────
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accentPrimary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.workspace_premium_rounded,
                    color: Color(0xFFCBB2FF), size: 24),
              ),
              const SizedBox(height: 14),
              Text(
                'Unlock Premium',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Go deeper on the data behind your training.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),

              // ── Features ──────────────────────────────────────────────
              for (final (icon, title, subtitle) in _features)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Icon(icon, size: 19, color: const Color(0xFF00C4A0)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),

              // ── Pricing ───────────────────────────────────────────────
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(
                        color: AppColors.accentPrimary, strokeWidth: 2),
                  ),
                )
              else if (_storeReady) ...[
                if (_annual != null)
                  _PackageRow(
                    title: 'Yearly',
                    price: _annual!.storeProduct.priceString,
                    caption: 'per year',
                    badge: 'BEST VALUE',
                    selected: _selected == _annual,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selected = _annual);
                    },
                  ),
                if (_annual != null && _monthly != null)
                  const SizedBox(height: 10),
                if (_monthly != null)
                  _PackageRow(
                    title: 'Monthly',
                    price: _monthly!.storeProduct.priceString,
                    caption: 'per month',
                    selected: _selected == _monthly,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selected = _monthly);
                    },
                  ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _purchasing ? null : _purchase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _purchasing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            _ctaLabel,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    _ctaCaption,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ] else
                // RevenueCat unreachable / unconfigured — honest, no fakes.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Pricing is unavailable right now. You are on the free '
                    'plan — workout logging stays free, forever.',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              // ── Secondary actions ─────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Maybe Later',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (_storeReady) ...[
                    Container(
                      width: 3,
                      height: 3,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6A6A6A),
                        shape: BoxShape.circle,
                      ),
                    ),
                    TextButton(
                      onPressed: _restore,
                      child: Text(
                        'Restore Purchases',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackageRow extends StatelessWidget {
  final String title;
  final String price;
  final String caption;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  const _PackageRow({
    required this.title,
    required this.price,
    required this.caption,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title plan, $price $caption',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentPrimary.withValues(alpha: 0.10)
                : AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.accentPrimary.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.06),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 18,
                color: selected
                    ? AppColors.accentPrimary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accentPrimary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: const Color(0xFFCBB2FF),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    caption,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
