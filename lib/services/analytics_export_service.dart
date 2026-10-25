import 'dart:typed_data';

import 'package:excel/excel.dart'
    show
        CellIndex,
        CellStyle,
        DoubleCellValue,
        Excel,
        IntCellValue,
        NumFormat,
        Sheet,
        TextCellValue;

import 'expense_analytics_service.dart';

/// Creates a separate workbook for analytics so the existing date-first
/// expense export remains unchanged.
Uint8List createAnalyticsWorkbook(AnalyticsDashboardData data) {
  final workbook = Excel.createExcel();
  final summary = workbook['Summary'];
  summary.appendRow(const ['Metric', 'Value'].map(TextCellValue.new).toList());
  summary.appendRow([
    TextCellValue('Date range'),
    TextCellValue(data.range.label),
  ]);
  summary.appendRow([
    TextCellValue('Total spending (₹)'),
    DoubleCellValue(data.totalPaise / 100),
  ]);
  summary.appendRow([
    TextCellValue('Expense count'),
    IntCellValue(data.expenseCount),
  ]);
  summary.appendRow([
    TextCellValue('Average expense (₹)'),
    data.averagePaise == null
        ? TextCellValue('—')
        : DoubleCellValue(data.averagePaise! / 100),
  ]);
  summary.appendRow([
    TextCellValue('Largest expense (₹)'),
    data.largestExpense == null
        ? TextCellValue('—')
        : DoubleCellValue(data.largestExpense!.amountPaise / 100),
  ]);
  summary.appendRow([
    TextCellValue('Previous period (₹)'),
    data.previousTotalPaise == null
        ? TextCellValue('—')
        : DoubleCellValue(data.previousTotalPaise! / 100),
  ]);
  summary.appendRow([
    TextCellValue('Change (%)'),
    data.percentageChange == null
        ? TextCellValue('—')
        : DoubleCellValue(data.percentageChange!),
  ]);
  for (final row in [2, 4, 5, 6]) {
    summary
        .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
        .cellStyle = CellStyle(
      numberFormat: NumFormat.custom(formatCode: '0.00'),
    );
  }
  summary
      .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 7))
      .cellStyle = CellStyle(
    numberFormat: NumFormat.custom(formatCode: '0.00"%"'),
  );

  _appendBreakdown(workbook, 'By Subject', data.subjects);
  _appendBreakdown(workbook, 'By Category', data.categories);
  _appendBreakdown(workbook, 'By Payment', data.paymentMethods);

  final trend = workbook['Trend'];
  trend.appendRow(
    const [
      'Period',
      'Total (₹)',
      'Expense count',
    ].map(TextCellValue.new).toList(),
  );
  for (final point in data.trend) {
    trend.appendRow([
      TextCellValue(_periodLabel(point.start, point.grain)),
      DoubleCellValue(point.totalPaise / 100),
      TextCellValue('${point.expenseCount}'),
    ]);
  }
  _formatRupeeColumn(trend, 1);

  final monthly = workbook['Monthly'];
  monthly.appendRow(
    const [
      'Month',
      'Total (₹)',
      'Expense count',
    ].map(TextCellValue.new).toList(),
  );
  for (final month in data.months) {
    monthly.appendRow([
      TextCellValue(
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}',
      ),
      DoubleCellValue(month.totalPaise / 100),
      TextCellValue('${month.expenseCount}'),
    ]);
  }
  _formatRupeeColumn(monthly, 1);

  final bytes = workbook.encode();
  if (bytes == null) {
    throw StateError('Could not encode the analytics workbook.');
  }
  return Uint8List.fromList(bytes);
}

void _appendBreakdown(
  Excel workbook,
  String name,
  List<AnalyticsBreakdownItem> items,
) {
  final sheet = workbook[name];
  sheet.appendRow(
    const [
      'Name',
      'Total (₹)',
      'Expense count',
      'Share (%)',
    ].map(TextCellValue.new).toList(),
  );
  final total = items.fold<int>(0, (sum, item) => sum + item.totalPaise);
  for (final item in items) {
    sheet.appendRow([
      TextCellValue(item.label),
      DoubleCellValue(item.totalPaise / 100),
      TextCellValue('${item.expenseCount}'),
      DoubleCellValue(item.shareOfTotal(total) * 100),
    ]);
  }
  _formatRupeeColumn(sheet, 1);
  for (var row = 1; row < sheet.rows.length; row++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
        .cellStyle = CellStyle(
      numberFormat: NumFormat.custom(formatCode: '0.00'),
    );
  }
}

void _formatRupeeColumn(Sheet sheet, int column) {
  for (var row = 1; row < sheet.rows.length; row++) {
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
        .cellStyle = CellStyle(
      numberFormat: NumFormat.custom(formatCode: '0.00'),
    );
  }
}

String _periodLabel(DateTime date, TrendGrain grain) => switch (grain) {
  TrendGrain.day =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
  TrendGrain.week =>
    'Week of ${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}-${date.year}',
  TrendGrain.month =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}',
  TrendGrain.year => '${date.year}',
};
