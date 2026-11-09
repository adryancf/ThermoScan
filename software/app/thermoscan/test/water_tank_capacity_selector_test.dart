import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/features/modules/presentation/widgets/water_tank_capacity_selector_widget.dart';

void main() {
  testWidgets('WaterTankCapacitySelectorWidget renders presets, custom stepper, and triggers modal', (tester) async {
    int currentMl = 2000;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return WaterTankCapacitySelectorWidget(
                selectedCapacityMl: currentMl,
                onChanged: (ml) => setState(() => currentMl = ml),
              );
            },
          ),
        ),
      ),
    );

    // Verify Title and 2.0 L preset with recommendation star
    expect(find.text('Water Tank Capacity'), findsOneWidget);
    expect(find.text('2.0 L'), findsOneWidget);
    expect(find.text('★'), findsOneWidget);
    expect(find.textContaining('Holds 2.0 Liters (2000 mL)'), findsOneWidget);

    // Select 1.0 L
    await tester.tap(find.byKey(const Key('water_tank_option_1000')));
    await tester.pumpAndSettle();
    expect(currentMl, 1000);
    expect(find.textContaining('Holds 1.0 Liters (1000 mL)'), findsOneWidget);

    // Select 1.5 L
    await tester.tap(find.byKey(const Key('water_tank_option_1500')));
    await tester.pumpAndSettle();
    expect(currentMl, 1500);

    // Select Custom (opens modal, defaults to 2500)
    await tester.tap(find.byKey(const Key('water_tank_option_custom')));
    await tester.pumpAndSettle();

    // Verify Modal is open
    expect(find.text('Custom Water Tank Volume'), findsOneWidget);
    expect(find.byKey(const Key('custom_water_tank_apply_button')), findsOneWidget);

    // Type new value 2400
    await tester.enterText(find.byKey(const Key('custom_water_tank_text_field')), '2400');
    await tester.pumpAndSettle();
    expect(find.text('= 2.4 Liters'), findsOneWidget);

    // Apply
    await tester.tap(find.byKey(const Key('custom_water_tank_apply_button')));
    await tester.pumpAndSettle();

    // Modal dismissed, capacity updated
    expect(currentMl, 2400);
    expect(find.text('Custom Water Tank Volume'), findsNothing);
    expect(find.byKey(const Key('custom_water_tank_increment')), findsOneWidget);

    // Increment custom: 2400 -> 2500
    await tester.tap(find.byKey(const Key('custom_water_tank_increment')));
    await tester.pumpAndSettle();
    expect(currentMl, 2500);

    // Open wheel modal via tune button
    await tester.tap(find.byKey(const Key('custom_water_tank_wheel_picker_button')));
    await tester.pumpAndSettle();
    expect(find.text('Custom Water Tank Volume'), findsOneWidget);

    // Close via Done button in header
    await tester.tap(find.byKey(const Key('custom_water_tank_done_header_button')));
    await tester.pumpAndSettle();
    expect(find.text('Custom Water Tank Volume'), findsNothing);
  });
}
