import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/features/alerts/data/alerts_repository.dart';
import 'package:thermoscan/features/alerts/domain/alert_models.dart';
import 'package:thermoscan/features/alerts/presentation/alerts_feed_screen.dart';
import 'package:thermoscan/features/auth/domain/auth_user.dart';
import 'package:thermoscan/features/auth/presentation/auth_controller.dart';

class _MockAlertsRepository extends AlertsRepository {
  final AlertsSummary summary;
  _MockAlertsRepository(this.summary) : super(dio: Dio());

  @override
  Future<AlertsSummary> listAlerts() async => summary;
}

class _FakeAuthController extends StateNotifier<AuthState>
    implements AuthController {
  _FakeAuthController(AuthUser user) : super(AuthState.authenticated(user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('FieldAlert Domain Model Tests', () {
    test('Correctly deserializes hotspot anomaly with inspection origin', () {
      final json = <String, dynamic>{
        'id': 'alt-101',
        'module_id': 'mod-uuid-1',
        'module_name': 'String Array Norte',
        'severity': 'critical',
        'type': 'hotspot_unresolved',
        'title': 'Hotspot Unresolved: String Array Norte (Panel 2)',
        'description':
            'Thermal anomaly confirmed on panel 2 at coordinate X=155.0 cm.',
        'metaText': 'Delta: +14.2°C vs Baseline',
        'panel_index': 2,
        'local_x_position_cm': 35.0,
        'x_position_cm': 155.0,
        'delta_c': 14.2,
        'inspection_id': 'insp-777',
        'inspection_date': '2026-11-08T14:30:00Z',
        'max_temperature_c': 58.4,
        'baseline_temperature_c': 44.2,
        'wash_attempts_count': 2,
        'created_at': '2026-11-08T14:35:00Z',
      };

      final alert = FieldAlert.fromJson(json);

      expect(alert.id, 'alt-101');
      expect(alert.isCritical, isTrue);
      expect(alert.isHotspot, isTrue);
      expect(alert.isReservoirLow, isFalse);
      expect(alert.inspectionId, 'insp-777');
      expect(alert.inspectionDate, '2026-11-08T14:30:00Z');
      expect(alert.maxTemperatureC, 58.4);
      expect(alert.baselineTemperatureC, 44.2);
      expect(alert.washAttemptsCount, 2);
      expect(alert.metaText, 'Delta: +14.2°C vs Baseline');
      expect(alert.localXPositionCm, 35.0);
    });

    test('Correctly deserializes reservoir_low alert', () {
      final json = <String, dynamic>{
        'id': 'alt-102',
        'module_id': 'mod-uuid-2',
        'module_name': 'Rooftop Array 1',
        'severity': 'warning',
        'type': 'reservoir_low',
        'title': 'Reservoir Low: Rooftop Array 1',
        'description': 'Water level is below safety minimum threshold.',
        'metaText': 'Safety Interlock: Wash Cycles Blocked',
        'created_at': '2026-11-08T12:00:00Z',
      };

      final alert = FieldAlert.fromJson(json);

      expect(alert.isCritical, isFalse);
      expect(alert.isHotspot, isFalse);
      expect(alert.isReservoirLow, isTrue);
      expect(alert.inspectionId, isNull);
    });
  });

  group('AlertsFeedScreen Widget Tests', () {
    const mockHotspot = FieldAlert(
      id: 'hotspot-1',
      moduleId: 'mod-1',
      moduleName: 'String Array Norte',
      severity: 'critical',
      type: 'hotspot_unresolved',
      title: 'Hotspot Unresolved: String Array Norte (Panel 2)',
      description:
          'Thermal anomaly confirmed on panel 2 at coordinate X=155.0 cm.',
      metaText: 'Delta: +14.2°C vs Baseline',
      panelIndex: 2,
      localXPositionCm: 35.0,
      xPositionCm: 155.0,
      deltaC: 14.2,
      inspectionId: 'insp-1',
      inspectionDate: '2026-11-08T14:30:00Z',
      maxTemperatureC: 58.4,
      baselineTemperatureC: 44.2,
      washAttemptsCount: 2,
      createdAt: '2026-11-08T14:35:00Z',
    );

    const mockWater = FieldAlert(
      id: 'water-1',
      moduleId: 'mod-1',
      moduleName: 'String Array Norte',
      severity: 'warning',
      type: 'reservoir_low',
      title: 'Reservoir Low: String Array Norte',
      description: 'Water level below 10%. Autonomous wash blocked.',
      metaText: 'Safety Interlock: Wash Cycles Blocked',
      createdAt: '2026-11-08T14:00:00Z',
    );

    const testUser = AuthUser(
      id: 'tech-1',
      companyId: 'comp-1',
      name: 'John Doe',
      email: 'john@example.com',
      role: 'technician',
      isActive: true,
      mustChangePassword: false,
    );

    Widget createSubject({required AlertsSummary summary}) {
      return ProviderScope(
        overrides: [
          alertsRepositoryProvider
              .overrideWithValue(_MockAlertsRepository(summary)),
          authControllerProvider
              .overrideWith((ref) => _FakeAuthController(testUser)),
        ],
        child: const MaterialApp(
          home: AlertsFeedScreen(),
        ),
      );
    }

    testWidgets(
        'Renders KPI Summary Bar, Filter Chips, and Structured Alert Cards',
        (WidgetTester tester) async {
      final summary = AlertsSummary(
        total: 2,
        critical: 1,
        warning: 1,
        alerts: const [mockHotspot, mockWater],
      );

      await tester.pumpWidget(createSubject(summary: summary));
      await tester.pumpAndSettle();

      // Screen Header & KPI Section
      expect(find.text('Active Field Alerts'), findsOneWidget);
      expect(find.text('FIELD STATUS SUMMARY'), findsOneWidget);

      // KPI stat counts
      expect(find.text('Critical'), findsWidgets);
      expect(find.text('Warnings'), findsWidgets);
      expect(find.text('Low Water'), findsWidgets);

      // Category filter chips
      expect(find.text('All Alerts (2)'), findsOneWidget);
      expect(find.text('🔥 Hotspots (1)'), findsOneWidget);
      expect(find.text('💧 Low Water (1)'), findsOneWidget);

      // Hotspot Card Scannable Elements
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('Panel 2'), findsOneWidget);
      expect(find.textContaining('Origin: Inspection'), findsOneWidget);
      expect(find.textContaining('+14.2°C Delta'), findsOneWidget);
      expect(find.textContaining('58.4°C Peak vs 44.2°C Base'), findsOneWidget);
      expect(find.textContaining('35.0 cm on panel'), findsOneWidget);
      expect(find.textContaining('2 of 3 washes attempted'), findsOneWidget);
      expect(find.text('View in Thermal Studio ➔'), findsOneWidget);

      // Water Card Scannable Elements
      expect(find.text('WARNING'), findsOneWidget);
      expect(find.text('Robot Tank'), findsOneWidget);
      expect(find.text('Origin: Robot Hardware Telemetry'), findsOneWidget);
      expect(find.textContaining('Reservoir water level low'), findsOneWidget);
      expect(find.text('Check Robot Status ➔'), findsOneWidget);
    });

    testWidgets('Tapping KPI Critical filters to only critical hotspot',
        (WidgetTester tester) async {
      final summary = AlertsSummary(
        total: 2,
        critical: 1,
        warning: 1,
        alerts: const [mockHotspot, mockWater],
      );

      await tester.pumpWidget(createSubject(summary: summary));
      await tester.pumpAndSettle();

      // Tap Critical KPI card
      await tester.tap(find.text('Critical'));
      await tester.pumpAndSettle();

      // Only hotspot remains visible
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('WARNING'), findsNothing);
      expect(find.text('View in Thermal Studio ➔'), findsOneWidget);
      expect(find.text('Check Robot Status ➔'), findsNothing);
    });

    testWidgets('Tapping 🔥 Hotspots chip filters out water alerts',
        (WidgetTester tester) async {
      final summary = AlertsSummary(
        total: 2,
        critical: 1,
        warning: 1,
        alerts: const [mockHotspot, mockWater],
      );

      await tester.pumpWidget(createSubject(summary: summary));
      await tester.pumpAndSettle();

      // Tap Hotspots filter chip
      await tester.tap(find.text('🔥 Hotspots (1)'));
      await tester.pumpAndSettle();

      expect(find.text('View in Thermal Studio ➔'), findsOneWidget);
      expect(find.text('Check Robot Status ➔'), findsNothing);
    });

    testWidgets('Tapping 💧 Low Water chip filters out hotspot alerts',
        (WidgetTester tester) async {
      final summary = AlertsSummary(
        total: 2,
        critical: 1,
        warning: 1,
        alerts: const [mockHotspot, mockWater],
      );

      await tester.pumpWidget(createSubject(summary: summary));
      await tester.pumpAndSettle();

      // Tap Low Water filter chip
      await tester.tap(find.text('💧 Low Water (1)'));
      await tester.pumpAndSettle();

      expect(find.text('View in Thermal Studio ➔'), findsNothing);
      expect(find.text('Check Robot Status ➔'), findsOneWidget);
      expect(find.text('Origin: Robot Hardware Telemetry'), findsOneWidget);
    });

    testWidgets('Displays friendly empty state when list is empty',
        (WidgetTester tester) async {
      const summary = AlertsSummary(
        total: 0,
        critical: 0,
        warning: 0,
        alerts: [],
      );

      await tester.pumpWidget(createSubject(summary: summary));
      await tester.pumpAndSettle();

      expect(find.text('No Active Field Alerts'), findsOneWidget);
      expect(
        find.text(
            'All solar arrays and cleaning robots are operating normally without anomalies.'),
        findsOneWidget,
      );
      expect(find.text('Automatic Alert Updates'), findsOneWidget);
    });
  });
}
