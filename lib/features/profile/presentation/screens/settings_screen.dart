import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gymlog/core/providers/app_info_provider.dart';
import 'package:gymlog/core/providers/database_provider.dart';
import 'package:gymlog/core/providers/premium_provider.dart';
import 'package:gymlog/core/providers/settings_provider.dart';
import 'package:gymlog/core/services/notification_service.dart';
import 'package:gymlog/core/services/sync_engine.dart';
import 'package:gymlog/core/services/sync_entitlement_gate.dart';
import 'package:gymlog/core/services/sync_status_provider.dart';
import 'package:gymlog/core/services/workout_export_service.dart';
import 'package:gymlog/core/services/sign_out_coordinator.dart';
import 'package:gymlog/core/services/exercise_media_cache_manager.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/theme/app_text.dart';
import 'package:gymlog/core/theme/dynamic_accent_theme.dart';
import 'package:gymlog/core/utils/tap_guard.dart';
import 'package:gymlog/features/auth/presentation/providers/auth_provider.dart';
import 'package:gymlog/features/auth/presentation/providers/tour_provider.dart';
import 'package:gymlog/features/profile/presentation/providers/profile_provider.dart';
import 'package:gymlog/features/profile/presentation/providers/profile_stats_provider.dart';
import 'package:gymlog/features/workout/presentation/providers/rest_timer_provider.dart';
import 'package:gymlog/shared/widgets/premium_paywall.dart';
import 'package:gymlog/shared/widgets/ui/app_action_row.dart';
import 'package:gymlog/shared/widgets/ui/app_card.dart';
import 'package:gymlog/shared/widgets/ui/app_dialog.dart';
import 'package:gymlog/shared/widgets/ui/app_snack_bar.dart';
import 'package:gymlog/shared/widgets/ui/branded_bottom_sheet.dart';
import 'package:gymlog/shared/widgets/ui/duration_slider.dart';
import 'package:gymlog/shared/widgets/ui/primary_button.dart';
import 'package:gymlog/shared/widgets/ui/time_range_filter.dart';
import 'package:gymlog/core/config/legal_links.dart';
import 'package:gymlog/shared/widgets/tour/spotlight_tour_overlay.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gymlog/shared/layout/adaptive.dart';

/// Weekly-goal picker, shared by Settings and the Profile goal ring.
Future<void> showWeeklyGoalSheet(BuildContext context, WidgetRef ref) async {
  final current = ref.read(weeklyGoalProvider);
  HapticFeedback.lightImpact();
  final accent = context.accent;
  final surface = context.surface;

  await showBrandedBottomSheet<void>(
    context: context,
    title: 'Weekly goal',
    subtitle: 'How many days a week do you want to train?',
    // C32: was a 7-way Expanded Row. Splitting a sheet only ~24dp-inset on
    // each side into 7 equal flex slots, each further shrunk by 4dp/side of
    // its own padding, left the actual tap target under 44dp on effectively
    // every phone width up to ~410dp (as low as ~31dp at 320dp) — a real
    // touch-target miss on the single most common device band (booked from
    // B20). Fixed-size buttons in a centered Wrap guarantee 46x48 everywhere
    // and simply drop to a second row on screens too narrow for all seven.
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var days = 1; days <= 7; days++)
          Semantics(
            button: true,
            selected: days == current,
            excludeSemantics: true,
            label: '$days day${days == 1 ? '' : 's'} per week',
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(weeklyGoalProvider.notifier).setGoal(days);
                Navigator.of(context, rootNavigator: true).pop();
              },
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                width: 46,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: days == current ? accent.base : surface.surface2,
                  borderRadius:
                      BorderRadius.circular(AppRadius.buttonSecondary),
                ),
                child: Text(
                  '$days',
                  style: AppText.button(
                    color:
                        days == current ? accent.onAccent : surface.textPrimary,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Settings — grouped rows, clear information architecture, zero social clutter.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool? _syncEnabled;
  int _devTapCount = 0;
  // C39: hasPermission() existed with zero call sites anywhere in the app —
  // once a user denied the cold-start notification prompt (see C36), nothing
  // in-app could ever show that, or offer a way back. This mirrors it live
  // and refreshes on resume so returning from the OS Settings app (via the
  // row below) reflects the change immediately.
  bool? _notificationsEnabled;

  /// Key attached to the Rest timer row — used by the step-3 tour spotlight
  /// so the overlay can locate its screen position from the Settings route.
  final GlobalKey _restTimerRowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSyncPref();
    _loadNotificationPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadNotificationPermission();
    }
  }

  Future<void> _loadNotificationPermission() async {
    final enabled = await ref.read(notificationServiceProvider).hasPermission();
    if (mounted) setState(() => _notificationsEnabled = enabled);
  }

  Future<void> _loadSyncPref() async {
    // A preferences read falling back to the getter's default is fine, but a
    // failure must still be surfaced — silently assuming sync is ON for a
    // sync that may not actually be configured is the same silent-failure
    // data-loss story as the toggle path below.
    var enabled = true;
    var readOk = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool(kSyncEnabledKey) ?? true;
    } catch (_) {
      enabled = true;
      readOk = false;
    }
    if (mounted) {
      setState(() => _syncEnabled = enabled);
      if (!readOk) {
        showAppSnackBar(
          context,
          message: "Couldn't read your sync setting. The default is shown.",
          variant: AppSnackBarVariant.error,
        );
      }
    }
  }

  Future<void> _toggleSync(bool value) async {
    final isPremium = ref.read(isPremiumProvider);
    final user = ref.read(authProvider);
    final userId = user?.id ?? '';
    if (userId.isEmpty) return;

    HapticFeedback.selectionClick();
    final gate = ref.read(syncEntitlementGateProvider);
    final engine = ref.read(syncEngineProvider);
    final previous = _syncEnabled;

    try {
      await gate.setSyncEnabled(value);
      if (mounted) setState(() => _syncEnabled = value);

      if (!value) {
        engine.pauseSync(userId);
      } else {
        await engine.resumeSync(userId, isPremium: isPremium);
      }
    } catch (_) {
      // The switch must not sit in a position the engine never reached. A
      // toggle reading ON over a sync that failed to resume is a silent
      // data-loss story: the user believes they are backed up.
      if (!mounted) return;
      setState(() => _syncEnabled = previous);
      showAppSnackBar(
        context,
        message: "Couldn't change sync. Please try again.",
        variant: AppSnackBarVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final isPremium = ref.watch(isPremiumProvider);
    final unit = ref.watch(weightUnitProvider);
    final restSeconds = ref.watch(defaultRestSecondsProvider);
    final goal = ref.watch(weeklyGoalProvider);
    final versionAsync = ref.watch(appVersionProvider);
    final accent = context.accent;
    final surface = context.surface;

    final version = versionAsync.valueOrNull ?? kAppVersionFallback;

    // C35: the engine already tracks phase (syncing/offline/error) and
    // exposes it live via syncStatusControllerProvider, but until now
    // nothing watched it — this row's subtitle was static regardless of
    // whether a sync was in flight, stuck offline, or failing outright. On
    // a slow or flapping connection that left the user with no signal that
    // anything was wrong.
    final syncPhase =
        ref.watch(syncStatusControllerProvider).valueOrNull?.phase;
    final syncDegraded =
        syncPhase == SyncPhase.offline || syncPhase == SyncPhase.error;

    final String syncSubtitle;
    if (!isPremium) {
      syncSubtitle = 'Upgrade to Pro to sync across devices';
    } else if (_syncEnabled == false) {
      syncSubtitle = 'Sync paused. Your data stays on this device.';
    } else if (syncPhase == SyncPhase.syncing) {
      syncSubtitle = 'Syncing…';
    } else if (syncPhase == SyncPhase.offline) {
      syncSubtitle =
          "Offline — your workouts are saved and will sync when you're back online";
    } else if (syncPhase == SyncPhase.error) {
      syncSubtitle = "Couldn't sync. Will retry automatically";
    } else {
      syncSubtitle = 'Backup across devices and protect against data loss';
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: surface.isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: surface.bgBase,
        appBar: AppBar(
          backgroundColor: surface.bgBase,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          leading: IconButton(
            tooltip: 'Back',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: surface.textPrimary),
            onPressed: () => context.pop(),
          ),
          title: Text('Settings',
              style: AppText.sheetTitle(color: surface.textPrimary)),
        ),
        body: AdaptiveContent(
            child: SafeArea(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _GroupHeader('ACCOUNT', color: surface.textSecondary),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        if (profile != null) ...[
                          AppActionRow(
                            icon: Icons.badge_rounded,
                            iconColor: accent.light,
                            title: 'Personal details',
                            subtitle: 'Age, gender, experience & more',
                            onTap: () {
                              if (!tapGuard()) return;
                              HapticFeedback.lightImpact();
                              context.push('/settings/personal');
                            },
                          ),
                        ],
                        Semantics(
                          hint: "Navigates to paywall",
                          child: AppActionRow(
                            icon: Icons.workspace_premium_rounded,
                            iconColor: accent.light,
                            title: isPremium ? 'GymLog Pro' : 'Upgrade to Pro',
                            subtitle: isPremium
                                ? 'Active (full history unlocked)'
                                : 'Full analytics history & more',
                            onTap: () =>
                                _openPremium(context, isPremium: isPremium),
                          ),
                        ),
                        if (isPremium) ...[
                          const AppActionDivider(),
                          AppActionRow(
                            icon: Icons.card_membership_rounded,
                            iconColor: accent.light,
                            title: 'Manage subscription',
                            subtitle: 'Change plans or cancel',
                            onTap: () async {
                              if (!tapGuard()) return;
                              HapticFeedback.lightImpact();
                              final service = ref.read(premiumServiceProvider);
                              final info = await service.getCustomerInfo();
                              if (!context.mounted) return;
                              final urlString = info?.managementURL;
                              if (urlString == null) {
                                showAppSnackBar(
                                  context,
                                  message: 'No active subscription found.',
                                );
                                return;
                              }
                              var opened = false;
                              try {
                                opened = await launchUrl(
                                  Uri.parse(urlString),
                                  mode: LaunchMode.externalApplication,
                                );
                              } catch (_) {
                                opened = false;
                              }
                              if (opened || !context.mounted) return;
                              showAppSnackBar(
                                context,
                                message: "Couldn't open the subscription page.",
                                variant: AppSnackBarVariant.error,
                              );
                            },
                          ),
                        ],
                        const AppActionDivider(),
                        AppActionRow(
                          icon: Icons.restore_rounded,
                          iconColor: accent.light,
                          title: 'Restore purchases',
                          subtitle: 'Re-verify your Pro status',
                          onTap: () async {
                            if (!tapGuard()) return;
                            HapticFeedback.lightImpact();
                            try {
                              final service = ref.read(premiumServiceProvider);
                              final info = await service.restorePurchases();
                              if (!context.mounted) return;
                              if (info != null && hasPremium(info)) {
                                showAppSnackBar(
                                  context,
                                  message:
                                      'Purchases restored successfully. You are now Pro!',
                                  variant: AppSnackBarVariant.success,
                                );
                              } else {
                                showAppSnackBar(
                                  context,
                                  message:
                                      'No active purchases found to restore.',
                                );
                              }
                            } catch (_) {
                              if (!context.mounted) return;
                              showAppSnackBar(
                                context,
                                message: 'Restore failed. Please try again.',
                                variant: AppSnackBarVariant.error,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _GroupHeader('PREFERENCES', color: surface.textSecondary),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        AppActionRow(
                          icon: Icons.scale_rounded,
                          iconColor: accent.light,
                          title: 'Weight unit',
                          subtitle:
                              unit == 'kg' ? 'Kilograms (kg)' : 'Pounds (lbs)',
                          onTap: () => _pickWeightUnit(context, ref, unit),
                        ),
                        const AppActionDivider(),
                        AppActionRow(
                          icon: Icons.flag_rounded,
                          iconColor: accent.light,
                          title: 'Weekly goal',
                          subtitle:
                              '$goal workout${goal != 1 ? 's' : ''} per week',
                          onTap: () => showWeeklyGoalSheet(context, ref),
                        ),
                        const AppActionDivider(),
                        AppActionRow(
                          key: _restTimerRowKey,
                          icon: Icons.timer_rounded,
                          iconColor: accent.light,
                          title: 'Rest timer',
                          // m:ss, matching the mid-workout rest tile. The old
                          // "$restSeconds seconds" made the same value read
                          // differently in two places ("90 seconds" vs "1:30").
                          subtitle: restSeconds == 0
                              ? 'Off'
                              : '${formatDurationLabel(restSeconds)} between sets',
                          onTap: () =>
                              _pickRestTimer(context, ref, restSeconds),
                        ),
                        const AppActionDivider(),
                        AppActionRow(
                          icon: Icons.palette_rounded,
                          iconColor: accent.light,
                          title: 'Appearance',
                          subtitle: 'Accent color',
                          onTap: () {
                            if (!tapGuard()) return;
                            HapticFeedback.lightImpact();
                            context.push('/settings/appearance');
                          },
                        ),
                        const AppActionDivider(),
                        AppActionRow(
                          icon: _notificationsEnabled == false
                              ? Icons.notifications_off_rounded
                              : Icons.notifications_rounded,
                          iconColor: accent.light,
                          title: 'Notifications',
                          subtitle: _notificationsEnabled == null
                              ? 'Rest timer alerts'
                              : _notificationsEnabled == true
                                  ? 'Enabled — rest timer alerts'
                                  : 'Disabled — tap to enable in Settings',
                          onTap: () {
                            if (!tapGuard()) return;
                            HapticFeedback.lightImpact();
                            openAppSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _GroupHeader('DATA', color: surface.textSecondary),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        AppActionRow(
                          icon: Icons.download_rounded,
                          title: 'Import workouts',
                          subtitle: 'From Hevy or Strong (CSV)',
                          onTap: () {
                            if (!tapGuard()) return;
                            HapticFeedback.lightImpact();
                            context.push('/settings/import');
                          },
                        ),
                        if (profile != null) ...[
                          const AppActionDivider(),
                          AppActionRow(
                            icon: Icons.ios_share_rounded,
                            title: 'Export workouts',
                            subtitle: 'CSV of every set, yours to keep',
                            onTap: () => _exportWorkouts(
                                context, ref, profile.id, profile.displayName),
                          ),
                        ],
                        const AppActionDivider(),
                        AppActionRow(
                          icon: Icons.cleaning_services_rounded,
                          title: 'Clear exercise media cache',
                          subtitle:
                              'Free up cache space without touching workout data',
                          onTap: () async {
                            if (!tapGuard()) return;
                            HapticFeedback.lightImpact();
                            await ExerciseMediaCacheManager().clearMediaCache();
                            if (!context.mounted) return;
                            showAppSnackBar(
                              context,
                              message: 'Exercise media cache cleared',
                              variant: AppSnackBarVariant.success,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _GroupHeader('CLOUD SYNC', color: surface.textSecondary),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Semantics(
                      button: !isPremium,
                      label: isPremium
                          ? 'Sync workout data to cloud. Currently ${_syncEnabled == false ? "off" : "on"}.'
                          : 'Upgrade to Pro to sync across devices',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: isPremium
                              ? null
                              : () {
                                  if (!tapGuard()) return;
                                  showPremiumPaywall(context,
                                      source: PaywallSource.sync);
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.sync_rounded,
                                  size: 20,
                                  color: syncDegraded
                                      ? AppColors.warning
                                      : surface.textSecondary,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Sync workout data to cloud',
                                            style: AppText.rowLabel(
                                                color: surface.textPrimary),
                                          ),
                                          if (!isPremium) ...[
                                            const SizedBox(width: 8),
                                            const ProLockPill(),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        syncSubtitle,
                                        style: AppText.meta(
                                            color: surface.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isPremium)
                                  // N3: branded Material Switch — the last
                                  // Switch.adaptive was the only stock platform
                                  // control left in a fully custom surface.
                                  Switch(
                                    value: _syncEnabled ?? true,
                                    onChanged: (v) => _toggleSync(v),
                                    activeTrackColor: accent.base,
                                    activeThumbColor: accent.onAccent,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (profile?.id != null) ...[
                    Consumer(
                      builder: (context, ref, child) {
                        final qCount = ref
                                .watch(
                                    quarantinedSyncCountProvider(profile!.id))
                                .valueOrNull ??
                            0;
                        if (qCount <= 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: AppRadius.cardAll,
                              border: Border.all(
                                  color: AppColors.warning
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded,
                                    size: 18, color: AppColors.warning),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '$qCount ${qCount == 1 ? "item" : "items"} could not be synchronized and ${qCount == 1 ? "was" : "were"} quarantined.',
                                    style: AppText.meta(
                                        color: surface.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 22),
                  _GroupHeader('HELP', color: surface.textSecondary),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        AppActionRow(
                          icon: Icons.help_rounded,
                          title: 'Help & feedback',
                          subtitle: 'Report a problem & support portal',
                          onTap: () {
                            if (!tapGuard()) return;
                            HapticFeedback.selectionClick();
                            context.push('/settings/help');
                          },
                        ),
                        const AppActionDivider(),
                        AppActionRow(
                          icon: Icons.shield_rounded,
                          title: 'Your data',
                          subtitle: isPremium
                              ? 'Stored on-device, backed up to your account'
                              : 'Stored locally on this device',
                          onTap: () => _showDataInfo(context, isPremium),
                        ),
                        const AppActionDivider(),
                        AppActionRow(
                          icon: Icons.privacy_tip_rounded,
                          title: 'Privacy Policy',
                          subtitle: 'Local-first. No tracking.',
                          onTap: () =>
                              _openExternalUrl(context, kPrivacyPolicyUrl),
                        ),
                        const AppActionDivider(),
                        AppActionRow(
                          icon: Icons.gavel_rounded,
                          title: 'Terms of Service',
                          subtitle: 'The short, readable kind',
                          onTap: () =>
                              _openExternalUrl(context, kTermsOfServiceUrl),
                        ),
                        const AppActionDivider(),
                        AppActionRow(
                          icon: Icons.tour_rounded,
                          title: 'Replay app tour',
                          subtitle: 'Walk through the basics again',
                          onTap: () {
                            if (!tapGuard()) return;
                            HapticFeedback.lightImpact();
                            ref.read(firstRunTourProvider.notifier).reset();
                            context.go('/');
                          },
                        ),
                        const AppActionDivider(),
                        // N9: release builds must not attach a dead tap that
                        // light-impacts then returns. Debug keeps the 5-tap
                        // Sentry smoke test; release is non-interactive chrome.
                        AppActionRow(
                          icon: Icons.info_rounded,
                          title: 'Version',
                          subtitle: 'GymLog $version',
                          showChevron: false,
                          onTap: kDebugMode
                              ? () {
                                  if (!tapGuard()) return;
                                  HapticFeedback.lightImpact();
                                  setState(() {
                                    _devTapCount++;
                                    if (_devTapCount >= 5) {
                                      _devTapCount = 0;
                                      throw StateError(
                                          'Sentry Diagnostic Controlled Test Error');
                                    }
                                  });
                                }
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  // N11: session-end is quieter (outline). Permanent delete is
                  // the sole high-weight destructive action below.
                  const _SignOutButton(),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        if (!tapGuard()) return;
                        HapticFeedback.selectionClick();
                        context.push('/settings/delete-account');
                      },
                      child: Text(
                        'Delete account',
                        style: AppText.button(color: AppColors.error),
                      ),
                    ),
                  ),
                ],
              ),

              // Step 3 — Rest-timer spotlight (framing C-b: Settings row).
              // Guard: only show when Settings is the active top route.
              if (ref.watch(firstRunTourProvider) == 3 &&
                  (ModalRoute.of(context)?.isCurrent ?? false))
                SpotlightTourOverlay(
                  targetKey: _restTimerRowKey,
                  title: 'Automatic rest timer',
                  description:
                      'GymLog starts a countdown after every completed set. '
                      'Drag to set your preferred rest here — 1:30 is great '
                      'for compound lifts, 1:00 for isolation work.',
                  step: 3,
                ),
            ],
          ),
        )),
      ),
    );
  }
}

const kAppVersionFallback = '1.0.0';

class _GroupHeader extends StatelessWidget {
  final String label;
  final Color color;
  const _GroupHeader(this.label, {required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(label, style: AppText.groupHeader(color: color)),
      );
}

/// The unsynced-work sign-out decision.
///
/// Was: three equal-weight rows — Stay signed in / Sync, then sign out /
/// Export a CSV, then sign out. Three problems with that (ship-readiness
/// #2): it asked the user to choose a data-safety strategy the app can
/// decide itself (it already knows premium status, sync state and queue
/// depth); the safe option and the two session-ending options looked
/// identical; and "Export a CSV" duplicated the Export row one screen up in
/// Settings → Data — a file operation is not a sign-out choice.
///
/// Now: ONE primary action that does the right thing (upload first, then
/// sign out — anything that cannot upload stays on this device), and ONE
/// low-emphasis destructive escape. Drag-dismiss returns null, which the
/// caller treats as "stay signed in" — the safe default is also the
/// accidental one.
Future<SignOutStrategy?> _showUnsyncedWorkSheet(BuildContext context) {
  HapticFeedback.mediumImpact();

  void choose(SignOutStrategy strategy) {
    HapticFeedback.selectionClick();
    Navigator.of(context, rootNavigator: true).pop(strategy);
  }

  return showBrandedBottomSheet<SignOutStrategy>(
    context: context,
    title: 'Back up before signing out?',
    subtitle: 'Some workouts on this device have not reached the cloud yet. '
        'GymLog will upload them first — anything that cannot upload '
        'stays on this device.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          label: 'Back up & sign out',
          icon: Icons.cloud_upload_rounded,
          onPressed: () => choose(SignOutStrategy.signOutAfterSync),
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: () => choose(SignOutStrategy.forceSignOut),
            child: Text(
              'Sign out anyway',
              style: AppText.button(color: AppColors.error),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  Future<void> _handleSignOut(BuildContext context, WidgetRef ref) async {
    if (!tapGuard()) return;
    final user = ref.read(authProvider);
    if (user == null) return;
    final coordinator = ref.read(signOutCoordinatorProvider);
    final prep = await coordinator.prepare(user.id);
    if (prep == SignOutResult.unsyncedWork) {
      if (!context.mounted) return;
      final strategy = await _showUnsyncedWorkSheet(context);
      if (strategy == null || strategy == SignOutStrategy.keepSignedIn) {
        return;
      }
      if (!context.mounted) return;
      final outcome = await coordinator.execute(strategy);
      if (outcome == SignOutOutcome.cloudSignOutFailed && context.mounted) {
        showAppSnackBar(
          context,
          message: 'Signed out on this device, but some cloud sessions '
              'could not be closed. For your security, sign out of '
              'GymLog on any other device you used.',
          variant: AppSnackBarVariant.error,
        );
      }
    } else {
      if (!context.mounted) return;
      final confirmed = await showAppConfirmDialog(
        context: context,
        title: 'Sign out?',
        message: 'Your workouts are stored locally and will be here '
            'when you sign back in.',
        confirmLabel: 'Sign Out',
        isDestructive: true,
      );
      if (confirmed) {
        if (!context.mounted) return;
        final outcome = await coordinator.execute(SignOutStrategy.forceSignOut);
        if (outcome == SignOutOutcome.cloudSignOutFailed && context.mounted) {
          showAppSnackBar(
            context,
            message: 'Signed out on this device, but some cloud '
                'sessions could not be closed. For your security, sign '
                'out of GymLog on any other device you used.',
            variant: AppSnackBarVariant.error,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // N11 hierarchy: session-end is outline + error text — not a filled red
    // slab competing with Delete account one row below. Permanent purge keeps
    // the sole high-weight destructive treatment.
    return Semantics(
      container: true,
      button: true,
      // Wrapper owns the name; the inner 'Sign Out' Text must not publish a
      // second node (docs/a11y-semantics-checklist.md §2). excludeSemantics
      // discards the InkWell's tap action, hence the explicit onTap.
      excludeSemantics: true,
      onTap: () => _handleSignOut(context, ref),
      label: 'Sign out',
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.cardAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: AppRadius.cardAll,
          onTap: () => _handleSignOut(context, ref),
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: AppRadius.cardAll,
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              'Sign Out',
              style: AppText.button(color: AppColors.error),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _pickWeightUnit(
    BuildContext context, WidgetRef ref, String unit) async {
  HapticFeedback.lightImpact();
  final selected = await showBrandedPickerSheet<String>(
    context: context,
    title: 'Weight Unit',
    selected: unit,
    options: [
      PickerOption(
        value: 'kg',
        label: 'Kilograms',
        subtitle: 'kg',
        icon: Icons.fitness_center_rounded,
        color: context.surface.textSecondary,
      ),
      PickerOption(
        value: 'lbs',
        label: 'Pounds',
        subtitle: 'lbs',
        icon: Icons.fitness_center_rounded,
        color: context.surface.textSecondary,
      ),
    ],
  );
  if (selected != null) {
    await ref.read(settingsActionsProvider).setWeightUnit(selected);
  }
}

/// Rest duration — a continuous slider, replacing a 7-item preset list.
///
/// The list could not express 45s, 75s, or anything above 3:00, and it labelled
/// values in raw seconds ("120 seconds") when lifters read rest as m:ss. See
/// [DurationSlider] for the interaction rationale.
///
/// Persistence happens in `onChangeEnd` only. A single drag emits dozens of
/// intermediate values; writing each one would hammer SharedPreferences and
/// invalidate the provider on every frame of the gesture.
Future<void> _pickRestTimer(
    BuildContext context, WidgetRef ref, int restSeconds) async {
  HapticFeedback.lightImpact();
  var value = restSeconds.clamp(0, kRestMaxSeconds);

  await showBrandedBottomSheet<void>(
    context: context,
    title: 'Rest Between Sets',
    subtitle: 'Drag to set the countdown that starts after each completed set. '
        'Slide to zero to turn it off.',
    child: StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DurationSlider(
          valueSeconds: value,
          maxSeconds: kRestMaxSeconds,
          stepSeconds: 5,
          onChanged: (v) => setSheetState(() => value = v),
          onChangeEnd: (v) =>
              ref.read(settingsActionsProvider).setDefaultRestSeconds(v),
        ),
      ),
    ),
  );

  // Safety net: if the sheet is dismissed by a back gesture between the last
  // detent and the drag-end callback, the final value would otherwise be lost.
  if (value != restSeconds) {
    await ref.read(settingsActionsProvider).setDefaultRestSeconds(value);
  }
}

void _openPremium(BuildContext context, {required bool isPremium}) {
  if (!tapGuard()) return;
  if (isPremium) {
    HapticFeedback.lightImpact();
    showAppSnackBar(
      context,
      message: 'You are on GymLog Pro. Thanks for the support!',
      variant: AppSnackBarVariant.success,
    );
  } else {
    showPremiumPaywall(context);
  }
}

Future<void> _exportWorkouts(BuildContext context, WidgetRef ref, String userId,
    String displayName) async {
  HapticFeedback.lightImpact();
  try {
    final service = WorkoutExportService(ref.read(databaseProvider));
    final file = await service.writeCsvFile(userId);
    final who = displayName.trim().isEmpty ? '' : ' (${displayName.trim()})';
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: 'GymLog workout export$who',
      text: 'GymLog training history$who',
    ));
  } catch (_) {
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: 'Export failed. Please try again.',
      variant: AppSnackBarVariant.error,
    );
  }
}

void _showDataInfo(BuildContext context, bool isPremium) {
  HapticFeedback.lightImpact();
  showAppConfirmDialog(
    context: context,
    title: isPremium ? 'Local-first, cloud-backed' : 'Local-first privacy',
    message: isPremium
        ? 'Every workout is saved instantly to a private database '
            'on this device — GymLog works fully offline. Workouts are '
            'automatically backed up to your account so your history survives '
            'a reinstall or a new phone. Only you can read it.'
        : 'Every workout is saved instantly to a private database '
            'on this device — GymLog works fully offline. Upgrade to '
            'GymLog Pro to automatically back up your history to the cloud '
            'and sync across devices.',
    confirmLabel: 'Got it',
    cancelLabel: 'Close',
  );
}

/// launchUrl THROWS a PlatformException when the platform has no handler for
/// the scheme - it does not merely return false. The original code inspected
/// only the bool, so on a device with no browser the Privacy Policy and Terms
/// rows raised an uncaught async exception and told the user nothing at all.
Future<void> _openExternalUrl(BuildContext context, String url) async {
  HapticFeedback.lightImpact();
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    opened = false;
  }
  if (opened || !context.mounted) return;
  showAppSnackBar(
    context,
    message: "Couldn't open the link.",
    variant: AppSnackBarVariant.error,
  );
}
