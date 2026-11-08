import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/core/widgets/top_app_bar.dart';
import 'package:thermoscan/features/auth/domain/auth_user.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/module_thermal_inspection_screen.dart';
import 'package:thermoscan/features/modules/presentation/modules_controller.dart';
import 'package:thermoscan/features/modules/presentation/widgets/radiometric_scan_card.dart';

class _FakeAuthController extends StateNotifier<AuthState>
    implements AuthController {
  _FakeAuthController(AuthUser user) : super(AuthState.authenticated(user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const testModuleId = 'mod-test-123';

  const dummyModule = PvModule(
    id: testModuleId,
    companyId: 'comp-1',
    installerTechnicianId: 'tech-1',
    installerName: 'Carlos Tech',
    installerEmail: 'carlos@thermoscan.com',
    name: 'PV Array Alpha Unit',
    macAddress: 'AA:BB:CC:DD:EE:FF',
    isActive: true,
    monitoringStatus: 'normal',
    panelCount: 3,
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

  const dummyInspection = LatestInspection(
    inspection: ModuleInspection(
      id: 'insp-1',
      moduleId: testModuleId,
      sourceEventId: 'evt-1',
      type: 'routine',
      scheduledFor: '2026-03-01T10:00:00Z',
      status: 'completed',
      createdAt: '2026-03-01T10:00:00Z',
      updatedAt: '2026-03-01T10:15:00Z',
      finishedAt: '2026-03-01T10:15:00Z',
      baselineTemperatureC: 28.5,
    ),
    totalMeasurements: 2,
    confirmedAnomalies: [
      ConfirmedAnomaly(
        id: 'anom-1',
        moduleId: testModuleId,
        originMeasurementId: 'meas-1',
        confirmingMeasurementIds: ['meas-1'],
        sourceEventId: 'evt-1',
        panelIndex: 1,
        localXPositionCm: 45.0,
        xPositionCm: 45.0,
        detectedAt: '2026-03-01T10:05:00Z',
        status: 'open',
        actuatedAttemptsCount: 0,
        retryPending: false,
      ),
    ],
  );

  const dummyMeasurements = [
    ModuleMeasurement(
      id: 'meas-1',
      moduleId: testModuleId,
      inspectionId: 'insp-1',
      sourceEventId: 'evt-1',
      panelIndex: 1,
      localXPositionCm: 45.0,
      xPositionCm: 45.0,
      measuredAt: '2026-03-01T10:05:00Z',
      maxTemperatureC: 48.2,
      receivedAt: '2026-03-01T10:05:01Z',
    ),
  ];

  const techUser = AuthUser(
    id: 'u-1',
    name: 'Carlos Tech',
    email: 'tech@thermoscan.com',
    role: 'technician',
    isActive: true,
    mustChangePassword: false,
  );

  testWidgets('Renders Thermal Inspection Studio with RadiometricScanCard and AppBar', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
            (ref) => Future.value(dummyMeasurements),
          ),
          latestInspectionProvider(testModuleId).overrideWith(
            (ref) => Future.value(dummyInspection),
          ),
        ],
        child: const MaterialApp(
          home: ModuleThermalInspectionScreen(moduleId: testModuleId),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify AppBar
    expect(find.byType(ThermoScanAppBar), findsOneWidget);
    expect(find.text('Thermal Inspection Studio'), findsOneWidget);

    // Verify Module Identity Header
    expect(find.text('PV Array Alpha Unit'), findsOneWidget);
    expect(find.textContaining('AA:BB:CC:DD:EE:FF'), findsOneWidget);

    // Verify Badges
    expect(find.text('Operational'), findsOneWidget);
    expect(find.text('1 anomaly(s)'), findsOneWidget);

    // Verify RadiometricScanCard is present
    expect(find.byType(RadiometricScanCard), findsOneWidget);

    // Verify Guide Card
    expect(find.text('Radiometric Studio Inspection Guide'), findsOneWidget);
  });
}
