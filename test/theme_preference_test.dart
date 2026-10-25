import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pocket_expense_tracker/data/app_database.dart';
import 'package:pocket_expense_tracker/main.dart';
import 'package:pocket_expense_tracker/models/expense.dart';
import 'package:pocket_expense_tracker/services/theme_preference.dart';
import 'package:pocket_expense_tracker/widgets/app_footer.dart';

void main() {
  late Directory directory;
  late AppDatabase database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('theme_preference_test_');
    database = AppDatabase(pathOverride: '${directory.path}/expenses.db');
    await database.open();
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test(
    'defaults to light, persists explicit changes, and restores after reload',
    () async {
      final initial = await ThemePreference.load(database);
      expect(initial.isDark, isFalse);

      await initial.setDark(true);
      expect(initial.isDark, isTrue);
      expect(await database.setting('dark_mode'), 'true');

      final restored = await ThemePreference.load(database);
      expect(restored.isDark, isTrue);
      await restored.setDark(false);
      expect(await database.setting('dark_mode'), 'false');
    },
  );

  test('invalid saved preference safely resolves to light mode', () async {
    await database.setSetting('dark_mode', 'not-a-boolean');
    final preference = await ThemePreference.load(database);
    expect(preference.isDark, isFalse);
  });

  testWidgets('Misc controls app theme and keeps copyright exclusive to Misc', (
    tester,
  ) async {
    final appDatabase = _ThemeTestDatabase();
    final preference = await ThemePreference.load(appDatabase);
    await tester.pumpWidget(
      PocketExpenseApp(database: appDatabase, themePreference: preference),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      Theme.of(tester.element(find.byType(NavigationBar))).brightness,
      Brightness.light,
    );
    expect(find.text('Dark Mode'), findsNothing);

    await tester.tap(find.text('Misc.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Dark Mode'), findsOneWidget);
    expect(find.text(AppFooter.notice), findsNothing);
    await tester.scrollUntilVisible(
      find.text(AppFooter.notice),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(AppFooter.notice), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(SwitchListTile),
      -260,
      scrollable: find.byType(Scrollable).first,
    );
    final switchFinder = find.byType(SwitchListTile);
    expect(switchFinder, findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      Theme.of(tester.element(find.byType(NavigationBar))).brightness,
      Brightness.dark,
    );

    for (final policy in [
      'Privacy Policy',
      'Data Storage and Synchronization',
      'Backup and Restore Policy',
      'Application Information',
    ]) {
      await tester.scrollUntilVisible(
        find.text(policy),
        260,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(policy).last);
      await tester.pumpAndSettle();
      expect(find.text('Effective October 25, 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, 'Backup and Restore'),
      -260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Backup and Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Create local backup'), findsOneWidget);
    expect(find.text('Back up to Google Drive'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.byType(Scaffold).last)).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calendar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Dark Mode'), findsNothing);
    expect(find.text(AppFooter.notice), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _ThemeTestDatabase extends AppDatabase {
  final Map<String, String> values = {};

  @override
  Future<String?> setting(String key) async => values[key];

  @override
  Future<void> setSetting(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<int> pendingCount() async => 0;

  @override
  Future<List<Expense>> day(DateTime date) async => [];

  @override
  Future<List<Expense>> month(int year, int month) async => [];

  @override
  Future<List<Expense>> year(int year) async => [];

  @override
  Future<Map<String, Object?>> analyticsTotals({
    DateTime? startDate,
    DateTime? endDate,
  }) async => {'total_paise': 0, 'expense_count': 0};

  @override
  Future<List<Map<String, Object?>>> analyticsBreakdown({
    required String field,
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];

  @override
  Future<List<Map<String, Object?>>> analyticsMonthlySummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];

  @override
  Future<List<Expense>> analyticsExpenses({
    DateTime? startDate,
    DateTime? endDate,
    String? filterField,
    String? filterValue,
    bool filterMissing = false,
    bool largestFirst = false,
    int? limit,
  }) async => [];

  @override
  Future<List<Map<String, Object?>>> analyticsTrend({
    required String grain,
    DateTime? startDate,
    DateTime? endDate,
  }) async => [];
}
