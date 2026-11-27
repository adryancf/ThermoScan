import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/features/modules/domain/module_models.dart';
import 'package:thermoscan/features/modules/domain/solar_window_calculator.dart';
import 'package:thermoscan/features/modules/presentation/widgets/solar_window_widgets.dart';

void main() {
  group('SolarWindowCalculator', () {
    test('computes valid solar window for Curitiba and narrows with higher angle',
        () {
      final date = DateTime(2026, 11, 26);
      final w15 = SolarWindowCalculator.computeDailyWindow(
        latitude: -25.4284,
        longitude: -49.2733,
        minSolarAngleDeg: 15.0,
        azimuthDeg: 0.0,
        tiltDeg: 25.0,
        dateLocal: date,
      );
      final w30 = SolarWindowCalculator.computeDailyWindow(
        latitude: -25.4284,
        longitude: -49.2733,
        minSolarAngleDeg: 30.0,
        azimuthDeg: 0.0,
        tiltDeg: 25.0,
        dateLocal: date,
      );

      expect(w15.hasWindow, isTrue);
      expect(w30.hasWindow, isTrue);
      expect(w15.duration.inMinutes, greaterThan(w30.duration.inMinutes));
      expect(w15.peakElevationDeg, greaterThan(60.0));
      expect(w15.bestCosineScore, greaterThan(0.8));
    });

    test('season dates are hemisphere-aware', () {
      final southSummer = SolarWindowCalculator.dateForSeason(
        season: SolarSeasonPreset.summer,
        latitude: -25.4,
        referenceLocal: DateTime(2026, 5, 1),
      );
      final northSummer = SolarWindowCalculator.dateForSeason(
        season: SolarSeasonPreset.summer,
        latitude: 40.0,
        referenceLocal: DateTime(2026, 5, 1),
      );
      expect(southSummer.month, 12);
      expect(northSummer.month, 6);
    });
  });

  group('SolarWindow widgets', () {
    testWidgets('SolarWindowCompactCard renders cleanly and opens sheet',
        (tester) async {
      final mod = PvModule(
        id: 'mod-1',
        companyId: 'comp-1',
        installerTechnicianId: 'tech-1',
        installerName: 'Tech',
        installerEmail: 'tech@example.com',
        name: 'Solar Array',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        isActive: true,
        monitoringStatus: 'active',
        latitude: -25.4284,
        longitude: -49.2733,
        azimuthDeg: 0.0,
        tiltDeg: 25.0,
        minimumSolarAngleDeg: 15.0,
        inspectionIntervalDays: 7,
        createdAt: '2026-11-01T00:00:00Z',
        updatedAt: '2026-11-26T00:00:00Z',
        userRelationship: 'client',
        permissions: const ModulePermissions(
          canEditGeometryAndLocation: false,
          canEditSolarAngle: false,
          canEditInterval: true,
          canManageAccess: false,
          canDelete: false,
        ),
      );

      final window = SolarWindowCalculator.computeDailyWindow(
        latitude: mod.latitude!,
        longitude: mod.longitude!,
        minSolarAngleDeg: mod.minimumSolarAngleDeg!,
        azimuthDeg: mod.azimuthDeg,
        tiltDeg: mod.tiltDeg,
        dateLocal: DateTime(2026, 11, 26),
        nowLocal: DateTime(2026, 11, 26, 12, 0),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Padding(
                padding: const EdgeInsets.all(16),
                child: SolarWindowCompactCard(
                  window: window,
                  nextScanLabel: 'Next: Today, 14:00',
                  onTap: () => showSolarWindowSheet(
                    context: ctx,
                    module: mod,
                    nextScanLabel: 'Next: Today, 14:00',
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Solar Window'), findsOneWidget);
      expect(find.text('Next: Today, 14:00'), findsOneWidget);

      await tester.tap(find.text('Solar Window'));
      await tester.pumpAndSettle();

      expect(find.text('Solar Scan Window'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Summer'), findsOneWidget);
      expect(find.text('Winter'), findsOneWidget);
    });
  });
}
