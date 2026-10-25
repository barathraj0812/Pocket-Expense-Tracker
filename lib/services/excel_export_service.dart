import 'dart:typed_data';

import 'package:excel/excel.dart'
    show
        CellIndex,
        CellStyle,
        DateCellValue,
        DoubleCellValue,
        Excel,
        NumFormat,
        TextCellValue;

import '../models/expense.dart';

Uint8List createExpenseWorkbook(List<Expense> expenses) {
  final workbook = Excel.createExcel();
  final sheet = workbook['Expenses'];
  sheet.appendRow(
    const [
      'Date',
      'Subject',
      'Amount (₹)',
      'Category',
      'Description',
      'Payment Method',
    ].map(TextCellValue.new).toList(),
  );
  for (final expense in expenses) {
    final dateParts = expense.expenseDate.split('-');
    if (dateParts.length != 3) {
      throw FormatException('Invalid expense date: ${expense.expenseDate}');
    }
    final year = int.tryParse(dateParts[0]);
    final month = int.tryParse(dateParts[1]);
    final day = int.tryParse(dateParts[2]);
    if (year == null || month == null || day == null) {
      throw FormatException('Invalid expense date: ${expense.expenseDate}');
    }
    sheet.appendRow([
      DateCellValue(year: year, month: month, day: day),
      TextCellValue(expense.subject),
      DoubleCellValue(expense.amountPaise / 100),
      TextCellValue(expense.category ?? ''),
      TextCellValue(expense.description ?? ''),
      TextCellValue(expense.paymentMethod ?? ''),
    ]);
    final rowIndex = sheet.rows.length - 1;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex))
        .cellStyle = CellStyle(
      numberFormat: NumFormat.custom(formatCode: '0.00'),
    );
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
        .cellStyle = CellStyle(
      numberFormat: NumFormat.custom(formatCode: 'dd-mm-yyyy'),
    );
  }
  final bytes = workbook.encode();
  if (bytes == null) throw StateError('Could not encode the expense workbook.');
  return Uint8List.fromList(bytes);
}
