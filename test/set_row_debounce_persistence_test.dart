// Release gate for P1.2 input pipeline (ship-readiness #1B).
//
// The debounce must be lossless: an in-flight edit that never reaches the
// 250ms idle window must still land when the user navigates away or the
// row is disposed (background/kill path). Without these two tests the
// behaviour change must not ship.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gymlog/features/workout/domain/active_workout_state.dart';
import 'package:gymlog/features/workout/presentation/widgets/set_row.dart';

void main() {
  testWidgets(
    'dispose mid-debounce flushes the in-flight weight (navigate-away gate)',
    (tester) async {
      WorkoutSetState? committed;
      var showRow = true;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: showRow
                    ? SetRow(
                        key: const ValueKey('s1'),
                        setIndex: 0,
                        setData: const WorkoutSetState(id: 's1'),
                        onChanged: (next) => committed = next,
                        onToggleComplete: () {},
                      )
                    : const SizedBox.shrink(),
                floatingActionButton: FloatingActionButton(
                  onPressed: () => setState(() => showRow = false),
                  child: const Icon(Icons.close),
                ),
              );
            },
          ),
        ),
      );

      final weightField = find.byType(TextField).first;
      await tester.tap(weightField);
      await tester.pump();
      await tester.enterText(weightField, '87.5');
      // Do NOT pump 250ms — leave the debounce window open.
      await tester.pump(const Duration(milliseconds: 50));

      // Navigate away / dispose the row mid-debounce.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();

      expect(committed, isNotNull);
      expect(committed!.weightKg, 87.5);
    },
  );

  testWidgets(
    'unfocus mid-debounce flushes the in-flight reps (background-path gate)',
    (tester) async {
      WorkoutSetState? committed;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SetRow(
                  key: const ValueKey('s1'),
                  setIndex: 0,
                  setData: const WorkoutSetState(id: 's1'),
                  onChanged: (next) => committed = next,
                  onToggleComplete: () {},
                ),
                // Sibling that can steal focus without disposing the row —
                // models the app-background / focus-loss flush path.
                TextField(
                  key: const ValueKey('other'),
                  decoration: const InputDecoration(hintText: 'other'),
                ),
              ],
            ),
          ),
        ),
      );

      // Reps is the second TextField inside SetRow.
      final repsField = find.byType(TextField).at(1);
      await tester.tap(repsField);
      await tester.pump();
      await tester.enterText(repsField, '12');
      await tester.pump(const Duration(milliseconds: 50));

      // Focus leaves the set row without waiting out the debounce.
      await tester.tap(find.byKey(const ValueKey('other')));
      await tester.pump();

      expect(committed, isNotNull);
      expect(committed!.reps, 12);
    },
  );

  testWidgets(
    'idle debounce still commits after 250ms without flush points',
    (tester) async {
      WorkoutSetState? committed;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SetRow(
              key: const ValueKey('s1'),
              setIndex: 0,
              setData: const WorkoutSetState(id: 's1'),
              onChanged: (next) => committed = next,
              onToggleComplete: () {},
            ),
          ),
        ),
      );

      final weightField = find.byType(TextField).first;
      await tester.tap(weightField);
      await tester.pump();
      await tester.enterText(weightField, '60');
      expect(committed, isNull);

      await tester.pump(const Duration(milliseconds: 260));
      expect(committed, isNotNull);
      expect(committed!.weightKg, 60);
    },
  );
}
