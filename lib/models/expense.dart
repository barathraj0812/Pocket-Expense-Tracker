class Expense {
  const Expense({
    required this.id,
    required this.subject,
    required this.amountPaise,
    required this.expenseDate,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.paymentMethod,
    this.category,
    this.deletedAt,
  });
  final String id, subject, expenseDate, createdAt, updatedAt;
  final int amountPaise;
  final String? description, paymentMethod, category, deletedAt;
  factory Expense.fromMap(Map<String, Object?> m) => Expense(
    id: m['id'] as String,
    subject: m['subject'] as String,
    amountPaise: m['amount_paise'] as int,
    expenseDate: m['expense_date'] as String,
    createdAt: m['created_at'] as String,
    updatedAt: m['updated_at'] as String,
    description: m['description'] as String?,
    paymentMethod: m['payment_method'] as String?,
    category: m['category'] as String?,
    deletedAt: m['deleted_at'] as String?,
  );
  Map<String, Object?> toMap() => {
    'id': id,
    'subject': subject,
    'amount_paise': amountPaise,
    'expense_date': expenseDate,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'description': description,
    'payment_method': paymentMethod,
    'category': category,
    'deleted_at': deletedAt,
  };
}

int parseAmountPaise(String input) {
  final value = input.trim();
  if (!RegExp(r'^(?:0|[1-9]\d*)(?:\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException(
      'Enter a valid amount with up to two decimal places.',
    );
  }
  final parts = value.split('.');
  final rupees = BigInt.parse(parts[0]);
  final paise = BigInt.from(
    parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0')),
  );
  final amount = rupees * BigInt.from(100) + paise;
  if (amount <= BigInt.zero) {
    throw const FormatException('Amount must be greater than zero.');
  }
  if (amount > BigInt.from(0x7fffffffffffffff)) {
    throw const FormatException(
      'Amount exceeds the maximum value supported by local storage.',
    );
  }
  return amount.toInt();
}

String formatPaise(int paise) =>
    '₹${(paise ~/ 100)}.${(paise % 100).toString().padLeft(2, '0')}';
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
