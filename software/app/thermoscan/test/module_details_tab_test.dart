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
import 'package:thermoscan/features/modules/presentation/widgets/thermal_panorama_painter.dart';
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
  List<ModuleMeasurement> mockAllMeasurements = const [];

  @override
  Future<LatestInspection?> getLatestInspection({required String moduleId}) async =>
      mockLatestInspection;

  @override
  Future<PagedMeasurements> listInspectionMeasurements({
    required String moduleId,
    required String inspectionId,
    int page = 1,
    int limit = 10,
    int? panelIndex,
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
    int? panelIndex,
  }) async =>
      mockAllMeasurements;

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
    test('ModuleMeasurement safely parses thermal_frame with null elements without crash', () {
      final json = {
        'id': 'm-1',
        'module_id': 'mod-1',
        'inspection_id': 'insp-1',
        'source_event_id': 'evt-1',
        'measured_at': '2026-11-03T12:00:00Z',
        'x_position_cm': 4.0,
        'max_temperature_c': 52.3,
        'voltage_v': 18.2,
        'current_a': 4.1,
        'power_w': 74.62,
        'thermal_frame': [28.1, null, 29.5, null],
        'received_at': '2026-11-03T12:00:05Z',
      };

      final measurement = ModuleMeasurement.fromJson(json);
      expect(measurement.xPositionCm, 4.0);
      expect(measurement.maxTemperatureC, 52.3);
      expect(measurement.thermalFrame, isNotNull);
      expect(measurement.thermalFrame!.length, 4);
      expect(measurement.thermalFrame![0], 28.1);
      expect(measurement.thermalFrame![1], isNull);
      expect(measurement.thermalFrame![2], 29.5);
      expect(measurement.thermalFrame![3], isNull);
    });

    test('ModuleMeasurement safely parses null electrical readings (INA219 unavailable)', () {
      final json = {
        'id': 'm-null-elec',
        'module_id': 'mod-1',
        'inspection_id': 'insp-1',
        'source_event_id': 'evt-null',
        'measured_at': '2026-11-03T12:00:00Z',
        'x_position_cm': 8.0,
        'max_temperature_c': 48.0,
        'voltage_v': null,
        'current_a': null,
        'power_w': null,
        'received_at': '2026-11-03T12:00:05Z',
      };

      final measurement = ModuleMeasurement.fromJson(json);
      expect(measurement.voltageV, isNull);
      expect(measurement.currentA, isNull);
      expect(measurement.powerW, isNull);
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

    testWidgets('RadiometricScanCard renders by X position, avoids thermal matrix fusion and does not display candidate as HOTSPOT', (tester) async {
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

      const meas1 = ModuleMeasurement(
        id: 'meas-1',
        moduleId: 'mod-1',
        inspectionId: 'insp-1',
        sourceEventId: 'evt-1',
        measuredAt: '2026-11-03T12:00:00Z',
        xPositionCm: 2.0,
        maxTemperatureC: 45.0,
        voltageV: 18.2,
        currentA: 4.1,
        powerW: 74.6,
        receivedAt: '2026-11-03T12:00:05Z',
      );

      const meas2 = ModuleMeasurement(
        id: 'meas-2',
        moduleId: 'mod-1',
        inspectionId: 'insp-1',
        sourceEventId: 'evt-2',
        measuredAt: '2026-11-03T12:00:10Z',
        xPositionCm: 4.0,
        maxTemperatureC: 58.0, // High temp candidate step without confirmed anomaly
        voltageV: 18.2,
        currentA: 4.1,
        powerW: 74.6,
        receivedAt: '2026-11-03T12:00:15Z',
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
        totalMeasurements: 2,
        confirmedAnomalies: [], // Empty! No confirmed hotspot
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RadiometricScanCard(
                module: mod,
                measurements: [meas1, meas2],
                latestInspection: inspWithoutConfirmed,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Rendered individually by X position without matrix fusion
      expect(find.text('F1 (2cm)'), findsOneWidget);
      expect(find.text('F2 (4cm)'), findsOneWidget);
      expect(find.text('F1 (X=2.0 cm)'), findsOneWidget);
      expect(find.text('F2 (X=4.0 cm)'), findsOneWidget);

      // Candidate is NEVER displayed as HOTSPOT
      expect(find.text('HOTSPOT'), findsNothing);
      expect(find.text('HOTSPOT DETECTED'), findsNothing);
      expect(find.text('Delta: +23.0°C (Normal)'), findsOneWidget);
    });

    testWidgets('RadiometricScanCard highlights exclusively confirmedAnomalies from completed inspection', (tester) async {
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

      const meas1 = ModuleMeasurement(
        id: 'meas-1',
        moduleId: 'mod-1',
        inspectionId: 'insp-1',
        sourceEventId: 'evt-1',
        measuredAt: '2026-11-03T12:00:00Z',
        xPositionCm: 2.0,
        maxTemperatureC: 40.0,
        voltageV: 18.2,
        currentA: 4.1,
        powerW: 74.6,
        receivedAt: '2026-11-03T12:00:05Z',
      );

      const meas2 = ModuleMeasurement(
        id: 'meas-2',
        moduleId: 'mod-1',
        inspectionId: 'insp-1',
        sourceEventId: 'evt-2',
        measuredAt: '2026-11-03T12:00:10Z',
        xPositionCm: 10.0,
        maxTemperatureC: 62.0,
        voltageV: 18.2,
        currentA: 4.1,
        powerW: 74.6,
        receivedAt: '2026-11-03T12:00:15Z',
      );

      const inspWithConfirmed = LatestInspection(
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
        totalMeasurements: 2,
        confirmedAnomalies: [
          ConfirmedAnomaly(
            id: 'anom-1',
            moduleId: 'mod-1',
            originMeasurementId: 'meas-2',
            confirmingMeasurementIds: ['meas-2'],
            sourceEventId: 'evt-anom-1',
            xPositionCm: 10.0,
            detectedAt: '2026-11-03T12:00:15Z',
            status: 'open',
            actuatedAttemptsCount: 0,
            retryPending: false,
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RadiometricScanCard(
                module: mod,
                measurements: [meas1, meas2],
                latestInspection: inspWithConfirmed,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Exclusively highlights confirmed anomaly
      expect(find.text('Delta: +27.0°C (Hotspot)'), findsWidgets);
      expect(find.text('HOTSPOT 10.0cm'), findsOneWidget);
      expect(find.text('HOTSPOT'), findsOneWidget);
    });

    testWidgets('RadiometricScanCard renders N/A for null electrical readings and never 0.0 V, 0.00 A, 0.0 W', (tester) async {
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

      const measNullElec = ModuleMeasurement(
        id: 'meas-null',
        moduleId: 'mod-1',
        inspectionId: 'insp-1',
        sourceEventId: 'evt-null',
        measuredAt: '2026-11-03T12:00:00Z',
        xPositionCm: 5.0,
        maxTemperatureC: 44.0,
        voltageV: null,
        currentA: null,
        powerW: null,
        receivedAt: '2026-11-03T12:00:05Z',
      );

      const insp = LatestInspection(
        inspection: ModuleInspection(
          id: 'insp-1',
          moduleId: 'mod-1',
          sourceEventId: 'evt-insp-1',
          type: 'scheduled',
          scheduledFor: '2026-11-03T12:00:00Z',
          status: 'completed',
          baselineTemperatureC: 34.0,
          createdAt: '2026-11-03T12:00:00Z',
          updatedAt: '2026-11-03T12:00:00Z',
        ),
        totalMeasurements: 1,
        confirmedAnomalies: [],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RadiometricScanCard(
                module: mod,
                latestMeasurement: measNullElec,
                latestInspection: insp,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Displays N/A in frame and metric tiles
      expect(find.text('N/A • N/A • N/A'), findsOneWidget);
      expect(find.text('N/A'), findsWidgets);

      // NEVER displays 0.0 V, 0.00 A, 0.0 W
      expect(find.textContaining('0.0 V'), findsNothing);
      expect(find.textContaining('0.00 A'), findsNothing);
      expect(find.textContaining('0.0 W'), findsNothing);
      expect(find.textContaining('0.0V'), findsNothing);
      expect(find.textContaining('0.00A'), findsNothing);
      expect(find.textContaining('0.0W'), findsNothing);
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
              // Intentionally returned unordered from API to test client ASC sorting
              ModuleMeasurement(
                id: 'm-page1-2',
                moduleId: 'mod-1',
                inspectionId: 'insp-paginated-1',
                sourceEventId: 'evt-p1-2',
                measuredAt: '2026-11-03T14:05:10Z',
                xPositionCm: 12.0,
                maxTemperatureC: 41.0,
                voltageV: 18.5,
                currentA: 4.2,
                powerW: 77.7,
                receivedAt: '2026-11-03T14:05:15Z',
              ),
              ModuleMeasurement(
                id: 'm-page1-1',
                moduleId: 'mod-1',
                inspectionId: 'insp-paginated-1',
                sourceEventId: 'evt-p1-1',
                measuredAt: '2026-11-03T14:05:00Z',
                xPositionCm: 10.0,
                maxTemperatureC: 40.0,
                voltageV: null, // Null electrical test in list
                currentA: null,
                powerW: null,
                receivedAt: '2026-11-03T14:05:05Z',
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

      // Verify page 1 rendered items strictly ordered by xPositionCm ASC
      expect(find.text('Active Inspection (Paginated)'), findsOneWidget);
      expect(find.text('X = 10.0 cm'), findsOneWidget);
      expect(find.text('X = 12.0 cm'), findsOneWidget);
      expect(find.text('Page 1 of 2 (20 items)'), findsOneWidget);
      expect(requestedPage, 1);

      // Verify null electrical reading shows N/A and not 0.0V or 0.0W
      expect(find.text('N/A'), findsWidgets);
      expect(find.text('0.0V'), findsNothing);
      expect(find.text('0.0W'), findsNothing);
      // Candidate never shown in item list
      expect(find.text('CANDIDATE'), findsNothing);

      // Tap Next button to paginate
      await tester.tap(find.byKey(const Key('btn_next_page')));
      await tester.pumpAndSettle();

      // Verify page 2 is requested and item at X = 30.0 cm is shown
      expect(requestedPage, 2);
      expect(find.text('X = 30.0 cm'), findsOneWidget);
      expect(find.text('Page 2 of 2 (20 items)'), findsOneWidget);
    });

    testWidgets(
      '1. Spatial ordering sorts measurements by x_position_cm ASC and tie-breaks by measured_at ASC and id ASC',
      (tester) async {
        const mod = PvModule(
          id: 'mod-sort',
          companyId: 'c1',
          installerTechnicianId: 'u1',
          installerName: 'Marco Silva',
          installerEmail: 'marco@soltech.io',
          name: 'PV Array Sort',
          macAddress: 'AA:BB:CC:11:22:33',
          isActive: true,
          monitoringStatus: 'active',
          panelLengthCm: 20.0,
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

        // Input provided in measured_at DESC order with tie at X = 4.0 cm
        const mDesc1 = ModuleMeasurement(
          id: 'm-z',
          moduleId: 'mod-sort',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-4',
          measuredAt: '2026-11-03T12:00:30Z',
          xPositionCm: 6.0,
          maxTemperatureC: 43.0,
          receivedAt: '2026-11-03T12:00:35Z',
        );
        const mDesc2 = ModuleMeasurement(
          id: 'm-b',
          moduleId: 'mod-sort',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-3',
          measuredAt: '2026-11-03T12:00:20Z',
          xPositionCm: 4.0,
          maxTemperatureC: 42.0,
          receivedAt: '2026-11-03T12:00:25Z',
        );
        const mDesc3 = ModuleMeasurement(
          id: 'm-c',
          moduleId: 'mod-sort',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-2',
          measuredAt: '2026-11-03T12:00:10Z',
          xPositionCm: 4.0,
          maxTemperatureC: 41.0,
          receivedAt: '2026-11-03T12:00:15Z',
        );
        const mDesc4 = ModuleMeasurement(
          id: 'm-a',
          moduleId: 'mod-sort',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-1',
          measuredAt: '2026-11-03T12:00:00Z',
          xPositionCm: 0.0,
          maxTemperatureC: 40.0,
          receivedAt: '2026-11-03T12:00:05Z',
        );

        final sorted = sortMeasurementsSpatially([
          mDesc1,
          mDesc2,
          mDesc3,
          mDesc4,
        ]);
        expect(sorted.map((m) => m.id).toList(), [
          'm-a', // X = 0.0
          'm-c', // X = 4.0, earlier measuredAt (12:00:10Z)
          'm-b', // X = 4.0, later measuredAt (12:00:20Z)
          'm-z', // X = 6.0
        ]);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadiometricScanCard(
                  module: mod,
                  measurements: [mDesc1, mDesc2, mDesc3, mDesc4],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // F1 is X=0.0 cm, F2 & F3 are X=4.0 cm, F4 is X=6.0 cm
        expect(find.text('F1 (X=0.0 cm)'), findsOneWidget);
        expect(find.text('F2 (X=4.0 cm)'), findsOneWidget);
        expect(find.text('F3 (X=4.0 cm)'), findsOneWidget);
        expect(find.text('F4 (X=6.0 cm)'), findsOneWidget);
        // Verify centered FOV span [X-2.5, X+2.5]
        expect(find.textContaining('Span: -2.5-2.5 cm'), findsOneWidget);
      },
    );

    testWidgets(
      '2 & 3. Anomaly association by origin_measurement_id and confirming_measurement_ids',
      (tester) async {
        const mod = PvModule(
          id: 'mod-assoc',
          companyId: 'c1',
          installerTechnicianId: 'u1',
          installerName: 'Marco Silva',
          installerEmail: 'marco@soltech.io',
          name: 'PV Array Assoc',
          macAddress: 'AA:BB:CC:11:22:33',
          isActive: true,
          monitoringStatus: 'active',
          panelLengthCm: 20.0,
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

        const f1 = ModuleMeasurement(
          id: 'meas-origin',
          moduleId: 'mod-assoc',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-1',
          measuredAt: '2026-11-03T12:00:00Z',
          xPositionCm: 4.0,
          maxTemperatureC: 61.0,
          receivedAt: '2026-11-03T12:00:05Z',
        );
        const f2 = ModuleMeasurement(
          id: 'meas-confirming',
          moduleId: 'mod-assoc',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-2',
          measuredAt: '2026-11-03T12:00:10Z',
          xPositionCm: 6.0,
          maxTemperatureC: 63.0,
          receivedAt: '2026-11-03T12:00:15Z',
        );
        const f3 = ModuleMeasurement(
          id: 'meas-unrelated',
          moduleId: 'mod-assoc',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-3',
          measuredAt: '2026-11-03T12:00:20Z',
          xPositionCm: 6.0, // Same X as anomaly, but NOT in origin/confirming IDs!
          maxTemperatureC: 39.0,
          receivedAt: '2026-11-03T12:00:25Z',
        );

        const anomaly = ConfirmedAnomaly(
          id: 'anom-1',
          moduleId: 'mod-assoc',
          originMeasurementId: 'meas-origin',
          confirmingMeasurementIds: ['meas-confirming'],
          sourceEventId: 'evt-anom-1',
          xPositionCm: 6.0,
          detectedAt: '2026-11-03T12:00:15Z',
          status: 'open',
          actuatedAttemptsCount: 0,
          retryPending: false,
        );

        // Pure association checks:
        expect(isFrameAssociatedWithAnomaly(f1, anomaly), isTrue);
        expect(isFrameAssociatedWithAnomaly(f2, anomaly), isTrue);
        // f3 is at X=6.0, but since explicit IDs exist on anomaly, f3 is NOT associated!
        expect(isFrameAssociatedWithAnomaly(f3, anomaly), isFalse);

        const insp = LatestInspection(
          inspection: ModuleInspection(
            id: 'insp-1',
            moduleId: 'mod-assoc',
            sourceEventId: 'evt-insp-1',
            type: 'scheduled',
            scheduledFor: '2026-11-03T12:00:00Z',
            status: 'completed',
            baselineTemperatureC: 35.0,
            createdAt: '2026-11-03T12:00:00Z',
            updatedAt: '2026-11-03T12:00:00Z',
          ),
          totalMeasurements: 3,
          confirmedAnomalies: [anomaly],
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadiometricScanCard(
                  module: mod,
                  measurements: [f1, f2, f3],
                  latestInspection: insp,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // F1 and F2 have H1 badges, F3 does not
        expect(find.byKey(const Key('frame_1_badge_H1')), findsOneWidget);
        expect(find.byKey(const Key('frame_2_badge_H1')), findsOneWidget);
        expect(find.byKey(const Key('frame_3_badge_H1')), findsNothing);
      },
    );

    testWidgets(
      '4. Multiple anomalies render independent rail markers and highlight shared frame with both H1 and H2',
      (tester) async {
        const mod = PvModule(
          id: 'mod-multi',
          companyId: 'c1',
          installerTechnicianId: 'u1',
          installerName: 'Marco Silva',
          installerEmail: 'marco@soltech.io',
          name: 'PV Array Multi',
          macAddress: 'AA:BB:CC:11:22:33',
          isActive: true,
          monitoringStatus: 'active',
          panelLengthCm: 20.0,
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

        const f1 = ModuleMeasurement(
          id: 'm-1',
          moduleId: 'mod-multi',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-1',
          measuredAt: '2026-11-03T12:00:00Z',
          xPositionCm: 4.0,
          maxTemperatureC: 60.0,
          receivedAt: '2026-11-03T12:00:05Z',
        );
        const fShared = ModuleMeasurement(
          id: 'm-shared',
          moduleId: 'mod-multi',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-2',
          measuredAt: '2026-11-03T12:00:10Z',
          xPositionCm: 6.0,
          maxTemperatureC: 64.0,
          receivedAt: '2026-11-03T12:00:15Z',
        );
        const f3 = ModuleMeasurement(
          id: 'm-3',
          moduleId: 'mod-multi',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-3',
          measuredAt: '2026-11-03T12:00:20Z',
          xPositionCm: 8.0,
          maxTemperatureC: 62.0,
          receivedAt: '2026-11-03T12:00:25Z',
        );

        const anom1 = ConfirmedAnomaly(
          id: 'anom-1',
          moduleId: 'mod-multi',
          originMeasurementId: 'm-1',
          confirmingMeasurementIds: ['m-1', 'm-shared'],
          sourceEventId: 'evt-a1',
          xPositionCm: 4.5,
          detectedAt: '2026-11-03T12:00:15Z',
          status: 'open',
          actuatedAttemptsCount: 0,
          retryPending: false,
        );
        const anom2 = ConfirmedAnomaly(
          id: 'anom-2',
          moduleId: 'mod-multi',
          originMeasurementId: 'm-shared',
          confirmingMeasurementIds: ['m-shared', 'm-3'],
          sourceEventId: 'evt-a2',
          xPositionCm: 7.5,
          detectedAt: '2026-11-03T12:00:25Z',
          status: 'open',
          actuatedAttemptsCount: 0,
          retryPending: false,
        );

        const insp = LatestInspection(
          inspection: ModuleInspection(
            id: 'insp-1',
            moduleId: 'mod-multi',
            sourceEventId: 'evt-insp-1',
            type: 'scheduled',
            scheduledFor: '2026-11-03T12:00:00Z',
            status: 'completed',
            baselineTemperatureC: 35.0,
            createdAt: '2026-11-03T12:00:00Z',
            updatedAt: '2026-11-03T12:00:00Z',
          ),
          totalMeasurements: 3,
          confirmedAnomalies: [anom1, anom2],
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadiometricScanCard(
                  module: mod,
                  measurements: [f1, fShared, f3],
                  latestInspection: insp,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Both hotspot markers are rendered on the rail
        expect(find.text('HOTSPOT 4.5cm'), findsOneWidget);
        expect(find.text('HOTSPOT 7.5cm'), findsOneWidget);

        // F1 has H1 only
        expect(find.byKey(const Key('frame_1_badge_H1')), findsOneWidget);
        expect(find.byKey(const Key('frame_1_badge_H2')), findsNothing);

        // F2 (m-shared) has BOTH H1 and H2 badges!
        expect(find.byKey(const Key('frame_2_badge_H1')), findsOneWidget);
        expect(find.byKey(const Key('frame_2_badge_H2')), findsOneWidget);

        // F3 has H2 only
        expect(find.byKey(const Key('frame_3_badge_H1')), findsNothing);
        expect(find.byKey(const Key('frame_3_badge_H2')), findsOneWidget);
      },
    );

    test(
      '5. Fallback FOV association uses half-open interval [X-2.5, X+2.5) without false boundary match at X+2.5 or X+5.0',
      () {
        const frameAtZero = ModuleMeasurement(
          id: 'm-0',
          moduleId: 'mod-1',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-0',
          measuredAt: '2026-11-03T12:00:00Z',
          xPositionCm: 0.0,
          maxTemperatureC: 45.0,
          receivedAt: '2026-11-03T12:00:05Z',
        );

        // Anomaly without IDs at X = 5.0 cm (old upper bound X + 5.0)
        const anomalyAt5 = ConfirmedAnomaly(
          id: 'a-5',
          moduleId: 'mod-1',
          originMeasurementId: '',
          confirmingMeasurementIds: [],
          sourceEventId: 'evt-a5',
          xPositionCm: 5.0,
          detectedAt: '2026-11-03T12:00:10Z',
          status: 'open',
          actuatedAttemptsCount: 0,
          retryPending: false,
        );

        // Anomaly without IDs at X = 2.5 cm (exact upper boundary X + 2.5)
        const anomalyAt2_5 = ConfirmedAnomaly(
          id: 'a-2.5',
          moduleId: 'mod-1',
          originMeasurementId: '',
          confirmingMeasurementIds: [],
          sourceEventId: 'evt-a25',
          xPositionCm: 2.5,
          detectedAt: '2026-11-03T12:00:10Z',
          status: 'open',
          actuatedAttemptsCount: 0,
          retryPending: false,
        );

        // Anomaly without IDs at X = -2.5 cm (lower inclusive boundary X - 2.5)
        const anomalyAtMinus2_5 = ConfirmedAnomaly(
          id: 'a-m2.5',
          moduleId: 'mod-1',
          originMeasurementId: '',
          confirmingMeasurementIds: [],
          sourceEventId: 'evt-am25',
          xPositionCm: -2.5,
          detectedAt: '2026-11-03T12:00:10Z',
          status: 'open',
          actuatedAttemptsCount: 0,
          retryPending: false,
        );

        expect(isFrameAssociatedWithAnomaly(frameAtZero, anomalyAt5), isFalse);
        expect(
          isFrameAssociatedWithAnomaly(frameAtZero, anomalyAt2_5),
          isFalse,
        );
        expect(
          isFrameAssociatedWithAnomaly(frameAtZero, anomalyAtMinus2_5),
          isTrue,
        );
      },
    );

    testWidgets(
      '6. Panorama renders valid thermal_frame, complements invalid pixels (null/NaN) from neighbor overlap, and uses neutral fallback (never 0.0°C)',
      (tester) async {
        // Frame 1 at X = 0.0 cm (covers [-2.5, +2.5]):
        // Has null at X = -2.0 cm (non-overlapping region -> unresolvedInvalid)
        // and NaN at X = +0.5 cm (overlapping region with Frame 2 -> complemented by Frame 2!)
        final frame1Pixels = List<double?>.filled(768, 35.0);
        // At X = -2.0 cm (col = (( -2.0 - (-2.5) ) / 5.0 * 32).floor() = 3), row 0 -> null
        frame1Pixels[3] = null;
        // At X = +0.5 cm (col = (( 0.5 - (-2.5) ) / 5.0 * 32).floor() = 19), row 0 -> NaN
        frame1Pixels[19] = double.nan;

        // Frame 2 at X = 2.0 cm (covers [-0.5, +4.5]): all valid 48.0°C
        final frame2Pixels = List<double?>.filled(768, 48.0);

        final m1 = ModuleMeasurement(
          id: 'm-1',
          moduleId: 'mod-1',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-1',
          measuredAt: '2026-11-03T12:00:00Z',
          xPositionCm: 0.0,
          maxTemperatureC: 35.0,
          thermalFrame: frame1Pixels,
          receivedAt: '2026-11-03T12:00:05Z',
        );
        final m2 = ModuleMeasurement(
          id: 'm-2',
          moduleId: 'mod-1',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-2',
          measuredAt: '2026-11-03T12:00:10Z',
          xPositionCm: 2.0,
          maxTemperatureC: 48.0,
          thermalFrame: frame2Pixels,
          receivedAt: '2026-11-03T12:00:15Z',
        );

        final panorama = ThermalPanoramaData.fromMeasurements(
          measurements: [m1, m2],
          panelLengthCm: 20.0,
        );

        // Verify minValidTempC is 35.0 (NEVER 0.0 from null/NaN!) and maxValidTempC is 48.0
        expect(panorama.minValidTempC, 35.0);
        expect(panorama.maxValidTempC, 48.0);
        expect(panorama.totalInvalidPixelsInFrames, 2);

        // At X = +0.5 cm, row 0: Frame 1 is closer (|0.5 - 0.0| = 0.5 < |0.5 - 2.0| = 1.5),
        // but Frame 1 has NaN at col 19, so Frame 2 complements it with 48.0°C!
        final complementedRes = panorama.resolveAt(0.5, 0);
        expect(complementedRes.status, ThermalCellStatus.complemented);
        expect(complementedRes.temperatureC, 48.0);

        // At X = -2.0 cm, row 0: Only Frame 1 covers X = -2.0 cm, and it has null -> unresolvedInvalid
        final unresolvedRes = panorama.resolveAt(-2.0, 0);
        expect(unresolvedRes.status, ThermalCellStatus.unresolvedInvalid);
        expect(unresolvedRes.temperatureC, isNull);

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
          panelLengthCm: 20.0,
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

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadiometricScanCard(
                  module: mod,
                  measurements: [m1, m2],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('thermal_panorama_canvas')), findsOneWidget);
        expect(find.byKey(const Key('notice_invalid_pixels')), findsOneWidget);
        expect(find.text('Min: 35.0°C'), findsOneWidget);
        expect(find.text('Max: 48.0°C'), findsOneWidget);
        expect(find.textContaining('0.0°C'), findsNothing);
      },
    );

    testWidgets(
      '7. Explicit UI states for measurements without thermal_frame, unlinked anomaly confirming IDs, and partial pagination',
      (tester) async {
        const mod = PvModule(
          id: 'mod-states',
          companyId: 'c1',
          installerTechnicianId: 'u1',
          installerName: 'Marco Silva',
          installerEmail: 'marco@soltech.io',
          name: 'PV Array States',
          macAddress: 'AA:BB:CC:11:22:33',
          isActive: true,
          monitoringStatus: 'active',
          panelLengthCm: 20.0,
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

        const mNoMatrix = ModuleMeasurement(
          id: 'm-loaded-1',
          moduleId: 'mod-states',
          inspectionId: 'insp-1',
          sourceEventId: 'evt-1',
          measuredAt: '2026-11-03T12:00:00Z',
          xPositionCm: 2.0,
          maxTemperatureC: 44.0,
          thermalFrame: null,
          receivedAt: '2026-11-03T12:00:05Z',
        );

        const insp = LatestInspection(
          inspection: ModuleInspection(
            id: 'insp-1',
            moduleId: 'mod-states',
            sourceEventId: 'evt-insp-1',
            type: 'scheduled',
            scheduledFor: '2026-11-03T12:00:00Z',
            status: 'completed',
            baselineTemperatureC: 34.0,
            createdAt: '2026-11-03T12:00:00Z',
            updatedAt: '2026-11-03T12:00:00Z',
          ),
          totalMeasurements: 11, // Only 1 of 11 loaded due to pagination
          confirmedAnomalies: [
            ConfirmedAnomaly(
              id: 'anom-unloaded',
              moduleId: 'mod-states',
              originMeasurementId: 'm-not-loaded-99',
              confirmingMeasurementIds: ['m-not-loaded-100'],
              sourceEventId: 'evt-a99',
              xPositionCm: 16.0,
              detectedAt: '2026-11-03T12:01:00Z',
              status: 'open',
              actuatedAttemptsCount: 0,
              retryPending: false,
            ),
          ],
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadiometricScanCard(
                  module: mod,
                  measurements: [mNoMatrix],
                  latestInspection: insp,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('No thermal_frame matrix available'), findsOneWidget);
        expect(
          find.byKey(const Key('notice_missing_thermal_frame')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('notice_unlinked_anomalies')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('notice_partial_pagination')),
          findsOneWidget,
        );
        expect(
          find.text('Scale: N/A (No valid thermal pixels)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '8. Expected coverage calculation (panelLengthCm=68.0 -> 35 acquisitions, 73.0 cm coverage) and incomplete coverage notice without fake strips',
      (tester) async {
        const coverage68 = ThermalCoverageInfo(
          panelLengthCm: 68.0,
          loadedMeasurementsCount: 2,
          totalInspectionMeasurements: 2,
        );
        expect(coverage68.expectedAcquisitions, 35);
        expect(coverage68.expectedThermalCoverageCm, 73.0);
        expect(coverage68.isIncompleteCoverage, isTrue);
        expect(coverage68.isPartiallyLoadedByPagination, isFalse);

        const mod68 = PvModule(
          id: 'mod-68',
          companyId: 'c1',
          installerTechnicianId: 'u1',
          installerName: 'Marco Silva',
          installerEmail: 'marco@soltech.io',
          name: 'PV Array 68cm',
          macAddress: 'AA:BB:CC:11:22:33',
          isActive: true,
          monitoringStatus: 'active',
          panelLengthCm: 68.0,
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

        const m1 = ModuleMeasurement(
          id: 'm-1',
          moduleId: 'mod-68',
          inspectionId: 'insp-68',
          sourceEventId: 'evt-1',
          measuredAt: '2026-11-03T12:00:00Z',
          xPositionCm: 0.0,
          maxTemperatureC: 38.0,
          receivedAt: '2026-11-03T12:00:05Z',
        );
        const m2 = ModuleMeasurement(
          id: 'm-2',
          moduleId: 'mod-68',
          inspectionId: 'insp-68',
          sourceEventId: 'evt-2',
          measuredAt: '2026-11-03T12:00:10Z',
          xPositionCm: 2.0,
          maxTemperatureC: 39.0,
          receivedAt: '2026-11-03T12:00:15Z',
        );

        const insp = LatestInspection(
          inspection: ModuleInspection(
            id: 'insp-68',
            moduleId: 'mod-68',
            sourceEventId: 'evt-insp-68',
            type: 'scheduled',
            scheduledFor: '2026-11-03T12:00:00Z',
            status: 'completed',
            baselineTemperatureC: 35.0,
            createdAt: '2026-11-03T12:00:00Z',
            updatedAt: '2026-11-03T12:00:00Z',
          ),
          totalMeasurements: 2,
          confirmedAnomalies: [],
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadiometricScanCard(
                  module: mod68,
                  measurements: [m1, m2],
                  latestInspection: insp,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Expected: 35 frames (73.0 cm)'),
          findsOneWidget,
        );
        expect(
          find.text('Incomplete coverage: 2 of 35 expected acquisitions'),
          findsOneWidget,
        );
        // Only 2 FOV strips rendered; NO fake strips generated for missing positions
        expect(find.byKey(const Key('fov_strip_1')), findsOneWidget);
        expect(find.byKey(const Key('fov_strip_2')), findsOneWidget);
        expect(find.byKey(const Key('fov_strip_3')), findsNothing);
      },
    );

    testWidgets(
      '9. RadiometricScanCard filters out measurements from older inspections so thermal frames do not accumulate',
      (tester) async {
        const mod = PvModule(
          id: 'mod-filter',
          companyId: 'c1',
          installerTechnicianId: 'u1',
          installerName: 'Marco Silva',
          installerEmail: 'marco@soltech.io',
          name: 'PV Array Filter',
          macAddress: 'AA:BB:CC:11:22:33',
          isActive: true,
          monitoringStatus: 'active',
          panelLengthCm: 20.0,
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

        const oldMeas1 = ModuleMeasurement(
          id: 'old-1',
          moduleId: 'mod-filter',
          inspectionId: 'insp-old-11111111',
          sourceEventId: 'evt-old-1',
          measuredAt: '2026-11-03T10:00:00Z',
          xPositionCm: 8.0,
          maxTemperatureC: 59.2,
          receivedAt: '2026-11-03T10:00:05Z',
        );
        const oldMeas2 = ModuleMeasurement(
          id: 'old-2',
          moduleId: 'mod-filter',
          inspectionId: 'insp-old-11111111',
          sourceEventId: 'evt-old-2',
          measuredAt: '2026-11-03T10:00:10Z',
          xPositionCm: 10.0,
          maxTemperatureC: 58.7,
          receivedAt: '2026-11-03T10:00:15Z',
        );
        const currentMeas1 = ModuleMeasurement(
          id: 'curr-1',
          moduleId: 'mod-filter',
          inspectionId: 'insp-current-2222',
          sourceEventId: 'evt-curr-1',
          measuredAt: '2026-11-04T12:00:00Z',
          xPositionCm: 0.0,
          maxTemperatureC: 35.4,
          receivedAt: '2026-11-04T12:00:05Z',
        );
        const currentMeas2 = ModuleMeasurement(
          id: 'curr-2',
          moduleId: 'mod-filter',
          inspectionId: 'insp-current-2222',
          sourceEventId: 'evt-curr-2',
          measuredAt: '2026-11-04T12:00:10Z',
          xPositionCm: 2.0,
          maxTemperatureC: 35.8,
          receivedAt: '2026-11-04T12:00:15Z',
        );

        const latestInsp = LatestInspection(
          inspection: ModuleInspection(
            id: 'insp-current-2222',
            moduleId: 'mod-filter',
            sourceEventId: 'evt-insp-curr',
            type: 'scheduled',
            scheduledFor: '2026-11-04T12:00:00Z',
            status: 'completed',
            baselineTemperatureC: 35.0,
            createdAt: '2026-11-04T12:00:00Z',
            updatedAt: '2026-11-04T12:00:20Z',
          ),
          totalMeasurements: 2,
          confirmedAnomalies: [],
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadiometricScanCard(
                  module: mod,
                  measurements: [currentMeas2, currentMeas1, oldMeas2, oldMeas1],
                  latestMeasurement: currentMeas2,
                  latestInspection: latestInsp,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Only the 2 frames from insp-current-2222 are rendered
        expect(find.byKey(const Key('fov_strip_1')), findsOneWidget);
        expect(find.byKey(const Key('fov_strip_2')), findsOneWidget);
        expect(find.byKey(const Key('fov_strip_3')), findsNothing);
        expect(find.text('F1 (X=0.0 cm)'), findsOneWidget);
        expect(find.text('F2 (X=2.0 cm)'), findsOneWidget);
        expect(find.textContaining('X=8.0 cm'), findsNothing);
        expect(find.textContaining('X=10.0 cm'), findsNothing);
      },
    );

    testWidgets(
      '10. ModuleMeasurementsScreen renders Inspection History grouped by inspection_id',
      (tester) async {
        final mockRepo = _MockModuleRepo();
        mockRepo.mockLatestInspection = const LatestInspection(
          inspection: ModuleInspection(
            id: 'insp-22222222-bbbb',
            moduleId: 'mod-1',
            sourceEventId: 'evt-insp-2',
            type: 'scheduled',
            scheduledFor: '2026-11-04T15:00:00Z',
            status: 'completed',
            baselineTemperatureC: 35.0,
            createdAt: '2026-11-04T15:00:00Z',
            updatedAt: '2026-11-04T15:00:10Z',
          ),
          totalMeasurements: 2,
          confirmedAnomalies: [],
        );
        mockRepo.pagedMeasurementsProvider = (_) => const PagedMeasurements(
          page: 1,
          limit: 10,
          totalCount: 2,
          totalPages: 1,
          hasNextPage: false,
          measurements: [
            ModuleMeasurement(
              id: 'm-new-1',
              moduleId: 'mod-1',
              inspectionId: 'insp-22222222-bbbb',
              sourceEventId: 'evt-n1',
              measuredAt: '2026-11-04T15:00:05Z',
              xPositionCm: 0.0,
              maxTemperatureC: 35.4,
              receivedAt: '2026-11-04T15:00:06Z',
            ),
            ModuleMeasurement(
              id: 'm-new-2',
              moduleId: 'mod-1',
              inspectionId: 'insp-22222222-bbbb',
              sourceEventId: 'evt-n2',
              measuredAt: '2026-11-04T15:00:08Z',
              xPositionCm: 2.0,
              maxTemperatureC: 35.8,
              receivedAt: '2026-11-04T15:00:09Z',
            ),
          ],
        );
        mockRepo.mockAllMeasurements = const [
          ModuleMeasurement(
            id: 'm-new-2',
            moduleId: 'mod-1',
            inspectionId: 'insp-22222222-bbbb',
            sourceEventId: 'evt-n2',
            measuredAt: '2026-11-04T15:00:08Z',
            xPositionCm: 2.0,
            maxTemperatureC: 35.8,
            receivedAt: '2026-11-04T15:00:09Z',
          ),
          ModuleMeasurement(
            id: 'm-new-1',
            moduleId: 'mod-1',
            inspectionId: 'insp-22222222-bbbb',
            sourceEventId: 'evt-n1',
            measuredAt: '2026-11-04T15:00:05Z',
            xPositionCm: 0.0,
            maxTemperatureC: 35.4,
            receivedAt: '2026-11-04T15:00:06Z',
          ),
          ModuleMeasurement(
            id: 'm-old-1',
            moduleId: 'mod-1',
            inspectionId: 'insp-11111111-aaaa',
            sourceEventId: 'evt-o1',
            measuredAt: '2026-11-03T11:00:05Z',
            xPositionCm: 8.0,
            maxTemperatureC: 58.4,
            receivedAt: '2026-11-03T11:00:06Z',
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
              authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
              authControllerProvider.overrideWith(
                (ref) => _FakeAuthController(techUser),
              ),
              moduleRepositoryProvider.overrideWithValue(mockRepo),
            ],
            child: const MaterialApp(
              home: ModuleMeasurementsScreen(moduleId: 'mod-1'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Inspection History (Grouped by Inspection)'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('history_group_insp-22222222-bbbb')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('history_group_insp-11111111-aaaa')),
          findsOneWidget,
        );
        expect(find.text('LATEST'), findsOneWidget);
        expect(find.text('X = 8.0 cm'), findsOneWidget);
      },
    );

    testWidgets(
      '11. RadiometricScanCard UX: toggles between Fit-to-Scan and Full-Panel zoom and inspects single frame 32x24 matrix',
      (tester) async {
        const mod200 = PvModule(
          id: 'mod-200',
          companyId: 'c1',
          installerTechnicianId: 'u1',
          installerName: 'Marco Silva',
          installerEmail: 'marco@soltech.io',
          name: 'PV Array 200cm',
          macAddress: 'AA:BB:CC:11:22:33',
          isActive: true,
          monitoringStatus: 'active',
          panelLengthCm: 200.0,
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

        final framePixels = List<double?>.filled(768, 38.0);
        final m1 = ModuleMeasurement(
          id: 'm-f1',
          moduleId: 'mod-200',
          inspectionId: 'insp-200',
          sourceEventId: 'evt-1',
          measuredAt: '2026-11-04T12:00:00Z',
          xPositionCm: 0.0,
          maxTemperatureC: 38.0,
          thermalFrame: framePixels,
          voltageV: 18.2,
          currentA: 4.1,
          powerW: 74.62,
          receivedAt: '2026-11-04T12:00:05Z',
        );
        final m2 = ModuleMeasurement(
          id: 'm-f2',
          moduleId: 'mod-200',
          inspectionId: 'insp-200',
          sourceEventId: 'evt-2',
          measuredAt: '2026-11-04T12:00:10Z',
          xPositionCm: 4.0,
          maxTemperatureC: 58.4,
          thermalFrame: framePixels,
          voltageV: 18.2,
          currentA: 4.1,
          powerW: 74.62,
          receivedAt: '2026-11-04T12:00:15Z',
        );

        const anomaly = ConfirmedAnomaly(
          id: 'anom-1',
          moduleId: 'mod-200',
          originMeasurementId: 'm-f2',
          confirmingMeasurementIds: ['m-f2'],
          sourceEventId: 'evt-a1',
          xPositionCm: 4.0,
          detectedAt: '2026-11-04T12:00:15Z',
          status: 'open',
          actuatedAttemptsCount: 0,
          retryPending: false,
        );

        const latestInsp = LatestInspection(
          inspection: ModuleInspection(
            id: 'insp-200',
            moduleId: 'mod-200',
            sourceEventId: 'evt-insp-200',
            type: 'scheduled',
            scheduledFor: '2026-11-04T12:00:00Z',
            status: 'completed',
            baselineTemperatureC: 35.0,
            createdAt: '2026-11-04T12:00:00Z',
            updatedAt: '2026-11-04T12:00:20Z',
          ),
          totalMeasurements: 2,
          confirmedAnomalies: [anomaly],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadiometricScanCard(
                  module: mod200,
                  measurements: [m1, m2],
                  latestInspection: latestInsp,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Initial mode is Fit-to-Scan
        expect(find.text('Zoom: Scan Area'), findsOneWidget);
        expect(find.textContaining('Range: -2.5 to 6.5 cm (9.0 cm)'), findsOneWidget);
        expect(find.textContaining('Rail Scan Coverage: 0.0 to 4.0 cm of 200 cm'), findsOneWidget);

        // 2. Dual-Frame Hotspot Confirmation explainer is visible
        expect(find.byKey(const Key('hotspot_confirmation_summary')), findsOneWidget);
        expect(find.textContaining('H1 at X=4.0 cm confirmed by: F2 (4.0 cm)'), findsOneWidget);

        // 3. Toggle to Full Panel zoom
        await tester.tap(find.byKey(const Key('toggle_zoom_mode')));
        await tester.pumpAndSettle();
        expect(find.text('Zoom: Full Panel'), findsOneWidget);
        expect(find.textContaining('Range: -2.5 to 202.5 cm (205.0 cm)'), findsOneWidget);

        // 4. Toggle back to Scan Area
        await tester.tap(find.byKey(const Key('toggle_zoom_mode')));
        await tester.pumpAndSettle();
        expect(find.text('Zoom: Scan Area'), findsOneWidget);

        // 5. Tap on frame card F2 to open single frame 32x24 inspector
        expect(find.byKey(const Key('selected_frame_inspector')), findsNothing);
        await tester.tap(find.byKey(const Key('thermal_frame_card_2')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('selected_frame_inspector')), findsOneWidget);
        expect(find.byKey(const Key('single_frame_matrix_canvas')), findsOneWidget);
        expect(find.text('Selected Frame (X = 4.0 cm)'), findsOneWidget);

        // 6. Tap Close to dismiss inspector (scroll down to ensure visible if needed)
        await tester.ensureVisible(find.text('Close'));
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('selected_frame_inspector')), findsNothing);
      },
    );
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

      // Modernized Executive Health Banner & Compact Hardware Quick Pills
      expect(find.text('Awaiting Initial Scan'), findsOneWidget);
      expect(find.text('Robot Online'), findsOneWidget);
      expect(find.text('Water OK'), findsOneWidget);

      // Open detailed diagnostics modal via 'Diagnostics' quick pill button
      expect(find.text('Diagnostics'), findsOneWidget);
      await tester.tap(find.text('Diagnostics'));
      await tester.pumpAndSettle();

      // Detailed Diagnostics modal items
      expect(find.text('Limits Check Passed'), findsOneWidget);
      expect(find.text('Thermal Sensor Active'), findsOneWidget);
      expect(find.text('Water Reservoir'), findsOneWidget);
      expect(find.text('ESP32 Connectivity'), findsOneWidget);
    });

    testWidgets(
        'Executive Health Banner shows Solar Array Healthy with baseline when no anomalies',
        (tester) async {
      const activeMod = PvModule(
        id: 'mod-healthy',
        companyId: 'c1',
        installerTechnicianId: 'u1',
        installerName: 'Tech',
        installerEmail: 'tech@ts.com',
        name: 'Healthy Array',
        macAddress: 'AA:BB:CC:11:22:33',
        isActive: true,
        monitoringStatus: 'active',
        inspectionIntervalDays: 7,
        panelLengthCm: 200,
        panelWidthCm: 100,
        panelCount: 3,
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

      final details = const ModuleDetails(
        module: activeMod,
        responsibleManagers: [],
        companyManagers: [],
        companyTechnicians: [],
        companyClients: [],
      );

      final mockRepo = _MockModuleRepo(
        details: details,
        status: const DeviceStatus(
          moduleId: 'mod-healthy',
          macAddress: 'AA:BB:CC:11:22:33',
          monitoringStatus: 'active',
          isConfigured: true,
          isOnline: true,
          waterAvailable: true,
          waterStatus: 'available',
          limitsCheckPassed: true,
          thermalSensorActive: true,
        ),
      );
      mockRepo.mockLatestInspection = const LatestInspection(
        inspection: ModuleInspection(
          id: 'insp-1',
          moduleId: 'mod-healthy',
          sourceEventId: 'evt-1',
          type: 'scheduled',
          baselineTemperatureC: 38.5,
          scheduledFor: '2026-11-01T10:00:00Z',
          status: 'completed',
          createdAt: '2026-11-01T10:00:00Z',
          updatedAt: '2026-11-01T10:30:00Z',
        ),
        totalMeasurements: 5,
        confirmedAnomalies: [],
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
            home: ModuleDetailsScreen(moduleId: 'mod-healthy'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Solar Array Healthy'), findsOneWidget);
      expect(
        find.text(
          'All panels operating within normal baseline temperature (38.5°C). No hotspots detected.',
        ),
        findsOneWidget,
      );
      expect(find.text('HEALTHY'), findsOneWidget);
    });

    testWidgets(
        'Executive Health Banner shows Hotspot on Panel X with relative delta when anomaly confirmed',
        (tester) async {
      const activeMod = PvModule(
        id: 'mod-hotspot',
        companyId: 'c1',
        installerTechnicianId: 'u1',
        installerName: 'Tech',
        installerEmail: 'tech@ts.com',
        name: 'Hotspot Array',
        macAddress: 'AA:BB:CC:44:55:66',
        isActive: true,
        monitoringStatus: 'active',
        inspectionIntervalDays: 7,
        panelLengthCm: 200,
        panelWidthCm: 100,
        panelCount: 3,
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

      final details = const ModuleDetails(
        module: activeMod,
        responsibleManagers: [],
        companyManagers: [],
        companyTechnicians: [],
        companyClients: [],
      );

      final mockRepo = _MockModuleRepo(
        details: details,
        status: const DeviceStatus(
          moduleId: 'mod-hotspot',
          macAddress: 'AA:BB:CC:44:55:66',
          monitoringStatus: 'active',
          isConfigured: true,
          isOnline: true,
          waterAvailable: true,
          waterStatus: 'available',
          limitsCheckPassed: true,
          thermalSensorActive: true,
        ),
      );
      mockRepo.mockLatestInspection = const LatestInspection(
        inspection: ModuleInspection(
          id: 'insp-hotspot',
          moduleId: 'mod-hotspot',
          sourceEventId: 'evt-2',
          type: 'scheduled',
          baselineTemperatureC: 35.0,
          scheduledFor: '2026-11-01T10:00:00Z',
          status: 'completed',
          createdAt: '2026-11-01T10:00:00Z',
          updatedAt: '2026-11-01T10:30:00Z',
        ),
        totalMeasurements: 1,
        confirmedAnomalies: [
          ConfirmedAnomaly(
            id: 'anom-1',
            moduleId: 'mod-hotspot',
            originMeasurementId: 'm-1',
            confirmingMeasurementIds: ['m-1'],
            sourceEventId: 'evt-2',
            panelIndex: 2,
            localXPositionCm: 50.0,
            xPositionCm: 252.5,
            detectedAt: '2026-11-01T10:15:00Z',
            status: 'open',
            actuatedAttemptsCount: 0,
            retryPending: false,
          ),
        ],
      );

      // Add a measurement with 48.0°C (delta +13.0°C above baseline 35.0°C)
      mockRepo.mockAllMeasurements = [
        const ModuleMeasurement(
          id: 'm-1',
          moduleId: 'mod-hotspot',
          inspectionId: 'insp-hotspot',
          sourceEventId: 'evt-2',
          panelIndex: 2,
          localXPositionCm: 50.0,
          measuredAt: '2026-11-01T10:15:00Z',
          xPositionCm: 252.5,
          maxTemperatureC: 48.0,
          receivedAt: '2026-11-01T10:15:05Z',
        ),
      ];

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
            home: ModuleDetailsScreen(moduleId: 'mod-hotspot'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Hotspot on Panel 2'), findsOneWidget);
      expect(
        find.text(
          '+13.0°C above baseline (35.0°C). Robot cleaning recommended.',
        ),
        findsOneWidget,
      );
      expect(find.text('HOTSPOT DETECTED'), findsOneWidget);
      expect(find.text('Relative Delta'), findsOneWidget);
      expect(find.text('+13.0°C'), findsOneWidget);
      expect(find.textContaining('Last inspected:'), findsOneWidget);

      // Verify CleanThermalPreviewCard on Overview
      expect(find.text('Thermal Inspection Map'), findsOneWidget);
      expect(find.text('Open Full Thermal Inspection Studio →'), findsOneWidget);
      expect(find.text('Hotspot +13.0°C ΔT'), findsOneWidget);

      // Verify Hotspot Cleaning Status Card
      expect(find.text('Hotspot Cleaning Status'), findsOneWidget);
      expect(find.text('Automated Cleaning Scheduled'), findsOneWidget);

      // Verify 4 Key Telemetry Metrics
      expect(find.text('Peak Temperature'), findsOneWidget);
      expect(find.text('48.0°C'), findsNWidgets(2));
      expect(find.text('Baseline Temperature'), findsOneWidget);
      expect(find.text('35.0°C'), findsNWidgets(2));
      expect(find.text('DC Output'), findsOneWidget);
      expect(find.text('Active Power'), findsOneWidget);
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

    testWidgets(
        'Overview isolates current inspection measurements from historical inspections and hides cool-down card when cleaning is already resolved',
        (tester) async {
      const activeMod = PvModule(
        id: 'mod-iso',
        companyId: 'c1',
        installerTechnicianId: 'u1',
        installerName: 'Tech',
        installerEmail: 'tech@ts.com',
        name: 'Isolated Array',
        macAddress: 'AA:BB:CC:99:88:77',
        isActive: true,
        monitoringStatus: 'active',
        inspectionIntervalDays: 7,
        panelLengthCm: 100,
        panelWidthCm: 100,
        panelCount: 2,
        panelSpacingCm: 2.0,
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

      const details = ModuleDetails(
        module: activeMod,
        responsibleManagers: [],
        companyManagers: [],
        companyTechnicians: [],
        companyClients: [],
      );

      final mockRepo = _MockModuleRepo(
        details: details,
        status: const DeviceStatus(
          moduleId: 'mod-iso',
          macAddress: 'AA:BB:CC:99:88:77',
          monitoringStatus: 'active',
          isConfigured: true,
          isOnline: true,
          waterAvailable: true,
          waterStatus: 'available',
          limitsCheckPassed: true,
          thermalSensorActive: true,
        ),
      );

      // Latest inspection is healthy with baseline 30.0°C
      mockRepo.mockLatestInspection = const LatestInspection(
        inspection: ModuleInspection(
          id: 'insp-current',
          moduleId: 'mod-iso',
          sourceEventId: 'evt-current',
          type: 'scheduled',
          baselineTemperatureC: 30.0,
          scheduledFor: '2026-11-07T12:00:00Z',
          status: 'completed',
          createdAt: '2026-11-07T12:00:00Z',
          updatedAt: '2026-11-07T12:15:00Z',
        ),
        totalMeasurements: 1,
        confirmedAnomalies: [],
      );

      // List contains current healthy measurement (32.0°C) AND old resolved hotspot measurement (68.0°C)
      mockRepo.mockAllMeasurements = [
        const ModuleMeasurement(
          id: 'm-current',
          moduleId: 'mod-iso',
          inspectionId: 'insp-current',
          sourceEventId: 'evt-current',
          panelIndex: 1,
          localXPositionCm: 20.0,
          measuredAt: '2026-11-07T12:10:00Z',
          xPositionCm: 20.0,
          maxTemperatureC: 32.0,
          receivedAt: '2026-11-07T12:10:05Z',
        ),
        const ModuleMeasurement(
          id: 'm-old-hotspot',
          moduleId: 'mod-iso',
          inspectionId: 'insp-old',
          sourceEventId: 'evt-old',
          panelIndex: 1,
          localXPositionCm: 20.0,
          measuredAt: '2026-11-01T10:15:00Z',
          xPositionCm: 20.0,
          maxTemperatureC: 68.0,
          receivedAt: '2026-11-01T10:15:05Z',
        ),
      ];

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
            home: ModuleDetailsScreen(moduleId: 'mod-iso'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Must show 32.0°C peak reading from current inspection, NEVER 68.0°C from old inspection
      expect(find.text('32.0°C'), findsWidgets);
      expect(find.text('68.0°C'), findsNothing);
      expect(find.text('ELEVATED'), findsNothing);

      // Default mock cleanings has status='completed' and postCleaningResult='resolved';
      // Cool-down card must NOT be rendered on a healthy resolved module.
      expect(find.text('COOL-DOWN (30M)'), findsNothing);
    });
  });
}

