import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/core/storage/token_storage.dart';
import 'package:thermoscan/features/auth/data/auth_repository.dart';
import 'package:thermoscan/features/auth/domain/auth_user.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/core/network/api_exception.dart';
import 'package:thermoscan/core/widgets/app_text_field.dart';
import 'package:thermoscan/features/modules/presentation/module_details_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_hardware_handshake_screen.dart';
import 'package:thermoscan/features/modules/presentation/module_installation_wizard_screen.dart';
import 'package:thermoscan/features/modules/presentation/widgets/radiometric_scan_card.dart';
import 'package:thermoscan/features/modules/presentation/module_measurements_screen.dart';

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
    this.details = const ModuleDetails(
      module: PvModule(
        id: 'mod-1',
        companyId: 'comp-1',
        installerTechnicianId: 'tech-1',
        installerName: 'Marco Silva',
        installerEmail: 'marco@soltech.io',
        name: 'PV-001 Roof Array',
        macAddress: 'AA:BB:CC:DD:EE:01',
        isActive: true,
        monitoringStatus: 'active',
        inspectionIntervalDays: 7,
        createdAt: '2026-10-29T10:00:00Z',
        updatedAt: '2026-10-29T10:00:00Z',
        userRelationship: 'installer_technician',
        permissions: ModulePermissions(
          canEditGeometryAndLocation: true,
          canEditSolarAngle: true,
          canEditInterval: true,
          canManageAccess: true,
        ),
      ),
      responsibleManagers: [],
      companyManagers: [],
      companyTechnicians: [],
      companyClients: [],
    ),
    this.status = const DeviceStatus(
      moduleId: 'mod-1',
      macAddress: 'AA:BB:CC:DD:EE:01',
      monitoringStatus: 'active',
      isConfigured: true,
      isOnline: true,
      waterAvailable: true,
      waterStatus: 'ok',
      limitsCheckPassed: true,
      thermalSensorActive: true,
    ),
    this.createModuleError,
  }) : super(dio: Dio());

  final ModuleDetails details;
  final DeviceStatus status;
  final Object? createModuleError;
  LatestInspection? mockLatestInspection;
  PagedMeasurements Function(int page)? pagedMeasurementsProvider;

  @override
  Future<LatestInspection?> getLatestInspection({required String moduleId}) async =>
      mockLatestInspection;

  @override
  Future<PagedMeasurements> listInspectionMeasurements({
    required String moduleId,
    required String inspectionId,
    int page = 1,
    int limit = 10,
  }) async {
    if (pagedMeasurementsProvider != null) {
      return pagedMeasurementsProvider!(page);
    }
    return const PagedMeasurements(
      page: 1,
      limit: 10,
      totalCount: 0,
      totalPages: 1,
      hasNextPage: false,
      measurements: [],
    );
  }

  @override
  Future<ModuleDetails> createModule({
    required String name,
    required String macAddress,
    List<String> managerIds = const [],
    List<String>? clientIds,
    double? panelLengthCm,
    double? panelWidthCm,
    int? panelCount,
    double? panelSpacingCm,
    double? latitude,
    double? longitude,
    double? elevationM,
    double? azimuthDeg,
    double? tiltDeg,
    String? azimuthSource,
    String? tiltSource,
    double? minimumSolarAngleDeg,
    int? inspectionIntervalDays,
    double? reservoirNominalCapacityMl,
  }) async {
    if (createModuleError != null) {
      throw createModuleError!;
    }
    return details;
  }

  @override
  Future<List<ModuleManagerItem>> listCompanyManagers() async => const [
        ModuleManagerItem(
          id: 'mgr-1',
          name: 'Default Manager',
          email: 'manager@thermoscan.com',
          isActive: true,
          isDefaultManager: true,
        ),
      ];

  @override
  Future<List<ModuleClientItem>> listCompanyClientOptions() async => const [];

  @override
  Future<ModuleDetails> getModuleDetails(String moduleId) async => details;

  @override
  Future<DeviceStatus> getDeviceStatus({required String moduleId}) async =>
      status;

  @override
  Future<List<ModuleMeasurement>> listMeasurements({
    required String moduleId,
    int limit = 50,
    int offset = 0,
  }) async =>
      const [];

  @override
  Future<List<ModuleCleaning>> listCleanings({
    required String moduleId,
    int limit = 50,
    int offset = 0,
  }) async =>
      const [];

}

void main() {
  const techUser = AuthUser(
    id: 'u1',
    companyId: 'c1',
    name: 'Tech 1',
    email: 'tech@thermoscan.com',
    role: 'technician',
    isActive: true,
    mustChangePassword: false,
  );

  group('ConfigurationSyncInfo & DeviceStatus Domain Tests', () {
    test('ConfigurationSyncInfo fromJson and toJson serialization', () {
      final now = DateTime.now().toUtc();
      final sync = ConfigurationSyncInfo(
        state: 'synced',
        configVersion: 3,
        configAppliedVersion: 3,
        configAppliedAt: now,
      );

      final json = sync.toJson();
      expect(json['state'], 'synced');
      expect(json['config_version'], 3);
      expect(json['config_applied_version'], 3);

      final parsed = ConfigurationSyncInfo.fromJson(json);
      expect(parsed.isSynced, isTrue);
      expect(parsed.isPending, isFalse);
      expect(parsed.isFailed, isFalse);
      expect(parsed.configVersion, 3);
      expect(parsed.configAppliedVersion, 3);
    });

    test('ConfigurationSyncInfo infers pending state when version > applied', () {
      final sync = ConfigurationSyncInfo.fromJson({
        'config_version': 2,
        'config_applied_version': 1,
      });

      expect(sync.state, 'pending');
      expect(sync.isPending, isTrue);
      expect(sync.isSynced, isFalse);
    });

    test('ConfigurationSyncInfo handles failed state with error message', () {
      final sync = ConfigurationSyncInfo.fromJson({
        'config_version': 2,
        'config_applied_version': 1,
        'config_apply_error': 'I2C timeout configuring MLX90640',
      });

      expect(sync.state, 'failed');
      expect(sync.isFailed, isTrue);
      expect(sync.configApplyError, 'I2C timeout configuring MLX90640');
    });

    test('DeviceStatus computes isOnline from lastPingAt and onlineWindowSeconds', () {
      final recentPing = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 15))
          .toIso8601String();
      final oldPing = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 120))
          .toIso8601String();

      final onlineStatus = DeviceStatus.fromJson({
        'module_id': 'm1',
        'mac_address': 'AA:BB:CC:11:22:33',
        'last_ping_at': recentPing,
        'online_window_seconds': 45,
        'limits_check_passed': true,
        'thermal_sensor_active': true,
      });

      expect(onlineStatus.isOnline, isTrue);

      final offlineStatus = DeviceStatus.fromJson({
        'module_id': 'm1',
        'mac_address': 'AA:BB:CC:11:22:33',
        'last_ping_at': oldPing,
        'online_window_seconds': 45,
        'limits_check_passed': true,
        'thermal_sensor_active': true,
      });

      expect(offlineStatus.isOnline, isFalse);
    });

    test('DeviceStatus falls back to explicit isOnline when ping info absent', () {
      final status = DeviceStatus.fromJson({
        'module_id': 'm1',
        'mac_address': 'AA:BB:CC:11:22:33',
        'is_online': true,
        'limits_check_passed': true,
        'thermal_sensor_active': true,
      });

      expect(status.isOnline, isTrue);
    });
  });

  group('ModuleMeasurement Domain & Radiometric Strict Compliance Tests', () {
    test('ModuleMeasurement safely parses thermal_frame with null elements', () {
      final json = {
        'id': 'm-1',
        'module_id': 'mod-1',
        'inspection_id': 'insp-1',
        'source_event_id': 'evt-1',
        'measured_at': '2026-11-03T12:00:00Z',
        'x_position_cm': 4.0,
        'max_temperature_c': 52.3,
        'hotspot_detected': true,
        'voltage_v': 18.2,
        'current_a': 4.1,
        'power_w': 74.62,
        'thermal_frame': [28.1, null, 29.5],
        'received_at': '2026-11-03T12:00:05Z',
      };

      final measurement = ModuleMeasurement.fromJson(json);
      expect(measurement.xPositionCm, 4.0);
      expect(measurement.maxTemperatureC, 52.3);
      expect(measurement.hotspotDetected, isTrue);
      expect(measurement.thermalFrame, isNotNull);
      expect(measurement.thermalFrame!.length, 3);
      expect(measurement.thermalFrame![0], 28.1);
      expect(measurement.thermalFrame![1], isNull);
      expect(measurement.thermalFrame![2], 29.5);
    });

    test('ModuleInspection stores baselineTemperatureC while measurement does not', () {
      const inspection = ModuleInspection(
        id: 'insp-1',
        moduleId: 'mod-1',
        sourceEventId: 'evt-insp-1',
        type: 'periodic',
        scheduledFor: '2026-11-03T11:00:00Z',
        startedAt: '2026-11-03T11:00:05Z',
        finishedAt: '2026-11-03T11:15:00Z',
        status: 'completed',
        baselineTemperatureC: 34.8,
        createdAt: '2026-11-03T11:00:05Z',
        updatedAt: '2026-11-03T11:15:00Z',
      );

      expect(inspection.baselineTemperatureC, 34.8);
    });

    testWidgets('RadiometricScanCard renders candidate step without triggering confirmed hotspot alarm', (tester) async {
      const mod = PvModule(
        id: 'mod-1',
        companyId: 'c1',
        installerTechnicianId: 'u1',
        installerName: 'Marco Silva',
        installerEmail: 'marco@soltech.io',
        name: 'PV Array 1',
        macAddress: 'AA:BB:CC:11:22:33',
        isActive: true,
        monitoringStatus: 'active',
        inspectionIntervalDays: 7,
        createdAt: '2026-11-01T10:00:00Z',
        updatedAt: '2026-11-01T10:00:00Z',
        userRelationship: 'installer_technician',
        permissions: ModulePermissions(
          canEditGeometryAndLocation: true,
          canEditSolarAngle: true,
          canEditInterval: true,
          canManageAccess: true,
        ),
      );

      const candidateMeas = ModuleMeasurement(
        id: 'meas-cand',
        moduleId: 'mod-1',
        inspectionId: 'insp-1',
        sourceEventId: 'evt-cand',
        measuredAt: '2026-11-03T12:00:00Z',
        xPositionCm: 15.0,
        maxTemperatureC: 55.0,
        hotspotDetected: true, // Candidate!
        voltageV: 18.2,
        currentA: 4.1,
        powerW: 74.6,
        receivedAt: '2026-11-03T12:00:05Z',
      );

      const inspWithoutConfirmed = LatestInspection(
        inspection: ModuleInspection(
          id: 'insp-1',
          moduleId: 'mod-1',
          sourceEventId: 'evt-insp-1',
          type: 'scheduled',
          scheduledFor: '2026-11-03T12:00:00Z',
          status: 'completed',
          baselineTemperatureC: 35.0,
          createdAt: '2026-11-03T12:00:00Z',
          updatedAt: '2026-11-03T12:00:00Z',
        ),
        totalMeasurements: 1,
        confirmedAnomalies: [], // Empty! No confirmed hotspot
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RadiometricScanCard(
                module: mod,
                latestMeasurement: candidateMeas,
                latestInspection: inspWithoutConfirmed,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Confirms: "Delta: +20.0°C (Candidate)" is shown, NOT "(Hotspot)"
      expect(find.text('Delta: +20.0°C (Candidate)'), findsWidgets);
      expect(find.text('HOTSPOT DETECTED'), findsNothing);
    });

    testWidgets('ModuleMeasurementsScreen consumes paginated measurements ordered by x_position_cm ASC and handles page changes', (tester) async {
      int requestedPage = 1;
      final mockRepo = _MockModuleRepo();
      mockRepo.mockLatestInspection = const LatestInspection(
        inspection: ModuleInspection(
          id: 'insp-paginated-1',
          moduleId: 'mod-1',
          sourceEventId: 'evt-insp-p1',
          type: 'scheduled',
          scheduledFor: '2026-11-03T14:00:00Z',
          status: 'completed',
          baselineTemperatureC: 35.0,
          createdAt: '2026-11-03T14:00:00Z',
          updatedAt: '2026-11-03T14:00:00Z',
        ),
        totalMeasurements: 20,
        confirmedAnomalies: [],
      );

      mockRepo.pagedMeasurementsProvider = (page) {
        requestedPage = page;
        if (page == 1) {
          return const PagedMeasurements(
            page: 1,
            limit: 10,
            totalCount: 20,
            totalPages: 2,
            hasNextPage: true,
            measurements: [
              ModuleMeasurement(
                id: 'm-page1-1',
                moduleId: 'mod-1',
                inspectionId: 'insp-paginated-1',
                sourceEventId: 'evt-p1-1',
                measuredAt: '2026-11-03T14:05:00Z',
                xPositionCm: 10.0, // First in ascending order
                maxTemperatureC: 40.0,
                hotspotDetected: false,
                voltageV: 18.5,
                currentA: 4.2,
                powerW: 77.7,
                receivedAt: '2026-11-03T14:05:05Z',
              ),
              ModuleMeasurement(
                id: 'm-page1-2',
                moduleId: 'mod-1',
                inspectionId: 'insp-paginated-1',
                sourceEventId: 'evt-p1-2',
                measuredAt: '2026-11-03T14:05:10Z',
                xPositionCm: 12.0, // Second in ascending order
                maxTemperatureC: 41.0,
                hotspotDetected: false,
                voltageV: 18.5,
                currentA: 4.2,
                powerW: 77.7,
                receivedAt: '2026-11-03T14:05:15Z',
              ),
            ],
          );
        } else {
          return const PagedMeasurements(
            page: 2,
            limit: 10,
            totalCount: 20,
            totalPages: 2,
            hasNextPage: false,
            measurements: [
              ModuleMeasurement(
                id: 'm-page2-1',
                moduleId: 'mod-1',
                inspectionId: 'insp-paginated-1',
                sourceEventId: 'evt-p2-1',
                measuredAt: '2026-11-03T14:05:20Z',
                xPositionCm: 30.0,
                maxTemperatureC: 45.0,
                hotspotDetected: false,
                voltageV: 18.5,
                currentA: 4.2,
                powerW: 77.7,
                receivedAt: '2026-11-03T14:05:25Z',
              ),
            ],
          );
        }
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: ModuleMeasurementsScreen(moduleId: 'mod-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify page 1 rendered items ordered by xPositionCm ASC
      expect(find.text('Active Inspection (Paginated)'), findsOneWidget);
      expect(find.text('X = 10.0 cm'), findsOneWidget);
      expect(find.text('X = 12.0 cm'), findsOneWidget);
      expect(find.text('Page 1 of 2 (20 items)'), findsOneWidget);
      expect(requestedPage, 1);

      // Tap Next button to paginate
      await tester.tap(find.byKey(const Key('btn_next_page')));
      await tester.pumpAndSettle();

      // Verify page 2 is requested and item at X = 30.0 cm is shown
      expect(requestedPage, 2);
      expect(find.text('X = 30.0 cm'), findsOneWidget);
      expect(find.text('Page 2 of 2 (20 items)'), findsOneWidget);
    });
  });

  group('Module Details TabBar & TabBarView UI Tests', () {
    testWidgets('Hides Configuração tab when pending_configuration', (tester) async {
      const pendingMod = PvModule(
        id: 'mod-pending',
        companyId: 'c1',
        installerTechnicianId: 'u1',
        installerName: 'Tech',
        installerEmail: 'tech@ts.com',
        name: 'Pending PV Module',
        macAddress: 'AA:BB:CC:00:11:22',
        isActive: true,
        monitoringStatus: 'pending_configuration',
        inspectionIntervalDays: 7,
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

      const details = ModuleDetails(
        module: pendingMod,
        responsibleManagers: [],
        companyManagers: [],
        companyTechnicians: [],
        companyClients: [],
      );

      const status = DeviceStatus(
        moduleId: 'mod-pending',
        macAddress: 'AA:BB:CC:00:11:22',
        monitoringStatus: 'pending_configuration',
        isConfigured: false,
        isOnline: false,
        waterStatus: 'unknown',
        limitsCheckPassed: false,
        thermalSensorActive: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider
                .overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(
              _MockModuleRepo(details: details, status: status),
            ),
          ],
          child: const MaterialApp(
            home: ModuleDetailsScreen(moduleId: 'mod-pending'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Only 3 tabs must be present: Overview, Measurements, Cleanings
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Measurements'), findsOneWidget);
      expect(find.text('Cleanings'), findsOneWidget);
      expect(find.text('Configuration'), findsNothing);

      // Pending configuration banner should be shown
      expect(find.text('Pending Installation Configuration'), findsOneWidget);
    });

    testWidgets('Shows 2x2 Sensor Health Grid & Configuration Sync Badge', (tester) async {
      final now = DateTime.now().toUtc();
      const activeMod = PvModule(
        id: 'mod-active',
        companyId: 'c1',
        installerTechnicianId: 'u1',
        installerName: 'Tech',
        installerEmail: 'tech@ts.com',
        name: 'Active PV Module',
        macAddress: 'AA:BB:CC:33:44:55',
        isActive: true,
        monitoringStatus: 'active',
        inspectionIntervalDays: 7,
        panelLengthCm: 200,
        panelWidthCm: 100,
        panelCount: 12,
        panelSpacingCm: 2.5,
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

      final details = ModuleDetails(
        module: activeMod,
        responsibleManagers: [],
        companyManagers: [],
        companyTechnicians: [],
        companyClients: [],
        configurationSync: ConfigurationSyncInfo(
          state: 'synced',
          configVersion: 2,
          configAppliedVersion: 2,
          configAppliedAt: now,
        ),
      );

      final status = DeviceStatus(
        moduleId: 'mod-active',
        macAddress: 'AA:BB:CC:33:44:55',
        monitoringStatus: 'active',
        isConfigured: true,
        isOnline: true,
        waterAvailable: true,
        waterStatus: 'available',
        limitsCheckPassed: true,
        thermalSensorActive: true,
        configurationSync: ConfigurationSyncInfo(
          state: 'synced',
          configVersion: 2,
          configAppliedVersion: 2,
          configAppliedAt: now,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider
                .overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(
              _MockModuleRepo(details: details, status: status),
            ),
          ],
          child: const MaterialApp(
            home: ModuleDetailsScreen(moduleId: 'mod-active'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // All 4 tabs present
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Measurements'), findsOneWidget);
      expect(find.text('Cleanings'), findsOneWidget);
      expect(find.text('Configuration'), findsOneWidget);

      // 2x2 Sensor Grid items & Connectivity status
      expect(find.text('Limits Check Passed'), findsOneWidget);
      expect(find.text('Thermal Sensor Active'), findsOneWidget);
      expect(find.text('Water Reservoir'), findsOneWidget);
      expect(find.text('ESP32 Connectivity'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
    });

    testWidgets('Device Verification Screen shows 2-step Setup verification', (tester) async {
      const activeMod = PvModule(
        id: 'mod-active',
        companyId: 'c1',
        installerTechnicianId: 'u1',
        installerName: 'Tech',
        installerEmail: 'tech@ts.com',
        name: 'Active PV Module',
        macAddress: 'AA:BB:CC:33:44:55',
        isActive: true,
        monitoringStatus: 'active',
        inspectionIntervalDays: 7,
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

      const details = ModuleDetails(
        module: activeMod,
        responsibleManagers: [],
        companyManagers: [],
        companyTechnicians: [],
        companyClients: [],
      );

      const status = DeviceStatus(
        moduleId: 'mod-active',
        macAddress: 'AA:BB:CC:33:44:55',
        monitoringStatus: 'active',
        isConfigured: true,
        isOnline: true,
        waterAvailable: true,
        waterStatus: 'available',
        limitsCheckPassed: true,
        thermalSensorActive: true,
        configurationSync: ConfigurationSyncInfo(
          state: 'synced',
          configVersion: 1,
          configAppliedVersion: 1,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider
                .overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(
              _MockModuleRepo(details: details, status: status),
            ),
          ],
          child: const MaterialApp(
            home: ModuleHardwareHandshakeScreen(moduleId: 'mod-active'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check 2-step setup verification
      expect(find.text('1. System Configuration & Setup'), findsOneWidget);
      expect(find.text('Step 1: Cloud Settings Saved'), findsOneWidget);
      expect(find.text('Step 2: Device Synchronized'), findsOneWidget);

      // Cleanly dispose periodic timer by unmounting widget
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'Wizard Step 1 halts and shows error when MAC address already exists',
        (tester) async {
      final mockRepo = _MockModuleRepo(
        createModuleError: const ApiException(
          message: 'A module with this MAC address is already registered.',
          code: 'MAC_CONFLICT',
          statusCode: 409,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider
                .overrideWith((ref) => _FakeAuthController(techUser)),
            moduleRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: ModuleInstallationWizardScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter module name and MAC address
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Module Name'),
        'New PV Array',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Device MAC Address'),
        'AA:BB:CC:DD:EE:01',
      );
      await tester.pumpAndSettle();

      // Scroll to button and tap Continue to Site Location
      await tester.ensureVisible(find.text('Continue to Site Location'));
      await tester.tap(find.text('Continue to Site Location'));
      await tester.pumpAndSettle();

      // Verify it halted on Step 1 and displayed the MAC conflict error
      expect(find.text('Module & Embedded Device'), findsOneWidget);
      expect(
        find.text('A module with this MAC address is already registered.'),
        findsWidgets,
      );
    });
  });
}

