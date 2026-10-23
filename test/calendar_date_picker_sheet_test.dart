import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/widgets/ui/calendar_date_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CalendarDatePickerSheet(
            initial: DateTime(2026, 10, 23, 15, 30),
            maxDate: DateTime(2026, 10, 23, 22),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('calendar keeps six date rows for a short month', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CalendarDatePickerSheet(
            initial: DateTime(2021, 2, 1),
            maxDate: DateTime(2026, 10, 23),
          ),
        ),
      ),
    );
    await tester.pump();

    final dateCells = tester.widgetList<SizedBox>(find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.height == 44,
    ));
    expect(dateCells.length, 6 * 7);
  });

  testWidgets('tapping a year or month selects it and closes the wheel',
      (tester) async {
    await pumpPicker(tester);

    await tester.tap(find.text('2026年'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('2025'));
    await tester.pump();

    expect(find.text('2025年'), findsOneWidget);
    expect(find.byType(ListWheelScrollView), findsNothing);

    await tester.tap(find.text('10月'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('9月'));
    await tester.pump();

    expect(find.text('9月'), findsOneWidget);
    expect(find.text('10月'), findsNothing);
    expect(find.byType(ListWheelScrollView), findsNothing);
  });

  testWidgets('arrows change month and year opens a wheel on this page',
      (tester) async {
    await pumpPicker(tester);

    expect(find.text('选择日期'), findsOneWidget);
    expect(find.text('2026年'), findsOneWidget);
    expect(find.text('10月'), findsOneWidget);
    expect(find.text('一'), findsOneWidget);
    expect(find.byType(ListWheelScrollView), findsNothing);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(find.text('9月'), findsOneWidget);
    expect(find.text('一'), findsOneWidget);
    expect(find.byType(ListWheelScrollView), findsNothing);

    await tester.tap(find.text('2026年'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ListWheelScrollView), findsOneWidget);
    expect(find.text('一'), findsOneWidget);

    await tester.drag(
      find.byType(ListWheelScrollView),
      const Offset(0, 52 * 2),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('2026年'), findsOneWidget);
    expect(find.text('2024年'), findsNothing);
    expect(find.text('一'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();

    expect(find.text('2024年'), findsOneWidget);
    expect(find.byType(ListWheelScrollView), findsNothing);
    expect(find.text('一'), findsOneWidget);
  });

  testWidgets('month wheel stays on the page and future days stay disabled',
      (tester) async {
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showCalendarDatePicker(
                  context,
                  initial: DateTime(2026, 10, 23, 15, 30),
                  maxDate: DateTime(2026, 10, 23, 22),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ListWheelScrollView), findsNothing);
    await tester.tap(find.text('10月'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ListWheelScrollView), findsOneWidget);
    expect(find.text('11月'), findsNothing);
    expect(find.text('一'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump();
    await tester.tap(find.text('24'));
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(result, DateTime(2026, 10, 23));
  });
}
