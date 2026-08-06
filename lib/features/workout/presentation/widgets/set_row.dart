import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/theme/app_text.dart';
import 'package:gymlog/core/theme/dynamic_accent_theme.dart';
import 'package:gymlog/core/theme/set_type.dart';
import 'package:gymlog/core/utils/units.dart';
import 'package:gymlog/features/workout/domain/active_workout_state.dart';
import 'package:gymlog/shared/widgets/ui/time_range_filter.dart';

import 'package:gymlog/core/models/measurement_type.dart';
import 'set_table_layout.dart';

// Column geometry (kSetColW / kCheckColW / kPrevFlex / kWeightFlex /
// kRepsFlex) now lives in set_table_layout.dart — re-exported here so
// existing importers of set_row.dart keep resolving it unchanged.
export 'set_table_layout.dart'
    show kSetColW, kCheckColW, kPrevFlex, kWeightFlex, kRepsFlex;

/// Background wash on a completed set row: 6% green over #000000.
///
/// WHY A LOCAL CONSTANT: [AppColors.completionTint] is an alias of
/// `successTint` (0x24 = 14% alpha) and is used for success SURFACES elsewhere,
/// where a visible fill is correct. A completed set row is not a surface — it is
/// a 44dp line of numbers that must stay readable, and it already carries two
/// other completion signals (the 3px left bar and the solid green check).
/// Retuning the shared token would silently wash out every other consumer.
const Color _kCompletionRowTint = Color(0x0F34C759);

/// One set inside the active workout — the most-touched interaction in the app.
///
/// Hevy-inspired restraint: weight/reps are plain numbers on the row surface
/// (no boxes), the unit lives in the column header, and the set TYPE letter
/// replaces the set NUMBER in the SET column. Set-type colors come from the
/// shared [SetType] enum so they're identical to every other screen.
///
/// ## P0-02 adaptive layout
///
/// | [MeasurementType]   | weight-slot column | reps-slot column |
/// |---------------------|--------------------|------------------|
/// | weightAndReps       | kg / lbs           | REPS             |
/// | repsOnly            | hidden             | REPS             |
/// | duration            | hidden             | SECS             |
/// | distance            | DIST (raw metres)  | hidden           |
///
/// DO NOT BOX THE INPUTS. Bordered/filled input boxes were tried and rejected:
/// at four sets per exercise and six exercises per session, 48 outlined boxes
/// turn a set table into a form. The row surface, the column headers, and the
/// cursor carry all the affordance that is needed — see [_numberField].
class SetRow extends StatefulWidget {
  final int setIndex;
  final WorkoutSetState setData;
  final MeasurementType measurementType;

  /// Previous-session baseline for THIS set index. Null when no prior history.
  final double? previousWeight;
  final int? previousReps;

  /// Display/input unit ('kg' | 'lbs'). Storage stays kg; conversion happens
  /// at this boundary only (ignored for [MeasurementType.distance]).
  final String unit;
  final ValueChanged<WorkoutSetState> onChanged;
  final VoidCallback onToggleComplete;

  const SetRow({
    super.key,
    required this.setIndex,
    required this.setData,
    this.measurementType = MeasurementType.weightAndReps,
    this.previousWeight,
    this.previousReps,
    this.unit = 'kg',
    required this.onChanged,
    required this.onToggleComplete,
  });

  @override
  State<SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<SetRow> {
  late TextEditingController _weightController;
  late TextEditingController _repsController;
  final _weightFocus = FocusNode();
  final _repsFocus = FocusNode();

  /// Rapid-tap guard — prevents a fast double-tap from toggling twice.
  bool _completing = false;

  /// When true, empty required fields briefly flash in the accent tint to
  /// signal which value is missing (instead of a silent non-response).
  bool _showValidationHint = false;

  // ── Formatting ────────────────────────────────────────────────────────────

  /// Formats a stored value for display in the weight-slot field.
  /// For [MeasurementType.distance] the value is raw metres — no unit
  /// conversion. For all others the user's preferred kg/lbs is applied.
  String _formatWeightField(double? value) {
    if (value == null || value <= 0) return '';
    if (widget.measurementType == MeasurementType.distance) {
      return value == value.truncateToDouble()
          ? value.toInt().toString()
          : value.toStringAsFixed(1);
    }
    final display = kgToDisplay(value, widget.unit);
    return display == display.truncateToDouble()
        ? display.toInt().toString()
        : display.toStringAsFixed(1);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(
      text: _formatWeightField(widget.setData.weightKg),
    );
    _repsController = TextEditingController(
      text: widget.setData.reps > 0 ? widget.setData.reps.toString() : '',
    );
  }

  @override
  void didUpdateWidget(covariant SetRow oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ── Measurement type changed ──────────────────────────────────────────
    // This can happen when the catalog resolves after exercise addition, or
    // when replaceExercise creates a new widget on the same key. Reset
    // controllers that are no longer applicable for the new type.
    if (widget.measurementType != oldWidget.measurementType) {
      if (!widget.measurementType.showsWeightColumn) {
        _weightController.text = '';
      } else if (!_weightFocus.hasFocus) {
        final t = _formatWeightField(widget.setData.weightKg);
        _weightController.value = _weightController.value.copyWith(
          text: t,
          selection: TextSelection.collapsed(offset: t.length),
        );
      }
      if (!widget.measurementType.showsRepsColumn) {
        _repsController.text = '';
      }
      return; // skip the per-field refresh below — type change is authoritative
    }

    // ── Weight or unit changed externally ────────────────────────────────
    final weightChanged = widget.setData.weightKg != oldWidget.setData.weightKg;
    final unitChanged = widget.unit != oldWidget.unit;
    if ((weightChanged || unitChanged) && !_weightFocus.hasFocus) {
      final newText = _formatWeightField(widget.setData.weightKg);
      _weightController.value = _weightController.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
    if (widget.setData.reps != oldWidget.setData.reps &&
        widget.setData.reps > 0 &&
        !_repsFocus.hasFocus) {
      final newText = widget.setData.reps.toString();
      _repsController.value = _repsController.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    _weightFocus.dispose();
    _repsFocus.dispose();
    super.dispose();
  }

  // ── Completion logic ──────────────────────────────────────────────────────

  // Whether the set has enough data to be marked complete.
  bool get _canComplete => canCompleteSetRaw(
        measurementType: widget.measurementType,
        weightKg: widget.setData.weightKg,
        reps: widget.setData.reps,
        previousWeight: widget.previousWeight,
        previousReps: widget.previousReps,
      );

  // ── Validation flash targets ───────────────────────────────────────────

  bool get _weightShouldFlash =>
      _showValidationHint &&
      widget.measurementType.showsWeightColumn &&
      (widget.setData.weightKg == null || widget.setData.weightKg! <= 0) &&
      widget.previousWeight == null;

  bool get _repsShouldFlash =>
      _showValidationHint &&
      widget.measurementType.showsRepsColumn &&
      widget.setData.reps <= 0 &&
      widget.previousReps == null;

  // ── Previous-session label ────────────────────────────────────────────────

  /// Last session's performance for this set index.
  /// Rendered as: "15kg x 12" | "12 reps" | "60s" | "400m" | null.
  String? get _previousLabel {
    final w = widget.previousWeight;
    final r = widget.previousReps;
    if (w == null && r == null) return null;
    return switch (widget.measurementType) {
      MeasurementType.weightAndReps => w != null
          ? '${formatWeight(w, widget.unit)}${widget.unit} x ${r ?? 0}'
          : (r != null ? '$r reps' : null),
      MeasurementType.distance => w != null
          ? '${w == w.truncateToDouble() ? w.toInt() : w.toStringAsFixed(1)}m'
          : null,
      MeasurementType.duration => r != null ? '${r}s' : null,
      _ => r != null ? '$r reps' : null, // repsOnly
    };
  }

  // ── Set-type picker ───────────────────────────────────────────────────────

  Future<void> _pickSetType() async {
    final selected = await showBrandedPickerSheet<String>(
      context: context,
      title: 'Set Type',
      selected: widget.setData.setType,
      options: [
        for (final t in SetType.values)
          PickerOption(
            value: t.raw,
            label: t.label,
            subtitle: t.subtitle,
            icon: t.icon,
            color: t.resolveColor(context),
          ),
      ],
    );
    if (selected != null && selected != widget.setData.setType) {
      widget.onChanged(widget.setData.copyWith(setType: selected));
    }
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  /// SET column content: the type letter REPLACES the number (Hevy pattern).
  /// Normal → set number; W/D/F → coloured letter (colors from [SetType]).
  Widget _setTypeIndicator() {
    final surface = context.surface;
    final type = SetType.of(widget.setData.setType);
    final isNormal = type == SetType.normal;
    final label = isNormal ? '${widget.setIndex + 1}' : type.short;
    final color = isNormal
        ? (widget.setData.isCompleted
            ? surface.textPrimary
            : surface.textSecondary)
        : type.color;
    return Text(label, style: AppText.value(color: color));
  }

  /// A bare value field — no box, border, fill, or radius. The number sits
  /// directly on the row surface; focus is signalled only by the cursor
  /// (tinted with the active accent palette).
  ///
  /// When [flashHint] is true the hint text briefly renders in a dim accent
  /// tint, signalling which field is missing a required value.
  ///
  /// The four `InputBorder.none` / `filled: false` lines below are LOAD-BEARING
  /// design, not leftovers. Removing them restores Material's default underline
  /// or outline and turns the set table back into a form.
  ///
  /// GEOMETRY: no per-field horizontal padding and no animating wrapper — the
  /// shared [SetTableRow] slot owns this field's extents, so the typed number
  /// is centred on exactly the same centre line as the column header above it
  /// (ship-readiness #6). The [Center] is load-bearing: it vertically centres
  /// the ~36dp field inside the 48dp tap target.
  Widget _numberField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isDecimal,
    required String semanticLabel,
    required ValueChanged<String> onChanged,
    TextInputAction action = TextInputAction.next,
    String? hintText,
    bool flashHint = false,
  }) {
    final completed = widget.setData.isCompleted;
    final accent = context.accent;
    final surface = context.surface;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      child: Center(
        child: Semantics(
          label: semanticLabel,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            readOnly: completed,
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            textInputAction: action,
            keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
            cursorColor: accent.base,
            inputFormatters: [
              if (isDecimal) ...[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                TextInputFormatter.withFunction((oldValue, newValue) {
                  if ('.'.allMatches(newValue.text).length > 1) {
                    return oldValue;
                  }
                  return newValue;
                }),
              ] else
                FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(isDecimal ? 6 : 5),
            ],
            style: AppText.value(color: surface.textPrimary),
            decoration: InputDecoration(
              hintText: hintText ?? '0',
              hintStyle: AppText.value(
                color: flashHint
                    ? accent.base.withValues(alpha: 0.85)
                    : surface.textTertiary,
              ),
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            ),
            onChanged: onChanged,
            onSubmitted: (_) => action == TextInputAction.next
                ? FocusScope.of(context).nextFocus()
                : FocusScope.of(context).unfocus(),
          ),
        ),
      ),
    );
  }

  String _buildCoherentSemanticLabel() {
    final type = SetType.of(widget.setData.setType);
    final setTypeName = type == SetType.normal
        ? 'Set ${widget.setIndex + 1}'
        : '${type.label} Set ${widget.setIndex + 1}';

    final prev = _previousLabel;
    final prevPart =
        (prev != null && prev.isNotEmpty) ? 'Previous: $prev. ' : '';

    final wVal = widget.setData.weightKg;
    final rVal = widget.setData.reps;

    String weightPart = '';
    if (widget.measurementType.showsWeightColumn) {
      if (widget.measurementType == MeasurementType.distance) {
        final distStr =
            wVal != null && wVal > 0 ? _formatWeightField(wVal) : '0';
        weightPart = 'Distance: $distStr metres. ';
      } else {
        final wStr =
            wVal != null && wVal > 0 ? formatWeight(wVal, widget.unit) : '0';
        final unitName = widget.unit == 'lbs' ? 'pounds' : 'kilograms';
        weightPart = 'Weight: $wStr $unitName. ';
      }
    }

    String repsPart = '';
    if (widget.measurementType.showsRepsColumn) {
      if (widget.measurementType == MeasurementType.duration) {
        repsPart = 'Duration: $rVal seconds. ';
      } else {
        repsPart = 'Reps: $rVal. ';
      }
    }

    final statusPart =
        widget.setData.isCompleted ? 'Completed.' : 'Not completed.';

    return '$setTypeName. $prevPart$weightPart$repsPart$statusPart';
  }

  Map<CustomSemanticsAction, VoidCallback> _buildCustomSemanticsActions() {
    final Map<CustomSemanticsAction, VoidCallback> actions = {};

    if (widget.measurementType.showsWeightColumn) {
      actions[const CustomSemanticsAction(label: 'Edit weight')] = () {
        _weightFocus.requestFocus();
      };
    }
    if (widget.measurementType.showsRepsColumn) {
      actions[const CustomSemanticsAction(label: 'Edit reps')] = () {
        _repsFocus.requestFocus();
      };
    }

    actions[CustomSemanticsAction(
      label:
          widget.setData.isCompleted ? 'Mark set incomplete' : 'Complete set',
    )] = () {
      if (widget.setData.isCompleted || _canComplete) {
        _onToggleComplete();
      }
    };

    if (!widget.setData.isCompleted) {
      actions[const CustomSemanticsAction(label: 'Change set type')] = () {
        _pickSetType();
      };
    }

    return actions;
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = widget.setData.isCompleted;
    final surface = context.surface;
    final prev = _previousLabel;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final coherentLabel = _buildCoherentSemanticLabel();
    final customActions = _buildCustomSemanticsActions();

    return Semantics(
      container: true,
      label: coherentLabel,
      customSemanticsActions: customActions,
      child: AnimatedContainer(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        // Completed row = 3px green left border + 6% green tint (not a full fill).
        // Completion is a fixed success semantic — like reward gold, it never
        // shifts with the accent palette. See [_kCompletionRowTint] for why this
        // does not use the shared success token.
        decoration: BoxDecoration(
          color: isCompleted ? _kCompletionRowTint : Colors.transparent,
          border: isCompleted
              ? const Border(
                  left: BorderSide(color: AppColors.success, width: 3))
              : null,
        ),
        // Horizontal inset is owned by [SetTableRow] — see
        // set_table_layout.dart. Vertical rhythm stays here.
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: SetTableRow(
          // ── SET — type letter replaces number, opens the type picker ──
          setSlot: Semantics(
            button: !isCompleted,
            label: 'Set type, ${SetType.of(widget.setData.setType).label}',
            child: GestureDetector(
              onTap: isCompleted
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      _pickSetType();
                    },
              behavior: HitTestBehavior.opaque,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _setTypeIndicator(),
              ),
            ),
          ),

          // ── PREVIOUS — read-only reference from the last session ────
          // C31: was FittedBox(scaleDown) — arbitrary shrink-to-fit text is
          // a WCAG 1.4.4 failure. Ellipsis truncates the tail instead of
          // shrinking glyphs below readable size.
          previousSlot: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              prev ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.statLabel(
                color: prev != null
                    ? surface.textSecondary
                    : surface.textTertiary,
              ),
            ),
          ),

          // ── WEIGHT / DISTANCE — hidden for repsOnly and duration ──────
          weightSlot: !widget.measurementType.showsWeightColumn
              ? const SizedBox.shrink()
              : _numberField(
                  controller: _weightController,
                  focusNode: _weightFocus,
                  isDecimal: true,
                  semanticLabel:
                      widget.measurementType == MeasurementType.distance
                          ? 'Distance in metres'
                          : 'Weight in ${widget.unit}',
                  hintText: widget.previousWeight != null
                      ? _formatWeightField(widget.previousWeight!)
                      : '0',
                  flashHint: _weightShouldFlash,
                  onChanged: (val) {
                    if (val.trim().isEmpty) {
                      widget.onChanged(
                          widget.setData.copyWith(weightKg: null));
                      return;
                    }
                    final parsed = double.tryParse(val);
                    if (parsed != null) {
                      // Distance: store raw value — no kg/lbs conversion.
                      // Weight: convert from the user's display unit to kg.
                      final stored = widget.measurementType ==
                              MeasurementType.distance
                          ? parsed.clamp(0.0, 99999.0)
                          : displayToKg(parsed, widget.unit)
                              .clamp(0.0, 999.5);
                      widget.onChanged(
                          widget.setData.copyWith(weightKg: stored));
                    }
                  },
                ),

          // ── REPS / SECS — hidden for distance ───────────────────────
          repsSlot: !widget.measurementType.showsRepsColumn
              ? const SizedBox.shrink()
              : _numberField(
                  controller: _repsController,
                  focusNode: _repsFocus,
                  isDecimal: false,
                  action: TextInputAction.done,
                  semanticLabel:
                      widget.measurementType.repsFieldSemanticLabel,
                  hintText: widget.previousReps != null
                      ? '${widget.previousReps!}'
                      : '0',
                  flashHint: _repsShouldFlash,
                  onChanged: (val) {
                    if (val.trim().isEmpty) {
                      widget.onChanged(widget.setData.copyWith(reps: 0));
                      return;
                    }
                    final parsed = int.tryParse(val);
                    if (parsed != null) {
                      widget.onChanged(widget.setData
                          .copyWith(reps: parsed.clamp(0, 99999)));
                    }
                  },
                ),

          // ── Completion — always tappable; validation fires on miss ───
          checkSlot: Semantics(
            button: true,
            label: isCompleted ? 'Mark set incomplete' : 'Complete set',
            child: GestureDetector(
              onTap: () {
                if (isCompleted) {
                  _onToggleComplete();
                  return;
                }
                if (!_canComplete) {
                  // Show which field(s) are empty for 1.4 s, then fade.
                  HapticFeedback.heavyImpact();
                  setState(() => _showValidationHint = true);
                  Future.delayed(const Duration(milliseconds: 1400), () {
                    if (mounted) {
                      setState(() => _showValidationHint = false);
                    }
                  });
                  return;
                }
                HapticFeedback.mediumImpact();
                _onToggleComplete();
              },
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(isCompleted),
                  tween: Tween<double>(
                    begin: isCompleted ? 1.15 : 1.0,
                    end: 1.0,
                  ),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 100),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.badgeAll,
                      color: isCompleted
                          ? AppColors.success
                          : Colors.transparent,
                      border: isCompleted
                          ? null
                          : Border.all(
                              color: _canComplete
                                  ? AppColors.success.withValues(alpha: 0.55)
                                  : surface.textPrimary
                                      .withValues(alpha: 0.15),
                            ),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      color: isCompleted
                          ? surface.textPrimary
                          : _canComplete
                              ? AppColors.success.withValues(alpha: 0.7)
                              : surface.textPrimary.withValues(alpha: 0.10),
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Backfills empty fields from the previous session, then toggles completion.
  /// Guards against rapid double-taps with [_completing].
  void _onToggleComplete() {
    if (_completing) return;
    _completing = true;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _completing = false;
    });

    if (!widget.setData.isCompleted) {
      var next = widget.setData;
      // Backfill weight-slot from previous session if still empty.
      if (widget.measurementType.showsWeightColumn &&
          (next.weightKg == null || next.weightKg! <= 0) &&
          widget.previousWeight != null) {
        next = next.copyWith(weightKg: widget.previousWeight!);
        _weightController.text = _formatWeightField(widget.previousWeight!);
      }
      // Backfill reps-slot from previous session if still empty.
      if (widget.measurementType.showsRepsColumn &&
          next.reps <= 0 &&
          widget.previousReps != null) {
        next = next.copyWith(reps: widget.previousReps!);
        _repsController.text = widget.previousReps!.toString();
      }
      if (next != widget.setData) widget.onChanged(next);
    }
    widget.onToggleComplete();
  }
}
