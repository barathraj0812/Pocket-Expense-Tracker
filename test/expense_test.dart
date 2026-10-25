import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_expense_tracker/models/expense.dart';

void main() {
  group('amount conversion', () {
    test('converts rupees to canonical integer paise', () {
      expect(parseAmountPaise('50'), 5000);
      expect(parseAmountPaise('50.75'), 5075);
      expect(parseAmountPaise('0.01'), 1);
    });
    test('rejects zero, negatives, malformed and excessive precision', () {
      for (final value in ['0', '-50', '12.345', '', '1.', '  ', '1e3']) {
        expect(() => parseAmountPaise(value), throwsFormatException);
      }
    });
    test('formats paise without floating point', () {
      expect(formatPaise(5075), '₹50.75');
      expect(formatPaise(1), '₹0.01');
    });
  });
  test('date keys are zero padded and use local calendar fields', () {
    expect(dateKey(DateTime(2026, 1, 4)), '2026-01-04');
  });
}
