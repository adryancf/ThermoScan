import 'dart:convert';

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
import 'package:thermoscan/features/modules/presentation/services/thermal_pdf_report_service.dart';
import 'package:thermoscan/features/modules/presentation/widgets/export_pdf_report_sheet.dart';

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
    this.mockMeasurements = const [],
    this.mockLatest,
  }) : super(dio: Dio());

  final ModuleDetails details;
  final List<ModuleInspection> mockInspections;
  final List<ModuleCleaning> mockCleanings;
  final List<ModuleMeasurement> mockMeasurements;
  final LatestInspection? mockLatest;

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

  @override
  Future<List<ModuleMeasurement>> listMeasurements({
    required String moduleId,
    int limit = 50,
    int offset = 0,
    int? panelIndex,
  }) async =>
      mockMeasurements;

  @override
  Future<LatestInspection?> getLatestInspection({
    required String moduleId,
  }) async =>
      mockLatest;
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
    id: 'mod-pdf-01',
    companyId: 'c1',
    installerTechnicianId: 'u1',
    installerName: 'Tech 1',
    installerEmail: 'tech@thermoscan.com',
    name: 'Array Roof South',
    macAddress: 'AA:BB:CC:DD:EE:99',
    isActive: true,
    monitoringStatus: 'active',
    panelLengthCm: 26.0,
    panelWidthCm: 20.0,
    panelCount: 2,
    panelSpacingCm: 4.0,
    totalLengthCm: 56.0,
    tiltDeg: 22.0,
    azimuthDeg: 0.0,
    hotspotThresholdDeltaC: 8.0,
    inspectionIntervalDays: 7,
    reservoirNominalCapacityMl: 2000,
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

  final healthyFrame = List<double?>.filled(768, 32.0);
  final hotspotFrame = List<double?>.filled(768, 33.0)..[12 * 32 + 18] = 48.5;

  final insp1 = const ModuleInspection(
    id: 'insp-healthy-1',
    moduleId: 'mod-pdf-01',
    sourceEventId: 'evt-i1',
    type: 'scheduled',
    scheduledFor: '2026-11-24T17:00:00Z',
    startedAt: '2026-11-24T17:00:00Z',
    finishedAt: '2026-11-24T17:02:00Z',
    baselineTemperatureC: 31.5,
    status: 'completed',
    createdAt: '2026-11-24T17:00:00Z',
    updatedAt: '2026-11-24T17:02:00Z',
    panelResults: [
      InspectionPanelResult(
        inspectionId: 'insp-healthy-1',
        moduleId: 'mod-pdf-01',
        panelIndex: 1,
        baselineTemperatureC: 31.2,
        truncatedByMemory: false,
        finishedAt: '2026-11-24T17:01:00Z',
        createdAt: '2026-11-24T17:01:00Z',
      ),
      InspectionPanelResult(
        inspectionId: 'insp-healthy-1',
        moduleId: 'mod-pdf-01',
        panelIndex: 2,
        baselineTemperatureC: 31.8,
        truncatedByMemory: false,
        finishedAt: '2026-11-24T17:02:00Z',
        createdAt: '2026-11-24T17:02:00Z',
      ),
    ],
  );

  final insp2 = const ModuleInspection(
    id: 'insp-hotspot-2',
    moduleId: 'mod-pdf-01',
    sourceEventId: 'evt-i2',
    type: 'scheduled',
    scheduledFor: '2026-11-24T14:38:00Z',
    startedAt: '2026-11-24T14:38:00Z',
    finishedAt: '2026-11-24T14:40:00Z',
    baselineTemperatureC: 33.3,
    status: 'completed',
    createdAt: '2026-11-24T14:38:00Z',
    updatedAt: '2026-11-24T14:40:00Z',
    confirmedAnomalies: [
      ConfirmedAnomaly(
        id: 'anom-1',
        moduleId: 'mod-pdf-01',
        sourceEventId: 'evt-a1',
        xPositionCm: 18.0,
        detectedAt: '2026-11-24T14:39:00Z',
        status: 'resolved',
        actuatedAttemptsCount: 1,
        retryPending: false,
        panelIndex: 1,
        localXPositionCm: 18.0,
        originMeasurementId: 'm-hot',
        confirmingMeasurementIds: [],
      ),
    ],
  );

  final measurements = <ModuleMeasurement>[
    ModuleMeasurement(
      id: 'm-ok-1',
      moduleId: 'mod-pdf-01',
      inspectionId: 'insp-healthy-1',
      sourceEventId: 'me-1',
      xPositionCm: 12.0,
      maxTemperatureC: 34.0,
      panelIndex: 1,
      voltageV: 4.82,
      currentA: 0.0055,
      powerW: 0.0265,
      thermalFrame: healthyFrame,
      measuredAt: '2026-11-24T17:01:00Z',
      receivedAt: '2026-11-24T17:01:05Z',
    ),
    ModuleMeasurement(
      id: 'm-hot',
      moduleId: 'mod-pdf-01',
      inspectionId: 'insp-hotspot-2',
      sourceEventId: 'me-2',
      xPositionCm: 18.0,
      maxTemperatureC: 48.5,
      panelIndex: 1,
      voltageV: 4.75,
      currentA: 0.0051,
      powerW: 0.0242,
      thermalFrame: hotspotFrame,
      measuredAt: '2026-11-24T14:39:00Z',
      receivedAt: '2026-11-24T14:39:05Z',
    ),
  ];

  final cleanings = <ModuleCleaning>[
    const ModuleCleaning(
      id: 'clean-1',
      moduleId: 'mod-pdf-01',
      anomalyEventId: 'anom-1',
      sourceEventId: 'ce-1',
      targetXPositionCm: 18.0,
      pumpActuated: true,
      status: 'verified',
      postCleaningResult: 'resolved',
      panelIndex: 1,
      attemptNumber: 1,
      durationSeconds: 10.0,
      estimatedWaterVolumeMl: 120.0,
      startedAt: '2026-11-24T14:41:00Z',
      createdAt: '2026-11-24T14:41:00Z',
    ),
  ];

  group('ThermalPdfReportService Unit Tests', () {
    test('Generates valid English single-inspection PDF bytes', () async {
      final bundles = InspectionRoutineBundle.buildBundles(
        allInspections: [insp2],
        allCleanings: cleanings,
        allMeasurements: measurements,
      );

      final bytes = await ThermalPdfReportService.buildReportBytes(
        module: testModule,
        entries: [
          PdfInspectionEntry(
            bundle: bundles.first,
            routineMeasurements: bundles.first.routineMeasurements,
          ),
        ],
        generatedByName: 'Tech 1',
        generatedByRole: 'technician',
        includeThermalImages: false,
      );

      expect(bytes.length, greaterThan(1500));
      expect(utf8.decode(bytes.sublist(0, 5)), equals('%PDF-'));
    });

    test(
      'Generates valid English multi-inspection consolidated PDF bytes',
      () async {
        final bundles = InspectionRoutineBundle.buildBundles(
          allInspections: [insp1, insp2],
          allCleanings: cleanings,
          allMeasurements: measurements,
        );

        final bytes = await ThermalPdfReportService.buildReportBytes(
          module: testModule,
          entries: [
            for (final b in bundles)
              PdfInspectionEntry(
                bundle: b,
                routineMeasurements: b.routineMeasurements,
              ),
          ],
          generatedByName: 'Tech 1',
          generatedByRole: 'technician',
          includeThermalImages: false,
        );

        expect(bytes.length, greaterThan(2500));
        expect(utf8.decode(bytes.sublist(0, 5)), equals('%PDF-'));
      },
    );
  });

  group('SCR-15 ExportPdfReportSheet Widget Tests', () {
    testWidgets(
      'Preselects active inspection and supports multi-select presets',
      (tester) async {
        final mockRepo = _MockModuleRepo(
          details: testDetails,
          mockInspections: [insp1, insp2],
          mockCleanings: cleanings,
          mockMeasurements: measurements,
          mockLatest: LatestInspection(
            inspection: insp1,
            totalMeasurements: 1,
            confirmedAnomalies: const [],
          ),
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
            child: MaterialApp(
              home: Scaffold(
                body: ExportPdfReportSheet(
                  module: testModule,
                  preselectedInspectionId: insp2.id,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('export_pdf_report_sheet')), findsOneWidget);
        expect(find.text('Export Telemetry PDF'), findsOneWidget);
        expect(find.text('Single Inspection Technical Report'), findsOneWidget);
        expect(find.text('Export PDF'), findsOneWidget);

        // Select All -> Consolidated Report (2 Inspections)
        await tester.tap(find.byKey(const Key('pdf_preset_all')));
        await tester.pumpAndSettle();

        expect(
          find.text('Consolidated Report (2 Inspections)'),
          findsOneWidget,
        );
        expect(find.text('Export PDF (2)'), findsOneWidget);

        // With Hotspots preset selects only insp2
        await tester.tap(find.byKey(const Key('pdf_preset_hotspots')));
        await tester.pumpAndSettle();
        expect(find.text('Single Inspection Technical Report'), findsOneWidget);

        // Clear disables export button
        await tester.tap(find.byKey(const Key('pdf_preset_clear')));
        await tester.pumpAndSettle();
        expect(find.text('Select at least 1 inspection'), findsOneWidget);
      },
    );
  });
}
