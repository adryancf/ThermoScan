import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/core/storage/token_storage.dart';
import 'package:thermoscan/features/auth/data/auth_repository.dart';
import 'package:thermoscan/features/auth/domain/auth_user.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/inspection_routine_bundle.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/module_details_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_measurements_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_thermal_inspection_screen.dart';
import 'package:thermoscan/features/modules/presentation/widgets/radiometric_scan_card.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';

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
        id: 'u-tech',
        companyId: 'c1',
        name: 'Post Clean Tech',
        email: 'tech@thermoscan.com',
        role: 'installer_technician',
        isActive: true,
        mustChangePassword: false,
      );
}

class _MockModuleRepo extends ModuleRepository {
  _MockModuleRepo({
    required this.module,
    this.latestInspection,
    this.inspections = const [],
    this.cleanings = const [],
    this.measurements = const [],
    this.pagedByInspection = const {},
  }) : super(dio: Dio());

  final PvModule module;
  final LatestInspection? latestInspection;
  final List<ModuleInspection> inspections;
  final List<ModuleCleaning> cleanings;
  final List<ModuleMeasurement> measurements;
  final Map<String, List<ModuleMeasurement>> pagedByInspection;

  @override
  Future<ModuleDetails> getModuleDetails(String moduleId) async =>
      ModuleDetails(
        module: module,
        responsibleManagers: const [],
        companyManagers: const [],
        companyTechnicians: const [],
        companyClients: const [],
      );

  @override
  Future<DeviceStatus> getDeviceStatus({required String moduleId}) async =>
      DeviceStatus(
        moduleId: moduleId,
        macAddress: module.macAddress,
        monitoringStatus: 'active',
        isConfigured: true,
        isOnline: true,
        waterAvailable: true,
        waterStatus: 'ok',
        limitsCheckPassed: true,
        thermalSensorActive: true,
        lastPingAt: '2026-11-24T12:00:00Z',
      );

  @override
  Future<LatestInspection?> getLatestInspection({
    required String moduleId,
  }) async =>
      latestInspection;

  @override
  Future<List<ModuleInspection>> listInspections({
    required String moduleId,
    int limit = 100,
    int offset = 0,
  }) async =>
      inspections;

  @override
  Future<List<ModuleCleaning>> listCleanings({
    required String moduleId,
    int limit = 50,
    int offset = 0,
  }) async =>
      cleanings;

  @override
  Future<List<ModuleMeasurement>> listMeasurements({
    required String moduleId,
    int limit = 200,
    int offset = 0,
    int? panelIndex,
  }) async =>
      measurements;

  @override
  Future<PagedMeasurements> listInspectionMeasurements({
    required String moduleId,
    required String inspectionId,
    int page = 1,
    int limit = 10,
    int? panelIndex,
  }) async {
    final items = pagedByInspection[inspectionId] ??
        measurements.where((m) => m.inspectionId == inspectionId).toList();
    return PagedMeasurements(
      page: page,
      limit: limit,
      totalCount: items.length,
      totalPages: 1,
      hasNextPage: false,
      measurements: items,
    );
  }
}

void main() {
  const techUser = AuthUser(
    id: 'u-tech',
    companyId: 'c1',
    name: 'Post Clean Tech',
    email: 'tech@thermoscan.com',
    role: 'installer_technician',
    isActive: true,
    mustChangePassword: false,
  );

  // 2-panel string: Panel 1 [0..100 cm], Gap [100..105 cm], Panel 2 [105..205 cm]
  const twoPanelModule = PvModule(
    id: 'mod-ux',
    companyId: 'c1',
    installerTechnicianId: 'u-tech',
    installerName: 'Post Clean Tech',
    installerEmail: 'tech@thermoscan.com',
    name: 'Solar Array UX Test',
    macAddress: 'AA:BB:CC:DD:EE:99',
    isActive: true,
    monitoringStatus: 'active',
    panelLengthCm: 100.0,
    panelWidthCm: 100.0,
    panelCount: 2,
    panelSpacingCm: 5.0,
    totalLengthCm: 205.0,
    hotspotThresholdDeltaC: 8.0,
    inspectionIntervalDays: 7,
    configuredAt: '2026-11-01T08:00:00Z',
    createdAt: '2026-11-01T08:00:00Z',
    updatedAt: '2026-11-01T08:00:00Z',
    userRelationship: 'installer_technician',
    permissions: ModulePermissions(
      canEditGeometryAndLocation: true,
      canEditSolarAngle: true,
      canEditInterval: true,
      canManageAccess: true,
    ),
  );

  List<double?> framePixels(double tempC) => List<double?>.filled(768, tempC);

  ModuleMeasurement makeFrame({
    required String id,
    required String inspectionId,
    required int panelIndex,
    required double xCm,
    required double maxTempC,
    required String measuredAt,
    double? localXCm,
  }) {
    return ModuleMeasurement(
      id: id,
      moduleId: twoPanelModule.id,
      inspectionId: inspectionId,
      sourceEventId: 'evt-$id',
      panelIndex: panelIndex,
      localXPositionCm: localXCm ?? xCm,
      xPositionCm: xCm,
      maxTemperatureC: maxTempC,
      measuredAt: measuredAt,
      receivedAt: measuredAt,
      thermalFrame: framePixels(maxTempC),
    );
  }

  group('Post-Cleaning UX, Multi-Hotspot & Scan History Tests', () {
    test(
      '1. Optical-window fusion replaces ±2.5 cm routine hotspot frames with verification frames',
      () {
        final routine = [
          makeFrame(
            id: 'r-14',
            inspectionId: 'insp-r',
            panelIndex: 1,
            xCm: 14.0,
            maxTempC: 34.0,
            measuredAt: '2026-11-24T10:00:00Z',
          ),
          makeFrame(
            id: 'r-16',
            inspectionId: 'insp-r',
            panelIndex: 1,
            xCm: 16.0,
            maxTempC: 44.0,
            measuredAt: '2026-11-24T10:00:05Z',
          ),
          makeFrame(
            id: 'r-18',
            inspectionId: 'insp-r',
            panelIndex: 1,
            xCm: 18.0,
            maxTempC: 46.2,
            measuredAt: '2026-11-24T10:00:10Z',
          ),
          makeFrame(
            id: 'r-20',
            inspectionId: 'insp-r',
            panelIndex: 1,
            xCm: 20.0,
            maxTempC: 43.0,
            measuredAt: '2026-11-24T10:00:15Z',
          ),
          makeFrame(
            id: 'r-22',
            inspectionId: 'insp-r',
            panelIndex: 1,
            xCm: 22.0,
            maxTempC: 34.2,
            measuredAt: '2026-11-24T10:00:20Z',
          ),
          makeFrame(
            id: 'r-p2',
            inspectionId: 'insp-r',
            panelIndex: 2,
            xCm: 120.0,
            localXCm: 15.0,
            maxTempC: 33.5,
            measuredAt: '2026-11-24T10:01:00Z',
          ),
        ];

        final verification = [
          makeFrame(
            id: 'v-173',
            inspectionId: 'insp-v',
            panelIndex: 1,
            xCm: 17.3,
            maxTempC: 35.1,
            measuredAt: '2026-11-24T10:35:00Z',
          ),
          makeFrame(
            id: 'v-193',
            inspectionId: 'insp-v',
            panelIndex: 1,
            xCm: 19.3,
            maxTempC: 34.8,
            measuredAt: '2026-11-24T10:35:05Z',
          ),
        ];

        final fused = fuseRoutineWithVerificationMeasurements(
          routineMeasurements: routine,
          verificationMeasurements: verification,
        );

        // 16.0, 18.0, and 20.0 fall within ±2.5 cm of 17.3 / 19.3 and are replaced.
        expect(
          fused.map((m) => m.id).toList(),
          equals(['r-14', 'v-173', 'v-193', 'r-22', 'r-p2']),
        );
        expect(
          fused.map((m) => m.xPositionCm).toList(),
          equals([14.0, 17.3, 19.3, 22.0, 120.0]),
        );
      },
    );

    testWidgets(
      '2. Multi-hotspot After Cleaning vs Before Cleaning toggle hides resolved marker, keeps unresolved marker, renders verdict rows, and keeps Overview anchored on full routine',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const anom1 = ConfirmedAnomaly(
          id: 'anom-h1',
          moduleId: 'mod-ux',
          originMeasurementId: 'm-r-18',
          confirmingMeasurementIds: ['m-r-18'],
          sourceEventId: 'evt-h1',
          panelIndex: 1,
          localXPositionCm: 18.0,
          xPositionCm: 18.0,
          detectedAt: '2026-11-24T10:00:10Z',
          status: 'resolved',
          actuatedAttemptsCount: 1,
          retryPending: false,
          closedAt: '2026-11-24T10:35:00Z',
        );

        const anom2 = ConfirmedAnomaly(
          id: 'anom-h2',
          moduleId: 'mod-ux',
          originMeasurementId: 'm-r-120',
          confirmingMeasurementIds: ['m-r-120'],
          sourceEventId: 'evt-h2',
          panelIndex: 2,
          localXPositionCm: 15.0,
          xPositionCm: 120.0,
          detectedAt: '2026-11-24T10:01:00Z',
          status: 'unresolved',
          actuatedAttemptsCount: 1,
          retryPending: false,
          closedAt: '2026-11-24T10:40:00Z',
        );

        const panelResults = [
          InspectionPanelResult(
            inspectionId: 'insp-routine-multi',
            moduleId: 'mod-ux',
            panelIndex: 1,
            baselineTemperatureC: 34.0,
            truncatedByMemory: false,
            finishedAt: '2026-11-24T10:00:30Z',
            createdAt: '2026-11-24T10:00:30Z',
          ),
          InspectionPanelResult(
            inspectionId: 'insp-routine-multi',
            moduleId: 'mod-ux',
            panelIndex: 2,
            baselineTemperatureC: 33.0,
            truncatedByMemory: false,
            finishedAt: '2026-11-24T10:01:30Z',
            createdAt: '2026-11-24T10:01:30Z',
          ),
        ];

        const routineInsp = ModuleInspection(
          id: 'insp-routine-multi',
          moduleId: 'mod-ux',
          sourceEventId: 'evt-rm',
          type: 'scheduled',
          scheduledFor: '2026-11-24T10:00:00Z',
          startedAt: '2026-11-24T10:00:00Z',
          finishedAt: '2026-11-24T10:01:30Z',
          status: 'completed',
          baselineTemperatureC: 33.5,
          createdAt: '2026-11-24T10:00:00Z',
          updatedAt: '2026-11-24T10:01:30Z',
          confirmedAnomalies: [anom1, anom2],
          panelResults: panelResults,
        );

        const verif1 = ModuleInspection(
          id: 'insp-verif-h1',
          moduleId: 'mod-ux',
          sourceEventId: 'evt-v1',
          type: 'verification',
          cleaningOperationId: 'cln-h1',
          scheduledFor: '2026-11-24T10:35:00Z',
          finishedAt: '2026-11-24T10:35:10Z',
          status: 'completed',
          verificationResult: 'resolved',
          createdAt: '2026-11-24T10:35:00Z',
          updatedAt: '2026-11-24T10:35:10Z',
        );

        const verif2 = ModuleInspection(
          id: 'insp-verif-h2',
          moduleId: 'mod-ux',
          sourceEventId: 'evt-v2',
          type: 'verification',
          cleaningOperationId: 'cln-h2',
          scheduledFor: '2026-11-24T10:40:00Z',
          finishedAt: '2026-11-24T10:40:10Z',
          status: 'completed',
          verificationResult: 'unresolved',
          createdAt: '2026-11-24T10:40:00Z',
          updatedAt: '2026-11-24T10:40:10Z',
        );

        const cln1 = ModuleCleaning(
          id: 'cln-h1',
          moduleId: 'mod-ux',
          anomalyEventId: 'anom-h1',
          sourceEventId: 'evt-c1',
          panelIndex: 1,
          localXPositionCm: 18.0,
          targetXPositionCm: 18.0,
          pumpActuated: true,
          attemptNumber: 1,
          endedAt: '2026-11-24T10:05:00Z',
          status: 'verified',
          postCleaningResult: 'resolved',
          createdAt: '2026-11-24T10:04:00Z',
        );

        const cln2 = ModuleCleaning(
          id: 'cln-h2',
          moduleId: 'mod-ux',
          anomalyEventId: 'anom-h2',
          sourceEventId: 'evt-c2',
          panelIndex: 2,
          localXPositionCm: 15.0,
          targetXPositionCm: 120.0,
          pumpActuated: true,
          attemptNumber: 1,
          endedAt: '2026-11-24T10:10:00Z',
          status: 'verified',
          postCleaningResult: 'unresolved',
          createdAt: '2026-11-24T10:09:00Z',
        );

        final allMeas = [
          makeFrame(
            id: 'm-r-10',
            inspectionId: 'insp-routine-multi',
            panelIndex: 1,
            xCm: 10.0,
            maxTempC: 34.0,
            measuredAt: '2026-11-24T10:00:02Z',
          ),
          makeFrame(
            id: 'm-r-18',
            inspectionId: 'insp-routine-multi',
            panelIndex: 1,
            xCm: 18.0,
            maxTempC: 46.2,
            measuredAt: '2026-11-24T10:00:10Z',
          ),
          makeFrame(
            id: 'm-r-120',
            inspectionId: 'insp-routine-multi',
            panelIndex: 2,
            xCm: 120.0,
            localXCm: 15.0,
            maxTempC: 48.0,
            measuredAt: '2026-11-24T10:01:00Z',
          ),
          makeFrame(
            id: 'm-r-150',
            inspectionId: 'insp-routine-multi',
            panelIndex: 2,
            xCm: 150.0,
            localXCm: 45.0,
            maxTempC: 33.0,
            measuredAt: '2026-11-24T10:01:20Z',
          ),
          makeFrame(
            id: 'm-v-173',
            inspectionId: 'insp-verif-h1',
            panelIndex: 1,
            xCm: 17.3,
            maxTempC: 35.1,
            measuredAt: '2026-11-24T10:35:05Z',
          ),
          makeFrame(
            id: 'm-v-1195',
            inspectionId: 'insp-verif-h2',
            panelIndex: 2,
            xCm: 119.5,
            localXCm: 14.5,
            maxTempC: 47.5,
            measuredAt: '2026-11-24T10:40:05Z',
          ),
        ];

        // Backend raw /latest-inspection points to the verification micro-inspection!
        const rawLatest = LatestInspection(
          inspection: verif2,
          totalMeasurements: 1,
          confirmedAnomalies: [],
        );

        final bundles = InspectionRoutineBundle.buildBundles(
          allInspections: const [verif2, verif1, routineInsp],
          allCleanings: const [cln2, cln1],
          allMeasurements: allMeas,
          latestInspection: rawLatest,
        );

        expect(bundles.length, 1);
        final bundle = bundles.first;
        expect(bundle.resolvedCount, 1);
        expect(bundle.unresolvedCount, 1);
        expect(bundle.hotspotSummaries.length, 2);

        final effectiveLatest = bundle.toEffectiveLatestInspection(rawLatest);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadiometricScanCard(
                  module: twoPanelModule,
                  latestMeasurement: bundle.routineMeasurements.last,
                  latestInspection: effectiveLatest,
                  measurements: bundle.routineMeasurements,
                  verificationMeasurements: bundle.verificationMeasurements,
                  postCleaningResult: bundle.verificationResult,
                  hotspotSummaries: bundle.hotspotSummaries,
                  showDetailedSections: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Toggle labels are After Cleaning / Before Cleaning
        expect(find.byKey(const Key('toggle_restored_view')), findsOneWidget);
        expect(find.byKey(const Key('toggle_original_scan')), findsOneWidget);
        expect(find.text('After Cleaning'), findsOneWidget);
        expect(find.text('Before Cleaning'), findsOneWidget);

        // Post-Cleaning Verdict Banner shows aggregate + per-hotspot rows
        expect(
          find.byKey(const Key('post_cleaning_verdict_banner')),
          findsOneWidget,
        );
        expect(
          find.text('Post-Cleaning Check · 1 of 2 Resolved'),
          findsOneWidget,
        );
        expect(
          find.text('P1 · X = 18.0 cm: 46.2 °C → 35.1 °C (-11.1 °C) · Resolved'),
          findsOneWidget,
        );
        expect(
          find.text('P2 · X = 120.0 cm: 48.0 °C → 47.5 °C (-0.5 °C) · Unresolved'),
          findsOneWidget,
        );

        // In After Cleaning (default), H1 is hidden and ONLY H2 marker remains!
        expect(find.byKey(const Key('rail_hotspot_marker_1')), findsOneWidget);
        expect(find.byKey(const Key('rail_hotspot_marker_2')), findsNothing);

        // Tap P1 verdict row -> focuses scrubber onto P1's fused frame (17.3 cm)
        await tester.tap(find.byKey(const Key('verdict_hotspot_row_1')));
        await tester.pumpAndSettle();
        expect(find.text('X = 17.3 cm'), findsOneWidget);

        // Switch to Before Cleaning -> BOTH H1 and H2 markers are rendered!
        await tester.tap(find.byKey(const Key('toggle_original_scan')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('rail_hotspot_marker_1')), findsOneWidget);
        expect(find.byKey(const Key('rail_hotspot_marker_2')), findsOneWidget);

        // Also check ModuleDetailsScreen (Overview) stays anchored on full routine (not 1-frame verif2!)
        final repo = _MockModuleRepo(
          module: twoPanelModule,
          latestInspection: rawLatest,
          inspections: const [verif2, verif1, routineInsp],
          cleanings: const [cln2, cln1],
          measurements: allMeas,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
              authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
              authControllerProvider
                  .overrideWith((ref) => _FakeAuthController(techUser)),
              moduleRepositoryProvider.overrideWithValue(repo),
            ],
            child: const MaterialApp(
              home: ModuleDetailsScreen(moduleId: 'mod-ux'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Remaining unresolved hotspot on Panel 2 is reported (not collapsed to healthy or 2-frame verif!)
        expect(find.text('Hotspot on Panel 2'), findsOneWidget);
        expect(find.text('HOTSPOT DETECTED'), findsOneWidget);
        // CleanThermalPreviewCard retains full 4-frame routine span + Panel 1 and Panel 2 labels
        expect(find.text('Panel 1'), findsOneWidget);
        expect(find.text('Panel 2'), findsOneWidget);
      },
    );

    testWidgets(
      '3. resolved_later renders Unresolved by Wash · Cleared in Later Scan and clears active alarm on Overview',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const anomLater = ConfirmedAnomaly(
          id: 'anom-later-1',
          moduleId: 'mod-ux',
          originMeasurementId: 'm-r-18',
          confirmingMeasurementIds: ['m-r-18'],
          sourceEventId: 'evt-later',
          panelIndex: 1,
          localXPositionCm: 18.0,
          xPositionCm: 18.0,
          detectedAt: '2026-11-20T10:00:00Z',
          status: 'resolved_later',
          actuatedAttemptsCount: 1,
          retryPending: false,
          closedAt: '2026-11-20T10:35:00Z',
        );

        const routineInsp = ModuleInspection(
          id: 'insp-later',
          moduleId: 'mod-ux',
          sourceEventId: 'evt-insp-later',
          type: 'scheduled',
          scheduledFor: '2026-11-20T10:00:00Z',
          finishedAt: '2026-11-20T10:02:00Z',
          status: 'completed',
          baselineTemperatureC: 34.0,
          createdAt: '2026-11-20T10:00:00Z',
          updatedAt: '2026-11-20T10:02:00Z',
          confirmedAnomalies: [anomLater],
        );

        const verifInsp = ModuleInspection(
          id: 'insp-verif-later',
          moduleId: 'mod-ux',
          sourceEventId: 'evt-v-later',
          type: 'verification',
          cleaningOperationId: 'cln-later',
          scheduledFor: '2026-11-20T10:35:00Z',
          finishedAt: '2026-11-20T10:35:10Z',
          status: 'completed',
          verificationResult: 'unresolved',
          createdAt: '2026-11-20T10:35:00Z',
          updatedAt: '2026-11-20T10:35:10Z',
        );

        const clnLater = ModuleCleaning(
          id: 'cln-later',
          moduleId: 'mod-ux',
          anomalyEventId: 'anom-later-1',
          sourceEventId: 'evt-cln-later',
          panelIndex: 1,
          localXPositionCm: 18.0,
          targetXPositionCm: 18.0,
          pumpActuated: true,
          attemptNumber: 1,
          endedAt: '2026-11-20T10:05:00Z',
          status: 'verified',
          postCleaningResult: 'unresolved',
          createdAt: '2026-11-20T10:04:00Z',
        );

        final meas = [
          makeFrame(
            id: 'm-r-18',
            inspectionId: 'insp-later',
            panelIndex: 1,
            xCm: 18.0,
            maxTempC: 46.2,
            measuredAt: '2026-11-20T10:00:10Z',
          ),
          makeFrame(
            id: 'm-v-173',
            inspectionId: 'insp-verif-later',
            panelIndex: 1,
            xCm: 17.3,
            maxTempC: 44.8,
            measuredAt: '2026-11-20T10:35:05Z',
          ),
        ];

        final bundles = InspectionRoutineBundle.buildBundles(
          allInspections: const [verifInsp, routineInsp],
          allCleanings: const [clnLater],
          allMeasurements: meas,
        );
        final bundle = bundles.first;
        expect(bundle.resolvedLaterCount, 1);
        expect(bundle.hotspotSummaries.first.outcome, 'resolved_later');

        // 3a. RadiometricScanCard shows Unresolved by Wash · Cleared in Later Scan & hides active marker in After Cleaning
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadiometricScanCard(
                  module: twoPanelModule,
                  latestMeasurement: bundle.routineMeasurements.first,
                  latestInspection: bundle.toEffectiveLatestInspection(null),
                  measurements: bundle.routineMeasurements,
                  verificationMeasurements: bundle.verificationMeasurements,
                  postCleaningResult: bundle.verificationResult,
                  hotspotSummaries: bundle.hotspotSummaries,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Unresolved by Wash · Cleared in Later Scan'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Cleared in Later Scan'),
          findsWidgets,
        );
        expect(find.byKey(const Key('rail_hotspot_marker_1')), findsNothing);

        // 3b. ModuleDetailsScreen (Overview) shows NO active alarm when anomaly is resolved_later
        final repo = _MockModuleRepo(
          module: twoPanelModule,
          latestInspection: bundle.toEffectiveLatestInspection(null),
          inspections: const [verifInsp, routineInsp],
          cleanings: const [clnLater],
          measurements: meas,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
              authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
              authControllerProvider
                  .overrideWith((ref) => _FakeAuthController(techUser)),
              moduleRepositoryProvider.overrideWithValue(repo),
            ],
            child: const MaterialApp(
              home: ModuleDetailsScreen(moduleId: 'mod-ux'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Solar Array Healthy'), findsOneWidget);
        expect(find.text('HEALTHY'), findsOneWidget);
        expect(find.text('HOTSPOT DETECTED'), findsNothing);
        expect(find.text('Normal'), findsOneWidget);
      },
    );

    testWidgets(
      '4. Historical inspection selection loads missing verification frames and preserves After/Before Cleaning toggle',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const latestInsp = ModuleInspection(
          id: 'insp-latest-2',
          moduleId: 'mod-ux',
          sourceEventId: 'evt-l2',
          type: 'scheduled',
          scheduledFor: '2026-11-24T10:00:00Z',
          finishedAt: '2026-11-24T10:05:00Z',
          status: 'completed',
          baselineTemperatureC: 32.0,
          createdAt: '2026-11-24T10:00:00Z',
          updatedAt: '2026-11-24T10:05:00Z',
        );

        const histAnom = ConfirmedAnomaly(
          id: 'anom-hist-ux',
          moduleId: 'mod-ux',
          originMeasurementId: 'm-hist-18',
          confirmingMeasurementIds: ['m-hist-18'],
          sourceEventId: 'evt-ah',
          panelIndex: 1,
          localXPositionCm: 18.0,
          xPositionCm: 18.0,
          detectedAt: '2026-11-18T10:00:10Z',
          status: 'resolved',
          actuatedAttemptsCount: 1,
          retryPending: false,
          closedAt: '2026-11-18T10:35:00Z',
        );

        const histRoutine = ModuleInspection(
          id: 'insp-hist-routine',
          moduleId: 'mod-ux',
          sourceEventId: 'evt-hr',
          type: 'scheduled',
          scheduledFor: '2026-11-18T10:00:00Z',
          finishedAt: '2026-11-18T10:02:00Z',
          status: 'completed',
          baselineTemperatureC: 34.0,
          createdAt: '2026-11-18T10:00:00Z',
          updatedAt: '2026-11-18T10:02:00Z',
          confirmedAnomalies: [histAnom],
          panelResults: [
            InspectionPanelResult(
              inspectionId: 'insp-hist-routine',
              moduleId: 'mod-ux',
              panelIndex: 1,
              baselineTemperatureC: 34.0,
              truncatedByMemory: false,
              finishedAt: '2026-11-18T10:01:00Z',
              createdAt: '2026-11-18T10:01:00Z',
            ),
          ],
        );

        const histVerif = ModuleInspection(
          id: 'insp-hist-verif',
          moduleId: 'mod-ux',
          sourceEventId: 'evt-hv',
          type: 'verification',
          cleaningOperationId: 'cln-hist-ux',
          scheduledFor: '2026-11-18T10:35:00Z',
          finishedAt: '2026-11-18T10:35:10Z',
          status: 'completed',
          verificationResult: 'resolved',
          createdAt: '2026-11-18T10:35:00Z',
          updatedAt: '2026-11-18T10:35:10Z',
        );

        const histCleaning = ModuleCleaning(
          id: 'cln-hist-ux',
          moduleId: 'mod-ux',
          anomalyEventId: 'anom-hist-ux',
          sourceEventId: 'evt-ch',
          panelIndex: 1,
          localXPositionCm: 18.0,
          targetXPositionCm: 18.0,
          pumpActuated: true,
          attemptNumber: 1,
          endedAt: '2026-11-18T10:05:00Z',
          status: 'verified',
          postCleaningResult: 'resolved',
          createdAt: '2026-11-18T10:04:00Z',
        );

        final latestMeas = [
          makeFrame(
            id: 'm-latest-1',
            inspectionId: 'insp-latest-2',
            panelIndex: 1,
            xCm: 10.0,
            maxTempC: 33.0,
            measuredAt: '2026-11-24T10:01:00Z',
          ),
        ];

        final histRoutineMeas = [
          makeFrame(
            id: 'm-hist-10',
            inspectionId: 'insp-hist-routine',
            panelIndex: 1,
            xCm: 10.0,
            maxTempC: 34.0,
            measuredAt: '2026-11-18T10:00:05Z',
          ),
          makeFrame(
            id: 'm-hist-18',
            inspectionId: 'insp-hist-routine',
            panelIndex: 1,
            xCm: 18.0,
            maxTempC: 46.2,
            measuredAt: '2026-11-18T10:00:10Z',
          ),
        ];

        final histVerifMeas = [
          makeFrame(
            id: 'm-hist-v173',
            inspectionId: 'insp-hist-verif',
            panelIndex: 1,
            xCm: 17.3,
            maxTempC: 35.1,
            measuredAt: '2026-11-18T10:35:05Z',
          ),
        ];

        final repo = _MockModuleRepo(
          module: twoPanelModule,
          latestInspection: const LatestInspection(
            inspection: latestInsp,
            totalMeasurements: 1,
            confirmedAnomalies: [],
          ),
          inspections: const [latestInsp, histVerif, histRoutine],
          cleanings: const [histCleaning],
          // Only latest scan measurements are preloaded in global allMeasurements!
          measurements: latestMeas,
          pagedByInspection: {
            'insp-hist-routine': histRoutineMeas,
            'insp-hist-verif': histVerifMeas,
          },
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
              authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
              authControllerProvider
                  .overrideWith((ref) => _FakeAuthController(techUser)),
              moduleRepositoryProvider.overrideWithValue(repo),
            ],
            child: const MaterialApp(
              home: ModuleThermalInspectionScreen(moduleId: 'mod-ux'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open Switch Scan selector
        await tester.tap(find.byKey(const Key('switch_scan_button')));
        await tester.pumpAndSettle();

        expect(find.text('All Resolved'), findsOneWidget);
        expect(find.text('Healthy'), findsOneWidget);

        // Select the historical inspection
        await tester.tap(
          find.byKey(const Key('scan_selector_item_insp-hist-routine')),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('historical_scan_banner')), findsOneWidget);
        expect(
          find.byKey(const Key('post_cleaning_toggle_bar')),
          findsOneWidget,
        );
        expect(find.text('After Cleaning'), findsOneWidget);
        expect(find.text('Before Cleaning'), findsOneWidget);
        expect(
          find.text('Post-Cleaning Verified · Hotspot Resolved'),
          findsOneWidget,
        );
        expect(
          find.text('P1 · X = 18.0 cm: 46.2 °C → 35.1 °C (-11.1 °C) · Resolved'),
          findsOneWidget,
        );

        // In After Cleaning, marker is hidden; switching to Before Cleaning reveals it!
        expect(find.byKey(const Key('rail_hotspot_marker_1')), findsNothing);
        await tester.tap(find.byKey(const Key('toggle_original_scan')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('rail_hotspot_marker_1')), findsOneWidget);
      },
    );

    testWidgets(
      '5. ModuleMeasurementsScreen declutters Scan History, supports All Scans / With Hotspots filters, and paginates with Load older scans',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final inspections = <ModuleInspection>[];
        final cleanings = <ModuleCleaning>[];
        final measurements = <ModuleMeasurement>[];

        // 1 empty scheduled placeholder (must be hidden!)
        inspections.add(
          const ModuleInspection(
            id: 'insp-scheduled-empty',
            moduleId: 'mod-ux',
            sourceEventId: 'evt-sched-empty',
            type: 'scheduled',
            scheduledFor: '2026-11-25T10:00:00Z',
            status: 'scheduled',
            createdAt: '2026-11-25T10:00:00Z',
            updatedAt: '2026-11-25T10:00:00Z',
          ),
        );

        // 10 completed routine inspections (indices 1 & 2 have hotspots; 3..10 are healthy)
        for (var i = 1; i <= 10; i++) {
          final day = (24 - i).toString().padLeft(2, '0');
          final inspId = 'insp-r-$i';
          final isHot1 = i == 1;
          final isHot2 = i == 2;
          final anomalies = <ConfirmedAnomaly>[
            if (isHot1)
              ConfirmedAnomaly(
                id: 'anom-r1',
                moduleId: 'mod-ux',
                originMeasurementId: 'm-r-1',
                confirmingMeasurementIds: const ['m-r-1'],
                sourceEventId: 'evt-a1',
                panelIndex: 1,
                xPositionCm: 18.0,
                detectedAt: '2026-11-${day}T10:00:00Z',
                status: 'resolved',
                actuatedAttemptsCount: 1,
                retryPending: false,
              ),
            if (isHot2)
              ConfirmedAnomaly(
                id: 'anom-r2',
                moduleId: 'mod-ux',
                originMeasurementId: 'm-r-2',
                confirmingMeasurementIds: const ['m-r-2'],
                sourceEventId: 'evt-a2',
                panelIndex: 1,
                xPositionCm: 22.0,
                detectedAt: '2026-11-${day}T10:00:00Z',
                status: 'resolved_later',
                actuatedAttemptsCount: 1,
                retryPending: false,
              ),
          ];

          inspections.add(
            ModuleInspection(
              id: inspId,
              moduleId: 'mod-ux',
              sourceEventId: 'evt-$inspId',
              type: 'scheduled',
              scheduledFor: '2026-11-${day}T10:00:00Z',
              finishedAt: '2026-11-${day}T10:05:00Z',
              status: 'completed',
              baselineTemperatureC: 34.0,
              createdAt: '2026-11-${day}T10:00:00Z',
              updatedAt: '2026-11-${day}T10:05:00Z',
              confirmedAnomalies: anomalies,
            ),
          );

          measurements.add(
            makeFrame(
              id: 'm-r-$i',
              inspectionId: inspId,
              panelIndex: 1,
              xCm: isHot1 ? 18.0 : (isHot2 ? 22.0 : 10.0),
              maxTempC: (isHot1 || isHot2) ? 46.2 : 35.5,
              measuredAt: '2026-11-${day}T10:01:00Z',
            ),
          );

          if (isHot1) {
            cleanings.add(
              const ModuleCleaning(
                id: 'cln-r1',
                moduleId: 'mod-ux',
                anomalyEventId: 'anom-r1',
                sourceEventId: 'evt-c-r1',
                panelIndex: 1,
                targetXPositionCm: 18.0,
                pumpActuated: true,
                attemptNumber: 1,
                status: 'verified',
                postCleaningResult: 'resolved',
                createdAt: '2026-11-23T10:06:00Z',
              ),
            );
            inspections.add(
              const ModuleInspection(
                id: 'insp-v-1',
                moduleId: 'mod-ux',
                sourceEventId: 'evt-v1',
                type: 'verification',
                cleaningOperationId: 'cln-r1',
                scheduledFor: '2026-11-23T10:36:00Z',
                finishedAt: '2026-11-23T10:36:10Z',
                status: 'completed',
                verificationResult: 'resolved',
                createdAt: '2026-11-23T10:36:00Z',
                updatedAt: '2026-11-23T10:36:10Z',
              ),
            );
            measurements.add(
              makeFrame(
                id: 'm-v-1',
                inspectionId: 'insp-v-1',
                panelIndex: 1,
                xCm: 17.3,
                maxTempC: 35.0,
                measuredAt: '2026-11-23T10:36:05Z',
              ),
            );
          }
        }

        final repo = _MockModuleRepo(
          module: twoPanelModule,
          latestInspection: LatestInspection(
            inspection: inspections[1], // insp-r-1
            totalMeasurements: 1,
            confirmedAnomalies: inspections[1].confirmedAnomalies,
          ),
          inspections: inspections,
          cleanings: cleanings,
          measurements: measurements,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
              authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
              authControllerProvider
                  .overrideWith((ref) => _FakeAuthController(techUser)),
              moduleRepositoryProvider.overrideWithValue(repo),
            ],
            child: const MaterialApp(
              home: ModuleMeasurementsScreen(moduleId: 'mod-ux'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Empty scheduled placeholder & nested verification do NOT get root cards
        expect(
          find.byKey(const Key('history_group_insp-scheduled-empty')),
          findsNothing,
        );
        expect(find.byKey(const Key('history_group_insp-v-1')), findsNothing);

        // Initially shows 8 routine cards + Load older scans button
        for (var i = 1; i <= 8; i++) {
          expect(
            find.byKey(Key('history_group_insp-r-$i')),
            findsOneWidget,
          );
        }
        expect(find.byKey(const Key('history_group_insp-r-9')), findsNothing);
        expect(find.byKey(const Key('history_group_insp-r-10')), findsNothing);
        expect(
          find.byKey(const Key('load_older_scans_button')),
          findsOneWidget,
        );
        expect(find.text('Load older scans'), findsOneWidget);

        // Compact header outcome badges, 1-line summary, View Thermal Map, collapsed Show N frames
        expect(find.text('1 Hotspot · Resolved'), findsOneWidget);
        expect(find.text('Cleared in Later Scan'), findsWidgets);
        expect(find.text('Healthy'), findsWidgets);
        expect(find.text('46.2 °C'), findsNWidgets(2));
        expect(find.text('+12.2 °C'), findsNWidgets(2));
        expect(
          find.byKey(const Key('view_thermal_map_insp-r-1')),
          findsOneWidget,
        );
        expect(find.text('Show 1 frame'), findsWidgets);
        // Raw panel accordions are collapsed by default!
        expect(
          find.byKey(const Key('panel_accordion_insp-r-1_1')),
          findsNothing,
        );

        // Expand Show 1 frame reveals panel accordion
        await tester.ensureVisible(
          find.byKey(const Key('show_frames_tile_insp-r-1')),
        );
        await tester.tap(find.byKey(const Key('show_frames_tile_insp-r-1')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('panel_accordion_insp-r-1_1')),
          findsOneWidget,
        );

        // Load older scans reveals items 9 and 10 and hides button
        await tester.ensureVisible(
          find.byKey(const Key('load_older_scans_button')),
        );
        await tester.tap(find.byKey(const Key('load_older_scans_button')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('history_group_insp-r-9')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('history_group_insp-r-10')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('load_older_scans_button')),
          findsNothing,
        );

        // Filter chip: With Hotspots -> only 2 hotspot scans visible
        await tester.ensureVisible(
          find.byKey(const Key('filter_hotspot_scans')),
        );
        await tester.tap(find.byKey(const Key('filter_hotspot_scans')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('history_group_insp-r-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('history_group_insp-r-2')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('history_group_insp-r-3')), findsNothing);

        // Filter chip: All Scans -> restores full list (paginated to 8 again)
        await tester.tap(find.byKey(const Key('filter_all_scans')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('history_group_insp-r-3')),
          findsOneWidget,
        );
      },
    );
  });
}
