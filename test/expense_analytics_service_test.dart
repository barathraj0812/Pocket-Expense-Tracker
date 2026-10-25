import 'dart:io';

import 'package:excel/excel.dart' show DoubleCellValue, Excel, TextCellValue;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pocket_expense_tracker/data/app_database.dart';
import 'package:pocket_expense_tracker/models/expense.dart';
import 'package:pocket_expense_tracker/services/analytics_export_service.dart';
import 'package:pocket_expense_tracker/services/expense_analytics_service.dart';

void main() {
  late Directory directory;
  late AppDatabase database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('analytics_test_');
    database = AppDatabase(pathOverride: '${directory.path}/expenses.db');
    await database.open();
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  Expense expense(
    String id,
    String date,
    int paise, {
    String subject = 'Lunch',
    String? category = 'Food',
    String? payment = 'UPI',
  }) => Expense(
    id: id,
    subject: subject,
    amountPaise: paise,
    expenseDate: date,
    createdAt: '${date}T09:00:00Z',
    updatedAt: '${date}T09:00:00Z',
    category: category,
    paymentMethod: payment,
  );

  test('date presets are date-only and include their end date', () {
    final today = DateTime(2026, 10, 25, 18, 30);
    final month = AnalyticsDateRange.fromPreset(
      AnalyticsPreset.thisMonth,
      now: today,
    );
    expect(month.start, DateTime(2026, 10, 1));
    expect(month.end, DateTime(2026, 10, 25));
    expect(
      AnalyticsDateRange.fromPreset(
        AnalyticsPreset.last7Days,
        now: today,
      ).start,
      DateTime(2026, 10, 19),
    );
    final lastMonth = AnalyticsDateRange.fromPreset(
      AnalyticsPreset.lastMonth,
      now: today,
    );
    expect(lastMonth.start, DateTime(2026, 9, 1));
    expect(lastMonth.end, DateTime(2026, 9, 30));
    expect(
      AnalyticsDateRange.custom(
        DateTime(2024, 2, 1, 22),
        DateTime(2024, 2, 29, 3),
      ).end,
      DateTime(2024, 2, 29),
    );
    expect(
      () =>
          AnalyticsDateRange.custom(DateTime(2026, 2, 2), DateTime(2026, 2, 1)),
      throwsArgumentError,
    );
  });

  test('comparison periods handle month lengths and leap years', () {
    final march = AnalyticsDateRange.fromPreset(
      AnalyticsPreset.thisMonth,
      now: DateTime(2026, 3, 31),
    );
    expect(march.previousPeriod()!.start, DateTime(2026, 2, 1));
    expect(march.previousPeriod()!.end, DateTime(2026, 2, 28));

    final year = AnalyticsDateRange.fromPreset(
      AnalyticsPreset.thisYear,
      now: DateTime(2024, 2, 29),
    );
    expect(year.previousPeriod()!.end, DateTime(2023, 2, 28));

    final custom = AnalyticsDateRange.custom(
      DateTime(2026, 10, 19),
      DateTime(2026, 10, 25),
    );
    expect(custom.previousPeriod()!.start, DateTime(2026, 10, 12));
    expect(custom.previousPeriod()!.end, DateTime(2026, 10, 18));
  });

  test(
    'dashboard totals, ranking, trend gaps, and monthly rollup are exact',
    () async {
      await database.add(expense('a', '2026-10-20', 1001));
      await database.add(
        expense(
          'b',
          '2026-10-20',
          2500,
          subject: 'Taxi',
          category: 'Travel',
          payment: 'Cash',
        ),
      );
      await database.add(
        expense(
          'c',
          '2026-10-22',
          199,
          subject: '',
          category: null,
          payment: null,
        ),
      );

      final result = await ExpenseAnalyticsService(database).load(
        AnalyticsDateRange.custom(
          DateTime(2026, 10, 19),
          DateTime(2026, 10, 23),
        ),
      );
      expect(result.totalPaise, 3700);
      expect(result.expenseCount, 3);
      expect(result.averagePaise, 1233);
      expect(result.largestExpense!.id, 'b');
      expect(result.trend, hasLength(5));
      expect(result.trend[0].totalPaise, 0);
      expect(result.trend[2].totalPaise, 0);
      expect(result.months.single.totalPaise, 3700);
      expect(result.recentExpenses.first.id, 'c');
      expect(result.largestExpenses.first.id, 'b');
      expect(result.subjects.first.label, 'Taxi');
      expect(result.subjects.last.isMissingValue, isTrue);
      expect(result.categories.last.isMissingValue, isTrue);
      expect(result.paymentMethods.last.isMissingValue, isTrue);
    },
  );

  test('all-time excludes tombstones and comparison zero is safe', () async {
    final active = expense('active', '2026-10-01', 500);
    final removed = expense('removed', '2026-10-02', 900);
    await database.add(active);
    await database.add(removed);
    await database.delete(removed);
    final result = await ExpenseAnalyticsService(database).load(
      AnalyticsDateRange.fromPreset(
        AnalyticsPreset.last7Days,
        now: DateTime(2026, 10, 7),
      ),
    );
    expect(result.totalPaise, 500);
    expect(result.percentageChange, isNull);
    expect(result.largestExpense!.id, 'active');

    final allTime = await ExpenseAnalyticsService(database)
        .load(AnalyticsDateRange.fromPreset(AnalyticsPreset.allTime));
    expect(allTime.totalPaise, 500);
    expect(allTime.trend, hasLength(1));
  });

  test(
    'analytics workbook has separate sheets and numeric rupee values',
    () async {
      await database.add(expense('export', '2026-10-20', 5075));
      final data = await ExpenseAnalyticsService(database).load(
        AnalyticsDateRange.fromPreset(
          AnalyticsPreset.thisMonth,
          now: DateTime(2026, 10, 25),
        ),
      );
      final workbook = Excel.decodeBytes(createAnalyticsWorkbook(data));
      expect(
        workbook.tables.keys,
        containsAll(['Summary', 'By Subject', 'Trend', 'Monthly']),
      );
      expect(workbook['By Subject'].rows[1][1]!.value, isA<DoubleCellValue>());
      expect(
        (workbook['By Subject'].rows[1][1]!.value as DoubleCellValue).value,
        50.75,
      );
      expect(workbook['Summary'].rows[2][1]!.value, isA<DoubleCellValue>());
      expect(
        (workbook['Summary'].rows[2][1]!.value as DoubleCellValue).value,
        50.75,
      );
      expect(workbook['Summary'].rows.first.first!.value, isA<TextCellValue>());
    },
  );
}
