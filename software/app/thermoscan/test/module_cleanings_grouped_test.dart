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
    this.mockInspections = const [],
    this.mockCleanings = const [],
  }) : super(dio: Dio());

  final ModuleDetails details;
  final List<ModuleInspection> mockInspections;
  final List<ModuleCleaning> mockCleanings;

  @override
  Future<ModuleDetails> getModuleDetails(String moduleId) async => details;

  @override
  Future<List<ModuleInspection>> listInspections({
    required String moduleId,
    int limit = 20,
    int offset = 0,
  }) async =>
      mockInspections;

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
    id: 'mod-group',
    companyId: 'c1',
    installerTechnicianId: 'u1',
    installerName: 'Tech 1',
    installerEmail: 'tech@thermoscan.com',
    name: 'Array North',
    macAddress: 'AA:BB:CC:DD:EE:10',
    isActive: true,
    monitoringStatus: 'active',
    panelLengthCm: 68.0,
    panelCount: 2,
    panelSpacingCm: 2.0,
    totalLengthCm: 138.0,
    inspectionIntervalDays: 7,
    createdAt: '2026-11-20T10:00:00Z',
    updatedAt: '2026-11-20T10:00:00Z',
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

  testWidgets(
    'Groups 3+ cleanings from same inspection with aggregate metrics, collapsed by default, and shows Manual Wash separately',
    (tester) async {
      final inspections = <ModuleInspection>[
        const ModuleInspection(
          id: 'insp-1',
          moduleId: 'mod-group',
          sourceEventId: 'insp-evt-1',
          type: 'scheduled',
          scheduledFor: '2026-11-24T13:00:00Z',
          startedAt: '2026-11-24T13:00:00Z',
          finishedAt: '2026-11-24T13:05:00Z',
          baselineTemperatureC: 30.0,
          status: 'completed',
          createdAt: '2026-11-24T13:00:00Z',
          updatedAt: '2026-11-24T13:05:00Z',
          confirmedAnomalies: [
            ConfirmedAnomaly(
              id: 'anom-1',
              moduleId: 'mod-group',
              sourceEventId: 'evt-a1',
              xPositionCm: 15.0,
              detectedAt: '2026-11-24T13:01:00Z',
              status: 'resolved',
              actuatedAttemptsCount: 1,
              retryPending: false,
              panelIndex: 1,
              originMeasurementId: 'm1',
              confirmingMeasurementIds: [],
            ),
            ConfirmedAnomaly(
              id: 'anom-2',
              moduleId: 'mod-group',
              sourceEventId: 'evt-a2',
              xPositionCm: 25.0,
              detectedAt: '2026-11-24T13:02:00Z',
              status: 'resolved',
              actuatedAttemptsCount: 1,
              retryPending: false,
              panelIndex: 1,
              originMeasurementId: 'm2',
              confirmingMeasurementIds: [],
            ),
            ConfirmedAnomaly(
              id: 'anom-3',
              moduleId: 'mod-group',
              sourceEventId: 'evt-a3',
              xPositionCm: 85.0,
              detectedAt: '2026-11-24T13:03:00Z',
              status: 'resolved',
              actuatedAttemptsCount: 1,
              retryPending: false,
              panelIndex: 2,
              originMeasurementId: 'm3',
              confirmingMeasurementIds: [],
            ),
          ],
        ),
      ];

      final cleanings = <ModuleCleaning>[
        const ModuleCleaning(
          id: 'c-1',
          moduleId: 'mod-group',
          anomalyEventId: 'anom-1',
          sourceEventId: 'ce-1',
          targetXPositionCm: 15.0,
          pumpActuated: true,
          status: 'verified',
          postCleaningResult: 'resolved',
          panelIndex: 1,
          attemptNumber: 1,
          durationSeconds: 10.0,
          estimatedWaterVolumeMl: 120.0,
          startedAt: '2026-11-24T13:06:00Z',
          createdAt: '2026-11-24T13:06:00Z',
        ),
        const ModuleCleaning(
          id: 'c-2',
          moduleId: 'mod-group',
          anomalyEventId: 'anom-2',
          sourceEventId: 'ce-2',
          targetXPositionCm: 25.0,
          pumpActuated: true,
          status: 'verified',
          postCleaningResult: 'resolved',
          panelIndex: 1,
          attemptNumber: 1,
          durationSeconds: 12.0,
          estimatedWaterVolumeMl: 150.0,
          startedAt: '2026-11-24T13:07:00Z',
          createdAt: '2026-11-24T13:07:00Z',
        ),
        const ModuleCleaning(
          id: 'c-3',
          moduleId: 'mod-group',
          anomalyEventId: 'anom-3',
          sourceEventId: 'ce-3',
          targetXPositionCm: 85.0,
          pumpActuated: true,
          status: 'verified',
          postCleaningResult: 'resolved',
          panelIndex: 2,
          attemptNumber: 1,
          durationSeconds: 8.0,
          estimatedWaterVolumeMl: 100.0,
          startedAt: '2026-11-24T13:08:00Z',
          createdAt: '2026-11-24T13:08:00Z',
        ),
        const ModuleCleaning(
          id: 'c-manual',
          moduleId: 'mod-group',
          anomalyEventId: 'manual-unlinked-id',
          sourceEventId: 'ce-manual',
          targetXPositionCm: 40.0,
          pumpActuated: true,
          status: 'completed',
          postCleaningResult: 'resolved',
          panelIndex: 1,
          attemptNumber: 1,
          durationSeconds: 5.0,
          estimatedWaterVolumeMl: 60.0,
          startedAt: '2026-11-24T12:00:00Z',
          createdAt: '2026-11-24T12:00:00Z',
        ),
      ];

      final mockRepo = _MockModuleRepo(
        details: testDetails,
        mockInspections: inspections,
        mockCleanings: cleanings,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
            authRepositoryProvider.overrideWithValue(_MockAuthRepo()),
            authControllerProvider
                .overrideWith((ref) => _FakeAuthController(testUser)),
            moduleRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: ModuleCleaningsScreen(moduleId: 'mod-group'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Grouped card is rendered with aggregate metrics
      expect(
        find.byKey(const Key('cleaning_group_card_insp-1')),
        findsOneWidget,
      );
      expect(find.text('3/3 Resolved'), findsOneWidget);
      expect(find.text('3 washes'), findsOneWidget);
      expect(find.text('30.0 s'), findsOneWidget);

      // Collapsed by default for 3+ washes
      expect(find.text('Show 3 washes'), findsOneWidget);
      expect(find.textContaining('Panel 2 • Wash Attempt #1'), findsNothing);

      // Standalone manual wash is shown separately
      expect(find.text('Manual Wash'), findsOneWidget);

      // Expand the grouped washes
      await tester.tap(find.byKey(const Key('show_washes_tile_insp-1')));
      await tester.pumpAndSettle();

      // Individual washes are now visible
      expect(find.textContaining('Panel 2 • Wash Attempt #1'), findsOneWidget);
      expect(find.textContaining('X = 85.0 cm'), findsOneWidget);
    },
  );
}
