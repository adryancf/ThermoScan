import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/features/modules/domain/inspection_routine_bundle.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';

void main() {
  ConfirmedAnomaly anomaly(String id, String status, String closedAt) =>
      ConfirmedAnomaly(
        id: id,
        moduleId: 'm1',
        originMeasurementId: 'meas-$id',
        confirmingMeasurementIds: ['meas-$id'],
        sourceEventId: 'evt-$id',
        panelIndex: 1,
        localXPositionCm: 10.0,
        xPositionCm: 10.0,
        detectedAt: '2026-11-24T14:54:30Z',
        status: status,
        actuatedAttemptsCount: 1,
        retryPending: false,
        closedAt: closedAt,
      );

  ModuleInspection routine(
    String id,
    String start,
    String end,
    List<ConfirmedAnomaly> anomalies,
  ) =>
      ModuleInspection(
        id: id,
        moduleId: 'm1',
        sourceEventId: 'evt-$id',
        type: 'scheduled',
        scheduledFor: start,
        startedAt: start,
        finishedAt: end,
        status: 'completed',
        createdAt: start,
        updatedAt: end,
        confirmedAnomalies: anomalies,
      );

  ModuleInspection verification(String id, String cleaningId, String at) =>
      ModuleInspection(
        id: id,
        moduleId: 'm1',
        sourceEventId: 'evt-$id',
        type: 'verification',
        cleaningOperationId: cleaningId,
        scheduledFor: at,
        startedAt: at,
        finishedAt: at,
        status: 'completed',
        verificationResult: 'resolved',
        createdAt: at,
        updatedAt: at,
      );

  ModuleCleaning cleaning(String id, String anomalyId) => ModuleCleaning(
        id: id,
        moduleId: 'm1',
        anomalyEventId: anomalyId,
        sourceEventId: 'evt-$id',
        panelIndex: 1,
        localXPositionCm: 10.0,
        targetXPositionCm: 10.0,
        pumpActuated: true,
        attemptNumber: 1,
        endedAt: '2026-11-24T14:55:00Z',
        status: 'completed',
        postCleaningResult: 'resolved',
        createdAt: '2026-11-24T14:55:00Z',
      );

  ModuleMeasurement frame(String id, String inspectionId, double x) =>
      ModuleMeasurement(
        id: id,
        moduleId: 'm1',
        inspectionId: inspectionId,
        sourceEventId: 'evt-$id',
        panelIndex: 1,
        localXPositionCm: x,
        xPositionCm: x,
        maxTemperatureC: 35.0,
        measuredAt: '2026-11-24T14:56:00Z',
        receivedAt: '2026-11-24T14:56:00Z',
      );

  test(
    'newer routine does not steal verifications owned by an older routine '
    'scanned only minutes earlier',
    () {
      // Routine A at 14:54 (older), verification at 14:56 owned by A.
      // Routine B at 14:59 (newer, 5 min later), verification at 15:01 owned by B.
      final routineA = routine(
        'routine-a',
        '2026-11-24T14:54:25Z',
        '2026-11-24T14:54:48Z',
        [anomaly('anom-a', 'resolved_later', '2026-11-24T14:59:32Z')],
      );
      final routineB = routine(
        'routine-b',
        '2026-11-24T14:59:07Z',
        '2026-11-24T14:59:32Z',
        [anomaly('anom-b', 'resolved', '2026-11-24T15:01:30Z')],
      );
      final verifA =
          verification('verif-a', 'cln-a', '2026-11-24T14:56:30Z');
      final verifB =
          verification('verif-b', 'cln-b', '2026-11-24T15:01:30Z');

      final bundles = InspectionRoutineBundle.buildBundles(
        allInspections: [routineA, routineB, verifA, verifB],
        allCleanings: [
          cleaning('cln-a', 'anom-a'),
          cleaning('cln-b', 'anom-b'),
        ],
        allMeasurements: [
          frame('ma1', 'routine-a', 10.0),
          frame('mb1', 'routine-b', 10.0),
          frame('va1', 'verif-a', 9.0),
          frame('va2', 'verif-a', 11.0),
          frame('vb1', 'verif-b', 9.0),
          frame('vb2', 'verif-b', 11.0),
        ],
      );

      final bundleA =
          bundles.firstWhere((b) => b.routineInspection.id == 'routine-a');
      final bundleB =
          bundles.firstWhere((b) => b.routineInspection.id == 'routine-b');

      expect(
        bundleA.verificationInspections.map((v) => v.id).toList(),
        ['verif-a'],
      );
      expect(bundleA.hasPostCleaning, isTrue);
      expect(
        bundleB.verificationInspections.map((v) => v.id).toList(),
        ['verif-b'],
      );
      expect(bundleB.hasPostCleaning, isTrue);
    },
  );
}
