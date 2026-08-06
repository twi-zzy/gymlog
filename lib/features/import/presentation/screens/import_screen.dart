import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:intl/intl.dart';

import 'package:gymlog/core/services/workout_export_service.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/theme/app_text.dart';
import 'package:gymlog/core/theme/dynamic_accent_theme.dart';
import 'package:gymlog/core/utils/units.dart';
import 'package:gymlog/features/import/domain/import_models.dart';
import 'package:gymlog/features/import/presentation/providers/import_provider.dart';
import 'package:gymlog/features/profile/presentation/providers/profile_provider.dart';
import 'package:gymlog/core/providers/settings_provider.dart';
import 'package:gymlog/features/routines/presentation/widgets/routine_detail_styles.dart';
import 'package:gymlog/shared/layout/adaptive.dart';
import 'package:gymlog/shared/widgets/ui/app_snack_bar.dart';

enum _Phase { intro, loading, preview, importing, done }

/// Import workout history exported from Hevy or Strong. The source app is
/// auto-detected from the file; nothing is written until the user confirms.
String _decodeBytes(List<int> bytes) {
  return utf8.decode(bytes, allowMalformed: true);
}

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  _Phase _phase = _Phase.intro;
  String? _content;
  String? _fileName;

  /// The unit the SOURCE FILE was logged in, used to parse it. This is not the
  /// user's display preference and must never be used to render a total — see
  /// _buildPreview. Defaults to kg (the parser's own default) until a Strong
  /// file that carries a unit column says otherwise; the preview unit chooser
  /// lets the user correct an assumption.
  String _assumedUnit = 'kg';
  ImportSummary? _summary;
  ImportResult? _result;
  String? _error;
  int _done = 0;
  int _total = 0;
  bool _cancelRequested = false;

  String? get _userId => ref.read(currentUserProfileProvider).valueOrNull?.id;

  Future<void> _pickFile() async {
    HapticFeedback.lightImpact();
    setState(() => _error = null);
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'tsv', 'txt'],
        withData: true,
      );
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: "Couldn't open the file picker.",
        variant: AppSnackBarVariant.error,
      );
      return;
    }
    if (picked == null || picked.files.isEmpty) return; // cancelled

    final file = picked.files.single;
    String content;
    try {
      final bytes = file.bytes;
      if (bytes != null) {
        content = await compute(_decodeBytes, bytes);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: "Couldn't read the file.",
          variant: AppSnackBarVariant.error,
        );
        return;
      }
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: "Couldn't read the file.",
        variant: AppSnackBarVariant.error,
      );
      return;
    }

    _content = content;
    _fileName = file.name;
    _assumedUnit = 'kg';
    await _runPreview();
  }

  Future<void> _runPreview() async {
    final userId = _userId;
    final content = _content;
    if (userId == null || content == null) return;
    setState(() => _phase = _Phase.loading);
    try {
      final summary = await ref.read(workoutImportServiceProvider).preview(
            content,
            userId: userId,
            assumedStrongUnit: _assumedUnit,
          );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _phase = _Phase.preview;
      });
    } on ImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _phase = _Phase.intro;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong reading that file.';
        _phase = _Phase.intro;
      });
    }
  }

  Future<void> _confirmImport() async {
    final userId = _userId;
    final content = _content;
    if (userId == null || content == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _phase = _Phase.importing;
      _done = 0;
      _total = _summary?.newSessionCount ?? 0;
      _cancelRequested = false;
    });
    try {
      final result = await ref
          .read(workoutImportServiceProvider)
          .import(
            content,
            userId: userId,
            assumedStrongUnit: _assumedUnit,
            onProgress: (done, total) {
              if (!mounted) return;
              setState(() {
                _done = done;
                _total = total;
              });
            },
            isCancelled: () => _cancelRequested,
          )
          .timeout(const Duration(minutes: 5));
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _result = result;
        _phase = _Phase.done;
      });
    } on TimeoutException catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'The import timed out. Any workouts imported before the '
            'timeout have been kept; try again with a smaller file.';
        _phase = _Phase.preview;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'The import could not be completed. No partial data was kept '
            'for the failed workout.';
        _phase = _Phase.preview;
      });
    }
  }

  Future<void> _shareTemplate() async {
    HapticFeedback.selectionClick();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/gymlog_import_template.csv');
      await file.writeAsString(WorkoutExportService.buildTemplateCsv());
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'GymLog import template',
        text:
            'Fill this CSV with your workouts and import it in GymLog (template matches the app\'s own export format).',
      ));
    } catch (_) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: "Couldn't share the template.",
        variant: AppSnackBarVariant.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;

    return PopScope(
      canPop: _phase != _Phase.importing,
      child: Scaffold(
        backgroundColor: surface.bgBase,
        appBar: AppBar(
          backgroundColor: surface.bgBase,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          leading: IconButton(
            tooltip: 'Back',
            icon: Icon(Icons.arrow_back_ios_new,
                size: 18, color: surface.textPrimary),
            onPressed: _phase == _Phase.importing
                ? null
                : () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            'Import workouts',
            style: AppText.sectionHeading(
              color: surface.textPrimary,
            ).copyWith(
              letterSpacing: -0.3,
            ),
          ),
        ),
        body: AdaptiveContent(child: SafeArea(top: false, child: _buildBody())),
      ),
    );
  }

  Widget _buildBody() => switch (_phase) {
        // Spinner color omitted — inherits the active palette base via
        // app_theme's progressIndicatorTheme.
        _Phase.loading =>
          _centered(const CircularProgressIndicator(strokeWidth: 2.5)),
        _Phase.importing => _buildImporting(),
        _Phase.done => _buildDone(),
        _Phase.preview => _buildPreview(),
        _Phase.intro => _buildIntro(),
      };

  Widget _centered(Widget child) => Center(child: child);

  // ── Intro ─────────────────────────────────────

  Widget _buildIntro() {
    final surface = context.surface;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        const _IconBadge(icon: Icons.download_rounded),
        const SizedBox(height: 18),
        Text('Bring your history with you',
            style: AppText.sectionHeading(
              color: surface.textPrimary,
            ).copyWith(
              fontSize: 21,
              letterSpacing: -0.3,
            )),
        const SizedBox(height: 8),
        Text(
          'Import every workout you logged in Hevy or Strong. Export a CSV '
          'from that app, then choose the file here — GymLog detects the '
          'format automatically and converts the units for you.',
          style: AppText.body(
            color: surface.textSecondary,
          ).copyWith(
            fontSize: 14,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        const _SourceChips(),
        const SizedBox(height: 24),
        if (_error != null) ...[
          _Banner(
            icon: Icons.error_outline_rounded,
            color: AppColors.error,
            text: _error!,
          ),
          const SizedBox(height: 16),
        ],
        _PrimaryButton(
            label: 'Choose CSV file',
            icon: Icons.folder_open_rounded,
            onTap: _pickFile),
        const SizedBox(height: 14),
        Center(
          child: TextButton.icon(
            onPressed: _shareTemplate,
            icon: Icon(Icons.download_rounded,
                size: 18, color: surface.textSecondary),
            label: Text('Download CSV template',
                style: AppText.rowLabel(
                  color: surface.textSecondary,
                )),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your data never leaves your device during import.',
          textAlign: TextAlign.center,
          style: AppText.caption(color: surface.textTertiary),
        ),
      ],
    );
  }

  // ── Preview ──────────────────────────────────

  Widget _buildPreview() {
    final s = _summary!;
    final accent = context.accent;
    final df = DateFormat('MMM d, yyyy');
    final range = (s.firstDate != null && s.lastDate != null)
        ? '${df.format(s.firstDate!)} – ${df.format(s.lastDate!)}'
        : '—';
    final surface = context.surface;
    // The user's DISPLAY preference. Deliberately not _assumedUnit: that is the
    // unit the source file was logged in, and the summary total has already
    // been normalised to kilograms by the parser.
    final displayUnit = ref.watch(weightUnitProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Row(children: [
          _DetectedPill(source: s.source),
          const Spacer(),
          if (_fileName != null)
            Flexible(
              child: Text(_fileName!,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption(color: surface.textTertiary)),
            ),
        ]),
        const SizedBox(height: 16),

        // Headline stats.
        _Card(
          child: Column(children: [
            _StatRow(
              label: 'Workouts to import',
              value: '${s.newSessionCount}',
              emphasize: true,
            ),
            if (s.duplicateCount > 0) ...[
              _divider(),
              _StatRow(
                  label: 'Already imported (skipped)',
                  value: '${s.duplicateCount}'),
            ],
            _divider(),
            _StatRow(label: 'Total sets', value: '${s.setCount}'),
            _divider(),
            _StatRow(label: 'Exercises', value: '${s.exerciseCount}'),
            _divider(),
            _StatRow(
                label: 'Total volume',
                value: formatVolume(s.totalVolumeKg.toDouble(), displayUnit)),
            _divider(),
            _StatRow(label: 'Date range', value: range),
          ]),
        ),

        // Strong files sometimes omit the unit — let the user confirm it.
        if (s.weightUnitAssumed) ...[
          const SizedBox(height: 16),
          _UnitChooser(
            unit: _assumedUnit,
            onChanged: (u) {
              setState(() => _assumedUnit = u);
              _runPreview();
            },
          ),
        ],

        if (s.newExerciseNames.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Banner(
            icon: Icons.add_circle_outline_rounded,
            color: accent.light,
            text: _newExercisesText(s.newExerciseNames),
          ),
        ],

        for (final w in s.warnings) ...[
          const SizedBox(height: 12),
          _Banner(
              icon: Icons.info_outline_rounded,
              color: AppColors.warning,
              text: w),
        ],

        const SizedBox(height: 24),
        if (s.hasAnythingToImport)
          _PrimaryButton(
            label: 'Import ${s.newSessionCount} '
                'workout${s.newSessionCount == 1 ? '' : 's'}',
            icon: Icons.check_rounded,
            onTap: _confirmImport,
          )
        else
          const _Banner(
            icon: Icons.task_alt_rounded,
            color: AppColors.success,
            text:
                'Everything in this file is already in GymLog. Nothing to import.',
          ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _pickFile,
            child: Text('Choose a different file',
                style: AppText.rowLabel(
                  color: surface.textSecondary,
                )),
          ),
        ),
      ],
    );
  }

  String _newExercisesText(List<String> names) {
    final count = names.length;
    const previewN = 4;
    final shown = names.take(previewN).join(', ');
    final extra = count > previewN ? ' +${count - previewN} more' : '';
    return '$count new exercise${count == 1 ? '' : 's'} will be added to your '
        'library: $shown$extra';
  }

  // ── Importing ─────────────────────────────────────

  Widget _buildImporting() {
    final pct = _total == 0 ? null : (_done / _total).clamp(0.0, 1.0);
    final surface = context.surface;
    return _centered(
      Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
              value: pct,
              color: context.accent.base,
              strokeWidth: 3,
              backgroundColor: surface.isLight
                  ? Colors.black.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.08)),
        ),
        const SizedBox(height: 22),
        Text('Importing your workouts',
            style: AppText.cardTitle(
              color: surface.textPrimary,
            )),
        const SizedBox(height: 6),
        Text('$_done of $_total',
            style: AppText.meta(
              color: surface.textSecondary,
            )),
        const SizedBox(height: 24),
        TextButton(
          onPressed: _cancelRequested
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  setState(() => _cancelRequested = true);
                },
          child: Text(
            _cancelRequested ? 'Cancelling…' : 'Cancel import',
            style: AppText.rowLabel(color: surface.textSecondary),
          ),
        ),
      ]),
    );
  }

  // ── Done ────────────────────────────────────

  Widget _buildDone() {
    final r = _result!;
    final surface = context.surface;
    final stopped = r.cancelled || r.failure != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: (stopped ? AppColors.warning : AppColors.success)
                  .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(stopped ? Icons.pause_rounded : Icons.check_rounded,
                color: stopped ? AppColors.warning : AppColors.success,
                size: 34),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            r.sessionsImported > 0
                ? 'Imported ${r.sessionsImported} '
                    'workout${r.sessionsImported == 1 ? '' : 's'}'
                : (r.cancelled ? 'Import cancelled' : 'Nothing new to import'),
            style: AppText.sectionHeading(
              color: surface.textPrimary,
            ).copyWith(
              letterSpacing: -0.3,
            ),
          ),
        ),
        if (stopped) ...[
          const SizedBox(height: 10),
          _Banner(
            icon: r.cancelled
                ? Icons.stop_circle_outlined
                : Icons.error_outline_rounded,
            color: AppColors.warning,
            text: r.cancelled
                ? 'Import cancelled — the workouts listed below were kept.'
                : (r.failure ??
                    'The import stopped early — the workouts listed below '
                        'were kept.'),
          ),
        ],
        const SizedBox(height: 20),
        _Card(
          child: Column(children: [
            _StatRow(label: 'Sets logged', value: '${r.setsImported}'),
            _divider(),
            _StatRow(
                label: 'Personal records found', value: '${r.prsDetected}'),
            if (r.exercisesCreated.isNotEmpty) ...[
              _divider(),
              _StatRow(
                  label: 'New exercises added',
                  value: '${r.exercisesCreated.length}'),
            ],
            if (r.sessionsSkipped > 0) ...[
              _divider(),
              _StatRow(
                  label: 'Duplicates skipped', value: '${r.sessionsSkipped}'),
            ],
          ]),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: 'View history',
          icon: Icons.history_rounded,
          onTap: () {
            HapticFeedback.selectionClick();
            context.go('/');
          },
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text('Done',
                style: AppText.rowLabel(
                  color: surface.textSecondary,
                )),
          ),
        ),
      ],
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(height: 1, color: RDStyles.hairline),
      );
}

// ── Reusable bits ─────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    return Container(
      decoration: BoxDecoration(
        gradient: surface.isLight
            ? AppColors.cardGradientLight
            : AppColors.cardGradient,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: surface.borderSubtle, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(
      {required this.label, required this.value, this.emphasize = false});
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    return Semantics(
      label: '$label: $value',
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppText.body(
                    color:
                        emphasize ? surface.textPrimary : surface.textSecondary,
                  ).copyWith(
                    fontSize: 14,
                    fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
                  )),
            ),
            Text(value,
                style: (emphasize
                        ? AppText.sheetTitle(color: context.accent.base)
                        : AppText.body(color: surface.textPrimary).copyWith(
                            fontWeight: FontWeight.w700,
                          ))
                    .copyWith(fontFeatures: kTabular)),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: context.accent.base,
        borderRadius: BorderRadius.circular(AppRadius.buttonPrimary),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.buttonPrimary),
          onTap: onTap,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: context.accent.onAccent),
              const SizedBox(width: 10),
              Text(label,
                  style: AppText.button(
                    color: context.accent.onAccent,
                  )),
            ]),
          ),
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    return Semantics(
      label: 'Notification: $text',
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: AppText.meta(
                  color: surface.textPrimary.withValues(alpha: 0.92),
                ).copyWith(
                  height: 1.4,
                )),
          ),
        ]),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: accent.base.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.badge),
      ),
      child: Icon(icon, color: accent.light, size: 26),
    );
  }
}

class _SourceChips extends StatelessWidget {
  const _SourceChips();

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    // TEXT SCALING: chips + the trailing note live in a Wrap, not a Row — at
    // larger OS text scales the fixed chips used to crowd "auto-detected"
    // into a clip; a Wrap reflows onto a second line instead of overflowing
    // (ship-readiness #3). Identical pixels wherever everything fits.
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final s in ImportSource.values)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: surface.isLight
                  ? AppColors.cardGradientLight
                  : AppColors.cardGradient,
              borderRadius: AppRadius.badgeAll,
              border: Border.all(color: surface.borderSubtle, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fitness_center_rounded,
                    size: 15, color: surface.textSecondary),
                const SizedBox(width: 8),
                Text(s.label,
                    style: AppText.statLabel(color: surface.textPrimary)),
              ],
            ),
          ),
        Text('auto-detected',
            style: AppText.caption(color: surface.textTertiary)),
      ],
    );
  }
}

class _DetectedPill extends StatelessWidget {
  const _DetectedPill({required this.source});
  final ImportSource source;

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final surface = context.surface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: accent.base.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.badge),
        border:
            Border.all(color: accent.base.withValues(alpha: 0.30), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle_rounded, size: 15, color: accent.light),
        const SizedBox(width: 7),
        Text('Detected: ${source.label}',
            style: AppText.statLabel(
              color: surface.textPrimary,
            )),
      ]),
    );
  }
}

class _UnitChooser extends StatelessWidget {
  const _UnitChooser({required this.unit, required this.onChanged});
  final String unit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final surface = context.surface;
    Widget chip(String value, String label) {
      final active = unit == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          label: label,
          child: GestureDetector(
            onTap: () {
              if (!active) {
                HapticFeedback.selectionClick();
                onChanged(value);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? accent.base : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.buttonSecondary),
              ),
              child: Text(label,
                  style: AppText.rowLabel(
                    color: active ? accent.onAccent : surface.textSecondary,
                  )),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Unit Selection. This file has no unit — what was it logged in?',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: surface.isLight
              ? AppColors.cardGradientLight
              : AppColors.cardGradient,
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: surface.borderSubtle, width: 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('This file has no unit — what was it logged in?',
              style: AppText.statLabel(
                color: surface.textPrimary,
              )),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: surface.surface3,
              borderRadius: BorderRadius.circular(AppRadius.buttonSecondary),
            ),
            child:
                Row(children: [chip('kg', 'Kilograms'), chip('lbs', 'Pounds')]),
          ),
        ]),
      ),
    );
  }
}

class ImportTestHelper {
  static Widget buildBanner({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return _Banner(icon: icon, color: color, text: text);
  }

  static Widget buildStatRow({
    required String label,
    required String value,
    bool emphasize = false,
  }) {
    return _StatRow(label: label, value: value, emphasize: emphasize);
  }

  static Widget buildUnitChooser({
    required String unit,
    required ValueChanged<String> onChanged,
  }) {
    return _UnitChooser(unit: unit, onChanged: onChanged);
  }
}
