import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/features/modules/presentation/widgets/solar_angle_selector_widget.dart';

void main() {
  testWidgets('SolarAngleSelectorWidget renders presets, handles dynamic recommendation, and persistent custom stepper', (tester) async {
    double currentAngle = 15.0;
    double recommended = 10.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SolarAngleSelectorWidget(
                selectedAngle: currentAngle,
                recommendedAngle: recommended,
                sourceDescription: 'estimated from latitude',
                onChanged: (angle) => setState(() => currentAngle = angle),
              );
            },
          ),
        ),
      ),
    );

    // Verify Title and Preset
    expect(find.text('Minimum Sun Height'), findsOneWidget);
    expect(find.text('15°'), findsOneWidget);
    // Since recommended is 10.0, the star is present
    expect(find.text('★'), findsOneWidget);

    // Select 10° Wide Window
    await tester.tap(find.byKey(const Key('sun_angle_option_10')));
    await tester.pumpAndSettle();
    expect(currentAngle, 10.0);
    expect(find.textContaining('Scans run from early morning'), findsOneWidget);

    // Select 20° High Sun
    await tester.tap(find.byKey(const Key('sun_angle_option_20')));
    await tester.pumpAndSettle();
    expect(currentAngle, 20.0);
    expect(find.textContaining('Avoids morning shadows'), findsOneWidget);

    // Select Custom (defaults to 12.0)
    await tester.tap(find.byKey(const Key('sun_angle_option_custom')));
    await tester.pumpAndSettle();
    expect(currentAngle, 12.0);
    expect(find.byKey(const Key('custom_sun_angle_increment')), findsOneWidget);

    // Increment Custom Angle: 12.0 -> 13.0 -> 14.0 -> 15.0
    await tester.tap(find.byKey(const Key('custom_sun_angle_increment')));
    await tester.pumpAndSettle();
    expect(currentAngle, 13.0);

    await tester.tap(find.byKey(const Key('custom_sun_angle_increment')));
    await tester.pumpAndSettle();
    expect(currentAngle, 14.0);

    // Increment 14.0 -> 15.0 (Hitting preset 15° MUST NOT deactivate custom mode or hide stepper)
    await tester.tap(find.byKey(const Key('custom_sun_angle_increment')));
    await tester.pumpAndSettle();
    expect(currentAngle, 15.0);
    expect(find.byKey(const Key('custom_sun_angle_increment')), findsOneWidget);

    // Increment 15.0 -> 16.0
    await tester.tap(find.byKey(const Key('custom_sun_angle_increment')));
    await tester.pumpAndSettle();
    expect(currentAngle, 16.0);
  });

  testWidgets('showSunHeightGuideModal explains why sun height matters and dismisses cleanly', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => showSunHeightGuideModal(context),
                child: const Text('Open Sun Guide'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sun Guide'));
    await tester.pumpAndSettle();

    // Verify Modal Title
    expect(find.text('Why Sun Height Matters'), findsOneWidget);

    // Verify 3 Steps / Reasons
    expect(find.text('Panels Must Be Generating Power'), findsOneWidget);
    expect(find.text('Eliminating Low-Angle Shadows & Glare'), findsOneWidget);
    expect(find.text('Location-Based Recommendation'), findsOneWidget);

    // Dismiss
    await tester.tap(find.text('Got it, Thanks!'));
    await tester.pumpAndSettle();

    expect(find.text('Why Sun Height Matters'), findsNothing);
  });
}
