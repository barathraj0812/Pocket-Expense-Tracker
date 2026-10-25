import '../data/app_database.dart';
import '../models/expense.dart';

int _roundedQuotient(BigInt numerator, int denominator) {
  final divisor = BigInt.from(denominator);
  var quotient = numerator ~/ divisor;
  final remainder = numerator.remainder(divisor);
  if (remainder * BigInt.from(2) >= divisor) quotient += BigInt.one;
  return quotient.toInt();
}

enum AnalyticsPreset {
  thisMonth,
  lastMonth,
  last7Days,
  last30Days,
  thisYear,
  allTime,
  custom,
}

enum TrendGrain { day, week, month, year }

class AnalyticsDateRange {
  const AnalyticsDateRange._({
    required this.preset,
    required this.start,
    required this.end,
  });

  final AnalyticsPreset preset;
  final DateTime? start;
  final DateTime? end;

  factory AnalyticsDateRange.fromPreset(
    AnalyticsPreset preset, {
    DateTime? now,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    switch (preset) {
      case AnalyticsPreset.thisMonth:
        return AnalyticsDateRange._(
          preset: preset,
          start: DateTime(today.year, today.month),
          end: today,
        );
      case AnalyticsPreset.lastMonth:
        final start = DateTime(today.year, today.month - 1);
        return AnalyticsDateRange._(
          preset: preset,
          start: start,
          end: DateTime(start.year, start.month + 1, 0),
        );
      case AnalyticsPreset.last7Days:
        return AnalyticsDateRange._(
          preset: preset,
          start: today.subtract(const Duration(days: 6)),
          end: today,
        );
      case AnalyticsPreset.last30Days:
        return AnalyticsDateRange._(
          preset: preset,
          start: today.subtract(const Duration(days: 29)),
          end: today,
        );
      case AnalyticsPreset.thisYear:
        return AnalyticsDateRange._(
          preset: preset,
          start: DateTime(today.year),
          end: today,
        );
      case AnalyticsPreset.allTime:
        return AnalyticsDateRange._(preset: preset, start: null, end: null);
      case AnalyticsPreset.custom:
        throw ArgumentError('Use AnalyticsDateRange.custom for custom dates.');
    }
  }

  factory AnalyticsDateRange.custom(DateTime start, DateTime end) {
    final first = _dateOnly(start);
    final last = _dateOnly(end);
    if (first.isAfter(last)) {
      throw ArgumentError('Start date must not come after end date.');
    }
    return AnalyticsDateRange._(
      preset: AnalyticsPreset.custom,
      start: first,
      end: last,
    );
  }

  String get label => switch (preset) {
    AnalyticsPreset.thisMonth => 'This month',
    AnalyticsPreset.lastMonth => 'Last month',
    AnalyticsPreset.last7Days => 'Last 7 days',
    AnalyticsPreset.last30Days => 'Last 30 days',
    AnalyticsPreset.thisYear => 'This year',
    AnalyticsPreset.allTime => 'All time',
    AnalyticsPreset.custom => '${dateKey(start!)} – ${dateKey(end!)}',
  };

  String get detailLabel => start == null || end == null
      ? 'All recorded dates'
      : '${dateKey(start!)} to ${dateKey(end!)} (inclusive)';

  /// Returns the immediately preceding comparison interval. This month and
  /// this year compare matching elapsed calendar spans; rolling/custom ranges
  /// compare an equal number of days immediately before the selected range.
  AnalyticsDateRange? previousPeriod() {
    final first = start;
    final last = end;
    if (first == null || last == null) return null;
    switch (preset) {
      case AnalyticsPreset.thisMonth:
        final previousStart = DateTime(first.year, first.month - 1);
        final previousMonthLength = DateTime(
          previousStart.year,
          previousStart.month + 1,
          0,
        ).day;
        final previousEnd = DateTime(
          previousStart.year,
          previousStart.month,
          last.day.clamp(1, previousMonthLength).toInt(),
        );
        return AnalyticsDateRange._(
          preset: AnalyticsPreset.custom,
          start: previousStart,
          end: previousEnd,
        );
      case AnalyticsPreset.thisYear:
        final year = first.year - 1;
        final maxDay = DateTime(year, last.month + 1, 0).day;
        return AnalyticsDateRange._(
          preset: AnalyticsPreset.custom,
          start: DateTime(year),
          end: DateTime(year, last.month, last.day.clamp(1, maxDay).toInt()),
        );
      case AnalyticsPreset.lastMonth:
        final previousStart = DateTime(first.year, first.month - 1);
        return AnalyticsDateRange._(
          preset: AnalyticsPreset.custom,
          start: previousStart,
          end: DateTime(previousStart.year, previousStart.month + 1, 0),
        );
      case AnalyticsPreset.last7Days:
      case AnalyticsPreset.last30Days:
      case AnalyticsPreset.custom:
        final days = last.difference(first).inDays + 1;
        final previousEnd = first.subtract(const Duration(days: 1));
        return AnalyticsDateRange._(
          preset: AnalyticsPreset.custom,
          start: previousEnd.subtract(Duration(days: days - 1)),
          end: previousEnd,
        );
      case AnalyticsPreset.allTime:
        return null;
    }
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class AnalyticsBreakdownItem {
  const AnalyticsBreakdownItem({
    required this.label,
    required this.totalPaise,
    required this.expenseCount,
    required this.filterField,
    required this.isMissingValue,
  });

  final String label;
  final int totalPaise;
  final int expenseCount;
  final String filterField;
  final bool isMissingValue;

  double shareOfTotal(int totalPaise) => totalPaise == 0
      ? 0
      : BigInt.from(this.totalPaise).toDouble() /
            BigInt.from(totalPaise).toDouble();
}

class AnalyticsTrendPoint {
  const AnalyticsTrendPoint({
    required this.start,
    required this.totalPaise,
    required this.expenseCount,
    required this.grain,
  });

  final DateTime start;
  final int totalPaise;
  final int expenseCount;
  final TrendGrain grain;
}

class AnalyticsMonthSummary {
  const AnalyticsMonthSummary({
    required this.year,
    required this.month,
    required this.totalPaise,
    required this.expenseCount,
  });

  final int year;
  final int month;
  final int totalPaise;
  final int expenseCount;

  DateTime get start => DateTime(year, month);
}

class AnalyticsDashboardData {
  const AnalyticsDashboardData({
    required this.range,
    required this.totalPaise,
    required this.expenseCount,
    required this.averagePaise,
    required this.largestExpense,
    required this.previousTotalPaise,
    required this.subjects,
    required this.categories,
    required this.paymentMethods,
    required this.trend,
    required this.trendGrain,
    required this.months,
    required this.recentExpenses,
    required this.largestExpenses,
  });

  final AnalyticsDateRange range;
  final int totalPaise;
  final int expenseCount;
  final int? averagePaise;
  final Expense? largestExpense;
  final int? previousTotalPaise;
  final List<AnalyticsBreakdownItem> subjects;
  final List<AnalyticsBreakdownItem> categories;
  final List<AnalyticsBreakdownItem> paymentMethods;
  final List<AnalyticsTrendPoint> trend;
  final TrendGrain trendGrain;
  final List<AnalyticsMonthSummary> months;
  final List<Expense> recentExpenses;
  final List<Expense> largestExpenses;

  BigInt? get absoluteChangePaise {
    final previous = previousTotalPaise;
    if (previous == null) return null;
    return (BigInt.from(totalPaise) - BigInt.from(previous)).abs();
  }

  double? get percentageChange {
    final previous = previousTotalPaise;
    if (previous == null || previous == 0) return null;
    final difference = BigInt.from(totalPaise) - BigInt.from(previous);
    return difference.toDouble() * 100 / previous.toDouble();
  }

  bool get spendingIncreased =>
      previousTotalPaise != null && totalPaise > previousTotalPaise!;

  bool get spendingDecreased =>
      previousTotalPaise != null && totalPaise < previousTotalPaise!;

  int? get activeMonthAveragePaise {
    if (months.isEmpty) return null;
    return _roundedQuotient(
      BigInt.from(months.fold<int>(0, (sum, month) => sum + month.totalPaise)),
      months.length,
    );
  }

  AnalyticsMonthSummary? get highestMonth {
    if (months.isEmpty) return null;
    return months.reduce(
      (a, b) =>
          a.totalPaise > b.totalPaise ||
              (a.totalPaise == b.totalPaise && a.start.isBefore(b.start))
          ? a
          : b,
    );
  }

  AnalyticsMonthSummary? get lowestMonth {
    if (months.isEmpty) return null;
    return months.reduce(
      (a, b) =>
          a.totalPaise < b.totalPaise ||
              (a.totalPaise == b.totalPaise && a.start.isBefore(b.start))
          ? a
          : b,
    );
  }
}

class ExpenseAnalyticsService {
  const ExpenseAnalyticsService(this.database);

  final AppDatabase database;

  Future<AnalyticsDashboardData> load(AnalyticsDateRange range) async {
    final bounds = range.preset == AnalyticsPreset.allTime
        ? await database.analyticsDateBounds()
        : null;
    final effectiveStart =
        range.start ?? _parseDate(bounds?['first_date'] as String?);
    final effectiveEnd =
        range.end ?? _parseDate(bounds?['last_date'] as String?);
    final previous = range.previousPeriod();

    final futures = await Future.wait<Object?>([
      database.analyticsTotals(startDate: range.start, endDate: range.end),
      database.analyticsBreakdown(
        field: 'subject',
        startDate: range.start,
        endDate: range.end,
      ),
      database.analyticsBreakdown(
        field: 'category',
        startDate: range.start,
        endDate: range.end,
      ),
      database.analyticsBreakdown(
        field: 'payment_method',
        startDate: range.start,
        endDate: range.end,
      ),
      if (previous == null) Future<int?>.value(null) else _totalFor(previous),
      database.analyticsMonthlySummary(
        startDate: range.start,
        endDate: range.end,
      ),
      database.analyticsExpenses(
        startDate: range.start,
        endDate: range.end,
        limit: 5,
      ),
      database.analyticsExpenses(
        startDate: range.start,
        endDate: range.end,
        largestFirst: true,
        limit: 5,
      ),
    ]);

    final totals = futures[0]! as Map<String, Object?>;
    final totalPaise = totals['total_paise']! as int;
    final count = totals['expense_count']! as int;
    final largestRows = futures[7]! as List<Expense>;
    final largest = largestRows.isEmpty ? null : largestRows.first;
    final trendGrain = _selectGrain(effectiveStart, effectiveEnd);
    final trendRows = effectiveStart == null || effectiveEnd == null
        ? <Map<String, Object?>>[]
        : await database.analyticsTrend(
            grain: trendGrain.name,
            startDate: range.start ?? effectiveStart,
            endDate: range.end ?? effectiveEnd,
          );
    final monthRows = futures[5]! as List<Map<String, Object?>>;

    return AnalyticsDashboardData(
      range: range,
      totalPaise: totalPaise,
      expenseCount: count,
      averagePaise: count == 0
          ? null
          : _roundedQuotient(BigInt.from(totalPaise), count),
      largestExpense: largest,
      previousTotalPaise: futures[4] as int?,
      subjects: _mapBreakdown(
        futures[1]! as List<Map<String, Object?>>,
        'subject',
      ),
      categories: _mapBreakdown(
        futures[2]! as List<Map<String, Object?>>,
        'category',
      ),
      paymentMethods: _mapBreakdown(
        futures[3]! as List<Map<String, Object?>>,
        'payment_method',
      ),
      trend: _fillTrend(trendRows, effectiveStart, effectiveEnd, trendGrain),
      trendGrain: trendGrain,
      months: monthRows.map((row) {
        final key = row['month']! as String;
        final parts = key.split('-');
        return AnalyticsMonthSummary(
          year: int.parse(parts[0]),
          month: int.parse(parts[1]),
          totalPaise: row['total_paise']! as int,
          expenseCount: row['expense_count']! as int,
        );
      }).toList(),
      recentExpenses: futures[6]! as List<Expense>,
      largestExpenses: largestRows,
    );
  }

  Future<int> _totalFor(AnalyticsDateRange range) async =>
      (await database.analyticsTotals(
            startDate: range.start,
            endDate: range.end,
          ))['total_paise']!
          as int;

  static List<AnalyticsBreakdownItem> _mapBreakdown(
    List<Map<String, Object?>> rows,
    String field,
  ) {
    return rows.map((row) {
      final label = row['label']! as String;
      return AnalyticsBreakdownItem(
        label: label,
        totalPaise: row['total_paise']! as int,
        expenseCount: row['expense_count']! as int,
        filterField: field,
        isMissingValue: row['is_missing'] == 1,
      );
    }).toList();
  }

  static TrendGrain _selectGrain(DateTime? start, DateTime? end) {
    if (start == null || end == null) return TrendGrain.month;
    final days = end.difference(start).inDays + 1;
    if (days <= 45) return TrendGrain.day;
    if (days <= 180) return TrendGrain.week;
    if (days <= 365 * 3) return TrendGrain.month;
    return TrendGrain.year;
  }

  static List<AnalyticsTrendPoint> _fillTrend(
    List<Map<String, Object?>> rows,
    DateTime? start,
    DateTime? end,
    TrendGrain grain,
  ) {
    if (start == null || end == null) return const [];
    final values = <String, (int, int)>{
      for (final row in rows)
        row['bucket']! as String: (
          row['total_paise']! as int,
          row['expense_count']! as int,
        ),
    };
    var cursor = _bucketStart(start, grain);
    final last = _bucketStart(end, grain);
    final result = <AnalyticsTrendPoint>[];
    while (!cursor.isAfter(last)) {
      final key = _bucketKey(cursor, grain);
      final value = values[key] ?? (0, 0);
      result.add(
        AnalyticsTrendPoint(
          start: cursor,
          totalPaise: value.$1,
          expenseCount: value.$2,
          grain: grain,
        ),
      );
      cursor = switch (grain) {
        TrendGrain.day => cursor.add(const Duration(days: 1)),
        TrendGrain.week => cursor.add(const Duration(days: 7)),
        TrendGrain.month => DateTime(cursor.year, cursor.month + 1),
        TrendGrain.year => DateTime(cursor.year + 1),
      };
    }
    return result;
  }

  static DateTime _bucketStart(DateTime date, TrendGrain grain) {
    final day = DateTime(date.year, date.month, date.day);
    return switch (grain) {
      TrendGrain.day => day,
      TrendGrain.week => day.subtract(Duration(days: day.weekday - 1)),
      TrendGrain.month => DateTime(day.year, day.month),
      TrendGrain.year => DateTime(day.year),
    };
  }

  static String _bucketKey(DateTime date, TrendGrain grain) => switch (grain) {
    TrendGrain.day => dateKey(date),
    TrendGrain.week => dateKey(date),
    TrendGrain.month =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}',
    TrendGrain.year => date.year.toString().padLeft(4, '0'),
  };

  static DateTime? _parseDate(String? value) {
    if (value == null) return null;
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }
}
