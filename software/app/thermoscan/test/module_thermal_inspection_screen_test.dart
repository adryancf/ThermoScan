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
    expect(find.text('1 hotspot(s)'), findsOneWidget);

    // Verify RadiometricScanCard is present
    expect(find.byType(RadiometricScanCard), findsOneWidget);

    // Item 4: Verify LATEST SCAN badge and Switch Scan button
    expect(find.byKey(const Key('latest_scan_badge')), findsOneWidget);
    expect(find.text('LATEST SCAN'), findsOneWidget);
    expect(find.byKey(const Key('switch_scan_button')), findsOneWidget);

    // Item 1: Verify Robot Carriage Timeline Scrubber is rendered
    expect(find.byKey(const Key('robot_timeline_scrubber')), findsOneWidget);
    expect(find.byKey(const Key('robot_timeline_icon')), findsOneWidget);
    expect(find.byKey(const Key('robot_timeline_play_button')), findsOneWidget);
    expect(find.byKey(const Key('inspect_frame_modal_button')), findsOneWidget);

    // Item 3: Verify 1D Thermal Profile Curve is collapsed by default and expands on tap
    expect(find.byKey(const Key('thermal_profile_curve_toggle')), findsOneWidget);
    expect(find.byKey(const Key('thermal_profile_curve_card')), findsNothing);
    await tester.tap(find.byKey(const Key('thermal_profile_curve_toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('thermal_profile_curve_card')), findsOneWidget);

    // Item 2: Verify 32x24 Matrix Inspector opens in Modal Bottom Sheet with pixel telemetry
    await tester.tap(find.byKey(const Key('inspect_frame_modal_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected_frame_inspector')), findsOneWidget);
    expect(find.byKey(const Key('single_frame_matrix_canvas')), findsOneWidget);
    expect(find.byKey(const Key('selected_pixel_telemetry')), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected_frame_inspector')), findsNothing);

    // Item 5: Verify '?' Help button in AppBar opens How to Read This Thermal Map modal
    expect(find.text('How to Read This Thermal Map'), findsNothing);
    expect(find.byKey(const Key('studio_help_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('studio_help_button')));
    await tester.pumpAndSettle();
    expect(find.text('How to Read This Thermal Map'), findsOneWidget);
  });

  testWidgets('Switches between Latest Scan and Historical Scan with clear indicators', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const olderInspection = ModuleInspection(
      id: 'insp-older-0',
      moduleId: testModuleId,
      sourceEventId: 'evt-0',
      type: 'post_cleaning',
      scheduledFor: '2026-02-20T09:00:00Z',
      status: 'completed',
      createdAt: '2026-02-20T09:00:00Z',
      updatedAt: '2026-02-20T09:10:00Z',
      finishedAt: '2026-02-20T09:10:00Z',
      baselineTemperatureC: 26.0,
      confirmedAnomalies: [
        ConfirmedAnomaly(
          id: 'anom-older-1',
          moduleId: testModuleId,
          originMeasurementId: 'meas-older-1',
          confirmingMeasurementIds: ['meas-older-1'],
          sourceEventId: 'evt-0',
          panelIndex: 1,
          localXPositionCm: 20.0,
          xPositionCm: 20.0,
          detectedAt: '2026-02-20T09:05:00Z',
          status: 'open',
          actuatedAttemptsCount: 0,
          retryPending: false,
        ),
      ],
    );

    const olderMeasurements = PagedMeasurements(
      page: 1,
      limit: 200,
      totalCount: 1,
      totalPages: 1,
      hasNextPage: false,
      measurements: [
        ModuleMeasurement(
          id: 'meas-older-1',
          moduleId: testModuleId,
          inspectionId: 'insp-older-0',
          sourceEventId: 'evt-0',
          panelIndex: 1,
          localXPositionCm: 20.0,
          xPositionCm: 20.0,
          measuredAt: '2026-02-20T09:05:00Z',
          maxTemperatureC: 31.0,
          receivedAt: '2026-02-20T09:05:01Z',
        ),
      ],
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
            (ref) => Future.value(dummyMeasurements),
          ),
          latestInspectionProvider(testModuleId).overrideWith(
            (ref) => Future.value(dummyInspection),
          ),
          moduleInspectionsProvider(testModuleId).overrideWith(
            (ref) => Future.value([dummyInspection.inspection, olderInspection]),
          ),
          inspectionMeasurementsPagedProvider((
            moduleId: testModuleId,
            inspectionId: 'insp-older-0',
            page: 1,
            limit: 200,
            panelIndex: null,
          )).overrideWith(
            (ref) => Future.value(olderMeasurements),
          ),
        ],
        child: const MaterialApp(
          home: ModuleThermalInspectionScreen(moduleId: testModuleId),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('latest_scan_badge')), findsOneWidget);
    expect(find.byKey(const Key('historical_scan_banner')), findsNothing);

    // Open Switch Scan modal
    await tester.tap(find.byKey(const Key('switch_scan_button')));
    await tester.pumpAndSettle();

    expect(find.text('LATEST'), findsOneWidget);
    expect(find.text('Post-Cleaning Verification'), findsOneWidget);

    // Select the older scan
    await tester.tap(find.text('Post-Cleaning Verification'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('historical_scan_badge')), findsOneWidget);
    expect(find.byKey(const Key('historical_scan_banner')), findsOneWidget);
    expect(find.byKey(const Key('back_to_latest_scan_button')), findsOneWidget);
    expect(find.byKey(const Key('rail_hotspot_marker_1')), findsOneWidget);

    // Return to Latest Scan
    await tester.tap(find.byKey(const Key('back_to_latest_scan_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('latest_scan_badge')), findsOneWidget);
    expect(find.byKey(const Key('historical_scan_banner')), findsNothing);
  });

  testWidgets('Quick Frame Selector in Scrubber jumps to section and displays shortened buttons', (tester) async {
    const multiFrames = [
      ModuleMeasurement(
        id: 'meas-1',
        moduleId: testModuleId,
        inspectionId: 'insp-1',
        sourceEventId: 'evt-1',
        panelIndex: 1,
        localXPositionCm: 10.0,
        xPositionCm: 10.0,
        measuredAt: '2026-03-01T10:05:00Z',
        maxTemperatureC: 25.0,
        receivedAt: '2026-03-01T10:05:01Z',
      ),
      ModuleMeasurement(
        id: 'meas-2',
        moduleId: testModuleId,
        inspectionId: 'insp-1',
        sourceEventId: 'evt-1',
        panelIndex: 1,
        localXPositionCm: 20.0,
        xPositionCm: 20.0,
        measuredAt: '2026-03-01T10:06:00Z',
        maxTemperatureC: 54.0,
        receivedAt: '2026-03-01T10:06:01Z',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(
              const AuthUser(
                id: 'tech-1',
                email: 'carlos@thermoscan.com',
                name: 'Carlos Tech',
                role: 'technician',
                isActive: true,
                mustChangePassword: false,
              ),
            ),
          ),
          moduleDetailsProvider(testModuleId).overrideWith(
            (ref) => Future.value(dummyDetails),
          ),
          latestInspectionProvider(testModuleId).overrideWith(
            (ref) => Future.value(dummyInspection),
          ),
          moduleMeasurementsProvider(testModuleId).overrideWith(
            (ref) => Future.value(multiFrames),
          ),
          moduleInspectionsProvider(testModuleId).overrideWith(
            (ref) => Future.value([dummyInspection.inspection]),
          ),
        ],
        child: const MaterialApp(
          home: ModuleThermalInspectionScreen(moduleId: testModuleId),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify shortened buttons
    expect(find.byKey(const Key('inspect_frame_modal_button')), findsOneWidget);
    expect(find.text('32×24'), findsOneWidget);

    // Verify quick frame selector chip in scrubber
    expect(find.byKey(const Key('scrubber_frame_selector_chip')), findsOneWidget);
    expect(find.text('F1/2'), findsOneWidget);

    // Scroll into view and tap on scrubber frame selector chip to open bottom sheet
    await tester.ensureVisible(find.byKey(const Key('scrubber_frame_selector_chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scrubber_frame_selector_chip')));
    await tester.pumpAndSettle();

    // Bottom sheet is displayed with quick jump frame options
    expect(find.text('Jump to Section (2 frames)'), findsOneWidget);
    expect(find.text('F1'), findsOneWidget);
    expect(find.text('F2'), findsOneWidget);

    // Tap F2 chip to jump
    await tester.tap(find.text('F2'));
    await tester.pumpAndSettle();

    // Robot scrubber updated to F2/2
    expect(find.text('F2/2'), findsOneWidget);
  });
}
