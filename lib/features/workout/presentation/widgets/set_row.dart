import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gymlog/core/theme/app_colors.dart';
import 'package:gymlog/core/utils/units.dart';
import 'package:gymlog/features/workout/domain/active_workout_state.dart';
import 'package:gymlog/shared/widgets/ui/time_range_filter.dart';

// ── Shared column geometry ──────────────────────────────────────────────────
// The header row (ExerciseBlock) and every data row (SetRow) consume these
// SAME constants so a caption can never drift from the column it labels.
// Layout, left → right: SET · PREVIOUS · KG · REPS · ✓
const double kSetColW = 44; // fixed — "1" / "W" / "D" / "F"
const double kCheckColW = 44; // fixed — completion square
const int kPrevFlex = 5; // "999kg x 99" — read-only reference, widest
const int kWeightFlex = 4; // editable number
const int kRepsFlex = 4; // editable number

/// One set inside the active workout — the most-touched interaction in the
/// entire app.
///
/// Hevy-inspired restraint (clean = fewer things drawn):
///   * Weight and reps are PLAIN TEXT on the row surface — no boxes, borders,
///     or fills. The number is the UI.
///   * The unit lives in the column header (KG/LBS), not inline; there is no
///     "×" divider between the two numbers.
///   * The set TYPE replaces the set NUMBER in the SET column (W/D/F as plain
///     coloured text) — one slot, no pill.
///   * A dedicated PREVIOUS column shows last session's "15kg x 12".
///   * Completion is a muted gray square, not a purple circle — purple stays
///     reserved for the Finish button and primary actions.
class SetRow extends StatefulWidget {
  final int setIndex;
  final WorkoutSetState setData;

  /// Previous-session baseline for THIS set index (kg + reps), shown in the
  /// PREVIOUS column. Null when this exercise has no prior history.
  final double? previousWeight;
  final int? previousReps;

  /// Display/input unit for this exercise ('kg' | 'lbs'). Storage stays kg;
  /// conversion happens at this boundary only.
  final String unit;
  final ValueChanged<WorkoutSetState> onChanged;
  final VoidCallback onToggleComplete;

  const SetRow({
    super.key,
    required this.setIndex,
    required this.setData,
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

  String _formatWeightField(double kg) {
    if (kg <= 0) return '';
    final display = kgToDisplay(kg, widget.unit);
    final text = display == display.truncateToDouble()
        ? display.toInt().toString()
        : display.toStringAsFixed(1);
    return text;
  }

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

  bool get _canComplete =>
      widget.setData.weightKg > 0 && widget.setData.reps > 0;

  /// Last session's performance for this set index → "15kg x 12".
  /// Null when there is no prior data (renders a ghosted dash).
  String? get _previousLabel {
    final w = widget.previousWeight;
    final r = widget.previousReps;
    if (w == null || r == null) return null;
    return '${formatWeight(w, widget.unit)}${widget.unit} x $r';
  }

  Future<void> _pickSetType() async {
    final selected = await showBrandedPickerSheet<String>(
      context: context,
      title: 'Set Type',
      selected: widget.setData.setType,
      options: const [
        PickerOption(
          value: 'normal',
          label: 'Normal',
          subtitle: 'Working set',
          icon: Icons.fitness_center_rounded,
          color: AppColors.textPrimary,
        ),
        PickerOption(
          value: 'warmup',
          label: 'Warm-up',
          subtitle: 'Lighter prep work',
          icon: Icons.local_fire_department_rounded,
          color: Color(0xFFE0A422),
        ),
        PickerOption(
          value: 'dropset',
          label: 'Drop Set',
          subtitle: 'Reduced weight, no rest',
          icon: Icons.trending_down_rounded,
          color: Color(0xFF00C4A0),
        ),
        PickerOption(
          value: 'failure',
          label: 'Failure',
          subtitle: 'Taken to the limit',
          icon: Icons.warning_amber_rounded,
          color: Color(0xFFFF6B70),
        ),
      ],
    );
    if (selected != null && selected != widget.setData.setType) {
      widget.onChanged(widget.setData.copyWith(setType: selected));
    }
  }

  /// SET column content: the type letter REPLACES the number (Hevy pattern).
  /// Plain coloured text — never a pill or container. Normal → number.
  Widget _setTypeIndicator() {
    String label;
    Color color;
    switch (widget.setData.setType) {
      case 'warmup':
        label = 'W';
        color = const Color(0xFFE0A422); // amber
        break;
      case 'dropset':
        label = 'D';
        color = const Color(0xFF00C4A0); // purple
        break;
      case 'failure':
        label = 'F';
        color = const Color(0xFFFF6B70); // red
        break;
      default:
        label = '${widget.setIndex + 1}';
        color = widget.setData.isCompleted
            ? AppColors.textPrimary
            : AppColors.textSecondary;
    }
    return Text(
      label,
      style: GoogleFonts.inter(
        color: color,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  /// A bare value field — no box, border, fill, or radius (Change 1).
  /// The number sits directly on the row surface; focus is signalled only
  /// by the cursor and keyboard.
  Widget _numberField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isDecimal,
    required ValueChanged<String> onChanged,
    TextInputAction action = TextInputAction.next,
  }) {
    final completed = widget.setData.isCompleted;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      readOnly: completed,
      textAlign: TextAlign.center,
      textAlignVertical: TextAlignVertical.center,
      textInputAction: action,
      keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
      cursorColor: AppColors.accentPrimary,
      inputFormatters: [
        if (isDecimal)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
        else
          FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(isDecimal ? 6 : 3),
      ],
      style: GoogleFonts.inter(
        // Completed values read at full opacity; in-progress at full white
        // too — colour/size/weight are unchanged from the boxed version,
        // only the container is gone.
        color: AppColors.textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        hintText: '–',
        hintStyle: GoogleFonts.inter(
          color: AppColors.textPrimary.withValues(alpha: 0.2),
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: onChanged,
      onSubmitted: (_) => action == TextInputAction.next
          ? FocusScope.of(context).nextFocus()
          : FocusScope.of(context).unfocus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = widget.setData.isCompleted;
    final prev = _previousLabel;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      // Completion reads as green success — the row carries a whisper of the
      // same green the check fills with, so the cue is cohesive, not a green
      // tick floating on a differently-tinted row.
      color: isCompleted
          ? AppColors.success.withValues(alpha: 0.07)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            // ── SET — type letter replaces number, opens the type picker ──
            SizedBox(
              width: kSetColW,
              child: Semantics(
                button: !isCompleted,
                label: 'Set type',
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
            ),

            // ── PREVIOUS — read-only "15kg x 12" from the last session ────
            Expanded(
              flex: kPrevFlex,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    prev ?? '—',
                    style: GoogleFonts.inter(
                      color: prev != null
                          ? AppColors.textSecondary
                          : AppColors.textSecondary.withValues(alpha: 0.35),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),

            // ── KG — bare number, unit lives in the header ────────────────
            Expanded(
              flex: kWeightFlex,
              child: _numberField(
                controller: _weightController,
                focusNode: _weightFocus,
                isDecimal: true,
                onChanged: (val) {
                  final parsed = double.tryParse(val);
                  if (parsed != null) {
                    final kg =
                        displayToKg(parsed, widget.unit).clamp(0.0, 999.5);
                    widget.onChanged(widget.setData.copyWith(weightKg: kg));
                  }
                },
              ),
            ),

            // ── REPS — bare number (no "×" divider before it) ─────────────
            Expanded(
              flex: kRepsFlex,
              child: _numberField(
                controller: _repsController,
                focusNode: _repsFocus,
                isDecimal: false,
                action: TextInputAction.done,
                onChanged: (val) {
                  final parsed = int.tryParse(val);
                  if (parsed != null) {
                    widget.onChanged(
                        widget.setData.copyWith(reps: parsed.clamp(0, 999)));
                  }
                },
              ),
            ),

            // ── Completion — muted gray square (no purple) ────────────────
            SizedBox(
              width: kCheckColW,
              child: Semantics(
                button: true,
                label: isCompleted ? 'Mark set incomplete' : 'Complete set',
                child: GestureDetector(
                  onTap: isCompleted || _canComplete
                      ? () {
                          if (!isCompleted) HapticFeedback.mediumImpact();
                          widget.onToggleComplete();
                        }
                      : null,
                  behavior: HitTestBehavior.opaque,
                  child: Center(
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(isCompleted),
                      tween: Tween<double>(
                        begin: isCompleted ? 1.15 : 1.0,
                        end: 1.0,
                      ),
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          // Three states: done = solid green, ready = green
                          // outline (invites the tap), idle = faint gray outline.
                          color: isCompleted
                              ? AppColors.success
                              : Colors.transparent,
                          border: isCompleted
                              ? null
                              : Border.all(
                                  color: _canComplete
                                      ? AppColors.success.withValues(alpha: 0.55)
                                      : AppColors.textPrimary
                                          .withValues(alpha: 0.15),
                                ),
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          color: isCompleted
                              ? Colors.white
                              : _canComplete
                                  ? AppColors.success.withValues(alpha: 0.7)
                                  : AppColors.textPrimary
                                      .withValues(alpha: 0.10),
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
