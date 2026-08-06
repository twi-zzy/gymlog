import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gymlog/core/config/legal_links.dart';
import 'package:gymlog/core/database/database.dart';
import 'package:gymlog/core/providers/app_info_provider.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/theme/app_text.dart';
import 'package:gymlog/core/theme/dynamic_accent_theme.dart';
import 'package:gymlog/core/utils/tap_guard.dart';
import 'package:gymlog/shared/widgets/ui/app_action_row.dart';
import 'package:gymlog/shared/widgets/ui/app_card.dart';
import 'package:gymlog/shared/widgets/ui/app_snack_bar.dart';
import 'package:gymlog/shared/widgets/ui/branded_bottom_sheet.dart';
import 'package:gymlog/shared/widgets/ui/primary_button.dart';
import 'package:gymlog/shared/widgets/ui/time_range_filter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gymlog/shared/layout/adaptive.dart';

/// Opens the Problem Report bottom sheet.
Future<void> showReportProblemSheet(BuildContext context, WidgetRef ref) async {
  HapticFeedback.lightImpact();

  final version = ref.read(appVersionProvider).valueOrNull ?? '1.0.0+1';
  const dbSchemaVersion = kDatabaseSchemaVersion;
  const catalogVersion = kExerciseCatalogVersion;
  final osName = kIsWeb
      ? 'Web'
      : Platform.isAndroid
          ? 'Android'
          : Platform.isIOS
              ? 'iOS'
              : Platform.operatingSystem;
  final opRef = 'op-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  await showBrandedBottomSheet<void>(
    context: context,
    title: 'Report a problem',
    subtitle: 'Sent to the GymLog Telegram channel — non-sensitive details only',
    scrollable: true,
    child: ReportProblemForm(
      appVersion: version,
      dbSchemaVersion: dbSchemaVersion,
      catalogVersion: catalogVersion,
      osName: osName,
      opRef: opRef,
    ),
  );
}

class ReportProblemForm extends StatefulWidget {
  final String appVersion;
  final int dbSchemaVersion;
  final int catalogVersion;
  final String osName;
  final String opRef;

  const ReportProblemForm({
    super.key,
    required this.appVersion,
    required this.dbSchemaVersion,
    required this.catalogVersion,
    required this.osName,
    required this.opRef,
  });

  @override
  State<ReportProblemForm> createState() => _ReportProblemFormState();
}

class _ReportProblemFormState extends State<ReportProblemForm> {
  String _category = 'Bug / Crash';
  bool _submitting = false;
  final _shortDescriptionController = TextEditingController();
  final _reproStepsController = TextEditingController();

  final List<String> _categories = [
    'Bug / Crash',
    'Sync Issue',
    'Exercise / Catalog',
    'Workout Tracker',
    'Personal Records',
    'Other',
  ];

  @override
  void dispose() {
    _shortDescriptionController.dispose();
    _reproStepsController.dispose();
    super.dispose();
  }

  IconData _categoryIcon(String c) => switch (c) {
        'Bug / Crash' => Icons.bug_report_outlined,
        'Sync Issue' => Icons.sync_rounded,
        'Exercise / Catalog' => Icons.fitness_center_rounded,
        'Workout Tracker' => Icons.timer_outlined,
        'Personal Records' => Icons.emoji_events_outlined,
        _ => Icons.more_horiz_rounded,
      };

  Future<void> _pickCategory() async {
    HapticFeedback.selectionClick();
    final selected = await showBrandedPickerSheet<String>(
      context: context,
      title: 'Category',
      selected: _category,
      options: [
        for (final c in _categories)
          PickerOption(
            value: c,
            label: c,
            icon: _categoryIcon(c),
            color: context.surface.textSecondary,
          ),
      ],
    );
    if (selected != null) setState(() => _category = selected);
  }

  String _buildDiagnosticReport() {
    final sb = StringBuffer();
    sb.writeln('--- GymLog Diagnostic Report ---');
    sb.writeln('Category: $_category');
    sb.writeln('Summary: ${_shortDescriptionController.text.trim()}');
    sb.writeln('Reproduction Steps: ${_reproStepsController.text.trim()}');
    sb.writeln('');
    sb.writeln('--- System Metadata ---');
    sb.writeln('App Version: ${widget.appVersion}');
    sb.writeln('OS: ${widget.osName}');
    sb.writeln('DB Schema Version: v${widget.dbSchemaVersion}');
    sb.writeln('Catalog Version: v${widget.catalogVersion}');
    sb.writeln('Op Reference: ${widget.opRef}');
    sb.writeln('');
    sb.writeln(
        'Privacy Guarantee: Workout history, emails, auth tokens, database payloads, and purchase tokens are excluded by default.');
    return sb.toString();
  }

  /// Delivery chain (ship-readiness #5):
  /// 1. The report goes on the clipboard FIRST — every failure path below can
  ///    honestly tell the user to paste it, and no report is ever lost.
  /// 2. Post to the `report-problem` Supabase Edge Function, which holds the
  ///    Telegram bot token server-side and delivers to the GymLog channel.
  ///    A token bundled in the APK would be extractable with `strings`, so
  ///    there is intentionally no direct Bot API call here.
  /// 3. Relay unreachable → open the channel; the report is already copied.
  Future<void> _submitReport() async {
    if (_shortDescriptionController.text.trim().isEmpty) {
      showAppSnackBar(
        context,
        message: 'Please enter a short description.',
      );
      return;
    }

    setState(() => _submitting = true);
    final reportText = _buildDiagnosticReport();
    await Clipboard.setData(ClipboardData(text: reportText));
    if (!mounted) return;

    var delivered = false;
    try {
      await Supabase.instance.client.functions.invoke(
        'report-problem',
        body: {
          'category': _category,
          'summary': _shortDescriptionController.text.trim(),
          'repro': _reproStepsController.text.trim(),
          'appVersion': widget.appVersion,
          'os': widget.osName,
          'dbSchema': widget.dbSchemaVersion,
          'catalog': widget.catalogVersion,
          'opRef': widget.opRef,
        },
      );
      delivered = true;
    } catch (_) {
      delivered = false;
    }
    if (!mounted) return;

    if (delivered) {
      showAppSnackBar(
        context,
        message: 'Report sent to the GymLog channel (ref ${widget.opRef}).',
        variant: AppSnackBarVariant.success,
      );
      Navigator.of(context, rootNavigator: true).pop();
      return;
    }

    // Fallback: the report is already on the clipboard — open the channel so
    // the user can paste it straight in.
    showAppSnackBar(
      context,
      message: 'Report copied — paste it in the GymLog channel.',
    );
    Navigator.of(context, rootNavigator: true).pop();

    try {
      final uri = Uri.parse(kTelegramChannelUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // The report is on the clipboard and the channel handle is on the
      // Help & Feedback screen — nothing more the app can do here.
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final surface = context.surface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('CATEGORY', style: AppText.meta(color: surface.textSecondary)),
        const SizedBox(height: 6),
        // Branded picker, not a stock Material DropdownButton — the last
        // unbranded menu in the app (N4).
        Material(
          color: surface.surface2,
          borderRadius: BorderRadius.circular(AppRadius.input),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.input),
            onTap: _submitting ? null : _pickCategory,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _category,
                      style: AppText.body(color: surface.textPrimary),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 18, color: surface.textTertiary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('SHORT DESCRIPTION',
            style: AppText.meta(color: surface.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: _shortDescriptionController,
          style: AppText.body(color: surface.textPrimary),
          decoration: InputDecoration(
            hintText: 'What happened?',
            hintStyle: AppText.body(color: surface.textSecondary),
            filled: true,
            fillColor: surface.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('REPRODUCTION STEPS (OPTIONAL)',
            style: AppText.meta(color: surface.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: _reproStepsController,
          maxLines: 3,
          style: AppText.body(color: surface.textPrimary),
          decoration: InputDecoration(
            hintText: '1. Tapped X\n2. Opened Y\n3. Saw error Z',
            hintStyle: AppText.body(color: surface.textSecondary),
            filled: true,
            fillColor: surface.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: surface.surface2,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SYSTEM METADATA (INCLUDED)',
                  style: AppText.meta(color: accent.base)),
              const SizedBox(height: 4),
              Text(
                'App: ${widget.appVersion} • OS: ${widget.osName} • DB: v${widget.dbSchemaVersion} • Catalog: v${widget.catalogVersion} • Ref: ${widget.opRef}',
                style: AppText.meta(color: surface.textSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                'Privacy Note: Workout contents, email, auth tokens, database payloads, and purchase tokens are strictly excluded.',
                style: AppText.caption(color: surface.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // PrimaryButton: minHeight + Flexible label, so the label can never
        // clip the way the old fixed-height SizedBox did (ship-readiness #3).
        PrimaryButton(
          label: 'Submit Report',
          icon: Icons.send_rounded,
          isLoading: _submitting,
          onPressed: _submitting ? null : _submitReport,
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Help & Feedback screen — canonical support identity and diagnostic portal.
class HelpFeedbackScreen extends ConsumerWidget {
  const HelpFeedbackScreen({super.key});

  Future<void> _launchUrl(BuildContext context, String url) async {
    if (!tapGuard()) return;
    HapticFeedback.selectionClick();
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (context.mounted) {
        showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Could not open link'),
            content: Text('Link: $url'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surface = context.surface;
    final accent = context.accent;
    final version = ref.watch(appVersionProvider).valueOrNull ?? '1.0.0+1';

    return Scaffold(
      backgroundColor: surface.bgBase,
      appBar: AppBar(
        backgroundColor: surface.bgBase,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: surface.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Help & Feedback',
            style: AppText.screenTitle(color: surface.textPrimary)),
      ),
      body: AdaptiveContent(
          child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.base.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.headset_mic_rounded,
                        color: accent.base, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('GymLog Support',
                            style:
                                AppText.cardTitle(color: surface.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          'Reports land in the Telegram channel · t.me/gym_log',
                          style: AppText.meta(color: surface.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text('SUPPORT & DIAGNOSTICS',
                style: AppText.meta(color: surface.textSecondary)),
            const SizedBox(height: 8),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  AppActionRow(
                    icon: Icons.bug_report_outlined,
                    title: 'Report a problem',
                    subtitle: 'Sent to the GymLog Telegram channel',
                    onTap: () => showReportProblemSheet(context, ref),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text('LEGAL & PRIVACY',
                style: AppText.meta(color: surface.textSecondary)),
            const SizedBox(height: 8),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  AppActionRow(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy Policy',
                    subtitle: 'Local-first. Zero ads, zero selling.',
                    onTap: () => _launchUrl(context, kPrivacyPolicyUrl),
                  ),
                  const AppActionDivider(),
                  AppActionRow(
                    icon: Icons.gavel_rounded,
                    title: 'Terms of Service',
                    subtitle: 'Subscription terms & data policies',
                    onTap: () => _launchUrl(context, kTermsOfServiceUrl),
                  ),
                  const AppActionDivider(),
                  AppActionRow(
                    icon: Icons.delete_outline_rounded,
                    title: 'Account Deletion',
                    subtitle: 'Web self-service deletion portal',
                    onTap: () => _launchUrl(context, kAccountDeletionUrl),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: Text(
                'GymLog $version • DB v$kDatabaseSchemaVersion • Catalog v$kExerciseCatalogVersion',
                style: AppText.caption(color: surface.textSecondary),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      )),
    );
  }
}
