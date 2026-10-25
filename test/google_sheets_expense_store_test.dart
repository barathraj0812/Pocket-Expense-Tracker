import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_expense_tracker/models/expense.dart';
import 'package:pocket_expense_tracker/services/google_sheets_expense_store.dart';

void main() {
  test('sheet mapping exposes six ordered columns and typed rupees', () {
    const expense = Expense(
      id: 'stable-internal-id',
      subject: 'Groceries',
      amountPaise: 8050,
      expenseDate: '2026-10-21',
      createdAt: '2026-10-21T20:30:00Z',
      updatedAt: '2026-10-21T20:30:00Z',
      description: 'Weekly shop',
      paymentMethod: 'UPI',
      category: 'Food',
    );

    expect(GoogleSheetsExpenseStore.headers.take(6), [
      'Date',
      'Subject',
      'Amount (₹)',
      'Category',
      'Description',
      'Payment Method',
    ]);
    final cells = GoogleSheetsExpenseStore.cellsFor(expense);
    expect(cells, [
      '21-10-2026',
      'Groceries',
      80.5,
      'Food',
      'Weekly shop',
      'UPI',
      'stable-internal-id',
      '',
    ]);
    expect(cells[2], isA<double>());
    expect(cells[6], 'stable-internal-id');
  });

  test(
    'tombstones clear visible data but retain hidden reconciliation fields',
    () {
      const deleted = Expense(
        id: 'deleted-internal-id',
        subject: 'Old expense',
        amountPaise: 1,
        expenseDate: '2026-01-02',
        createdAt: '2026-01-02T00:00:00Z',
        updatedAt: '2026-01-03T00:00:00Z',
        deletedAt: '2026-01-03T00:00:00Z',
      );

      expect(GoogleSheetsExpenseStore.cellsFor(deleted), [
        '',
        '',
        '',
        '',
        '',
        '',
        'deleted-internal-id',
        '2026-01-03T00:00:00Z',
      ]);
    },
  );

  test(
    'previous sheet rows migrate date-first with hidden metadata intact',
    () {
      final migrated = GoogleSheetsExpenseStore.remapPreviousCurrentRows([
        [
          'Subject',
          'Amount (₹)',
          'Category',
          'Date',
          'Description',
          'Payment Method',
          'Expense ID',
          'Deleted At',
        ],
        [
          'Groceries',
          80.5,
          'Food',
          '21-10-2026',
          'Weekly shop',
          'UPI',
          'stable-id',
          '',
        ],
        ['', '', '', '', '', '', 'deleted-id', '2026-10-22T00:00:00Z'],
      ]);

      expect(migrated.first, GoogleSheetsExpenseStore.headers);
      expect(migrated[1], [
        '21-10-2026',
        'Groceries',
        80.5,
        'Food',
        'Weekly shop',
        'UPI',
        'stable-id',
        '',
      ]);
      expect(migrated[2], [
        '',
        '',
        '',
        '',
        '',
        '',
        'deleted-id',
        '2026-10-22T00:00:00Z',
      ]);
    },
  );
}
