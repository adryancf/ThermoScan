import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/features/modules/presentation/widgets/routine_progress_stepper.dart';

void main() {
  testWidgets('RoutineProgressStepper hides completely in IDLE', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoutineProgressStepper(firmwareState: 'IDLE'),
        ),
      ),
    );
    expect(find.text('Scan'), findsNothing);
    expect(find.text('Final Check'), findsNothing);
  });

  testWidgets('RoutineProgressStepper renders active and error states',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoutineProgressStepper(firmwareState: 'SCANNING'),
        ),
      ),
    );
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Analysis'), findsOneWidget);
    expect(find.text('Cleaning'), findsOneWidget);
    expect(find.text('Final Check'), findsOneWidget);
    expect(
      find.text('Step 1/4 • Scanning thermal profile across panels...'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoutineProgressStepper(
            firmwareState: 'WAITING_VERIFICATION',
            firmwareStateDetail: 'cooldown_wait',
          ),
        ),
      ),
    );
    expect(
      find.text('Step 4/4 • Cooling down before final check...'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoutineProgressStepper(
            firmwareState: 'ERROR_HALT',
            firmwareStateDetail: 'homing_failed',
          ),
        ),
      ),
    );
    expect(
      find.text(
        'Robot halted (homing_failed) — use Abort & Reset Routine to recover.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoutineProgressStepper(
            firmwareState: 'IDLE',
            resetPending: true,
          ),
        ),
      ),
    );
    expect(
      find.text('Reset requested — waiting for robot acknowledgement...'),
      findsOneWidget,
    );
  });
}
