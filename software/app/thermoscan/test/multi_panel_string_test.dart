import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/core/storage/token_storage.dart';
import 'package:thermoscan/features/auth/data/auth_repository.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/auth/domain/auth_user.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/widgets/radiometric_scan_card.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';
import 'package:thermoscan/features/modules/presentation/module_measurements_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_cleanings_screen.dart';

class _FakeAuthController extends StateNotifier<AuthState>
    implements AuthController {
  _FakeAuthController(AuthUser user) : super(AuthState.authenticated(user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockAuthRepo extends AuthRepository {
  _MockAuthRepo() : super(dio: Dio());
  @override
  Future<AuthUser> getMe() async => const AuthUser(
        id: 'u1',
        companyId: 'c1',
        name: 'Tech 1',
        email: 'tech@thermoscan.com',
        role: 'technician',
        isActive: true,
        mustChangePassword: false,
      );
}

class _MockModuleRepo extends ModuleRepository {
  _MockModuleRepo({
    required this.details,
    this.mockLatestInspection,
    this.mockAllMeasurements = const [],
    this.mockCleanings = const [],
  }) : status = const DeviceStatus(
          moduleId: 'mod-multi',
          macAddress: 'AA:BB:CC:DD:EE:02',
          monitoringStatus: 'active',
          isConfigured: true,
          isOnline: true,
          waterAvailable: true,
          waterStatus: 'ok',
          limitsCheckPassed: true,
          thermalSensorActive: true,
        ),
        super(dio: Dio());

  final ModuleDetails details;
  final DeviceStatus status;
  LatestInspection? mockLatestInspection;
  List<ModuleMeasurement> mockAllMeasurements;
  List<ModuleCleaning> mockCleanings;

  @override
  Future<ModuleDetails> getModuleDetails(String moduleId) async => details;

  @override
  Future<DeviceStatus> getDeviceStatus({required String moduleId}) async =>
      status;

  @override
  Future<LatestInspection?> getLatestInspection({required String moduleId}) async =>
      mockLatestInspection;

  @override
  Future<List<ModuleMeasurement>> listMeasurements({
    required String moduleId,
    int limit = 50,
    int offset = 0,
    int? panelIndex,
  }) async =>
      mockAllMeasurements;

  @override
  Future<PagedMeasurements> listInspectionMeasurements({
    required String moduleId,
    required String inspectionId,
    int page = 1,
    int limit = 10,
    int? panelIndex,
  }) async {
    return PagedMeasurements(
      page: 1,
      limit: 10,
      totalCount: mockAllMeasurements.length,
      totalPages: 1,
      hasNextPage: false,
      measurements: mockAllMeasurements,
    );
  }

  @override
  Future<List<ModuleCleaning>> listCleanings({
    required String moduleId,
    int limit = 50,
    int offset = 0,
  }) async =>
      mockCleanings;
}

void main() {
  const testUser = AuthUser(
    id: 'u1',
    companyId: 'c1',
    name: 'Tech 1',
    email: 'tech@thermoscan.com',
    role: 'technician',
    isActive: true,
    mustChangePassword: false,
  );

  const testModule = PvModule(
    id: 'mod-multi',
    companyId: 'c1',
    installerTechnicianId: 'u1',
    installerName: 'Tech 1',
    installerEmail: 'tech@thermoscan.com',
    name: 'String Telhado Bloco A',
    macAddress: 'AA:BB:CC:DD:EE:02',
    isActive: true,
    monitoringStatus: 'active',
    panelLengthCm: 68.0,
    panelCount: 3,
    panelSpacingCm: 2.0,
    totalLengthCm: 208.0,
    inspectionIntervalDays: 7,
    createdAt: '2026-11-05T10:00:00Z',
    updatedAt: '2026-11-05T10:00:00Z',
    userRelationship: 'installer_technician',
    permissions: ModulePermissions(
      canEditGeometryAndLocation: true,
      canEditSolarAngle: true,
      canEditInterval: true,
      canManageAccess: true,
    ),
  );

  const testDetails = ModuleDetails(
    module: testModule,
    responsibleManagers: [],
    companyManagers: [],
    companyTechnicians: [],
    companyClients: [],
  );

  group('Multi-Panel Geometry and Coverage Unit Tests', () {
    test('ThermalCoverageInfo computes multi-panel string acquisitions and coverage', () {
      final stringCoverage = ThermalCoverageInfo(
        panelLengthCm: 68.0,
        panelCount: 3,
        panelSpacingCm: 2.0,
        loadedMeasurementsCount: 105,
      );

      // Per panel: ceil(68.0 / 2.0) + 1 = 35. Total string: 3 * 35 = 105.
      expect(stringCoverage.expectedAcquisitions, 105);
      // Rail: (3 * 68) + (2 * 2) = 208 cm. Coverage span: 208 + 5 = 213 cm.
      expect(stringCoverage.expectedThermalCoverageCm, 213.0);

      // Focused on panel 2:
      final panelCoverage = ThermalCoverageInfo(
        panelLengthCm: 68.0,
        panelCount: 3,
        panelSpacingCm: 2.0,
        focusedPanelIndex: 2,
        loadedMeasurementsCount: 35,
      );
      expect(panelCoverage.expectedAcquisitions, 35);
      expect(panelCoverage.expectedThermalCoverageCm, 73.0);
    });

    test('ThermalPanoramaData builds panel bounds, gap intervals, and respects focusedPanelIndex', () {
      final panorama = ThermalPanoramaData.fromMeasurements(
        measurements: const [],
        panelLengthCm: 68.0,
        panelCount: 3,
        panelSpacingCm: 2.0,
      );

      expect(panorama.panelBounds.length, 3);
      expect(panorama.gapIntervals.length, 2);

      // Panel 1: [0..68]
      expect(panorama.panelBounds[0].startXCm, 0.0);
      expect(panorama.panelBounds[0].endXCm, 68.0);
      // Gap 1: [68..70]
      expect(panorama.gapIntervals[0].startXCm, 68.0);
      expect(panorama.gapIntervals[0].endXCm, 70.0);
      // Panel 2: [70..138]
      expect(panorama.panelBounds[1].startXCm, 70.0);
      expect(panorama.panelBounds[1].endXCm, 138.0);
      // Gap 2: [138..140]
      expect(panorama.gapIntervals[1].startXCm, 138.0);
      expect(panorama.gapIntervals[1].endXCm, 140.0);
      // Panel 3: [140..208]
      expect(panorama.panelBounds[2].startXCm, 140.0);
      expect(panorama.panelBounds[2].endXCm, 208.0);

      // Focused on Panel 2:
      final focusedPanorama = ThermalPanoramaData.fromMeasurements(
        measurements: const [],
        panelLengthCm: 68.0,
        panelCount: 3,
        panelSpacingCm: 2.0,
        focusedPanelIndex: 2,
      );
      expect(focusedPanorama.minDomainX, 70.0 - ThermalCoverageInfo.halfFovCm);
      expect(focusedPanorama.maxDomainX, 138.0 + ThermalCoverageInfo.halfFovCm);
    });
  });

  group('RadiometricScanCard Multi-Panel Widget Tests', () {
    testWidgets('Renders panel selector chips and zooms to selected panel', (tester) async {
      final dummyMeasurements = <ModuleMeasurement>[
        const ModuleMeasurement(
          id: 'm1',
          moduleId: 'mod-multi',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-1',
          xPositionCm: 10.0,
          maxTemperatureC: 32.0,
          panelIndex: 1,
          localXPositionCm: 10.0,
          measuredAt: '2026-11-05T10:00:00Z',
          receivedAt: '2026-11-05T10:00:00Z',
        ),
        const ModuleMeasurement(
          id: 'm2',
          moduleId: 'mod-multi',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-2',
          xPositionCm: 80.0,
          maxTemperatureC: 45.0,
          panelIndex: 2,
          localXPositionCm: 10.0,
          measuredAt: '2026-11-05T10:01:00Z',
          receivedAt: '2026-11-05T10:01:00Z',
        ),
        const ModuleMeasurement(
          id: 'm3',
          moduleId: 'mod-multi',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-3',
          xPositionCm: 150.0,
          maxTemperatureC: 30.0,
          panelIndex: 3,
          localXPositionCm: 10.0,
          measuredAt: '2026-11-05T10:02:00Z',
          receivedAt: '2026-11-05T10:02:00Z',
        ),
      ];

      final dummyInspection = LatestInspection(
        inspection: const ModuleInspection(
          id: 'insp-1',
          moduleId: 'mod-multi',
          sourceEventId: 'insp-evt-1',
          type: 'scheduled',
          scheduledFor: '2026-11-05T10:00:00Z',
          baselineTemperatureC: 28.0,
          status: 'completed',
          createdAt: '2026-11-05T10:00:00Z',
          updatedAt: '2026-11-05T10:03:00Z',
        ),
        totalMeasurements: 3,
        confirmedAnomalies: const [
          ConfirmedAnomaly(
            id: 'anom-1',
            moduleId: 'mod-multi',
            sourceEventId: 'evt-2',
            xPositionCm: 80.0,
            detectedAt: '2026-11-05T10:01:00Z',
            status: 'open',
            actuatedAttemptsCount: 0,
            retryPending: false,
            panelIndex: 2,
            localXPositionCm: 10.0,
            originMeasurementId: 'm2',
            confirmingMeasurementIds: [],
          ),
        ],
        panelResults: const [
          InspectionPanelResult(
            inspectionId: 'insp-1',
            moduleId: 'mod-multi',
            panelIndex: 1,
            baselineTemperatureC: 27.5,
            truncatedByMemory: false,
            finishedAt: '2026-11-05T10:01:00Z',
            createdAt: '2026-11-05T10:01:00Z',
          ),
          InspectionPanelResult(
            inspectionId: 'insp-1',
            moduleId: 'mod-multi',
            panelIndex: 2,
            baselineTemperatureC: 28.5,
            truncatedByMemory: false,
            finishedAt: '2026-11-05T10:02:00Z',
            createdAt: '2026-11-05T10:02:00Z',
          ),
          InspectionPanelResult(
            inspectionId: 'insp-1',
            moduleId: 'mod-multi',
            panelIndex: 3,
            baselineTemperatureC: 28.0,
            truncatedByMemory: false,
            finishedAt: '2026-11-05T10:03:00Z',
            createdAt: '2026-11-05T10:03:00Z',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RadiometricScanCard(
                module: testModule,
                measurements: dummyMeasurements,
                latestInspection: dummyInspection,
                showDetailedSections: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check selector chips: String Completa, Painel 1, Painel 2, Painel 3
      expect(find.byKey(const Key('panel_chip_all')), findsOneWidget);
      expect(find.byKey(const Key('panel_chip_1')), findsOneWidget);
      expect(find.byKey(const Key('panel_chip_2')), findsOneWidget);
      expect(find.byKey(const Key('panel_chip_3')), findsOneWidget);

      // In String Completa mode, all 3 frame cards are listed
      expect(find.byKey(const Key('thermal_frame_card_1')), findsOneWidget);
      expect(find.byKey(const Key('thermal_frame_card_2')), findsOneWidget);
      expect(find.byKey(const Key('thermal_frame_card_3')), findsOneWidget);

      // Tap 'Painel 2' chip
      await tester.tap(find.byKey(const Key('panel_chip_2')));
      await tester.pumpAndSettle();

      // Now only frame card for Painel 2 is shown
      expect(find.byKey(const Key('thermal_frame_card_1')), findsOneWidget); // F1 of filtered list (m2)
      expect(find.text('F1 (X=80.0 cm)'), findsOneWidget);
      expect(find.text('F2 (X=10.0 cm)'), findsNothing);
      expect(find.text('F3 (X=150.0 cm)'), findsNothing);

      // And baseline shows Painel 2 baseline: 28.5°C
      expect(find.textContaining('28.5°C'), findsWidgets);
    });
  });

  group('ModuleMeasurementsScreen Multi-Panel Accordion Tests', () {
    testWidgets('Renders inspection history accordion grouped by panel', (tester) async {
      final dummyMeasurements = <ModuleMeasurement>[
        const ModuleMeasurement(
          id: 'm1',
          moduleId: 'mod-multi',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-1',
          xPositionCm: 10.0,
          maxTemperatureC: 30.0,
          panelIndex: 1,
          measuredAt: '2026-11-05T10:00:00Z',
          receivedAt: '2026-11-05T10:00:00Z',
        ),
        const ModuleMeasurement(
          id: 'm2',
          moduleId: 'mod-multi',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-2',
          xPositionCm: 80.0,
          maxTemperatureC: 31.0,
          panelIndex: 2,
          measuredAt: '2026-11-05T10:01:00Z',
          receivedAt: '2026-11-05T10:01:00Z',
        ),
        const ModuleMeasurement(
          id: 'm3',
          moduleId: 'mod-multi',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-3',
          xPositionCm: 150.0,
          maxTemperatureC: 29.5,
          panelIndex: 3,
          measuredAt: '2026-11-05T10:02:00Z',
          receivedAt: '2026-11-05T10:02:00Z',
        ),
      ];

      final dummyInspection = LatestInspection(
        inspection: const ModuleInspection(
          id: 'insp-1',
          moduleId: 'mod-multi',
          sourceEventId: 'insp-evt-1',
          type: 'scheduled',
          scheduledFor: '2026-11-05T10:00:00Z',
          baselineTemperatureC: 28.0,
          status: 'completed',
          createdAt: '2026-11-05T10:00:00Z',
          updatedAt: '2026-11-05T10:03:00Z',
        ),
        totalMeasurements: 3,
        confirmedAnomalies: const [],
        panelResults: const [
          InspectionPanelResult(
            inspectionId: 'insp-1',
            moduleId: 'mod-multi',
            panelIndex: 1,
            baselineTemperatureC: 28.0,
            truncatedByMemory: false,
            finishedAt: '2026-11-05T10:01:00Z',
            createdAt: '2026-11-05T10:01:00Z',
          ),
          InspectionPanelResult(
            inspectionId: 'insp-1',
            moduleId: 'mod-multi',
            panelIndex: 2,
            baselineTemperatureC: 28.2,
            truncatedByMemory: false,
            finishedAt: '2026-11-05T10:02:00Z',
            createdAt: '2026-11-05T10:02:00Z',
          ),
          InspectionPanelResult(
            inspectionId: 'insp-1',
            moduleId: 'mod-multi',
            panelIndex: 3,
            baselineTemperatureC: 27.9,
            truncatedByMemory: false,
            finishedAt: '2026-11-05T10:03:00Z',
            createdAt: '2026-11-05T10:03:00Z',
          ),
        ],
      );

      final mockRepo = _MockModuleRepo(
        details: testDetails,
        mockLatestInspection: dummyInspection,
        mockAllMeasurements: dummyMeasurements,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(testUser)),
            moduleRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: ModuleMeasurementsScreen(moduleId: 'mod-multi'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Panel Accordions are present in the Inspection History
      expect(find.byKey(const Key('panel_accordion_insp-1_1')), findsOneWidget);
      expect(find.byKey(const Key('panel_accordion_insp-1_2')), findsOneWidget);
      expect(find.byKey(const Key('panel_accordion_insp-1_3')), findsOneWidget);

      // Header shows Panel 1 with baseline
      expect(find.textContaining('Panel 1 ('), findsOneWidget);
      expect(find.textContaining('Baseline: 28.0°C'), findsWidgets);
    });
  });

  group('ModuleCleaningsScreen Multi-Panel & Gap Tests', () {
    testWidgets('Renders refused in gap status for target_in_gap cleaning', (tester) async {
      final cleanings = <ModuleCleaning>[
        const ModuleCleaning(
          id: 'clean-gap',
          moduleId: 'mod-multi',
          anomalyEventId: 'anom-gap',
          sourceEventId: 'clean-evt-1',
          targetXPositionCm: 69.0, // In the 2cm gap between Panel 1 (0..68) and Panel 2 (70..138)
          pumpActuated: false,
          status: 'refused',
          failureReason: 'target_in_gap',
          postCleaningResult: 'skipped',
          panelIndex: 1,
          createdAt: '2026-11-05T10:10:00Z',
        ),
        const ModuleCleaning(
          id: 'clean-ok',
          moduleId: 'mod-multi',
          anomalyEventId: 'anom-p2',
          sourceEventId: 'clean-evt-2',
          targetXPositionCm: 80.0,
          pumpActuated: true,
          status: 'verified',
          postCleaningResult: 'resolved',
          panelIndex: 2,
          localXPositionCm: 10.0,
          attemptNumber: 1,
          createdAt: '2026-11-05T10:15:00Z',
        ),
      ];

      final mockRepo = _MockModuleRepo(
        details: testDetails,
        mockCleanings: cleanings,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(testUser)),
            moduleRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: ModuleCleaningsScreen(moduleId: 'mod-multi'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check SKIPPED (GAP BETWEEN PANELS) status badge
      expect(find.text('SKIPPED (GAP BETWEEN PANELS)'), findsOneWidget);
      expect(find.textContaining('Target located in inter-panel gap'), findsOneWidget);

      // Check normal verified cleaning with Panel 2
      expect(find.textContaining('Panel 2 • Wash Attempt #1'), findsOneWidget);
      expect(find.text('VERIFIED POST-CLEAN'), findsOneWidget);
    });
  });
}
