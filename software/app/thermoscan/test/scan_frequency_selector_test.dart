import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoscan/features/modules/presentation/widgets/scan_frequency_selector_widget.dart';

void main() {
  testWidgets('ScanFrequencySelectorWidget renders presets and triggers selection', (tester) async {
    int currentDays = 7;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ScanFrequencySelectorWidget(
                selectedDays: currentDays,
                onChanged: (days) => setState(() => currentDays = days),
              );
            },
          ),
        ),
      ),
    );

    // Verify Title and Subtitle
    expect(find.text('Inspection Schedule Frequency'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('★'), findsOneWidget); // Recommended badge

    // Select Daily
    await tester.tap(find.byKey(const Key('frequency_option_daily')));
    await tester.pumpAndSettle();
    expect(currentDays, 1);
    expect(find.text('The robot will inspect panels daily during safe sun hours.'), findsOneWidget);

    // Select Bi-Weekly
    await tester.tap(find.byKey(const Key('frequency_option_biweekly')));
    await tester.pumpAndSettle();
    expect(currentDays, 15);
    expect(find.text('The robot will automatically scan panels every 15 days.'), findsOneWidget);

    // Select Custom (defaults to 5)
    await tester.tap(find.byKey(const Key('frequency_option_custom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('custom_frequency_increment')), findsOneWidget);

    // Increment
    await tester.tap(find.byKey(const Key('custom_frequency_increment')));
    await tester.pumpAndSettle();
    expect(currentDays, 6);
    expect(find.text('The robot will automatically scan panels every 6 days.'), findsOneWidget);
  });
}
