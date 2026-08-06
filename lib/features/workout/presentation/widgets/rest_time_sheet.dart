import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gymlog/core/models/rest_preference.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/theme/app_text.dart';
import 'package:gymlog/core/theme/dynamic_accent_theme.dart';
import 'package:gymlog/shared/widgets/ui/duration_slider.dart';

/// Opens the compact rest-time selection sheet for an exercise.
///
/// Returns the normalized [RestPreference] selected by the user on Save,
/// or `null` if the user cancels or dismisses the sheet.
Future<RestPreference?> showRestTimeSheet({
  required BuildContext context,
  required String exerciseName,
  required RestPreference currentPreference,
  required int globalSeconds,
}) {
  return showModalBottomSheet<RestPreference>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (_) => RestTimeSheet(
      exerciseName: exerciseName,
      currentPreference: currentPreference,
      globalSeconds: globalSeconds,
    ),
  );
}

String _formatDuration(int seconds) {
  if (seconds <= 0) return '0:00';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Compact rest-time sheet for exercise-level rest duration preference.
///
/// One concept, one control: the same [DurationSlider] Settings uses, with
/// the ±15s steppers flanking it. The six preset chips were a third input
/// method for a single integer — a 5s-detent slider already expresses every
/// preset value (plus 45s and 75s, which the presets couldn't), so they were
/// removed rather than maintained (ship-readiness #9).
class RestTimeSheet extends StatefulWidget {
  final String exerciseName;
  final RestPreference currentPreference;
  final int globalSeconds;

  const RestTimeSheet({
    super.key,
    required this.exerciseName,
    required this.currentPreference,
    required this.globalSeconds,
  });

  @override
  State<RestTimeSheet> createState() => _RestTimeSheetState();
}

class _RestTimeSheetState extends State<RestTimeSheet> {
  static const int _minCustomSeconds = 15;
  static const int _maxCustomSeconds = 600;

  late RestPreference draft;

  @override
  void initState() {
    super.initState();
    draft = normalizeRestPreference(
      preference: widget.currentPreference,
      globalSeconds: widget.globalSeconds,
    );
  }

  int get _workingSeconds {
    if (isOff(draft)) {
      return widget.globalSeconds > 0 ? widget.globalSeconds : 90;
    }
    return resolveRestSeconds(
          preference: draft,
          globalSeconds: widget.globalSeconds,
        ) ??
        (widget.globalSeconds > 0 ? widget.globalSeconds : 90);
  }

  void decrease() {
    final startSec = isOff(draft)
        ? (widget.globalSeconds > 0 ? widget.globalSeconds : 90)
        : _workingSeconds;
    setState(() {
      draft = RestPreference.custom(
        (startSec - 15).clamp(_minCustomSeconds, _maxCustomSeconds),
      );
    });
  }

  void increase() {
    final startSec = isOff(draft)
        ? (widget.globalSeconds > 0 ? widget.globalSeconds : 90)
        : _workingSeconds;
    setState(() {
      draft = RestPreference.custom(
        (startSec + 15).clamp(_minCustomSeconds, _maxCustomSeconds),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.accent;
    final surface = context.surface;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = math.max(20.0, mediaQuery.viewPadding.bottom);
    final maxHeight = mediaQuery.size.height * 0.72;

    final displaySeconds = _workingSeconds;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: surface.surface2,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag handle: 36x4
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: surface.borderEmphasis,
                        borderRadius: BorderRadius.circular(AppRadius.badge),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Title: Rest time (20/700)
                  Text(
                    'Rest time',
                    style: AppText.sectionHeading(color: surface.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),

                  // Subtitle: exerciseName · This workout only (14/400)
                  Text(
                    '${widget.exerciseName} · This workout only',
                    style: AppText.body(color: surface.textSecondary)
                        .copyWith(fontSize: 14),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 20),

                  // Top Option buttons: [ Default · 1:30 ] [ Off ] (option height 48)
                  Row(
                    children: [
                      Expanded(
                        child: _OptionButton(
                          height: 48,
                          isSelected: isDefault(draft),
                          label:
                              'Default · ${_formatDuration(widget.globalSeconds)}',
                          accent: accent,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              draft = const RestPreference.useDefault();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      _OptionButton(
                        height: 48,
                        isSelected: isOff(draft),
                        label: 'Off',
                        accent: accent,
                        minWidth: 80,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            draft = const RestPreference.disabled();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Header / Section label: CUSTOM
                  Text(
                    'CUSTOM',
                    style: AppText.columnHeader(color: surface.textSecondary),
                    textAlign: TextAlign.start,
                  ),
                  const SizedBox(height: 12),

                  // ±15s steppers flanking the shared [DurationSlider] — the
                  // exact control Settings uses for the same concept. The
                  // slider's own readout (AppText.statNumber, tabular) is the
                  // value display; the old monospace 32pt readout — the only
                  // monospace glyph in the app — is gone (ship-readiness #9).
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _StepperButton(
                        label: '−15s',
                        semanticLabel: 'Decrease rest by 15 seconds',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          decrease();
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DurationSlider(
                          valueSeconds: displaySeconds.clamp(
                              _minCustomSeconds, _maxCustomSeconds),
                          minSeconds: _minCustomSeconds,
                          maxSeconds: _maxCustomSeconds,
                          stepSeconds: 5,
                          onChanged: (s) {
                            setState(() {
                              draft = RestPreference.custom(s);
                            });
                          },
                          onChangeEnd: (s) {
                            setState(() {
                              draft = RestPreference.custom(s);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StepperButton(
                        label: '+15s',
                        semanticLabel: 'Increase rest by 15 seconds',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          increase();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Action buttons: [ Cancel ] [ Save ] (action height 50)
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: surface.textSecondary,
                              shape: const RoundedRectangleBorder(
                                borderRadius: AppRadius.buttonPrimaryAll,
                              ),
                            ),
                            onPressed: () => Navigator.pop(context, null),
                            child: Text(
                              'Cancel',
                              style:
                                  AppText.button(color: surface.textSecondary),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent.base,
                              foregroundColor: accent.onAccent,
                              elevation: 0,
                              shape: const RoundedRectangleBorder(
                                borderRadius: AppRadius.buttonPrimaryAll,
                              ),
                            ),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              final normalized = normalizeRestPreference(
                                preference: draft,
                                globalSeconds: widget.globalSeconds,
                              );
                              Navigator.pop(context, normalized);
                            },
                            child: Text(
                              'Save',
                              style: AppText.button(color: accent.onAccent),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final double height;
  final bool isSelected;
  final String label;
  final AccentColors accent;
  final double? minWidth;
  final VoidCallback onTap;

  const _OptionButton({
    required this.height,
    required this.isSelected,
    required this.label,
    required this.accent,
    this.minWidth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    return Material(
      color:
          isSelected ? accent.base.withValues(alpha: 0.14) : surface.surface3,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.buttonPrimaryAll,
        side: BorderSide(
          color: isSelected
              ? accent.base.withValues(alpha: 0.60)
              : surface.borderSubtle,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: AppRadius.buttonPrimaryAll,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            minHeight: height,
            minWidth: minWidth ?? height,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppText.rowLabel(
              color: isSelected ? accent.light : surface.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  const _StepperButton({
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = context.surface;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: surface.surface3,
        borderRadius: AppRadius.buttonSecondaryAll,
        child: InkWell(
          borderRadius: AppRadius.buttonSecondaryAll,
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppText.rowLabel(color: surface.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
