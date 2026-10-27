import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_database.dart';
import '../models/expense.dart';
import '../theme/app_theme.dart';

class ExpenseSearchScreen extends StatefulWidget {
  const ExpenseSearchScreen({
    super.key,
    required this.database,
    required this.onEdit,
    required this.onDelete,
  });

  final AppDatabase database;
  final Future<bool> Function(Expense expense) onEdit;
  final Future<bool> Function(Expense expense) onDelete;

  @override
  State<ExpenseSearchScreen> createState() => _ExpenseSearchScreenState();
}

class _ExpenseSearchScreenState extends State<ExpenseSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  late Future<List<Expense>> _results;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _results = _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<List<Expense>> _load(String query) =>
      widget.database.searchExpenses(query: query);

  void _queryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        _revision++;
        _results = _load(value.trim());
      });
    });
  }

  Future<void> _refreshResults() async {
    if (!mounted) return;
    setState(() {
      _revision++;
      _results = _load(_controller.text.trim());
    });
  }

  Future<void> _edit(Expense expense) async {
    if (await widget.onEdit(expense)) await _refreshResults();
  }

  Future<void> _delete(Expense expense) async {
    if (await widget.onDelete(expense)) await _refreshResults();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appPalette;
    return Scaffold(
      appBar: AppBar(title: const Text('Search expenses')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _queryChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search expenses...',
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _debounce?.cancel();
                            _controller.clear();
                            setState(() {
                              _revision++;
                              _results = _load('');
                            });
                          },
                          icon: const Icon(Icons.clear),
                        ),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Expense>>(
                key: ValueKey(_revision),
                future: _results,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Could not search expenses. Please try again.',
                      ),
                    );
                  }
                  final expenses = snapshot.data ?? const <Expense>[];
                  final searching = _controller.text.trim().isNotEmpty;
                  if (expenses.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 42,
                              color: colors.border,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              searching
                                  ? 'No matching expenses'
                                  : 'No expenses yet',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              searching
                                  ? 'Try a subject, amount, description, payment mode, category, or date.'
                                  : 'Saved expenses will appear here.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 4,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            searching
                                ? '${expenses.length} matching ${expenses.length == 1 ? 'expense' : 'expenses'}'
                                : '${expenses.length} ${expenses.length == 1 ? 'expense' : 'expenses'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: expenses.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final expense = expenses[index];
                            final details = <String>[
                              DateFormat('d MMM yyyy')
                                  .format(DateTime.parse(expense.expenseDate)),
                              if ((expense.category ?? '').isNotEmpty)
                                expense.category!,
                              if ((expense.paymentMethod ?? '').isNotEmpty)
                                expense.paymentMethod!,
                            ].join(' · ');
                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                key: ValueKey(expense.id),
                                leading: CircleAvatar(
                                  backgroundColor: colors.iconSurface,
                                  child: Icon(
                                    Icons.receipt_long_outlined,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                                ),
                                title: Text(
                                  expense.subject.isEmpty
                                      ? 'Expense'
                                      : expense.subject,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    details,
                                    if ((expense.description ?? '')
                                        .trim()
                                        .isNotEmpty)
                                      expense.description!.trim(),
                                  ].join('\n'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                isThreeLine: (expense.description ?? '')
                                    .trim()
                                    .isNotEmpty,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      formatPaise(expense.amountPaise),
                                      style: TextStyle(
                                        color: colors.expense,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: 'Expense actions',
                                      onSelected: (action) => action == 'edit'
                                          ? _edit(expense)
                                          : _delete(expense),
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
