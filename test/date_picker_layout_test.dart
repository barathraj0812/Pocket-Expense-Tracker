import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_expense_tracker/data/app_database.dart';
import 'package:pocket_expense_tracker/models/expense.dart';
import 'package:pocket_expense_tracker/screens/home_screen.dart';
import 'package:pocket_expense_tracker/widgets/app_footer.dart';

void main() {
  testWidgets('calendar tab fits Pixel 4 layout', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains(
        'ListTile background color or ink splashes may be invisible.',
      )) {
        return;
      }
      previousFlutterErrorHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousFlutterErrorHandler);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFFFFBD0),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5F8738),
            surface: const Color(0xFFFFFBD0),
          ),
        ),
        home: HomeScreen(database: _CalendarDatabase()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();

    expect(find.text('YEARLY EXPENSES'), findsOneWidget);
    expect(find.text(AppFooter.notice), findsNothing);
    final exceptions = <Object>[];
    Object? exception;
    while ((exception = tester.takeException()) != null) {
      exceptions.add(exception!);
    }
    expect(
      exceptions.where(
        (error) => error.toString().toLowerCase().contains('overflowed'),
      ),
      isEmpty,
      reason: 'Calendar tab overflowed: $exceptions',
    );

    await tester.tap(find.text('Misc.'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(AppFooter.notice),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text(AppFooter.notice), findsOneWidget);
    expect(
      tester.getRect(find.byType(AppFooter)).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(NavigationBar)).top),
    );
  });

  testWidgets('copyright footer wraps on narrow screens', (tester) async {
    tester.view.physicalSize = const Size(960, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: AppFooter()),
        ),
      ),
    );

    expect(find.text(AppFooter.notice), findsOneWidget);
    expect(tester.getSize(find.text(AppFooter.notice)).height, greaterThan(14));
    expect(tester.takeException(), isNull);
  });

  testWidgets('native date picker fits Pixel 4 for all month row counts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (var month = 1; month <= 12; month++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showDatePicker(
                    context: context,
                    initialDate: DateTime(2026, month, 15),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2026, 12, 31),
                  ),
                  child: Text('Open $month'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open $month'));
      await tester.pumpAndSettle();
      final exceptions = <Object>[];
      Object? exception;
      while ((exception = tester.takeException()) != null) {
        exceptions.add(exception!);
      }
      expect(
        exceptions.where(
          (error) => error.toString().toLowerCase().contains('overflowed'),
        ),
        isEmpty,
        reason: 'Date picker overflow for month $month: $exceptions',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
  });
}

class _CalendarDatabase extends AppDatabase {
  @override
  Future<String?> setting(String key) async => null;

  @override
  Future<List<Expense>> day(DateTime date) async => [];

  @override
  Future<List<Expense>> month(int year, int month) async => [];

  @override
  Future<List<Expense>> year(int year) async => [];

  @override
  Future<int> pendingCount() async => 0;
}
