import 'dart:convert';
import 'dart:typed_data';

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
import 'package:thermoscan/features/modules/presentation/module_details_screen.dart';
import 'package:thermoscan/features/modules/presentation/widgets/thermal_matrix_inspector_modal.dart';

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

class _CapturingHttpAdapter implements HttpClientAdapter {
  _CapturingHttpAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);
}

class _LocalizedMockRepo extends ModuleRepository {
  _LocalizedMockRepo({
    required this.details,
    required DeviceStatus initialStatus,
    this.localizedReading,
  })  : currentStatus = initialStatus,
        super(dio: Dio());

  final ModuleDetails details;
  DeviceStatus currentStatus;
  LocalizedReading? localizedReading;

  int triggerManualReadingCalls = 0;
  double? lastTriggeredXCm;
  int getLocalizedReadingCalls = 0;

  @override
  Future<ModuleDetails> getModuleDetails(String moduleId) async => details;

  @override
  Future<DeviceStatus> getDeviceStatus({required String moduleId}) async =>
      currentStatus;

  @override
  Future<LatestInspection?> getLatestInspection({
    required String moduleId,
  }) async =>
      null;

  @override
  Future<List<ModuleMeasurement>> listMeasurements({
    required String moduleId,
    int limit = 200,
    int offset = 0,
    int? panelIndex,
  }) async =>
      const [];

  @override
  Future<List<ModuleCleaning>> listCleanings({
    required String moduleId,
    int limit = 50,
    int offset = 0,
  }) async =>
      const [];

  @override
  Future<List<ModuleInspection>> listInspections({
    required String moduleId,
    int limit = 100,
    int offset = 0,
  }) async =>
      const [];

  @override
  Future<void> triggerManualReading({
    required String moduleId,
    required double targetXPositionCm,
  }) async {
    triggerManualReadingCalls++;
    lastTriggeredXCm = targetXPositionCm;
  }

  @override
  Future<LocalizedReading> getLocalizedReading(String moduleId) async {
    getLocalizedReadingCalls++;
    return localizedReading!;
  }
}

List<double> _buildTestMatrix768({
  double baseTemp = 30.0,
  int hotCol = 20,
  int hotRow = 12,
  double hotTemp = 62.5,
  int coolCol = 2,
  int coolRow = 2,
  double coolTemp = 22.0,
}) {
  final matrix = List<double>.filled(768, baseTemp);
  matrix[hotRow * 32 + hotCol] = hotTemp;
  matrix[coolRow * 32 + coolCol] = coolTemp;
  return matrix;
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

  const testModule = PvModule(
    id: 'mod-loc-1',
    companyId: 'c1',
    installerTechnicianId: 'u1',
    installerName: 'Marco Silva',
    installerEmail: 'marco@soltech.io',
    name: 'Localized Array 1',
    macAddress: 'AA:BB:CC:DD:EE:01',
    isActive: true,
    monitoringStatus: 'active',
    panelCount: 2,
    panelLengthCm: 100.0,
    panelSpacingCm: 2.0,
    totalLengthCm: 202.0,
    inspectionIntervalDays: 7,
    createdAt: '2026-11-01T10:00:00Z',
    updatedAt: '2026-11-01T10:00:00Z',
    userRelationship: 'installer_technician',
    permissions: ModulePermissions(
      canEditGeometryAndLocation: true,
      canEditSolarAngle: true,
      canEditInterval: true,
      canManageAccess: true,
      canDelete: true,
    ),
  );

  const testDetails = ModuleDetails(
    module: testModule,
    responsibleManagers: [],
    companyManagers: [],
    companyTechnicians: [],
    companyClients: [],
  );

  group('LocalizedReading & DeviceStatus Domain Parsing', () {
    test('LocalizedReading.fromJson parses full 768-element matrix and fields', () {
      final matrix = _buildTestMatrix768(
        baseTemp: 32.0,
        hotCol: 10,
        hotRow: 5,
        hotTemp: 58.4,
        coolCol: 0,
        coolRow: 0,
        coolTemp: 24.5,
      );

      final reading = LocalizedReading.fromJson({
        'module_id': 'mod-123',
        'x_position_cm': 42.5,
        'panel_index': 2,
        'measured_at': '2026-11-24T12:00:00Z',
        'localized_reading_at': '2026-11-24T12:00:02Z',
        'min_temperature_c': 24.5,
        'max_temperature_c': 58.4,
        'avg_temperature_c': 32.0,
        'thermal_matrix': matrix,
      });

      expect(reading.moduleId, 'mod-123');
      expect(reading.xPositionCm, 42.5);
      expect(reading.panelIndex, 2);
      expect(reading.measuredAt, '2026-11-24T12:00:00Z');
      expect(reading.localizedReadingAt, '2026-11-24T12:00:02Z');
      expect(reading.minTemperatureC, 24.5);
      expect(reading.maxTemperatureC, 58.4);
      expect(reading.avgTemperatureC, 32.0);
      expect(reading.thermalMatrix.length, 768);
      expect(reading.thermalMatrix[5 * 32 + 10], 58.4);
      expect(reading.effectiveTimestamp, '2026-11-24T12:00:02Z');
    });

    test('LocalizedReading.fromJson computes min/avg/max fallback and safely handles nulls', () {
      final raw = List<dynamic>.filled(768, 30.0);
      raw[0] = 20.0;
      raw[1] = 40.0;
      raw[2] = null;

      final reading = LocalizedReading.fromJson({
        'module_id': 'mod-456',
        'x_position_cm': '15.0',
        'measured_at': '2026-11-24T12:10:00Z',
        'thermal_matrix': raw,
      });

      expect(reading.xPositionCm, 15.0);
      expect(reading.panelIndex, isNull);
      expect(reading.thermalMatrix.length, 768);
      expect(reading.thermalMatrix[2].isNaN, isTrue);
      expect(reading.minTemperatureC, 20.0);
      expect(reading.maxTemperatureC, 40.0);
      expect(reading.avgTemperatureC, closeTo(30.0, 0.05));
    });

    test('DeviceStatus and PvModule parse manual_reading_* and localized_reading_* fields', () {
      final status = DeviceStatus.fromJson({
        'module_id': 'mod-1',
        'mac_address': 'AA:BB:CC:DD:EE:01',
        'limits_check_passed': true,
        'thermal_sensor_active': true,
        'manual_reading_pending': true,
        'manual_reading_target_x_cm': 64.5,
        'localized_reading_at': '2026-11-24T11:30:00Z',
        'localized_reading_x_cm': 42.0,
      });

      expect(status.manualReadingPending, isTrue);
      expect(status.manualReadingTargetXCm, 64.5);
      expect(status.localizedReadingAt, '2026-11-24T11:30:00Z');
      expect(status.localizedReadingXCm, 42.0);

      final defaultStatus = DeviceStatus.fromJson({
        'module_id': 'mod-1',
        'mac_address': 'AA:BB:CC:DD:EE:01',
      });
      expect(defaultStatus.manualReadingPending, isFalse);
      expect(defaultStatus.manualReadingTargetXCm, isNull);
      expect(defaultStatus.localizedReadingAt, isNull);
      expect(defaultStatus.localizedReadingXCm, isNull);

      final mod = PvModule.fromJson({
        'id': 'mod-1',
        'manual_reading_pending': true,
        'manual_reading_target_x_cm': 18.0,
        'localized_reading_at': '2026-11-24T11:30:00Z',
        'localized_reading_x_cm': 42.0,
      });
      expect(mod.manualReadingPending, isTrue);
      expect(mod.manualReadingTargetXCm, 18.0);
      expect(mod.localizedReadingAt, '2026-11-24T11:30:00Z');
      expect(mod.localizedReadingXCm, 42.0);
    });
  });

  group('ModuleRepository Localized Reading API', () {
    test('triggerManualReading posts target_x_position_cm and getLocalizedReading parses response', () async {
      RequestOptions? lastPostOptions;
      final matrix = _buildTestMatrix768();
      final dio = Dio();
      dio.httpClientAdapter = _CapturingHttpAdapter((options) async {
        if (options.method == 'POST' &&
            options.path == '/modules/mod-1/trigger-reading') {
          lastPostOptions = options;
          return ResponseBody.fromString(
            jsonEncode({'status': 'pending'}),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        if (options.method == 'GET' &&
            options.path == '/modules/mod-1/localized-reading') {
          return ResponseBody.fromString(
            jsonEncode({
              'localized_reading': {
                'module_id': 'mod-1',
                'x_position_cm': 42.5,
                'panel_index': 1,
                'measured_at': '2026-11-24T12:00:00Z',
                'localized_reading_at': '2026-11-24T12:00:02Z',
                'min_temperature_c': 22.0,
                'max_temperature_c': 62.5,
                'avg_temperature_c': 30.1,
                'thermal_matrix': matrix,
              },
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{}', 404);
      });

      final repo = ModuleRepository(dio: dio);
      await repo.triggerManualReading(
        moduleId: 'mod-1',
        targetXPositionCm: 42.5,
      );
      expect(lastPostOptions?.data, {'target_x_position_cm': 42.5});

      final reading = await repo.getLocalizedReading('mod-1');
      expect(reading.moduleId, 'mod-1');
      expect(reading.xPositionCm, 42.5);
      expect(reading.panelIndex, 1);
      expect(reading.thermalMatrix.length, 768);
      expect(reading.maxTemperatureC, 62.5);
    });
  });

  group('showLocalizedReadingDialog & Pixel Inspection', () {
    testWidgets('renders header, summary metrics, and updates pixel readout on tap & drag', (tester) async {
      final matrix = _buildTestMatrix768(
        baseTemp: 31.0,
        hotCol: 20,
        hotRow: 12,
        hotTemp: 62.5,
        coolCol: 1,
        coolRow: 1,
        coolTemp: 21.4,
      );
      // Set a distinct pixel near bottom-right corner (col 31, row 23)
      matrix[23 * 32 + 31] = 44.8;

      final reading = LocalizedReading(
        moduleId: 'mod-loc-1',
        xPositionCm: 42.5,
        panelIndex: 2,
        measuredAt: '2026-11-24T12:00:00Z',
        localizedReadingAt: '2026-11-24T12:00:03Z',
        minTemperatureC: 21.4,
        maxTemperatureC: 62.5,
        avgTemperatureC: 31.0,
        thermalMatrix: matrix,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showLocalizedReadingDialog(context, reading),
                  child: const Text('Open Reading'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Reading'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('localized_reading_dialog')), findsOneWidget);
      expect(find.text('Localized Thermal Reading'), findsOneWidget);
      expect(find.text('X = 42.5 cm (Panel P2)'), findsOneWidget);

      expect(
        find.descendant(
          of: find.byKey(const Key('localized_stat_min')),
          matching: find.text('21.4°C'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('localized_stat_avg')),
          matching: find.text('31.0°C'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('localized_stat_max')),
          matching: find.text('62.5°C'),
        ),
        findsOneWidget,
      );

      // Initially defaults to peak pixel (Col 20, Row 12)
      final telemetry = find.byKey(const Key('selected_pixel_telemetry'));
      expect(
        find.descendant(of: telemetry, matching: find.text('Pixel (Col 20, Row 12)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: telemetry, matching: find.text('62.5 °C')),
        findsOneWidget,
      );

      // Tap near top-left cell (Col 1, Row 1) -> 21.4 °C
      final canvasFinder = find.byKey(const Key('single_frame_matrix_canvas'));
      final rect = tester.getRect(canvasFinder);
      final cell1x1Pos = Offset(
        rect.left + (1.5 / 32.0) * rect.width,
        rect.top + (1.5 / 24.0) * rect.height,
      );
      await tester.tapAt(cell1x1Pos);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: telemetry, matching: find.text('Pixel (Col 1, Row 1)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: telemetry, matching: find.text('21.4 °C')),
        findsOneWidget,
      );

      // Drag across canvas to bottom-right corner (Col 31, Row 23) -> 44.8 °C
      final bottomRightTarget = Offset(
        rect.right - 2.0,
        rect.bottom - 2.0,
      );
      await tester.dragFrom(
        cell1x1Pos,
        bottomRightTarget - cell1x1Pos,
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: telemetry, matching: find.text('Pixel (Col 31, Row 23)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: telemetry, matching: find.text('44.8 °C')),
        findsOneWidget,
      );

      // Close dialog cleanly
      await tester.tap(find.byKey(const Key('localized_reading_close_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('localized_reading_dialog')), findsNothing);
    });
  });

  group('ModuleDetailsScreen 3-dot Action Bottom Sheet & Localized Reading Flow', () {
    testWidgets('3-dot sheet displays grouped sections and Last chip opens stored reading', (tester) async {
      final matrix = _buildTestMatrix768(hotTemp: 54.0);
      final repo = _LocalizedMockRepo(
        details: testDetails,
        initialStatus: const DeviceStatus(
          moduleId: 'mod-loc-1',
          macAddress: 'AA:BB:CC:DD:EE:01',
          monitoringStatus: 'active',
          isConfigured: true,
          isOnline: true,
          waterAvailable: true,
          waterStatus: 'ok',
          limitsCheckPassed: true,
          thermalSensorActive: true,
          localizedReadingAt: '2026-11-24T10:00:00Z',
          localizedReadingXCm: 42.0,
        ),
        localizedReading: LocalizedReading(
          moduleId: 'mod-loc-1',
          xPositionCm: 42.0,
          panelIndex: 1,
          measuredAt: '2026-11-24T10:00:00Z',
          localizedReadingAt: '2026-11-24T10:00:01Z',
          minTemperatureC: 22.0,
          maxTemperatureC: 54.0,
          avgTemperatureC: 30.0,
          thermalMatrix: matrix,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith(
              (ref) => _FakeAuthController(techUser),
            ),
            moduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ModuleDetailsScreen(moduleId: 'mod-loc-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('module_actions_bottom_sheet')), findsOneWidget);
      expect(find.text('ROBOT CONTROLS'), findsOneWidget);
      expect(find.text('DIAGNOSTICS'), findsOneWidget);
      expect(find.text('DANGER ZONE'), findsOneWidget);
      expect(find.text('Run Scan Now'), findsOneWidget);
      expect(find.text('Localized Reading'), findsOneWidget);
      expect(find.text('Last: 42 cm'), findsOneWidget);
      expect(find.text('Manual Cleaning'), findsOneWidget);
      expect(find.text('State Logs'), findsOneWidget);
      expect(find.text('Robot Connection Check'), findsOneWidget);
      expect(find.text('Abort & Reset Routine'), findsOneWidget);
      expect(find.text('Delete Module'), findsOneWidget);

      // Tap Last: 42 cm chip -> fetches getLocalizedReading and opens 32x24 pop-up
      await tester.tap(
        find.byKey(const Key('action_sheet_view_last_localized_reading')),
      );
      await tester.pumpAndSettle();

      expect(repo.getLocalizedReadingCalls, 1);
      expect(find.byKey(const Key('localized_reading_dialog')), findsOneWidget);
      expect(find.text('X = 42.0 cm (Panel P1)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('localized_reading_close_button')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('hides Last chip when null, validates X bounds, triggers reading, and auto-opens dialog on new timestamp', (tester) async {
      final matrix = _buildTestMatrix768(hotTemp: 59.3);
      final repo = _LocalizedMockRepo(
        details: testDetails,
        initialStatus: const DeviceStatus(
          moduleId: 'mod-loc-1',
          macAddress: 'AA:BB:CC:DD:EE:01',
          monitoringStatus: 'active',
          isConfigured: true,
          isOnline: true,
          waterAvailable: true,
          waterStatus: 'ok',
          limitsCheckPassed: true,
          thermalSensorActive: true,
          localizedReadingAt: null,
        ),
        localizedReading: LocalizedReading(
          moduleId: 'mod-loc-1',
          xPositionCm: 48.0,
          panelIndex: 1,
          measuredAt: '2026-11-24T12:15:00Z',
          localizedReadingAt: '2026-11-24T12:15:02Z',
          minTemperatureC: 22.0,
          maxTemperatureC: 59.3,
          avgTemperatureC: 30.0,
          thermalMatrix: matrix,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith(
              (ref) => _FakeAuthController(techUser),
            ),
            moduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ModuleDetailsScreen(moduleId: 'mod-loc-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('action_sheet_view_last_localized_reading')),
        findsNothing,
      );

      // Tap Localized Reading to open position picker
      await tester.tap(find.byKey(const Key('action_sheet_localized_reading')));
      await tester.pumpAndSettle();

      // Negative value rejected
      await tester.enterText(
        find.byKey(const Key('target_x_position_field')),
        '-5',
      );
      await tester.tap(find.byKey(const Key('confirm_target_x_button')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid non-negative number'), findsOneWidget);

      // Value above rail length (202 cm) rejected
      await tester.enterText(
        find.byKey(const Key('target_x_position_field')),
        '250',
      );
      await tester.tap(find.byKey(const Key('confirm_target_x_button')));
      await tester.pumpAndSettle();
      expect(find.text('Must be between 0 and 202.0 cm'), findsOneWidget);

      // Value inside 2 cm gap (100..102) rejected
      await tester.enterText(
        find.byKey(const Key('target_x_position_field')),
        '101',
      );
      await tester.tap(find.byKey(const Key('confirm_target_x_button')));
      await tester.pumpAndSettle();
      expect(
        find.text('Target falls inside an inter-panel gap'),
        findsOneWidget,
      );

      // Valid value confirmed -> calls triggerManualReading & shows capturing banner
      await tester.enterText(
        find.byKey(const Key('target_x_position_field')),
        '48.0',
      );
      await tester.tap(find.byKey(const Key('confirm_target_x_button')));
      await tester.pumpAndSettle();

      expect(repo.triggerManualReadingCalls, 1);
      expect(repo.lastTriggeredXCm, 48.0);
      expect(
        find.byKey(const Key('localized_reading_capturing_banner')),
        findsOneWidget,
      );
      expect(
        find.text('Capturing localized thermal frame at 48.0 cm...'),
        findsOneWidget,
      );

      // Robot completes localized reading -> next 4s poll returns new localizedReadingAt
      repo.currentStatus = const DeviceStatus(
        moduleId: 'mod-loc-1',
        macAddress: 'AA:BB:CC:DD:EE:01',
        monitoringStatus: 'active',
        isConfigured: true,
        isOnline: true,
        waterAvailable: true,
        waterStatus: 'ok',
        limitsCheckPassed: true,
        thermalSensorActive: true,
        localizedReadingAt: '2026-11-24T12:15:02Z',
        localizedReadingXCm: 48.0,
      );

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Capturing banner clears and dialog auto-opens!
      expect(
        find.byKey(const Key('localized_reading_capturing_banner')),
        findsNothing,
      );
      expect(repo.getLocalizedReadingCalls, 1);
      expect(find.byKey(const Key('localized_reading_dialog')), findsOneWidget);
      expect(find.text('X = 48.0 cm (Panel P1)'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('localized_stat_max')),
          matching: find.text('59.3°C'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('localized_reading_close_button')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('60s timeout fallback clears capturing banner when no reading arrives', (tester) async {
      final repo = _LocalizedMockRepo(
        details: testDetails,
        initialStatus: const DeviceStatus(
          moduleId: 'mod-loc-1',
          macAddress: 'AA:BB:CC:DD:EE:01',
          monitoringStatus: 'active',
          isConfigured: true,
          isOnline: true,
          waterAvailable: true,
          waterStatus: 'ok',
          limitsCheckPassed: true,
          thermalSensorActive: true,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider.overrideWith(
              (ref) => _FakeAuthController(techUser),
            ),
            moduleRepositoryProvider.overrideWithValue(repo),
          ],
          child: const MaterialApp(
            home: ModuleDetailsScreen(moduleId: 'mod-loc-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action_sheet_localized_reading')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('target_x_position_field')),
        '30',
      );
      await tester.tap(find.byKey(const Key('confirm_target_x_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('localized_reading_capturing_banner')),
        findsOneWidget,
      );

      // Advance 61 seconds without updating localizedReadingAt
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('localized_reading_capturing_banner')),
        findsNothing,
      );
      expect(repo.getLocalizedReadingCalls, 0);
      expect(find.byKey(const Key('localized_reading_dialog')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
