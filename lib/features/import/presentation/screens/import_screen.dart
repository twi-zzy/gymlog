import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/utils/units.dart';
import 'package:gymlog/features/import/domain/import_models.dart';
import 'package:gymlog/features/import/presentation/providers/import_provider.dart';
import 'package:gymlog/features/profile/presentation/providers/profile_provider.dart';
import 'package:gymlog/core/providers/settings_provider.dart';
import 'package:gymlog/features/routines/presentation/widgets/routine_detail_styles.dart';

enum _Phase { intro, loading, preview, importing, done }

/// Import workout history exported from Hevy or Strong. The source app is
/// auto-detected from the file; nothing is written until the user confirms.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  _Phase _phase = _Phase.intro;
  String? _content;
  String? _fileName;
  String _assumedUnit = 'kg';
  ImportSummary? _summary;
  ImportResult? _result;
  String? _error;
  int _done = 0;
  int _total = 0;

  String? get _userId => ref.read(currentUserProfileProvider).valueOrNull?.id;

  Future<void> _pickFile() async {
    HapticFeedback.lightImpact();
    setState(() => _error = null);
    final messenger = ScaffoldMessenger.of(context);
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'tsv', 'txt'],
        withData: true,
      );
    } catch (_) {
      messenger.showSnackBar(_snack("Couldn't open the file picker."));
      return;
    }
    if (picked == null || picked.files.isEmpty) return; // cancelled

    final file = picked.files.single;
    String content;
    try {
      final bytes = file.bytes;
      if (bytes != null) {
        content = utf8.decode(bytes, allowMalformed: true);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        messenger.showSnackBar(_snack("Couldn't read the file."));
        return;
      }
    } catch (_) {
      messenger.showSnackBar(_snack("Couldn't read the file."));
      return;
    }

    _content = content;
    _fileName = file.name;
    _assumedUnit = ref.read(weightUnitProvider);
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
      _total = _summary?.sessionCount ?? 0;
    });
    try {
      final result = await ref.read(workoutImportServiceProvider).import(
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
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _result = result;
        _phase = _Phase.done;
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

  SnackBar _snack(String msg) => SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: AppColors.textPrimary)),
        backgroundColor: AppColors.bgSurface,
        behavior: SnackBarBehavior.floating,
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _Phase.importing,
      child: Scaffold(
        backgroundColor: AppColors.bgBase,
        appBar: AppBar(
          backgroundColor: AppColors.bgBase,
          scrolledUnderElevation: 0,
          titleSpacing: 0,
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_ios_new,
                size: 18, color: AppColors.textPrimary),
            onPressed: _phase == _Phase.importing
                ? null
                : () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            'Import workouts',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: -0.3,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        body: SafeArea(top: false, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() => switch (_phase) {
        _Phase.loading => _centered(const CircularProgressIndicator(
            color: AppColors.accentPrimary, strokeWidth: 2.5)),
        _Phase.importing => _buildImporting(),
        _Phase.done => _buildDone(),
        _Phase.preview => _buildPreview(),
        _Phase.intro => _buildIntro(),
      };

  Widget _centered(Widget child) => Center(child: child);

  // ── Intro ──────────────────────────────────────────────────────────────────

  Widget _buildIntro() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        const _IconBadge(icon: Icons.download_rounded),
        const SizedBox(height: 18),
        Text('Bring your history with you',
            style: GoogleFonts.inter(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(
          'Import every workout you logged in Hevy or Strong. Export a CSV '
          'from that app, then choose the file here — GymLog detects the '
          'format automatically and converts the units for you.',
          style: GoogleFonts.inter(
              fontSize: 14, height: 1.45, color: AppColors.textSecondary),
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
        _PrimaryButton(label: 'Choose CSV file', icon: Icons.folder_open_rounded, onTap: _pickFile),
        const SizedBox(height: 14),
        Text(
          'Your data never leaves your device during import.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 12, color: AppColors.chartAxisLabel),
        ),
      ],
    );
  }

  // ── Preview ────────────────────────────────────────────────────────────────

  Widget _buildPreview() {
    final s = _summary!;
    final df = DateFormat('MMM d, yyyy');
    final range = (s.firstDate != null && s.lastDate != null)
        ? '${df.format(s.firstDate!)} – ${df.format(s.lastDate!)}'
        : '—';

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
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.chartAxisLabel)),
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
            _StatRow(label: 'Total volume', value: '${groupThousands(s.totalVolumeKg)} kg'),
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
            color: const Color(0xFF00C4A0),
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
            text: 'Everything in this file is already in GymLog. Nothing to import.',
          ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _pickFile,
            child: Text('Choose a different file',
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
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

  // ── Importing ────────────────────────────────────────────────────────────────

  Widget _buildImporting() {
    final pct = _total == 0 ? null : (_done / _total).clamp(0.0, 1.0);
    return _centered(
      Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
              value: pct,
              color: AppColors.accentPrimary,
              strokeWidth: 3,
              backgroundColor: Colors.white.withValues(alpha: 0.08)),
        ),
        const SizedBox(height: 22),
        Text('Importing your workouts',
            style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text('$_done of $_total',
            style: GoogleFonts.inter(
                fontSize: 13, color: AppColors.textSecondary)),
      ]),
    );
  }

  // ── Done ──────────────────────────────────────────────────────────────────

  Widget _buildDone() {
    final r = _result!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: AppColors.success, size: 34),
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: Text(
            r.sessionsImported > 0
                ? 'Imported ${r.sessionsImported} '
                    'workout${r.sessionsImported == 1 ? '' : 's'}'
                : 'Nothing new to import',
            style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 20),
        _Card(
          child: Column(children: [
            _StatRow(label: 'Sets logged', value: '${r.setsImported}'),
            _divider(),
            _StatRow(label: 'Personal records found', value: '${r.prsDetected}'),
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
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
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

// ── Reusable bits ─────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: RDStyles.cardGradient,
          borderRadius: BorderRadius.circular(12),
          border: RDStyles.hairlineBorder,
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class _StatRow extends StatelessWidget {
  const _StatRow(
      {required this.label, required this.value, this.emphasize = false});
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      color: emphasize
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight:
                          emphasize ? FontWeight.w600 : FontWeight.w500)),
            ),
            Text(value,
                style: GoogleFonts.inter(
                    fontSize: emphasize ? 18 : 15,
                    fontWeight: FontWeight.w700,
                    color: emphasize
                        ? AppColors.accentPrimary
                        : AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
      );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.accentPrimary,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 10),
              Text(label,
                  style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ]),
          ),
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner(
      {required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textPrimary.withValues(alpha: 0.92))),
          ),
        ]),
      );
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.accentPrimary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFF00C4A0), size: 26),
      );
}

class _SourceChips extends StatelessWidget {
  const _SourceChips();

  @override
  Widget build(BuildContext context) => Row(children: [
        for (final s in ImportSource.values) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              gradient: RDStyles.cardGradient,
              borderRadius: BorderRadius.circular(12),
              border: RDStyles.hairlineBorder,
            ),
            child: Row(children: [
              const Icon(Icons.fitness_center_rounded,
                  size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(s.label,
                  style: GoogleFonts.inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ]),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text('auto-detected',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.chartAxisLabel)),
        ),
      ]);
}

class _DetectedPill extends StatelessWidget {
  const _DetectedPill({required this.source});
  final ImportSource source;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.accentPrimary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: AppColors.accentPrimary.withValues(alpha: 0.30), width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_rounded,
              size: 15, color: Color(0xFF00C4A0)),
          const SizedBox(width: 7),
          Text('Detected: ${source.label}',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ]),
      );
}

class _UnitChooser extends StatelessWidget {
  const _UnitChooser({required this.unit, required this.onChanged});
  final String unit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(String value, String label) {
      final active = unit == value;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (!active) {
              HapticFeedback.selectionClick();
              onChanged(value);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.accentPrimary : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(label,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : AppColors.textSecondary)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: RDStyles.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: RDStyles.hairlineBorder,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('This file has no unit — what was it logged in?',
            style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [chip('kg', 'Kilograms'), chip('lbs', 'Pounds')]),
        ),
      ]),
    );
  }
}
