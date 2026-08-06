import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:gymlog/core/services/account_deletion_service.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/theme/app_text.dart';
import 'package:gymlog/core/providers/database_provider.dart';
import 'package:gymlog/features/auth/presentation/providers/auth_provider.dart';
import 'package:gymlog/features/profile/presentation/providers/profile_provider.dart';
import 'package:gymlog/core/services/workout_export_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gymlog/shared/layout/adaptive.dart';
import 'package:gymlog/shared/widgets/ui/app_snack_bar.dart';

/// Irreversible account deletion. Reached from Settings (not buried). The user
/// reads exactly what is destroyed vs preserved, types DELETE to confirm, and
/// the final button initiates the permanent purge.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  bool _deleting = false;

  static const _confirmWord = 'DELETE';

  bool get _canDelete =>
      _confirm.text.trim().toUpperCase() == _confirmWord && !_deleting;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_canDelete) return;
    HapticFeedback.heavyImpact();
    setState(() => _deleting = true);

    final outcome =
        await ref.read(accountDeletionServiceProvider).deleteAccount();

    if (!mounted) return;

    // Completion is derived from ALL three outcome flags. A cloud-failure
    // deletion must never present itself as success.
    final fullyDeleted =
        outcome.localWiped && outcome.cloudPurged && outcome.authUserDeleted;

    // Local wipe always signs the user out, so the session is gone even on
    // partial failure. Show the honest copy on the current scaffold first,
    // then navigate — the current route's Scaffold remains mounted long
    // enough for the message to be visible.
    if (outcome.localWiped) {
      final router = GoRouter.of(context);
      showAppSnackBar(
        context,
        message: fullyDeleted
            ? 'Your account and data have been permanently deleted.'
            : 'Your data on this device was deleted, but some cloud data '
                'could not be removed. Reach out in the GymLog Telegram '
                'channel (t.me/gym_log) to finish the purge.',
      );
      router.go('/auth');
    } else {
      setState(() => _deleting = false);
      showAppSnackBar(context, message: 'Deletion failed. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: surface.isLight
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: !_deleting,
        child: Scaffold(
          backgroundColor: surface.bgBase,
          appBar: AppBar(
            backgroundColor: surface.bgBase,
            scrolledUnderElevation: 0,
            titleSpacing: 0,
            leading: IconButton(
              tooltip: 'Back',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(Icons.arrow_back_ios_new,
                  size: 18, color: surface.textPrimary),
              onPressed: _deleting ? null : () => context.pop(),
            ),
            title: Text('Delete account', style: AppText.sheetTitle()),
          ),
          body: AdaptiveContent(
            child: AbsorbPointer(
              absorbing: _deleting,
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: AppRadius.buttonPrimaryAll,
                      ),
                      child: const Icon(Icons.delete_forever_rounded,
                          color: AppColors.error, size: 26),
                    ),
                    const SizedBox(height: 16),
                    MergeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'This is permanent',
                            style: AppText.sectionHeading(),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Deleting your account cannot be undone. Once you confirm, your '
                            'data will be permanently deleted. There is no recovery.',
                            style: AppText.body(),
                          ),
                        ],
                      ),
                    ),
                    const _ExportBackupButton(),
                    const SizedBox(height: 24),
                    const _SectionCard(
                      title: 'What will be permanently deleted',
                      tone: AppColors.error,
                      icon: Icons.remove_circle_outline_rounded,
                      lines: [
                        'Your sign-in account and profile on our servers.',
                        'Any workout, routine, or preference data synced to the cloud.',
                        'All workout history, routines, and custom exercises stored on '
                            'this device.',
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _SectionCard(
                      title: 'What stays yours',
                      tone: AppColors.success,
                      icon: Icons.check_circle_outline_rounded,
                      lines: [
                        'Any CSV files you exported to your phone (Downloads / Files) '
                            'are your property. They are never touched or removed.',
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _SectionCard(
                      title: 'Active Subscriptions (Store Managed)',
                      tone: AppColors.warning,
                      icon: Icons.info_outline_rounded,
                      lines: [
                        'Deleting your GymLog account does NOT cancel your subscription.',
                        'You must cancel active billing in your App Store / Google Play account settings to prevent future renewals.',
                        'Any refund requests must be initiated directly through the store processor.',
                      ],
                    ),
                    const SizedBox(height: 26),
                    Text(
                      'Type $_confirmWord to confirm',
                      style: AppText.columnHeader(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _confirm,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _canDelete ? _delete() : null,
                      onChanged: (_) => setState(() {}),
                      cursorColor: AppColors.error,
                      style: AppText.button(
                        color: surface.textPrimary,
                      ).copyWith(
                        letterSpacing: 1.5,
                      ),
                      decoration: InputDecoration(
                        hintText: _confirmWord,
                        hintStyle: AppText.button(
                          color: surface.textDisabled,
                        ).copyWith(
                          letterSpacing: 1.5,
                        ),
                        filled: true,
                        fillColor: surface.surface2,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide:
                              BorderSide(color: AppColors.error, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _canDelete ? _delete : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          disabledBackgroundColor:
                              AppColors.error.withValues(alpha: 0.18),
                          foregroundColor: Colors.white,
                          disabledForegroundColor:
                              Colors.white.withValues(alpha: 0.5),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppRadius.buttonPrimary)),
                        ),
                        child: _deleting
                            ? const CupertinoActivityIndicator(
                                color: Colors.white)
                            : Text(
                                'Delete my account permanently',
                                style: AppText.button(),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: _deleting ? null : () => context.pop(),
                        child: Text(
                          'Cancel',
                          style: AppText.button(color: surface.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Color tone;
  final IconData icon;
  final List<String> lines;

  const _SectionCard({
    required this.title,
    required this.tone,
    required this.icon,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: surface.surface2,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: AppText.rowLabel()),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 8),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: surface.textSecondary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(line, style: AppText.body()),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ExportBackupButton extends ConsumerWidget {
  const _ExportBackupButton();

  Future<void> _export(BuildContext context, WidgetRef ref, String userId,
      String displayName) async {
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    final bgSurface = context.surface.bgSurface;
    try {
      final service = WorkoutExportService(ref.read(databaseProvider));
      final file = await service.writeCsvFile(userId);
      final who = displayName.trim().isEmpty ? '' : ' (${displayName.trim()})';
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'GymLog workout export$who',
        text: 'GymLog training history$who',
      ));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Export failed. Please try again.',
            style: AppText.button(),
          ),
          backgroundColor: bgSurface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    if (user == null) return const SizedBox.shrink();
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    final displayName = profile?.displayName ?? '';
    final surface = context.surface;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surface.surface2,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: surface.borderSubtle),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Backup your training history',
                    style: AppText.rowLabel(),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Download a CSV of all your sets before purging your account.',
                    style: AppText.body(color: surface.textSecondary)
                        .copyWith(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => _export(context, ref, user.id, displayName),
              style: ElevatedButton.styleFrom(
                backgroundColor: surface.surface3,
                foregroundColor: surface.textPrimary,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.buttonPrimary),
                  side: BorderSide(color: surface.borderSubtle),
                ),
              ),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: Text(
                'Export',
                style: AppText.button(color: surface.textPrimary)
                    .copyWith(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
