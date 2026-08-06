import 'package:flutter/material.dart';

// ── Shared set-table geometry ─────────────────────────────────────────
// The ONE layout contract for the set table. The header strip
// (ExerciseBlock) and every data row (SetRow) render through [SetTableRow],
// so column widths, flex weights and the horizontal inset are declared
// exactly once. When they were declared twice — the header sitting directly
// in the card's 15dp padding while every SetRow added its own
// `horizontal: 16` (plus a further 4dp inside each number field) — the
// resulting width delta was redistributed across the flex columns and the
// misalignment accumulated left-to-right, worst at REPS and ✓
// (ship-readiness #6).
//
// Layout, left → right: SET · PREVIOUS · KG · REPS · ✓
const double kSetColW = 48; // fixed — "1" / "W" / "D" / "F"
const double kCheckColW = 48; // fixed — completion square
const int kPrevFlex = 5; // "999kg x 99" — read-only reference, widest
const int kWeightFlex = 4; // editable number
const int kRepsFlex = 4; // editable number

/// Horizontal inset applied ONCE around every [SetTableRow] — header strip
/// and data rows alike. No consumer may add its own horizontal padding.
const double kSetTableInset = 16;

/// One row of the set table: the header and the data rows are the SAME
/// widget with different slot content. Owns, exactly once:
///   • the horizontal inset ([kSetTableInset])
///   • column widths + flex (constants above)
///   • the row's minimum height
///
/// Slot contract: SET and PREVIOUS content left-aligns itself (the tap
/// target must fill the slot, so alignment stays inside the slot);
/// WEIGHT/REPS content fills its slot and centres its own text; ✓ content
/// centres itself. Slots must NOT add horizontal padding — that is the
/// divergence this type exists to make impossible.
class SetTableRow extends StatelessWidget {
  final Widget setSlot;
  final Widget previousSlot;
  final Widget weightSlot;
  final Widget repsSlot;
  final Widget checkSlot;

  /// 44 for data rows, 22 for the header strip. A minimum, never a pin — at
  /// large OS text scales the row grows instead of clipping.
  final double minHeight;

  const SetTableRow({
    super.key,
    required this.setSlot,
    required this.previousSlot,
    required this.weightSlot,
    required this.repsSlot,
    required this.checkSlot,
    this.minHeight = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kSetTableInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Row(
          children: [
            SizedBox(width: kSetColW, child: setSlot),
            Expanded(flex: kPrevFlex, child: previousSlot),
            Expanded(flex: kWeightFlex, child: weightSlot),
            Expanded(flex: kRepsFlex, child: repsSlot),
            SizedBox(width: kCheckColW, child: checkSlot),
          ],
        ),
      ),
    );
  }
}
