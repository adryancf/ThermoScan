import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/core/storage/token_storage.dart';
import 'package:thermoscan/features/auth/data/auth_repository.dart';
import 'package:thermoscan/features/auth/domain/auth_user.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/module_cleanings_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_details_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_measurements_screen.dart';
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
        name: 'Audit Tech',
        email: 'tech@thermoscan.com',
        role: 'installer_technician',
        isActive: true,
        mustChangePassword: false,
      );
}

class _AuditMockRepo extends ModuleRepository {
  _AuditMockRepo({
    required this.module,
    this.latestInspection,
    this.mockMeasurements = const [],
    this.mockCleanings = const [],
    this.mockInspections = const [],
  }) : super(dio: Dio());

  final PvModule module;
  final LatestInspection? latestInspection;
  final List<ModuleMeasurement> mockMeasurements;
  final List<ModuleCleaning> mockCleanings;
  final List<ModuleInspection> mockInspections;

  @override
  Future<ModuleDetails> getModuleDetails(String moduleId) async {
    return ModuleDetails(
      module: module,
      responsibleManagers: const [],
      companyManagers: const [],
      companyTechnicians: const [],
      companyClients: const [],
    );
  }

  @override
  Future<DeviceStatus> getDeviceStatus({required String moduleId}) async {
    return DeviceStatus(
      moduleId: moduleId,
      macAddress: module.macAddress,
      monitoringStatus: 'active',
      isConfigured: true,
      isOnline: true,
      waterAvailable: true,
      waterStatus: 'ok',
      limitsCheckPassed: true,
      thermalSensorActive: true,
      lastPingAt: '2026-11-12T06:00:00Z',
    );
  }

  @override
  Future<LatestInspection?> getLatestInspection({required String moduleId}) async =>
      latestInspection;

  @override
  Future<List<ModuleMeasurement>> listMeasurements({
    required String moduleId,
    int limit = 50,
    int offset = 0,
    int? panelIndex,
  }) async =>
      mockMeasurements;

  @override
  Future<List<ModuleCleaning>> listCleanings({
    required String moduleId,
    int limit = 50,
    int offset = 0,
  }) async =>
      mockCleanings;

  @override
  Future<List<ModuleInspection>> listInspections({
    required String moduleId,
    int limit = 20,
    int offset = 0,
  }) async =>
      mockInspections;

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
      totalCount: mockMeasurements.length,
      totalPages: 1,
      hasNextPage: false,
      measurements: mockMeasurements,
    );
  }
}

void main() {
  const techUser = AuthUser(
    id: 'u-tech',
    companyId: 'c1',
    name: 'Audit Tech',
    email: 'tech@thermoscan.com',
    role: 'installer_technician',
    isActive: true,
    mustChangePassword: false,
  );

  final baseModule = PvModule(
    id: 'mod-audit',
    companyId: 'comp-1',
    installerTechnicianId: 'u-tech',
    installerName: 'Audit Tech',
    installerEmail: 'tech@thermoscan.com',
    name: 'Audit String Array',
    macAddress: 'AA:BB:CC:DD:EE:01',
    panelCount: 3,
    panelLengthCm: 100.0,
    panelSpacingCm: 10.0,
    isActive: true,
    monitoringStatus: 'active',
    inspectionIntervalDays: 7,
    createdAt: '2026-11-12T00:00:00Z',
    updatedAt: '2026-11-12T00:00:00Z',
    userRelationship: 'installer_technician',
    permissions: const ModulePermissions(
      canEditGeometryAndLocation: true,
      canEditSolarAngle: true,
      canEditInterval: true,
      canManageAccess: true,
    ),
  );

  group('1. PvModule.resolvePanelPosition bounds safety', () {
    test('xCm < 0 returns Panel 1 at 0.0 cm without gap', () {
      final res = baseModule.resolvePanelPosition(-15.0);
      expect(res.panelIndex, equals(1));
      expect(res.localXCm, equals(0.0));
      expect(res.inGap, isFalse);
    });

    test('xCm beyond total length returns last panel at len without gap', () {
      // 3 panels * 100 + 2 gaps * 10 = 320 cm total
      final res = baseModule.resolvePanelPosition(450.0);
      expect(res.panelIndex, equals(3));
      expect(res.localXCm, equals(100.0));
      expect(res.inGap, isFalse);
    });

    test('xCm inside gap returns panelIndex 0 and inGap true', () {
      // Panel 1: [0, 100], Gap 1: (100, 110)
      final res = baseModule.resolvePanelPosition(105.0);
      expect(res.panelIndex, equals(0));
      expect(res.inGap, isTrue);
    });
  });

  group('2. Absence of ELEVATED - UNCONFIRMED status', () {
    testWidgets('RadiometricScanCard shows Normal delta (+12.0°C (Normal)) when hasConfirmedHotspots is false', (tester) async {
      const m1 = ModuleMeasurement(
        id: 'm-1',
        moduleId: 'mod-audit',
        inspectionId: 'insp-1',
        sourceEventId: 'evt-1',
        xPositionCm: 50.0,
        maxTemperatureC: 47.0, // Baseline is 35.0 -> delta +12.0°C >= 10°C
        measuredAt: '2026-11-12T06:00:00Z',
        receivedAt: '2026-11-12T06:00:05Z',
      );

      const insp = LatestInspection(
        inspection: ModuleInspection(
          id: 'insp-1',
          moduleId: 'mod-audit',
          sourceEventId: 'evt-1',
          type: 'scheduled',
          scheduledFor: '2026-11-12T06:00:00Z',
          status: 'completed',
          baselineTemperatureC: 35.0,
          createdAt: '2026-11-12T06:00:00Z',
          updatedAt: '2026-11-12T06:00:00Z',
        ),
        totalMeasurements: 1,
        confirmedAnomalies: [], // Unconfirmed!
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RadiometricScanCard(
                module: baseModule,
                measurements: const [m1],
                latestInspection: insp,
                showDetailedSections: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Delta should be Normal, never Elevated
      expect(find.text('+12.0°C (Normal)'), findsWidgets);
      expect(find.textContaining('Elevated'), findsNothing);
      expect(find.text('HOTSPOT'), findsNothing);
    });

    testWidgets('ModuleDetailsScreen metric tile shows Normal (+12.0°C) without ELEVATED badge when unconfirmed', (tester) async {
      const m1 = ModuleMeasurement(
        id: 'm-1',
        moduleId: 'mod-audit',
        inspectionId: 'insp-1',
        sourceEventId: 'evt-1',
        xPositionCm: 50.0,
        maxTemperatureC: 47.0,
        measuredAt: '2026-11-12T06:00:00Z',
        receivedAt: '2026-11-12T06:00:05Z',
      );

      const insp = LatestInspection(
        inspection: ModuleInspection(
          id: 'insp-1',
          moduleId: 'mod-audit',
          sourceEventId: 'evt-1',
          type: 'scheduled',
          scheduledFor: '2026-11-12T06:00:00Z',
          status: 'completed',
          baselineTemperatureC: 35.0,
          createdAt: '2026-11-12T06:00:00Z',
          updatedAt: '2026-11-12T06:00:00Z',
        ),
        totalMeasurements: 1,
        confirmedAnomalies: [],
      );

      final repo = _AuditMockRepo(
        module: baseModule,
        latestInspection: insp,
        mockMeasurements: const [m1],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ModuleDetailsScreen(moduleId: 'mod-audit'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ELEVATED'), findsNothing);
      expect(find.text('+12.0°C (Normal)'), findsWidgets);
    });
  });

  group('3. Persistent Hotspot Card UUID match', () {
    testWidgets('Matches anomalyEventId to ConfirmedAnomaly.id (UUID match)', (tester) async {
      const anomUuid = 'uuid-anom-1234';
      const confirmed = ConfirmedAnomaly(
        id: anomUuid,
        moduleId: 'mod-audit',
        originMeasurementId: 'm-hot',
        confirmingMeasurementIds: ['m-hot-2'],
        sourceEventId: 'source-evt-9999', // Different from UUID
        panelIndex: 1,
        xPositionCm: 50.0,
        detectedAt: '2026-11-12T06:00:00Z',
        status: 'open',
        actuatedAttemptsCount: 3,
        retryPending: false,
      );

      const insp = LatestInspection(
        inspection: ModuleInspection(
          id: 'insp-1',
          moduleId: 'mod-audit',
          sourceEventId: 'evt-1',
          type: 'scheduled',
          scheduledFor: '2026-11-12T06:00:00Z',
          status: 'completed',
          baselineTemperatureC: 35.0,
          createdAt: '2026-11-12T06:00:00Z',
          updatedAt: '2026-11-12T06:00:00Z',
        ),
        totalMeasurements: 1,
        confirmedAnomalies: [confirmed],
      );

      const cleaning = ModuleCleaning(
        id: 'clean-pers',
        moduleId: 'mod-audit',
        anomalyEventId: anomUuid, // Matches confirmed.id!
        sourceEventId: 'clean-evt-1',
        targetXPositionCm: 50.0,
        pumpActuated: true,
        attemptNumber: 3,
        startedAt: '2026-11-12T06:00:00Z',
        status: 'completed',
        postCleaningResult: 'unresolved',
        createdAt: '2026-11-12T06:00:00Z',
      );

      final repo = _AuditMockRepo(
        module: baseModule,
        latestInspection: insp,
        mockCleanings: const [cleaning],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ModuleDetailsScreen(moduleId: 'mod-audit'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PERSISTENT HOTSPOT'), findsOneWidget);
      expect(find.text('Still Overheating After 3 Washes'), findsOneWidget);
    });
  });

  group('4. Cool-down temporal check (>= 30 min)', () {
    testWidgets('Shows COOL-DOWN (30M) when endedAt was 5 minutes ago', (tester) async {
      final fiveMinAgo = DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String();
      final cleaning = ModuleCleaning(
        id: 'cln-recent',
        moduleId: 'mod-audit',
        anomalyEventId: 'anom-1',
        sourceEventId: 'clean-evt-1',
        targetXPositionCm: 50.0,
        pumpActuated: true,
        attemptNumber: 1,
        endedAt: fiveMinAgo,
        status: 'completed',
        postCleaningResult: 'pending',
        createdAt: fiveMinAgo,
      );

      final repo = _AuditMockRepo(
        module: baseModule,
        mockCleanings: [cleaning],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ModuleDetailsScreen(moduleId: 'mod-audit'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('COOL-DOWN (30M)'), findsOneWidget);
      expect(find.text('Wash Completed — Cooling Down'), findsOneWidget);
    });

    testWidgets('Shows Awaiting Post-Clean Verification when endedAt was 35 minutes ago', (tester) async {
      final thirtyFiveMinAgo = DateTime.now().toUtc().subtract(const Duration(minutes: 35)).toIso8601String();
      final cleaning = ModuleCleaning(
        id: 'cln-old',
        moduleId: 'mod-audit',
        anomalyEventId: 'anom-1',
        sourceEventId: 'clean-evt-1',
        targetXPositionCm: 50.0,
        pumpActuated: true,
        attemptNumber: 1,
        endedAt: thirtyFiveMinAgo,
        status: 'completed',
        postCleaningResult: 'pending',
        createdAt: thirtyFiveMinAgo,
      );

      final repo = _AuditMockRepo(
        module: baseModule,
        mockCleanings: [cleaning],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ModuleDetailsScreen(moduleId: 'mod-audit'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AWAITING VERIFICATION'), findsOneWidget);
      expect(find.text('Awaiting Post-Clean Verification'), findsOneWidget);
      expect(find.text('COOL-DOWN (30M)'), findsNothing);
    });
  });

  group('5. RadiometricScanCard clamp safety on narrow screens', () {
    testWidgets('Does not throw ArgumentError on extremely narrow screen (e.g. 50px)', (tester) async {
      tester.view.physicalSize = const Size(50, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final oldOnError = FlutterError.onError;
      Object? argumentError;
      FlutterError.onError = (details) {
        if (details.exception is ArgumentError) {
          argumentError = details.exception;
        }
      };

      try {
        const m1 = ModuleMeasurement(
          id: 'm-1',
          moduleId: 'mod-audit',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-1',
          xPositionCm: 50.0,
          maxTemperatureC: 38.0,
          measuredAt: '2026-11-12T06:00:00Z',
          receivedAt: '2026-11-12T06:00:05Z',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 50,
                  child: RadiometricScanCard(
                    module: baseModule,
                    measurements: const [m1],
                    showDetailedSections: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        tester.takeException();
      } finally {
        FlutterError.onError = oldOnError;
      }

      expect(argumentError, isNull);
    });
  });

  group('6. Fair wash attempt labeling in ModuleCleaningsScreen', () {
    testWidgets('Labels refused cleaning as Cleaning Request (Refused)', (tester) async {
      const cleaning = ModuleCleaning(
        id: 'cln-refused',
        moduleId: 'mod-audit',
        anomalyEventId: 'anom-1',
        sourceEventId: 'evt-1',
        targetXPositionCm: 50.0,
        pumpActuated: false,
        attemptNumber: 2,
        status: 'refused',
        failureReason: 'insufficient_water',
        postCleaningResult: 'skipped',
        createdAt: '2026-11-12T06:00:00Z',
      );

      final repo = _AuditMockRepo(
        module: baseModule,
        mockCleanings: const [cleaning],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ModuleCleaningsScreen(moduleId: 'mod-audit'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cleaning Request (Refused)'), findsOneWidget);
      expect(find.textContaining('Wash Attempt #2'), findsNothing);
    });

    testWidgets('Labels pumpActuated=false as Safety Hold (Pump Inactive)', (tester) async {
      const cleaning = ModuleCleaning(
        id: 'cln-pump-inactive',
        moduleId: 'mod-audit',
        anomalyEventId: 'anom-1',
        sourceEventId: 'evt-1',
        targetXPositionCm: 50.0,
        pumpActuated: false,
        attemptNumber: 1,
        status: 'completed',
        postCleaningResult: 'pending',
        createdAt: '2026-11-12T06:00:00Z',
      );

      final repo = _AuditMockRepo(
        module: baseModule,
        mockCleanings: const [cleaning],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ModuleCleaningsScreen(moduleId: 'mod-audit'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Safety Hold (Pump Inactive)'), findsOneWidget);
      expect(find.textContaining('Wash Attempt #1'), findsNothing);
    });
  });

  group('7. ModuleMeasurementsScreen gap nearest panel association', () {
    testWidgets('Associates gap measurement to nearest panel rather than forcing Panel 1', (tester) async {
      // Panel 1: [0..100], Gap 1: [100..110], Panel 2: [110..210]
      // x=108 cm is in Gap 1, closer to Panel 2 (midpoint is 105 cm)
      const mGap = ModuleMeasurement(
        id: 'm-gap',
        moduleId: 'mod-audit',
        inspectionId: 'insp-1',
        sourceEventId: 'evt-1',
        xPositionCm: 108.0,
        maxTemperatureC: 36.0,
        measuredAt: '2026-11-12T06:00:00Z',
        receivedAt: '2026-11-12T06:00:05Z',
      );

      const insp = LatestInspection(
        inspection: ModuleInspection(
          id: 'insp-1',
          moduleId: 'mod-audit',
          sourceEventId: 'evt-1',
          type: 'scheduled',
          scheduledFor: '2026-11-12T06:00:00Z',
          status: 'completed',
          baselineTemperatureC: 35.0,
          createdAt: '2026-11-12T06:00:00Z',
          updatedAt: '2026-11-12T06:00:00Z',
        ),
        totalMeasurements: 1,
        confirmedAnomalies: [],
      );

      final repo = _AuditMockRepo(
        module: baseModule,
        latestInspection: insp,
        mockMeasurements: const [mGap],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ModuleMeasurementsScreen(moduleId: 'mod-audit'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should be grouped under Panel 2, not Panel 1
      expect(find.textContaining('Panel 2'), findsOneWidget);
      expect(find.textContaining('Panel 1'), findsNothing);
    });

    testWidgets(
        '8. Peak Temp icon color respects firmware confirmation, staying secondary when deltaT > 5.0 without confirmed anomalies',
        (tester) async {
      const mHot = ModuleMeasurement(
        id: 'meas-hot',
        moduleId: 'mod-audit',
        inspectionId: 'insp-1',
        sourceEventId: 'evt-1',
        panelIndex: 1,
        xPositionCm: 10.0,
        localXPositionCm: 10.0,
        maxTemperatureC: 38.0, // Baseline is 30.0 -> deltaT is +8.0C (> 5.0C!)
        measuredAt: '2026-11-12T06:00:00Z',
        receivedAt: '2026-11-12T06:00:05Z',
      );

      const insp = LatestInspection(
        inspection: ModuleInspection(
          id: 'insp-1',
          moduleId: 'mod-audit',
          sourceEventId: 'evt-1',
          type: 'scheduled',
          scheduledFor: '2026-11-12T06:00:00Z',
          status: 'completed',
          baselineTemperatureC: 30.0,
          createdAt: '2026-11-12T06:00:00Z',
          updatedAt: '2026-11-12T06:00:00Z',
        ),
        totalMeasurements: 1,
        confirmedAnomalies: [], // 0 confirmed anomalies by firmware!
      );

      final repo = _AuditMockRepo(
        module: baseModule,
        latestInspection: insp,
        mockMeasurements: const [mHot],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ModuleMeasurementsScreen(moduleId: 'mod-audit'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Delta text is visible as informational
      expect(find.text('+8.0°C above normal'), findsOneWidget);

      // Thermostat icon should be AppColors.secondary, NOT AppColors.error
      final iconFinder = find.byIcon(Icons.thermostat_rounded);
      expect(iconFinder, findsOneWidget);
      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.color, equals(AppColors.secondary));
    });

    testWidgets('9. Electrical current displays in milliamperes (mA) rather than Amperes', (tester) async {
      const mElec = ModuleMeasurement(
        id: 'meas-elec',
        moduleId: 'mod-audit',
        inspectionId: 'insp-1',
        sourceEventId: 'evt-1',
        panelIndex: 1,
        xPositionCm: 10.0,
        localXPositionCm: 10.0,
        maxTemperatureC: 30.0,
        voltageV: 18.50,
        currentA: 0.250, // 0.25A should be displayed as 250.0mA
        powerW: 4.625,
        measuredAt: '2026-11-12T06:00:00Z',
        receivedAt: '2026-11-12T06:00:05Z',
      );

      const insp = LatestInspection(
        inspection: ModuleInspection(
          id: 'insp-1',
          moduleId: 'mod-audit',
          sourceEventId: 'evt-1',
          type: 'scheduled',
          scheduledFor: '2026-11-12T06:00:00Z',
          status: 'completed',
          baselineTemperatureC: 30.0,
          createdAt: '2026-11-12T06:00:00Z',
          updatedAt: '2026-11-12T06:00:00Z',
        ),
        totalMeasurements: 1,
        confirmedAnomalies: [],
      );

      final repo = _AuditMockRepo(
        module: baseModule,
        latestInspection: insp,
        mockMeasurements: const [mElec],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ModuleMeasurementsScreen(moduleId: 'mod-audit'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should display '250.0mA', never '0.25A'
      expect(find.textContaining('250.0mA'), findsWidgets);
      expect(find.textContaining('0.25A'), findsNothing);
    });

    test('10. Isotherm colormap strictly highlights hotspot temperatures >= baseline + delta', () {
      final frame768 = List.filled(768, 25.0);
      frame768[10] = 34.0;
      frame768[20] = 45.0;

      final panorama = ThermalPanoramaData.fromMeasurements(
        measurements: [
          ModuleMeasurement(
            id: 'm1',
            moduleId: 'mod-audit',
            inspectionId: 'insp-1',
            sourceEventId: 'evt-1',
            xPositionCm: 5.0,
            maxTemperatureC: 45.0,
            measuredAt: '2026-11-12T06:00:00Z',
            receivedAt: '2026-11-12T06:00:05Z',
            thermalFrame: frame768,
          ),
        ],
        baselineTempC: 25.0,
        hotspotDeltaThresholdC: 8.0,
      );

      // Normal temperature at baseline (25.0°C) -> Cold/cool blue tone
      final normalColor = panorama.colorForTemperature(25.0);
      expect(normalColor.red, lessThan(100));
      expect(normalColor.blue, greaterThan(150));

      // Hotspot temperature exceeding threshold (34.0°C >= 25.0 + 8.0) -> Isotherm alarm (warm/red)
      final hotspotColor = panorama.colorForTemperature(34.0);
      expect(hotspotColor.red, greaterThan(200));

      // Scale bar colors contain the isotherm alarm spectrum
      expect(panorama.scaleGradientColors.length, equals(6));
      expect(panorama.scaleGradientColors.last, equals(const Color(0xFFFFFFFF)));
    });

    testWidgets('11. Restored View toggle is strictly conditional on post-cleaning verifications', (tester) async {
      const routineMeas = ModuleMeasurement(
        id: 'm-routine-1',
        moduleId: 'mod-audit',
        inspectionId: 'insp-routine-1',
        sourceEventId: 'evt-r1',
        xPositionCm: 45.0,
        maxTemperatureC: 48.0,
        measuredAt: '2026-11-12T06:00:00Z',
        receivedAt: '2026-11-12T06:00:05Z',
      );

      const verifMeas = ModuleMeasurement(
        id: 'm-verif-1',
        moduleId: 'mod-audit',
        inspectionId: 'insp-verif-1',
        sourceEventId: 'evt-v1',
        xPositionCm: 45.0,
        maxTemperatureC: 34.5,
        measuredAt: '2026-11-12T06:35:00Z',
        receivedAt: '2026-11-12T06:35:05Z',
      );

      const routineInsp = LatestInspection(
        inspection: ModuleInspection(
          id: 'insp-routine-1',
          moduleId: 'mod-audit',
          sourceEventId: 'evt-insp-r1',
          type: 'scheduled',
          scheduledFor: '2026-11-12T06:00:00Z',
          status: 'completed',
          baselineTemperatureC: 35.0,
          createdAt: '2026-11-12T06:00:00Z',
          updatedAt: '2026-11-12T06:05:00Z',
        ),
        totalMeasurements: 1,
        confirmedAnomalies: [
          ConfirmedAnomaly(
            id: 'anom-hotspot-1',
            moduleId: 'mod-audit',
            originMeasurementId: 'm-routine-1',
            confirmingMeasurementIds: ['m-routine-1'],
            sourceEventId: 'evt-anom-1',
            panelIndex: 1,
            xPositionCm: 45.0,
            detectedAt: '2026-11-12T06:01:00Z',
            status: 'resolved',
            actuatedAttemptsCount: 1,
            retryPending: false,
          ),
        ],
      );

      // Case 1: NO verification measurements -> Toggle bar MUST NOT be rendered
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadiometricScanCard(
              module: baseModule,
              latestInspection: routineInsp,
              measurements: const [routineMeas],
              verificationMeasurements: null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('post_cleaning_toggle_bar')), findsNothing);
      expect(find.byKey(const Key('toggle_restored_view')), findsNothing);
      expect(find.byKey(const Key('toggle_original_scan')), findsNothing);

      // Case 2: WITH verification measurements -> Toggle bar MUST be rendered
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RadiometricScanCard(
              module: baseModule,
              latestInspection: routineInsp,
              measurements: const [routineMeas],
              verificationMeasurements: const [verifMeas],
              postCleaningResult: 'resolved',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('post_cleaning_toggle_bar')), findsOneWidget);
      expect(find.byKey(const Key('toggle_restored_view')), findsOneWidget);
      expect(find.byKey(const Key('toggle_original_scan')), findsOneWidget);
      expect(find.text('Restored View · Hotspot Healed'), findsOneWidget);

      // Tapping Original Scan switches to pre-cleaning view
      await tester.tap(find.byKey(const Key('toggle_original_scan')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Original Scan · +13.0°C Hotspot'), findsOneWidget);

      // Tapping Restored View switches back
      await tester.tap(find.byKey(const Key('toggle_restored_view')));
      await tester.pumpAndSettle();

      expect(find.text('Restored View · Hotspot Healed'), findsOneWidget);
    });

    testWidgets('12. ModuleMeasurementsScreen nests post-cleaning verifications under parent routine', (tester) async {
      const routineInsp = ModuleInspection(
        id: 'insp-routine-main',
        moduleId: 'mod-audit',
        sourceEventId: 'evt-r-main',
        type: 'scheduled',
        scheduledFor: '2026-11-12T06:00:00Z',
        status: 'completed',
        baselineTemperatureC: 35.0,
        createdAt: '2026-11-12T06:00:00Z',
        updatedAt: '2026-11-12T06:05:00Z',
        confirmedAnomalies: [
          ConfirmedAnomaly(
            id: 'anom-nest-1',
            moduleId: 'mod-audit',
            originMeasurementId: 'm-r1',
            confirmingMeasurementIds: ['m-r1'],
            sourceEventId: 'evt-anom-nest-1',
            panelIndex: 1,
            xPositionCm: 30.0,
            detectedAt: '2026-11-12T06:01:00Z',
            status: 'resolved',
            actuatedAttemptsCount: 1,
            retryPending: false,
          ),
        ],
      );

      const verifInsp = ModuleInspection(
        id: 'insp-verif-child',
        moduleId: 'mod-audit',
        sourceEventId: 'evt-v-child',
        type: 'verification',
        cleaningOperationId: 'cln-nest-1',
        scheduledFor: '2026-11-12T06:35:00Z',
        status: 'completed',
        verificationResult: 'resolved',
        createdAt: '2026-11-12T06:35:00Z',
        updatedAt: '2026-11-12T06:36:00Z',
      );

      const cleaning = ModuleCleaning(
        id: 'cln-nest-1',
        moduleId: 'mod-audit',
        anomalyEventId: 'anom-nest-1',
        sourceEventId: 'evt-cln-1',
        targetXPositionCm: 30.0,
        pumpActuated: true,
        attemptNumber: 1,
        status: 'completed',
        postCleaningResult: 'resolved',
        createdAt: '2026-11-12T06:05:00Z',
      );

      const mRoutine = ModuleMeasurement(
        id: 'm-r1',
        moduleId: 'mod-audit',
        inspectionId: 'insp-routine-main',
        sourceEventId: 'evt-mr1',
        xPositionCm: 30.0,
        maxTemperatureC: 48.0,
        measuredAt: '2026-11-12T06:00:05Z',
        receivedAt: '2026-11-12T06:00:10Z',
      );

      const mVerif = ModuleMeasurement(
        id: 'm-v1',
        moduleId: 'mod-audit',
        inspectionId: 'insp-verif-child',
        sourceEventId: 'evt-mv1',
        xPositionCm: 30.0,
        maxTemperatureC: 34.0,
        measuredAt: '2026-11-12T06:35:05Z',
        receivedAt: '2026-11-12T06:35:10Z',
      );

      final repo = _AuditMockRepo(
        module: baseModule,
        latestInspection: const LatestInspection(
          inspection: routineInsp,
          totalMeasurements: 1,
          confirmedAnomalies: [],
        ),
        mockInspections: const [routineInsp, verifInsp],
        mockCleanings: const [cleaning],
        mockMeasurements: const [mRoutine, mVerif],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ModuleMeasurementsScreen(moduleId: 'mod-audit'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Parent routine group is rendered
      expect(find.byKey(const Key('history_group_insp-routine-main')), findsOneWidget);

      // Child verification is nested inside parent, NOT as a separate root group
      expect(find.byKey(const Key('history_group_insp-verif-child')), findsNothing);
      expect(find.byKey(const Key('nested_post_cleaning_insp-routine-main')), findsOneWidget);

      // Verified badge in header
      expect(find.text('VERIFIED RESOLVED'), findsOneWidget);
      expect(find.text('Post-Cleaning Verification'), findsOneWidget);
    });
  });
}
