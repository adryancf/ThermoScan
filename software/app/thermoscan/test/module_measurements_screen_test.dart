import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/features/auth/domain/auth_user.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/module_measurements_screen.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';

class _FakeAuthController extends StateNotifier<AuthState>
    implements AuthController {
  _FakeAuthController(AuthUser user) : super(AuthState.authenticated(user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const testModuleId = 'mod-hist-test';

  const dummyModule = PvModule(
    id: testModuleId,
    companyId: 'comp-1',
    installerTechnicianId: 'tech-1',
    installerName: 'Carlos Tech',
    installerEmail: 'carlos@thermoscan.com',
    name: 'PV Array Historic',
    macAddress: 'AA:BB:CC:DD:EE:11',
    isActive: true,
    monitoringStatus: 'normal',
    panelCount: 2,
    panelLengthCm: 100.0,
    inspectionIntervalDays: 7,
    createdAt: '2026-01-01T10:00:00Z',
    updatedAt: '2026-01-01T10:00:00Z',
    userRelationship: 'technician',
    permissions: ModulePermissions(
      canEditGeometryAndLocation: true,
      canEditSolarAngle: true,
      canEditInterval: true,
      canManageAccess: true,
    ),
  );

  const dummyDetails = ModuleDetails(
    module: dummyModule,
    responsibleManagers: [],
    companyManagers: [],
    companyTechnicians: [],
    companyClients: [],
  );

  const techUser = AuthUser(
    id: 'u-1',
    name: 'Carlos Tech',
    email: 'tech@thermoscan.com',
    role: 'technician',
    isActive: true,
    mustChangePassword: false,
  );

  group('ModuleInspection Domain Tests', () {
    test('ModuleInspection deserializes confirmed_anomalies correctly', () {
      final json = {
        'id': 'insp-test',
        'module_id': 'mod-1',
        'source_event_id': 'evt-1',
        'type': 'scheduled',
        'scheduled_for': '2026-11-01T10:00:00Z',
        'status': 'completed',
        'baseline_temperature_c': 32.5,
        'created_at': '2026-11-01T10:00:00Z',
        'updated_at': '2026-11-01T10:15:00Z',
        'confirmed_anomalies': [
          {
            'id': 'anom-99',
            'module_id': 'mod-1',
            'origin_measurement_id': 'meas-10',
            'confirming_measurement_ids': ['meas-10', 'meas-11'],
            'source_event_id': 'evt-1',
            'panel_index': 1,
            'local_x_position_cm': 50.0,
            'x_position_cm': 50.0,
            'detected_at': '2026-11-01T10:05:00Z',
            'status': 'open',
            'actuated_attempts_count': 1,
            'retry_pending': false,
          }
        ],
      };

      final inspection = ModuleInspection.fromJson(json);
      expect(inspection.id, 'insp-test');
      expect(inspection.baselineTemperatureC, 32.5);
      expect(inspection.confirmedAnomalies.length, 1);
      expect(inspection.confirmedAnomalies.first.id, 'anom-99');
      expect(inspection.confirmedAnomalies.first.panelIndex, 1);
      expect(inspection.confirmedAnomalies.first.xPositionCm, 50.0);

      final copied = inspection.copyWith(status: 'failed');
      expect(copied.status, 'failed');
      expect(copied.confirmedAnomalies.length, 1);
    });

    test('ModuleInspection falls back to empty list when confirmed_anomalies is absent', () {
      final json = {
        'id': 'insp-test-2',
        'module_id': 'mod-1',
        'source_event_id': 'evt-1',
        'type': 'routine',
        'scheduled_for': '2026-11-01T10:00:00Z',
        'status': 'completed',
        'created_at': '2026-11-01T10:00:00Z',
        'updated_at': '2026-11-01T10:15:00Z',
      };

      final inspection = ModuleInspection.fromJson(json);
      expect(inspection.confirmedAnomalies, isEmpty);
    });
  });

  group('ModuleMeasurementsScreen Historical Scans & Hotspot Badges', () {
    testWidgets('Renders historical inspection with baseline, confirmed hotspot count and HOTSPOT (CONFIRMED) badge', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const historicalAnomaly = ConfirmedAnomaly(
        id: 'anom-hist-1',
        moduleId: testModuleId,
        originMeasurementId: 'meas-hist-1',
        confirmingMeasurementIds: ['meas-hist-1'],
        sourceEventId: 'evt-hist',
        panelIndex: 1,
        localXPositionCm: 30.0,
        xPositionCm: 30.0,
        detectedAt: '2026-02-15T09:05:00Z',
        status: 'open',
        actuatedAttemptsCount: 0,
        retryPending: false,
      );

      const historicalInspection = ModuleInspection(
        id: 'insp-hist-12345678',
        moduleId: testModuleId,
        sourceEventId: 'evt-hist',
        type: 'scheduled',
        scheduledFor: '2026-02-15T09:00:00Z',
        status: 'completed',
        createdAt: '2026-02-15T09:00:00Z',
        updatedAt: '2026-02-15T09:15:00Z',
        finishedAt: '2026-02-15T09:15:00Z',
        baselineTemperatureC: 27.0,
        confirmedAnomalies: [historicalAnomaly],
      );

      const historicalMeasurement = ModuleMeasurement(
        id: 'meas-hist-1',
        moduleId: testModuleId,
        inspectionId: 'insp-hist-12345678',
        sourceEventId: 'evt-hist',
        panelIndex: 1,
        localXPositionCm: 30.0,
        xPositionCm: 30.0,
        measuredAt: '2026-02-15T09:05:00Z',
        maxTemperatureC: 45.0,
        receivedAt: '2026-02-15T09:05:01Z',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              (ref) => _FakeAuthController(techUser),
            ),
            moduleDetailsProvider(testModuleId).overrideWith(
              (ref) => Future.value(dummyDetails),
            ),
            moduleMeasurementsProvider(testModuleId).overrideWith(
              (ref) => Future.value([historicalMeasurement]),
            ),
            latestInspectionProvider(testModuleId).overrideWith(
              (ref) => Future.value(null),
            ),
            moduleInspectionsProvider(testModuleId).overrideWith(
              (ref) => Future.value([historicalInspection]),
            ),
          ],
          child: const MaterialApp(
            home: ModuleMeasurementsScreen(moduleId: testModuleId),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Card of historical inspection is rendered
      expect(find.byKey(const Key('history_group_insp-hist-12345678')), findsOneWidget);

      // Baseline temp is rendered
      expect(find.textContaining('Baseline: 27.0°C'), findsWidgets);

      // Health badge displays 1 Hotspot
      expect(find.text('1 Hotspot'), findsOneWidget);

      // Panel 1 accordion shows 1 HOTSPOT
      expect(find.text('1 HOTSPOT'), findsOneWidget);

      // Inside step tile, HOTSPOT (CONFIRMED) badge is rendered
      expect(find.text('HOTSPOT (CONFIRMED)'), findsOneWidget);
    });
  });
}
