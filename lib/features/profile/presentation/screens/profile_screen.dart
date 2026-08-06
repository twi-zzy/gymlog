import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/providers/premium_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/services/profile_image_sync_service.dart';
import '../../../../core/services/profile_sync_service.dart';
import '../../../../core/services/sync_entitlement_gate.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../shared/widgets/ui/app_dialog.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/theme/dynamic_accent_theme.dart';
import '../../../../core/utils/tap_guard.dart';
import '../../../../shared/providers/bottom_chrome_provider.dart';
import '../../../../shared/widgets/premium_paywall.dart';
import '../../../../shared/widgets/ui/app_action_row.dart';
import '../../../../shared/widgets/ui/app_button_shell.dart';
import '../../../../shared/widgets/ui/app_card.dart';
import '../../../../shared/widgets/ui/app_snack_bar.dart';
import '../../../../shared/widgets/ui/goal_ring.dart';
import '../../../../shared/widgets/ui/app_refresh_indicator.dart';
import '../../../../shared/widgets/ui/segmented_control.dart';
import '../../../../shared/widgets/ui/skeleton.dart';
import '../providers/profile_provider.dart';
import '../providers/profile_stats_provider.dart';
import '../widgets/graph_kpi_header.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_graph_empty_state.dart';
import 'package:gymlog/features/workout/presentation/providers/active_workout_provider.dart';

import '../widgets/weekly_bar_chart.dart';
import 'settings_screen.dart';

const _kProfileImageKey = 'profile_image_path';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String? _profileImagePath;

  @override
  void initState() {
    super.initState();
    _loadImagePath();
  }

  Future<void> _loadImagePath() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _profileImagePath = prefs.getString(_kProfileImageKey));
    }
  }

  Future<void> _onImageChanged(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path != null) {
      await FileImage(File(path)).evict();
      await prefs.setString(_kProfileImageKey, path);
    } else {
      await prefs.remove(_kProfileImageKey);
    }
    if (mounted) setState(() => _profileImagePath = path);

    // Silent cloud backup — enabled for all users. The service resolves the user
    // id internally.
    final isPremium = ref.read(isPremiumProvider);
    final syncService = ref.read(profileImageSyncProvider);
    if (path != null) {
      await syncService.uploadIfEntitled(isPremium: isPremium, localPath: path);
    } else {
      await syncService.deleteRemoteIfEntitled(isPremium: isPremium);
    }
  }

  void _openSettings() {
    if (!tapGuard()) return;
    HapticFeedback.selectionClick();
    context.push('/settings');
  }

  void _openExerciseLibrary() {
    if (!tapGuard()) return;
    HapticFeedback.selectionClick();
    context.push('/exercises/library');
  }

  Future<void> _onRefresh() async {
    HapticFeedback.mediumImpact();
    ref.invalidate(currentUserProfileProvider);
    ref.invalidate(workoutCountProvider);
    ref.invalidate(sessionStatsProvider);
    ref.invalidate(streakStatsProvider);
    ref.invalidate(isSyncAllowedProvider);
    await _loadImagePath();
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _openBillingSettings() async {
    HapticFeedback.lightImpact();
    // No affordance exists in the paywall for this — the paywall is for
    // purchasing, not fixing a failing payment method. Send the user
    // straight to the store's native subscription management page.
    final url = defaultTargetPlatform == TargetPlatform.iOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final workoutCount = ref.watch(workoutCountProvider).valueOrNull ?? 0;
    final profileAsync = ref.watch(currentUserProfileProvider);
    final streak = ref.watch(streakStatsProvider);
    final goal = ref.watch(weeklyGoalProvider);
    final isPremium = ref.watch(isPremiumProvider);
    final syncAllowed = ref.watch(isSyncAllowedProvider).valueOrNull ?? true;
    final showSyncPausedBadge = isPremium && !syncAllowed;
    final customerInfo = ref.watch(customerInfoProvider).valueOrNull;
    final billingIssueMessage =
        customerInfo != null ? billingIssueBannerCopy(customerInfo) : null;

    final bottomClearance = ref.watch(bottomChromeInsetProvider) + 24;

    final surface = context.surface;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: surface.isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: surface.bgBase,
        body: SafeArea(
          child: profileAsync.when(
            loading: () => _LoadingBody(bottomClearance: bottomClearance),
            error: (e, _) => _ErrorBody(
              bottomClearance: bottomClearance,
              onRetry: () => ref.invalidate(currentUserProfileProvider),
            ),
            data: (profile) {
              final displayName = profile?.displayName ?? 'Athlete';
              final email = profile?.email ?? '';

              return AppRefreshIndicator(
                onRefresh: _onRefresh,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, bottomClearance),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              'Profile',
                              style: AppText.screenTitle(
                                color: surface.textPrimary,
                                shadows: AppText.depthFor(context),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Settings',
                          constraints:
                              const BoxConstraints(minWidth: 48, minHeight: 48),
                          icon: Icon(Icons.settings_rounded,
                              size: 22, color: surface.textPrimary),
                          onPressed: _openSettings,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (billingIssueMessage != null) ...[
                      _BillingIssueBanner(
                        message: billingIssueMessage,
                        onTap: _openBillingSettings,
                      ),
                      const SizedBox(height: 12),
                    ],
                    Semantics(
                      container: true,
                      label: 'Profile, $displayName, $email',
                      child: _IdentityHeader(
                        displayName: displayName,
                        email: email,
                        isPremium: isPremium,
                        showSyncPausedBadge: showSyncPausedBadge,
                        imagePath: _profileImagePath,
                        onImageChanged: _onImageChanged,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AppCard(
                      radius: AppRadius.card,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.x1, vertical: AppSpacing.x4),
                      child: _StatsStrip(
                        streak: streak,
                        goal: goal,
                        workoutCount: workoutCount,
                        onGoalTap: () => showWeeklyGoalSheet(context, ref),
                        onRetryStreak: () =>
                            ref.invalidate(trainingDatesProvider),
                      ),
                    ),
                    if (streak.isResolved) ...[
                      if (goal > 0 && streak.workoutsThisWeek >= goal) ...[
                        const SizedBox(height: 10),
                        const _GoalReachedBanner(),
                      ] else if (!streak.trainedToday) ...[
                        const SizedBox(height: 10),
                        _StreakReminder(streak: streak),
                      ],
                    ],
                    const SizedBox(height: 28),
                    const _TrainingChartSection(),
                    const SizedBox(height: 28),
                    // N12: Upgrade to Pro lives in Settings → Account only.
                    // Profile Quick Links keeps the unique Exercise Library entry.
                    _QuickLinks(onExerciseLibraryTap: _openExerciseLibrary),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BillingIssueBanner extends StatelessWidget {
  final String message;
  final VoidCallback onTap;

  const _BillingIssueBanner({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    return Semantics(
      button: true,
      label: '$message Double tap to update your payment method.',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 18, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      message,
                      style: AppText.caption(color: surface.textPrimary),
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: surface.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IdentityHeader extends ConsumerWidget {
  final String displayName;
  final String email;
  final bool isPremium;
  final bool showSyncPausedBadge;
  final String? imagePath;
  final ValueChanged<String?> onImageChanged;

  const _IdentityHeader({
    required this.displayName,
    required this.email,
    required this.isPremium,
    this.showSyncPausedBadge = false,
    this.imagePath,
    required this.onImageChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surface = context.surface;
    return Row(
      children: [
        ProfileAvatar(
          displayName: displayName,
          imagePath: imagePath,
          onImageChanged: onImageChanged,
          size: 56,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: GestureDetector(
                      onTap: () async {
                        HapticFeedback.lightImpact();
                        final newName = await showAppTextInputDialog(
                          context: context,
                          title: 'Change name',
                          hint: 'Display name',
                          initialValue: displayName,
                          maxLength: 40,
                        );
                        if (newName != null && newName.trim().isNotEmpty) {
                          if (!context.mounted) return;
                          final user = ref.read(authProvider);
                          if (user != null) {
                            final success = await ref
                                .read(profileSyncProvider)
                                .submitDisplayName(
                                  userId: user.id,
                                  email: user.email ?? '',
                                  name: newName,
                                );
                            if (success) {
                              ref.invalidate(currentUserProfileProvider);
                            } else {
                              if (!context.mounted) return;
                              showAppSnackBar(
                                context,
                                message: "Couldn't save your name. Try again.",
                                variant: AppSnackBarVariant.error,
                              );
                            }
                          }
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.profileName(
                                  color: surface.textPrimary,
                                  shadows: AppText.depthFor(context)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.edit_rounded,
                            size: 13,
                            color: surface.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (showSyncPausedBadge) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: surface.surface3,
                        borderRadius: BorderRadius.circular(AppRadius.badge),
                        border: Border.all(color: surface.borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            size: 11,
                            color: surface.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Sync paused',
                            style: AppText.badge(color: surface.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              if (email.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.profileEmail(color: surface.textSecondary),
                ),
              ],
            ],
          ),
        ),
        if (isPremium)
          // N10: same badge spec as Sync paused — fill + border (was border-only).
          Semantics(
            label: 'Pro status active',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: surface.surface3,
                borderRadius: BorderRadius.circular(AppRadius.badge),
                border: Border.all(color: surface.borderSubtle),
              ),
              child: Text(
                'PRO',
                style: AppText.badge(color: surface.textSecondary),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatsStrip extends StatelessWidget {
  final StreakStats streak;
  final int goal;
  final int workoutCount;
  final VoidCallback onGoalTap;
  final VoidCallback onRetryStreak;

  const _StatsStrip({
    required this.streak,
    required this.goal,
    required this.workoutCount,
    required this.onGoalTap,
    required this.onRetryStreak,
  });

  @override
  Widget build(BuildContext context) {
    const iconSize = 18.0;

    return Row(
      children: [
        Expanded(
          child: streak.isLoading
              ? const _StatCellSkeleton()
              : streak.hasError
                  ? _StatCellError(onRetry: onRetryStreak)
                  : _StatCell(
                      value: '${streak.currentStreak}',
                      label: 'DAY STREAK',
                      leading: Icon(
                        Icons.local_fire_department_rounded,
                        size: iconSize,
                        color: streak.currentStreak > 0
                            ? AppColors.warning
                            : context.surface.textTertiary,
                      ),
                    ),
        ),
        const _StatDivider(),
        Expanded(
          child: streak.isLoading
              ? const _StatCellSkeleton()
              : streak.hasError
                  ? _StatCellError(onRetry: onRetryStreak)
                  : Semantics(
                      button: true,
                      label:
                          'Weekly goal: ${streak.workoutsThisWeek} of $goal workouts. Tap to change goal.',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onGoalTap,
                        child: _StatCell(
                          value: streak.workoutsThisWeek >= goal
                              ? '${streak.workoutsThisWeek}'
                              : '${streak.workoutsThisWeek}/$goal',
                          label: 'THIS WEEK',
                          leading: GoalRing(
                            progress: goal == 0
                                ? 0
                                : (streak.workoutsThisWeek / goal)
                                    .clamp(0.0, 1.0),
                          ),
                        ),
                      ),
                    ),
        ),
        const _StatDivider(),
        Expanded(
          child: _StatCell(
            value: '$workoutCount',
            label: 'WORKOUTS',
            leading: Icon(
              Icons.fitness_center_rounded,
              size: iconSize,
              color: context.surface.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final Widget leading;

  const _StatCell({
    required this.value,
    required this.label,
    required this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    return Semantics(
      container: true,
      label: '$label $value',
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 6),
              Text(value,
                  style: AppText.statValue(
                      color: surface.textPrimary,
                      shadows: AppText.depthFor(context))),
            ],
          ),
          const SizedBox(height: 5),
          Text(label,
              style: AppText.statCellLabel(color: surface.textSecondary)),
        ],
      ),
    );
  }
}

/// Rendered instead of [_StatCell] while [StreakStats.isLoading] is true —
/// the streak/week numbers are not real yet and must not read as fact.
class _StatCellSkeleton extends StatelessWidget {
  const _StatCellSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SkeletonBox(width: 40, height: 17, radius: AppRadius.input),
        SizedBox(height: 5),
        SkeletonBox(width: 56, height: 10, radius: AppRadius.input),
      ],
    );
  }
}

/// Rendered instead of [_StatCell] while [StreakStats.hasError] is true —
/// offers the real retry `trainingDatesProvider` was made public for,
/// instead of a silent, confident 0.
class _StatCellError extends StatelessWidget {
  final VoidCallback onRetry;

  const _StatCellError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    return Semantics(
      button: true,
      label: 'Could not load. Double tap to retry.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRetry,
        child: Column(
          children: [
            Icon(Icons.refresh_rounded, size: 18, color: surface.textTertiary),
            const SizedBox(height: 5),
            Text('RETRY',
                style: AppText.statCellLabel(color: surface.textTertiary)),
          ],
        ),
      ),
    );
  }
}

/// Shared height with routine detail's _StatDivider (N5) — one geometry.
class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      color: context.surface.borderSubtle,
    );
  }
}

class _StreakReminder extends StatelessWidget {
  final StreakStats streak;

  const _StreakReminder({required this.streak});

  @override
  Widget build(BuildContext context) {
    final message = streak.currentStreak > 0
        ? 'Train today to keep your ${streak.currentStreak}-day streak alive.'
        : 'Train today to start a streak.';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        message,
        style: AppText.caption(color: context.surface.textSecondary),
      ),
    );
  }
}

class _GoalReachedBanner extends StatelessWidget {
  const _GoalReachedBanner();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.emoji_events_rounded,
            size: 14, color: AppColors.warning),
        const SizedBox(width: 6),
        Text(
          'Weekly goal reached — great work!',
          style: AppText.caption(color: AppColors.warning),
        ),
      ],
    );
  }
}

class _TrainingChartSection extends ConsumerStatefulWidget {
  const _TrainingChartSection();

  @override
  ConsumerState<_TrainingChartSection> createState() =>
      _TrainingChartSectionState();
}

class _TrainingChartSectionState extends ConsumerState<_TrainingChartSection> {
  int _switchVersion = 0;

  @override
  Widget build(BuildContext context) {
    final metric = ref.watch(profileChartMetricProvider);
    // weeklyAggregatesProvider carries the stream's loading/error/data states
    // itself (mapped explicitly, never flattened with `valueOrNull ?? []`) so
    // a loading or failed stream can never masquerade as an all-zero week.
    final aggregatesAsync = ref.watch(weeklyAggregatesProvider);
    final isPremium = ref.watch(isPremiumProvider);
    // Weekly aggregates are stored in kilograms; the KPI header and the chart
    // both need the active unit to render volume the way the rest of the app
    // does.
    final unit = ref.watch(weightUnitProvider);
    final isLoadingStats =
        aggregatesAsync.isLoading && !aggregatesAsync.hasValue;
    final hasStatsError = aggregatesAsync.hasError;
    final aggregates = aggregatesAsync.valueOrNull ?? const <WeeklyAggregate>[];
    final filledWeeks = aggregates.where((a) => a.workoutCount > 0).length;
    final isEmpty = !isLoadingStats && !hasStatsError && filledWeeks == 0;

    void onStartWorkout() {
      if (!tapGuard()) return;
      HapticFeedback.mediumImpact();
      if (ref.read(activeWorkoutProvider) == null) {
        ref.read(activeWorkoutProvider.notifier).startWorkout();
      }
      context.push('/workout/active');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text('Training',
              style: AppText.sectionHeading(
                  color: context.surface.textPrimary,
                  shadows: AppText.depthFor(context))),
        ),
        const SizedBox(height: 24),
        if (isLoadingStats)
          const _ChartLoadingPlaceholder()
        else if (hasStatsError)
          _ChartErrorPlaceholder(
            onRetry: () => ref.invalidate(sessionStatsProvider),
          )
        else if (isEmpty)
          ProfileGraphEmptyState(onStartWorkout: onStartWorkout)
        else ...[
          GraphKpiHeader(
            aggregates: aggregates,
            metric: metric,
            unit: unit,
          ),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            child: WeeklyBarChart(
              key: ValueKey('${metric.name}_$_switchVersion'),
              aggregates: aggregates,
              metric: metric,
              isPremium: isPremium,
              unit: unit,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Semantics(
          label: 'Chart metric selector',
          child: SegmentedControl(
            segments: const ['Volume', 'Duration', 'Reps'],
            selected: metric.label,
            onChanged: (label) {
              final next = ProfileGraphMetric.values.firstWhere(
                (m) => m.label == label,
              );
              if (next == metric) return;
              HapticFeedback.selectionClick();
              setState(() => _switchVersion++);
              ref.read(profileChartMetricProvider.notifier).setMetric(next);
            },
          ),
        ),
      ],
    );
  }
}

/// Rendered instead of the chart while [sessionStatsProvider] has not yet
/// emitted a value — a genuinely-empty chart and a not-yet-known chart must
/// not look identical.
class _ChartLoadingPlaceholder extends StatelessWidget {
  const _ChartLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const SkeletonPulse(
      label: 'Loading your training history',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 120, height: 16, radius: AppRadius.input),
          SizedBox(height: 12),
          SkeletonBox(
              width: double.infinity, height: 150, radius: AppRadius.card),
          SizedBox(height: 14),
          SkeletonBox(
              width: double.infinity,
              height: 36,
              radius: AppRadius.segmentedOuter),
        ],
      ),
    );
  }
}

/// Rendered instead of the chart when [sessionStatsProvider] failed —
/// offers a real retry rather than the "log your first workout" empty state.
class _ChartErrorPlaceholder extends StatelessWidget {
  final VoidCallback onRetry;

  const _ChartErrorPlaceholder({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.error_outline_rounded,
            size: 40, color: surface.textTertiary),
        const SizedBox(height: 12),
        Text(
          "Couldn't load your training history",
          style: AppText.body(color: surface.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onRetry,
          child:
              Text('Retry', style: AppText.button(color: context.accent.base)),
        ),
      ],
    );
  }
}

/// N12: single unique quick link. Upgrade to Pro is canonical in Settings.
class _QuickLinks extends StatelessWidget {
  final VoidCallback onExerciseLibraryTap;

  const _QuickLinks({required this.onExerciseLibraryTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: AppRadius.card,
      padding: EdgeInsets.zero,
      child: AppActionRow(
        icon: Icons.fitness_center_rounded,
        title: 'Exercise Library',
        subtitle: 'Browse exercises, form guides & records',
        onTap: onExerciseLibraryTap,
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  final double bottomClearance;

  const _LoadingBody({required this.bottomClearance});

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      label: 'Loading your profile',
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, bottomClearance),
        children: [
          const Row(
            children: [
              SkeletonBox(
                  width: 56, height: 56, radius: AppRadius.buttonPrimary),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(
                        width: 140, height: 19, radius: AppRadius.input),
                    SizedBox(height: 6),
                    SkeletonBox(
                        width: 180, height: 13, radius: AppRadius.input),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AppCard(
            radius: AppRadius.card,
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  const Expanded(
                    child: Column(
                      children: [
                        SkeletonBox(
                            width: 50, height: 17, radius: AppRadius.input),
                        SizedBox(height: 5),
                        SkeletonBox(
                            width: 56, height: 10, radius: AppRadius.input),
                      ],
                    ),
                  ),
                  if (i < 2) const SizedBox(width: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
          const AppCard(
            radius: AppRadius.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 120, height: 16, radius: AppRadius.input),
                SizedBox(height: 12),
                SkeletonBox(
                    width: double.infinity,
                    height: 150,
                    radius: AppRadius.card),
                SizedBox(height: 14),
                SkeletonBox(
                    width: double.infinity,
                    height: 36,
                    radius: AppRadius.segmentedOuter),
              ],
            ),
          ),
          const SizedBox(height: 28),
          AppCard(
            radius: AppRadius.card,
            child: Column(
              children: [
                for (var i = 0; i < 1; i++) ...[
                  const SkeletonBox(
                      width: double.infinity,
                      height: 48,
                      radius: AppRadius.input),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final double bottomClearance;
  final VoidCallback onRetry;

  const _ErrorBody({required this.bottomClearance, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    final accent = context.accent;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, bottomClearance),
      children: [
        AppCard(
          radius: AppRadius.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 28),
              const SizedBox(height: 12),
              Text('Could not load profile',
                  style: AppText.sheetTitle(color: surface.textPrimary)),
              const SizedBox(height: 6),
              Text(
                'We had trouble reading your local profile. Your workouts are safe.',
                style: AppText.body(color: surface.textSecondary),
              ),
              const SizedBox(height: 16),
              // D2 / #3: no fixed height — AppButtonShell minHeight floor.
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent.base,
                    foregroundColor: accent.onAccent,
                    elevation: 0,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.buttonPrimary)),
                  ),
                  child: AppButtonShell(
                    label: 'Retry',
                    style: AppText.button(color: accent.onAccent),
                    minHeight: 48,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
