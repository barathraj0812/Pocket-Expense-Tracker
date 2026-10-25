import 'package:excel/excel.dart'
    show DateCellValue, DoubleCellValue, Excel, TextCellValue;
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_expense_tracker/models/expense.dart';
import 'package:pocket_expense_tracker/services/excel_export_service.dart';

void main() {
  test('creates a genuine workbook with typed amount columns', () {
    final bytes = createExpenseWorkbook([
      const Expense(
        id: 'expense-1',
        subject: 'Lunch',
        amountPaise: 5075,
        expenseDate: '2026-10-21',
        createdAt: '2026-10-21T08:00:00Z',
        updatedAt: '2026-10-21T08:00:00Z',
      ),
    ]);
    final sheet = Excel.decodeBytes(bytes)['Expenses'];
    expect(sheet.rows.length, 2);
    expect(sheet.rows.first.length, 6);
    expect(
      sheet.rows.first.map((cell) => (cell?.value as TextCellValue).value.text),
      [
        'Date',
        'Subject',
        'Amount (₹)',
        'Category',
        'Description',
        'Payment Method',
      ],
    );
    expect(
      sheet.rows[1][1]?.value,
      isA<TextCellValue>().having((cell) => cell.value.text, 'text', 'Lunch'),
    );
    expect(
      sheet.rows[1][2]?.value,
      isA<DoubleCellValue>().having((cell) => cell.value, 'rupees', 50.75),
    );
    expect(
      sheet.rows[1][0]?.value,
      isA<DateCellValue>()
          .having((cell) => cell.year, 'year', 2026)
          .having((cell) => cell.month, 'month', 10)
          .having((cell) => cell.day, 'day', 21),
    );
    expect(sheet.rows[1][4]?.value, isA<TextCellValue>());
    expect((sheet.rows[1][4]?.value as TextCellValue).value.text, '');
    expect(sheet.rows[1][3]?.value, isA<TextCellValue>());
    expect((sheet.rows[1][3]?.value as TextCellValue).value.text, '');
  });

  test('empty exports still include the workbook headers', () {
    final sheet = Excel.decodeBytes(createExpenseWorkbook([]))['Expenses'];
    expect(sheet.rows.length, 1);
    expect(sheet.rows.first.length, 6);
  });

  test('date values never inherit a timestamp timezone', () {
    final sheet = Excel.decodeBytes(
      createExpenseWorkbook([
        const Expense(
          id: 'local-date',
          subject: 'Dinner',
          amountPaise: 99,
          expenseDate: '2026-01-01',
          createdAt: '2025-12-31T18:30:00Z',
          updatedAt: '2025-12-31T18:30:00Z',
        ),
      ]),
    )['Expenses'];
    final date = sheet.rows[1][0]!.value as DateCellValue;
    expect(date.asDateTimeLocal(), DateTime(2026, 1, 1));
  });
}
