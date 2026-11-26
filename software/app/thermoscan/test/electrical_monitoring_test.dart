import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/presentation/services/electrical_pdf_report_service.dart';
import 'package:thermoscan/features/modules/presentation/widgets/electrical_series_chart.dart';

void main() {
  group('Electrical formatters', () {
    test('formatElectricalCurrent switches automatically between mA and A', () {
      expect(formatElectricalCurrent(null), 'N/A');
      expect(formatElectricalCurrent(0.4567), '456.7 mA');
      expect(formatElectricalCurrent(0.999), '999.0 mA');
      expect(formatElectricalCurrent(1.0), '1.00 A');
      expect(formatElectricalCurrent(2.345), '2.35 A');
    });

    test('formatElectricalVoltage and formatElectricalPower handle null', () {
      expect(formatElectricalVoltage(null), 'N/A');
      expect(formatElectricalVoltage(18.423), '18.42 V');
      expect(formatElectricalPower(null), 'N/A');
      expect(formatElectricalPower(5.123), '5.12 W');
      expect(formatElectricalPower(24.87), '24.9 W');
    });
  });

  group('ElectricalSeriesChart widget', () {
    testWidgets('renders empty state cleanly when no points', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ElectricalSeriesChart(
              points: [],
              metric: ElectricalChartMetric.power,
              range: '24h',
            ),
          ),
        ),
      );
      expect(
        find.text('No electrical readings recorded for this period yet.'),
        findsOneWidget,
      );
    });

    testWidgets('renders chart and responds to tap tooltip', (tester) async {
      final now = DateTime.utc(2026, 11, 25, 14, 0);
      final points = [
        PowerSeriesPoint(
          bucketAt: now,
          voltageV: 18.0,
          currentA: 0.5,
          powerW: 9.0,
          peakPowerW: 9.0,
          sampleCount: 5,
        ),
        PowerSeriesPoint(
          bucketAt: now.add(const Duration(minutes: 10)),
          voltageV: 19.0,
          currentA: 1.5,
          powerW: 28.5,
          peakPowerW: 28.5,
          sampleCount: 5,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: ElectricalSeriesChart(
                points: points,
                metric: ElectricalChartMetric.power,
                range: '1h',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
      expect(find.textContaining('W'), findsWidgets);
    });
  });

  group('ElectricalPdfReportService', () {
    test('builds valid non-empty PDF bytes with vector chart and table',
        () async {
      final mod = PvModule(
        id: 'mod-1',
        companyId: 'comp-1',
        installerTechnicianId: 'tech-1',
        installerName: 'Tech',
        installerEmail: 'tech@example.com',
        name: 'Lab Solar String',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        monitoringStatus: 'active',
        panelCount: 2,
        inspectionIntervalDays: 7,
        createdAt: '2026-11-01T00:00:00Z',
        updatedAt: '2026-11-25T00:00:00Z',
        userRelationship: 'manager',
        permissions: const ModulePermissions(
          canEditGeometryAndLocation: true,
          canEditSolarAngle: true,
          canEditInterval: true,
          canManageAccess: true,
          canDelete: false,
        ),
      );

      final now = DateTime.utc(2026, 11, 25, 14, 0);
      final series = PowerReadingsSeries(
        range: '24h',
        bucketSeconds: 600,
        summary: const PowerSeriesSummary(
          totalReadings: 2,
          peakPowerW: 28.5,
          avgPowerW: 18.75,
          avgVoltageV: 18.5,
          avgCurrentA: 1.0,
        ),
        points: [
          PowerSeriesPoint(
            bucketAt: now,
            voltageV: 18.0,
            currentA: 0.5,
            powerW: 9.0,
            peakPowerW: 9.0,
            sampleCount: 1,
          ),
          PowerSeriesPoint(
            bucketAt: now.add(const Duration(minutes: 10)),
            voltageV: 19.0,
            currentA: 1.5,
            powerW: 28.5,
            peakPowerW: 28.5,
            sampleCount: 1,
          ),
        ],
      );

      final readings = [
        PowerReadingItem(
          id: 'r1',
          moduleId: 'mod-1',
          panelIndex: 1,
          voltageV: 19.0,
          currentA: 1.5,
          powerW: 28.5,
          measuredAt: now.add(const Duration(minutes: 10)).toIso8601String(),
          receivedAt: now.add(const Duration(minutes: 10)).toIso8601String(),
        ),
      ];

      final bytes = await ElectricalPdfReportService.buildReportBytes(
        module: mod,
        series: series,
        recentReadings: readings,
        generatedBy: 'Test Manager',
      );

      expect(bytes.length, greaterThan(1000));
      // PDF magic header "%PDF-"
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
