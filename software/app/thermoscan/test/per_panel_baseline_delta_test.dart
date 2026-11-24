import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/core/storage/token_storage.dart';
import 'package:thermoscan/core/theme/app_colors.dart';
import 'package:thermoscan/features/auth/data/auth_repository.dart';
import 'package:thermoscan/features/auth/domain/auth_user.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';
import 'package:thermoscan/features/modules/data/module_repository.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/module_details_screen.dart';
import 'package:thermoscan/features/modules/presentation/widgets/clean_thermal_preview_card.dart';
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
    required this.latestInspection,
    required this.measurements,
  }) : super(dio: Dio());

  final ModuleDetails details;
  final LatestInspection latestInspection;
  final List<ModuleMeasurement> measurements;

  @override
  Future<ModuleDetails> getModuleDetails(String moduleId) async => details;

  @override
  Future<DeviceStatus> getDeviceStatus({required String moduleId}) async =>
      const DeviceStatus(
        moduleId: 'mod-2panel',
        macAddress: 'AA:BB:CC:DD:EE:01',
        monitoringStatus: 'active',
        isConfigured: true,
        isOnline: true,
        waterAvailable: true,
        waterStatus: 'ok',
        limitsCheckPassed: true,
        thermalSensorActive: true,
      );

  @override
  Future<LatestInspection?> getLatestInspection({required String moduleId}) async =>
      latestInspection;

  @override
  Future<List<ModuleInspection>> listInspections({
    required String moduleId,
    int limit = 20,
    int offset = 0,
  }) async =>
      [latestInspection.inspection];

  @override
  Future<List<ModuleMeasurement>> listMeasurements({
    required String moduleId,
    int limit = 50,
    int offset = 0,
    int? panelIndex,
  }) async =>
      measurements;

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

  // 2-panel string: Panel 1 [0..100 cm], Gap [100..105 cm], Panel 2 [105..205 cm]
  const twoPanelModule = PvModule(
    id: 'mod-2panel',
    companyId: 'c1',
    installerTechnicianId: 'u1',
    installerName: 'Tech 1',
    installerEmail: 'tech@thermoscan.com',
    name: '2-Panel String Alpha',
    macAddress: 'AA:BB:CC:DD:EE:01',
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

  const twoPanelDetails = ModuleDetails(
    module: twoPanelModule,
    responsibleManagers: [],
    companyManagers: [],
    companyTechnicians: [],
    companyClients: [],
  );

  // Panel 1: baseline 33.55°C, max 40.77°C -> real delta +7.22°C (< 8.0°C)
  // Panel 2: baseline 29.65°C, max 35.50°C -> real delta +5.85°C (< 8.0°C)
  // Consolidated average baseline = (33.55 + 29.65) / 2 = 31.60°C
  List<double?> buildFrame(double normalTemp, double peakTemp) {
    final frame = List<double?>.filled(768, normalTemp);
    frame[12 * 32 + 16] = peakTemp;
    return frame;
  }

  final panel1Frame = ModuleMeasurement(
    id: 'm-p1',
    moduleId: 'mod-2panel',
    inspectionId: 'insp-2panel',
    sourceEventId: 'evt-p1',
    panelIndex: 1,
    localXPositionCm: 50.0,
    xPositionCm: 50.0,
    maxTemperatureC: 40.77,
    measuredAt: '2026-11-24T10:00:00Z',
    receivedAt: '2026-11-24T10:00:01Z',
    thermalFrame: buildFrame(33.55, 40.77),
  );

  final panel2Frame = ModuleMeasurement(
    id: 'm-p2',
    moduleId: 'mod-2panel',
    inspectionId: 'insp-2panel',
    sourceEventId: 'evt-p2',
    panelIndex: 2,
    localXPositionCm: 50.0,
    xPositionCm: 155.0,
    maxTemperatureC: 35.50,
    measuredAt: '2026-11-24T10:01:00Z',
    receivedAt: '2026-11-24T10:01:01Z',
    thermalFrame: buildFrame(29.65, 35.50),
  );

  const twoPanelInspection = LatestInspection(
    inspection: ModuleInspection(
      id: 'insp-2panel',
      moduleId: 'mod-2panel',
      sourceEventId: 'evt-insp',
      type: 'scheduled',
      scheduledFor: '2026-11-24T10:00:00Z',
      baselineTemperatureC: 31.60,
      hotspotThresholdDeltaC: 8.0,
      status: 'completed',
      createdAt: '2026-11-24T10:00:00Z',
      updatedAt: '2026-11-24T10:02:00Z',
    ),
    totalMeasurements: 2,
    confirmedAnomalies: [],
    panelResults: [
      InspectionPanelResult(
        inspectionId: 'insp-2panel',
        moduleId: 'mod-2panel',
        panelIndex: 1,
        baselineTemperatureC: 33.55,
        truncatedByMemory: false,
        finishedAt: '2026-11-24T10:01:00Z',
        createdAt: '2026-11-24T10:01:00Z',
      ),
      InspectionPanelResult(
        inspectionId: 'insp-2panel',
        moduleId: 'mod-2panel',
        panelIndex: 2,
        baselineTemperatureC: 29.65,
        truncatedByMemory: false,
        finishedAt: '2026-11-24T10:02:00Z',
        createdAt: '2026-11-24T10:02:00Z',
      ),
    ],
  );

  group('Per-panel baseline helper unit tests', () {
    test('buildPanelBaselineMap maps valid panel results and skips invalid ones', () {
      final map = buildPanelBaselineMap(const [
        InspectionPanelResult(
          inspectionId: 'i1',
          moduleId: 'm1',
          panelIndex: 1,
          baselineTemperatureC: 33.55,
          truncatedByMemory: false,
          finishedAt: '',
          createdAt: '',
        ),
        InspectionPanelResult(
          inspectionId: 'i1',
          moduleId: 'm1',
          panelIndex: 2,
          baselineTemperatureC: 29.65,
          truncatedByMemory: false,
          finishedAt: '',
          createdAt: '',
        ),
        InspectionPanelResult(
          inspectionId: 'i1',
          moduleId: 'm1',
          panelIndex: 3,
          baselineTemperatureC: 0.0,
          truncatedByMemory: false,
          finishedAt: '',
          createdAt: '',
        ),
      ]);

      expect(map, equals({1: 33.55, 2: 29.65}));
      expect(buildPanelBaselineMap(null), isEmpty);
    });

    test('resolveFrameBaseline resolves by panelIndex or spatial position and falls back to global baseline', () {
      final map = buildPanelBaselineMap(twoPanelInspection.panelResults);

      expect(
        resolveFrameBaseline(panel1Frame, map, 31.60, twoPanelModule),
        equals(33.55),
      );
      expect(
        resolveFrameBaseline(panel2Frame, map, 31.60, twoPanelModule),
        equals(29.65),
      );

      // Measurement without panelIndex falls back to spatial position on Panel 2 (x = 155 cm)
      const noPanelIdxFrame = ModuleMeasurement(
        id: 'm-no-idx',
        moduleId: 'mod-2panel',
        inspectionId: 'insp-2panel',
        sourceEventId: 'evt',
        xPositionCm: 155.0,
        maxTemperatureC: 35.50,
        measuredAt: '2026-11-24T10:01:00Z',
        receivedAt: '2026-11-24T10:01:01Z',
      );
      expect(
        resolveFrameBaseline(noPanelIdxFrame, map, 31.60, twoPanelModule),
        equals(29.65),
      );

      // Empty map falls back to global baseline (single-panel compatibility)
      expect(
        resolveFrameBaseline(panel1Frame, const {}, 31.60, twoPanelModule),
        equals(31.60),
      );
    });

    test('computeMaxPerPanelDelta returns +7.22 C (not +9.17 C) and detects true panel elevation', () {
      final map = buildPanelBaselineMap(twoPanelInspection.panelResults);

      final maxDelta = computeMaxPerPanelDelta(
        measurements: [panel1Frame, panel2Frame],
        panelBaselines: map,
        fallbackBaseline: 31.60,
        module: twoPanelModule,
      );
      expect(maxDelta, closeTo(7.22, 1e-6));

      // Panel 1 is NOT elevated above 8.0 C threshold against 33.55 C
      expect(
        isMeasurementElevated(
          panel1Frame,
          panelBaselines: map,
          fallbackBaseline: 31.60,
          module: twoPanelModule,
          hotspotDeltaThresholdC: 8.0,
        ),
        isFalse,
      );

      // Panel 1 against global average 31.60 C would have falsely exceeded 8.0 C
      expect(
        isMeasurementElevated(
          panel1Frame,
          panelBaselines: const {},
          fallbackBaseline: 31.60,
          module: twoPanelModule,
          hotspotDeltaThresholdC: 8.0,
        ),
        isTrue,
      );
    });

    test('ThermalPanoramaData uses per-panel baselines so Panel 1 (40.77 C vs 33.55 C) is not painted alarm red', () {
      final map = buildPanelBaselineMap(twoPanelInspection.panelResults);

      final panorama = ThermalPanoramaData.fromMeasurements(
        measurements: [panel1Frame, panel2Frame],
        panelLengthCm: twoPanelModule.panelLengthCm,
        panelCount: twoPanelModule.panelCount,
        panelSpacingCm: twoPanelModule.panelSpacingCm,
        baselineTempC: 31.60,
        panelBaselines: map,
        hotspotDeltaThresholdC: 8.0,
      );

      expect(panorama.baselineForFrame(panel1Frame), equals(33.55));
      expect(panorama.baselineForFrame(panel2Frame), equals(29.65));

      // 40.77 C on Panel 1 is +7.22 C < 8.0 C -> Band 2 (thermalCool -> thermalMid), high green channel (> 180)
      final p1Color = panorama.colorMapperForFrame(panel1Frame)(40.77);
      expect((p1Color.g * 255.0).round(), greaterThan(180));

      // Verify cell resolution in Panel 1 also uses Panel 1's baseline (not alarm orange/red).
      // Peak pixel was placed at raw (sensorRow=12, sensorCol=16) -> rotated display row 16 at X=50.0 cm.
      final hotCell = panorama.resolveAt(50.0, 16);
      expect(hotCell.hasValidTemperature, isTrue);
      expect(hotCell.temperatureC, equals(40.77));
      final cellColor = panorama.colorForCell(hotCell, xCm: 50.0);
      expect((cellColor.g * 255.0).round(), greaterThan(180));

      // At 41.60 C on Panel 1 (+8.05 C >= 8.0 C), it enters the alarm orange/red band (green <= 145)
      final alarmColor = panorama.colorMapperForFrame(panel1Frame)(41.60);
      expect((alarmColor.g * 255.0).round(), lessThan(145));
    });
  });

  group('Multi-panel per-panel baseline widget tests', () {
    testWidgets(
      'RadiometricScanCard All Panels & Frame Inspector Modal report +7.2 C for Panel 1 (not +9.2 C) and update on frame switch',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadiometricScanCard(
                  module: twoPanelModule,
                  latestMeasurement: panel2Frame,
                  latestInspection: twoPanelInspection,
                  measurements: [panel1Frame, panel2Frame],
                  showDetailedSections: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // "All Panels" summary shows +7.2°C (Normal), never +9.2°C
        expect(find.text('+7.2°C (Normal)'), findsWidgets);
        expect(find.textContaining('+9.2'), findsNothing);
        expect(find.textContaining('Hotspot'), findsNothing);
        expect(find.text('HOTSPOT'), findsNothing);

        // Open 32x24 Frame Inspector Modal for Panel 1 frame (F1) from "All Panels"
        await tester.ensureVisible(find.byKey(const Key('thermal_frame_card_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('thermal_frame_card_1')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('selected_frame_inspector')), findsOneWidget);
        final telemetryFinder = find.byKey(const Key('selected_pixel_telemetry'));
        expect(telemetryFinder, findsOneWidget);

        // Panel 1 pixelDelta is +7.2 °C vs Normal (40.77 - 33.55 = 7.22), NOT +9.2 °C
        final p1DeltaFinder = find.descendant(
          of: telemetryFinder,
          matching: find.text('+7.2 °C vs Normal'),
        );
        expect(p1DeltaFinder, findsOneWidget);
        expect(find.textContaining('+9.2'), findsNothing);

        // Pixel delta text is NOT colored red (AppColors.error) because 7.22 < 8.0
        final p1DeltaWidget = tester.widget<Text>(p1DeltaFinder);
        expect(p1DeltaWidget.style?.color, equals(AppColors.textSecondary));

        // Modal footer frame delta also shows +7.2 °C
        expect(find.textContaining('+7.2 °C'), findsWidgets);

        // Switch to Panel 2 frame (F2) inside the modal
        await tester.tap(find.byKey(const Key('modal_next_frame_button')));
        await tester.pumpAndSettle();

        // Panel 2 pixelDelta updates to Panel 2's baseline (35.50 - 29.65 = +5.85 -> +5.9 °C vs Normal)
        final p2DeltaFinder = find.descendant(
          of: telemetryFinder,
          matching: find.text('+5.9 °C vs Normal'),
        );
        expect(p2DeltaFinder, findsOneWidget);
        final p2DeltaWidget = tester.widget<Text>(p2DeltaFinder);
        expect(p2DeltaWidget.style?.color, equals(AppColors.textSecondary));

        // Switch back to Panel 1 frame (F1) -> returns to +7.2 °C vs Normal
        await tester.tap(find.byKey(const Key('modal_prev_frame_button')));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: telemetryFinder,
            matching: find.text('+7.2 °C vs Normal'),
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        // Expand Temperature Chart Along Panel to verify curve renders cleanly with per-panel baselines
        await tester.ensureVisible(find.byKey(const Key('thermal_profile_curve_toggle')));
        await tester.tap(find.byKey(const Key('thermal_profile_curve_toggle')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('thermal_profile_curve_card')), findsOneWidget);
        expect(find.textContaining('Per-panel Normal'), findsOneWidget);
      },
    );

    testWidgets(
      'RadiometricScanCard uses geometry fallback when panelIndex is null on measurements',
      (tester) async {
        final p1NoIdx = ModuleMeasurement(
          id: 'm-p1-noidx',
          moduleId: 'mod-2panel',
          inspectionId: 'insp-2panel',
          sourceEventId: 'evt-p1',
          panelIndex: null,
          xPositionCm: 50.0, // Panel 1 [0..100]
          maxTemperatureC: 40.77,
          measuredAt: '2026-11-24T10:00:00Z',
          receivedAt: '2026-11-24T10:00:01Z',
          thermalFrame: buildFrame(33.55, 40.77),
        );
        final p2NoIdx = ModuleMeasurement(
          id: 'm-p2-noidx',
          moduleId: 'mod-2panel',
          inspectionId: 'insp-2panel',
          sourceEventId: 'evt-p2',
          panelIndex: null,
          xPositionCm: 155.0, // Panel 2 [105..205]
          maxTemperatureC: 35.50,
          measuredAt: '2026-11-24T10:01:00Z',
          receivedAt: '2026-11-24T10:01:01Z',
          thermalFrame: buildFrame(29.65, 35.50),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RadiometricScanCard(
                  module: twoPanelModule,
                  latestMeasurement: p2NoIdx,
                  latestInspection: twoPanelInspection,
                  measurements: [p1NoIdx, p2NoIdx],
                  showDetailedSections: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('+7.2°C (Normal)'), findsWidgets);
        expect(find.textContaining('+9.2'), findsNothing);

        // Open modal via timeline 32x24 button on F1 (defaults to last frame when no hotspot -> jump to F1 first)
        await tester.ensureVisible(find.byKey(const Key('robot_timeline_prev_button')));
        await tester.tap(find.byKey(const Key('robot_timeline_prev_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('inspect_frame_modal_button')));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('selected_pixel_telemetry')),
            matching: find.text('+7.2 °C vs Normal'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'CleanThermalPreviewCard uses per-panel baselines and reports +7.2 C (not +9.2 C)',
      (tester) async {
        // Without anomalies: stays Normal and never reports +9.2 C
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CleanThermalPreviewCard(
                module: twoPanelModule,
                latestMeasurement: panel2Frame,
                latestInspection: twoPanelInspection,
                measurements: [panel1Frame, panel2Frame],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Normal'), findsOneWidget);
        expect(find.textContaining('+9.2'), findsNothing);

        // With a confirmed anomaly referencing Panel 1 frame: badge uses Panel 1 baseline (+7.2°C, not +9.2°C)
        final inspectionWithAnomaly = LatestInspection(
          inspection: twoPanelInspection.inspection,
          totalMeasurements: 2,
          confirmedAnomalies: const [
            ConfirmedAnomaly(
              id: 'anom-p1',
              moduleId: 'mod-2panel',
              originMeasurementId: 'm-p1',
              confirmingMeasurementIds: ['m-p1'],
              sourceEventId: 'evt-p1',
              panelIndex: 1,
              localXPositionCm: 50.0,
              xPositionCm: 50.0,
              detectedAt: '2026-11-24T10:00:00Z',
              status: 'open',
              actuatedAttemptsCount: 0,
              retryPending: false,
            ),
          ],
          panelResults: twoPanelInspection.panelResults,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CleanThermalPreviewCard(
                module: twoPanelModule,
                latestMeasurement: panel2Frame,
                latestInspection: inspectionWithAnomaly,
                measurements: [panel1Frame, panel2Frame],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Hotspot +7.2°C above normal'), findsOneWidget);
        expect(find.textContaining('+9.2'), findsNothing);
      },
    );

    testWidgets(
      'ModuleDetailsScreen (Module Overview) reports +7.2 C (not +9.2 C) across Health Banner and Key Telemetry Grid',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final repo = _MockModuleRepo(
          details: twoPanelDetails,
          latestInspection: twoPanelInspection,
          measurements: [panel1Frame, panel2Frame],
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
              home: ModuleDetailsScreen(moduleId: 'mod-2panel'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Solar Array Healthy'), findsOneWidget);
        expect(find.text('HEALTHY'), findsOneWidget);
        expect(find.text('+7.2°C'), findsOneWidget);
        expect(find.text('+7.2°C (Normal)'), findsOneWidget);
        expect(find.textContaining('+9.2'), findsNothing);
        expect(find.text('HOTSPOT DETECTED'), findsNothing);
      },
    );
  });
}
