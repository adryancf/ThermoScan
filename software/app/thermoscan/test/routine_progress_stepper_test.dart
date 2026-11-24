import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
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

  testWidgets('RoutineProgressStepper shows live cooldown countdown',
      (tester) async {
    final target =
        DateTime.now().toUtc().add(const Duration(minutes: 24, seconds: 20));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoutineProgressStepper(
            firmwareState: 'WAITING_VERIFICATION',
            firmwareStateDetail: 'cooldown_wait',
            verificationReadyAt: target.toIso8601String(),
          ),
        ),
      ),
    );

    expect(find.textContaining('Step 4/4 • Cooling down • 24m '), findsOneWidget);
    expect(find.textContaining(' remaining'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Step 4/4 • Cooling down • 24m '), findsOneWidget);

    // Expired timestamp shows completion message
    final past = DateTime.now().toUtc().subtract(const Duration(seconds: 10));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoutineProgressStepper(
            firmwareState: 'WAITING_VERIFICATION',
            firmwareStateDetail: 'cooldown_wait',
            verificationReadyAt: past.toIso8601String(),
          ),
        ),
      ),
    );
    expect(
      find.text('Step 4/4 • Cooldown complete, preparing check...'),
      findsOneWidget,
    );

    // Invalid timestamp falls back to generic cooldown message
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoutineProgressStepper(
            firmwareState: 'WAITING_VERIFICATION',
            firmwareStateDetail: 'cooldown_wait',
            verificationReadyAt: 'not-a-timestamp',
          ),
        ),
      ),
    );
    expect(
      find.text('Step 4/4 • Cooling down before final check...'),
      findsOneWidget,
    );

    // Non-cooldown waiting reasons keep their specific messages
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoutineProgressStepper(
            firmwareState: 'WAITING_VERIFICATION',
            firmwareStateDetail: 'solar_window_closed',
            verificationReadyAt: target.toIso8601String(),
          ),
        ),
      ),
    );
    expect(
      find.text('Step 4/4 • Waiting for valid solar window to verify...'),
      findsOneWidget,
    );
  });

  test('DeviceStatus parses verification_ready_at and verificationReadyAt', () {
    final snake = DeviceStatus.fromJson({
      'module_id': 'm1',
      'mac_address': 'AA:BB:CC:DD:EE:FF',
      'monitoring_status': 'active',
      'is_configured': true,
      'water_status': 'ok',
      'limits_check_passed': true,
      'thermal_sensor_active': true,
      'verification_ready_at': '2026-11-24T12:30:00Z',
    });
    expect(snake.verificationReadyAt, '2026-11-24T12:30:00Z');
    expect(snake.toJson()['verification_ready_at'], '2026-11-24T12:30:00Z');

    final camel = DeviceStatus.fromJson({
      'module_id': 'm1',
      'mac_address': 'AA:BB:CC:DD:EE:FF',
      'monitoring_status': 'active',
      'is_configured': true,
      'water_status': 'ok',
      'limits_check_passed': true,
      'thermal_sensor_active': true,
      'verificationReadyAt': '2026-11-24T12:45:00Z',
    });
    expect(camel.verificationReadyAt, '2026-11-24T12:45:00Z');
  });
}
