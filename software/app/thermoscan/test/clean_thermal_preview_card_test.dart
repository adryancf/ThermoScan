import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/widgets/clean_thermal_preview_card.dart';

void main() {
  const sampleModule = PvModule(
    id: 'mod-clean-1',
    companyId: 'c1',
    installerTechnicianId: 'u1',
    installerName: 'Tech',
    installerEmail: 'tech@ts.com',
    name: 'Clean Preview Array',
    macAddress: 'AA:BB:CC:11:22:33',
    isActive: true,
    monitoringStatus: 'active',
    inspectionIntervalDays: 7,
    panelLengthCm: 200,
    panelWidthCm: 100,
    panelCount: 2,
    panelSpacingCm: 5.0,
    latitude: -23.5505,
    longitude: -46.6333,
    elevationM: 760,
    azimuthDeg: 0,
    tiltDeg: 22,
    minimumSolarAngleDeg: 15,
    configuredAt: '2026-11-01T08:00:00Z',
    createdAt: '2026-10-30T10:00:00Z',
    updatedAt: '2026-10-30T10:00:00Z',
    userRelationship: 'installer_technician',
    permissions: ModulePermissions(
      canEditGeometryAndLocation: true,
      canEditSolarAngle: true,
      canEditInterval: true,
      canManageAccess: true,
    ),
  );

  testWidgets('CleanThermalPreviewCard renders healthy state cleanly', (tester) async {
    const measurement = ModuleMeasurement(
      id: 'm1',
      moduleId: 'mod-clean-1',
      inspectionId: 'insp-1',
      sourceEventId: 'evt-1',
      panelIndex: 1,
      localXPositionCm: 50.0,
      xPositionCm: 50.0,
      measuredAt: '2026-11-07T14:07:00Z',
      maxTemperatureC: 38.5,
      receivedAt: '2026-11-07T14:07:05Z',
    );

    const inspection = LatestInspection(
      inspection: ModuleInspection(
        id: 'insp-1',
        moduleId: 'mod-clean-1',
        sourceEventId: 'evt-1',
        type: 'scheduled',
        scheduledFor: '2026-11-07T14:00:00Z',
        baselineTemperatureC: 35.0,
        status: 'completed',
        createdAt: '2026-11-07T14:07:00Z',
        updatedAt: '2026-11-07T14:30:00Z',
      ),
      totalMeasurements: 1,
      confirmedAnomalies: [],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CleanThermalPreviewCard(
            module: sampleModule,
            latestMeasurement: measurement,
            latestInspection: inspection,
            measurements: [measurement],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Title & Header
    expect(find.text('Thermal Inspection Map'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.textContaining('Reading from:'), findsOneWidget);

    // Verify Semantic Thermal Scale
    expect(find.textContaining('Min'), findsOneWidget);
    expect(find.textContaining('Baseline (35.0°C)'), findsOneWidget);
    expect(find.textContaining('Max (38.5°C)'), findsOneWidget);

    // Verify Studio CTA button
    expect(
      find.text('Open Full Thermal Inspection Studio →'),
      findsOneWidget,
    );
  });

  testWidgets('CleanThermalPreviewCard renders hotspot badge and friendly pin marker', (tester) async {
    const measurement = ModuleMeasurement(
      id: 'm-hotspot',
      moduleId: 'mod-clean-1',
      inspectionId: 'insp-hot',
      sourceEventId: 'evt-2',
      panelIndex: 2,
      localXPositionCm: 25.0,
      xPositionCm: 230.0,
      measuredAt: '2026-11-07T14:07:00Z',
      maxTemperatureC: 52.4,
      receivedAt: '2026-11-07T14:07:05Z',
    );

    const inspection = LatestInspection(
      inspection: ModuleInspection(
        id: 'insp-hot',
        moduleId: 'mod-clean-1',
        sourceEventId: 'evt-2',
        type: 'scheduled',
        scheduledFor: '2026-11-07T14:00:00Z',
        baselineTemperatureC: 35.0,
        status: 'completed',
        createdAt: '2026-11-07T14:07:00Z',
        updatedAt: '2026-11-07T14:30:00Z',
      ),
      totalMeasurements: 1,
      confirmedAnomalies: [
        ConfirmedAnomaly(
          id: 'anom-clean-1',
          moduleId: 'mod-clean-1',
          originMeasurementId: 'm-hotspot',
          confirmingMeasurementIds: ['m-hotspot'],
          sourceEventId: 'evt-2',
          panelIndex: 2,
          localXPositionCm: 25.0,
          xPositionCm: 230.0,
          detectedAt: '2026-11-07T14:07:00Z',
          status: 'open',
          actuatedAttemptsCount: 0,
          retryPending: false,
        ),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CleanThermalPreviewCard(
            module: sampleModule,
            latestMeasurement: measurement,
            latestInspection: inspection,
            measurements: [measurement],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Hotspot Header Badge with Delta (+17.4°C ΔT)
    expect(find.text('Hotspot +17.4°C ΔT'), findsOneWidget);

    // Verify Friendly Pin marker
    expect(find.text('Hotspot'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);

    // Verify Panel labels exist
    expect(find.text('Panel 1'), findsOneWidget);
    expect(find.text('Panel 2'), findsOneWidget);

    // Verify Semantic Thermal Scale shows Max (52.4°C)
    expect(find.textContaining('Max (52.4°C)'), findsOneWidget);
  });

  testWidgets('CleanThermalPreviewCard CTA button triggers navigation', (tester) async {
    String? navigatedRoute;

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: CleanThermalPreviewCard(
              module: sampleModule,
            ),
          ),
        ),
        GoRoute(
          path: '/modules/:moduleId/thermal-inspection',
          builder: (context, state) {
            navigatedRoute = state.matchedLocation;
            return const Scaffold(body: Text('Studio Page'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
      ),
    );

    await tester.pumpAndSettle();

    // Tap CTA button
    await tester.tap(find.text('Open Full Thermal Inspection Studio →'));
    await tester.pumpAndSettle();

    expect(navigatedRoute, '/modules/mod-clean-1/thermal-inspection');
    expect(find.text('Studio Page'), findsOneWidget);
  });
}
