import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/features/modules/presentation/widgets/array_geometry_blueprint_widget.dart';

void main() {
  testWidgets('ArrayGeometryBlueprintWidget renders technical schematic, dimensions and total track', (tester) async {
    bool swapped = false;
    bool guideOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArrayGeometryBlueprintWidget(
            panelLengthCm: 195.5,
            panelWidthCm: 99.2,
            panelCount: 2,
            panelSpacingCm: 2.5,
            onSwapDimensions: () => swapped = true,
            onOpenMeasureGuide: () => guideOpened = true,
          ),
        ),
      ),
    );

    // Verify Blueprint Header and Subtitle
    expect(find.text('Live Array Blueprint'), findsOneWidget);
    expect(find.text('Track layout & dimensions'), findsOneWidget);

    // Verify Calculation Badge: 2 panels * 195.5 + 1 * 2.5 = 393.5 cm
    expect(find.textContaining('393.5 cm'), findsOneWidget);
    expect(find.textContaining('2 panel(s) × 195.5 cm + 1 × 2.5 cm gap'), findsOneWidget);

    // Verify Swap Dimensions button and trigger
    final swapButton = find.byKey(const Key('swap_dimensions_button'));
    expect(swapButton, findsOneWidget);
    await tester.tap(swapButton);
    expect(swapped, isTrue);

    // Verify How to Measure guide button and trigger
    final guideButton = find.byKey(const Key('how_to_measure_guide_button'));
    expect(guideButton, findsOneWidget);
    await tester.tap(guideButton);
    expect(guideOpened, isTrue);
  });

  testWidgets('showHowToMeasureModal presents 3 illustrated steps and dismisses cleanly', (tester) async {
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
                onPressed: () => showHowToMeasureModal(context),
                child: const Text('Open Guide'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Guide'));
    await tester.pumpAndSettle();

    // Verify Modal Title
    expect(find.text('How to Measure Your Solar Array'), findsOneWidget);

    // Verify 3 Steps
    expect(find.text('Panel Length along Track (Travel Direction)'), findsOneWidget);
    expect(find.text('Panel Width across (Perpendicular)'), findsOneWidget);
    expect(find.text('Gap Between Panels (Inter-Panel Spacing)'), findsOneWidget);

    // Verify Dismissal
    expect(find.text('Got it, Thanks!'), findsOneWidget);
    await tester.tap(find.text('Got it, Thanks!'));
    await tester.pumpAndSettle();

    expect(find.text('How to Measure Your Solar Array'), findsNothing);
  });
}
