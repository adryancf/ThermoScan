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
  }) : super(dio: Dio());

  final PvModule module;
  final LatestInspection? latestInspection;
  final List<ModuleMeasurement> mockMeasurements;
  final List<ModuleCleaning> mockCleanings;

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
  });
}
