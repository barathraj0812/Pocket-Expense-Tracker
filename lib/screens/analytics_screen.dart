import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_database.dart';
import '../models/expense.dart';
import '../services/expense_analytics_service.dart';
import '../services/analytics_export_service.dart';
import '../theme/app_theme.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({
    super.key,
    required this.database,
    required this.refreshToken,
    required this.onExpenseSelected,
  });

  final AppDatabase database;
  final int refreshToken;
  final Future<void> Function(Expense expense) onExpenseSelected;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late AnalyticsDateRange _range;
  late Future<AnalyticsDashboardData> _dashboard;
  int? _selectedTrendIndex;
  bool _showLargest = false;

  ExpenseAnalyticsService get _service =>
      ExpenseAnalyticsService(widget.database);

  @override
  void initState() {
    super.initState();
    _range = AnalyticsDateRange.fromPreset(AnalyticsPreset.thisMonth);
    _dashboard = _service.load(_range);
  }

  @override
  void didUpdateWidget(covariant AnalyticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _dashboard = _service.load(_range);
    }
  }

  void _setRange(AnalyticsDateRange range) {
    setState(() {
      _range = range;
      _selectedTrendIndex = null;
      _dashboard = _service.load(range);
    });
  }

  Future<void> _chooseCustomRange() async {
    final today = DateTime.now();
    final start = await showDatePicker(
      context: context,
      initialDate: _range.start ?? today,
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'Choose start date',
    );
    if (start == null || !mounted) return;
    final end = await showDatePicker(
      context: context,
      initialDate: _range.end ?? today,
      firstDate: start,
      lastDate: today,
      helpText: 'Choose end date',
    );
    if (end == null || !mounted) return;
    _setRange(AnalyticsDateRange.custom(start, end));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AnalyticsDashboardData>(
    future: _dashboard,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting &&
          !snapshot.hasData) {
        return Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      }
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Analytics could not be loaded.'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _dashboard = _service.load(_range);
                  }),
                  icon: const Icon(Icons.refresh),
                  label: Text('Try again'),
                ),
              ],
            ),
          ),
        );
      }
      final data = snapshot.data;
      if (data == null) return const SizedBox.shrink();
      return _content(data);
    },
  );

  Widget _content(AnalyticsDashboardData data) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Expense Analytics',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Export analytics report',
            onPressed: () => _export(data),
            icon: Icon(
              Icons.ios_share,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          IconButton(
            tooltip: 'Refresh analytics',
            onPressed: () => setState(() {
              _selectedTrendIndex = null;
              _dashboard = _service.load(_range);
            }),
            icon: Icon(
              Icons.refresh,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _rangeCard(data.range),
      const SizedBox(height: 8),
      Text(
        data.range.detailLabel,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 12),
      _summaryCards(data),
      const SizedBox(height: 4),
      _comparisonCard(data),
      const SizedBox(height: 4),
      _trendCard(data),
      const SizedBox(height: 4),
      _breakdownCard(
        title: 'Spending by subject',
        items: data.subjects,
        totalPaise: data.totalPaise,
        range: data.range,
        emptyMessage: 'No subjects to show in this date range.',
      ),
      _breakdownCard(
        title: 'Spending by category',
        items: data.categories,
        totalPaise: data.totalPaise,
        range: data.range,
        emptyMessage: 'No categories to show in this date range.',
      ),
      _breakdownCard(
        title: 'Spending by payment method',
        items: data.paymentMethods,
        totalPaise: data.totalPaise,
        range: data.range,
        emptyMessage: 'No payment methods to show in this date range.',
      ),
      _monthlyCard(data),
      _expenseListCard(data),
    ],
  );

  Widget _rangeCard(AnalyticsDateRange current) => _card(
    child: Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<AnalyticsPreset>(
            initialValue: current.preset,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Date range',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: AnalyticsPreset.thisMonth,
                child: Text('This month'),
              ),
              DropdownMenuItem(
                value: AnalyticsPreset.lastMonth,
                child: Text('Last month'),
              ),
              DropdownMenuItem(
                value: AnalyticsPreset.last7Days,
                child: Text('Last 7 days'),
              ),
              DropdownMenuItem(
                value: AnalyticsPreset.last30Days,
                child: Text('Last 30 days'),
              ),
              DropdownMenuItem(
                value: AnalyticsPreset.thisYear,
                child: Text('This year'),
              ),
              DropdownMenuItem(
                value: AnalyticsPreset.allTime,
                child: Text('All time'),
              ),
              DropdownMenuItem(
                value: AnalyticsPreset.custom,
                child: Text('Custom range'),
              ),
            ],
            onChanged: (preset) async {
              if (preset == null) return;
              if (preset == AnalyticsPreset.custom) {
                await _chooseCustomRange();
              } else {
                _setRange(AnalyticsDateRange.fromPreset(preset));
              }
            },
          ),
        ),
        if (current.preset == AnalyticsPreset.custom) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Edit custom dates',
            onPressed: _chooseCustomRange,
            icon: const Icon(Icons.edit_calendar_outlined),
          ),
        ],
      ],
    ),
  );

  Widget _summaryCards(AnalyticsDashboardData data) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _summaryCard(
            width,
            'TOTAL SPENT',
            formatPaise(data.totalPaise),
            Icons.account_balance_wallet_outlined,
            amount: true,
          ),
          _summaryCard(
            width,
            'EXPENSES',
            data.expenseCount.toString(),
            Icons.receipt_long_outlined,
          ),
          _summaryCard(
            width,
            'AVERAGE EXPENSE',
            data.averagePaise == null ? '—' : formatPaise(data.averagePaise!),
            Icons.functions,
            amount: true,
          ),
          _summaryCard(
            width,
            'LARGEST EXPENSE',
            data.largestExpense == null
                ? '—'
                : formatPaise(data.largestExpense!.amountPaise),
            Icons.trending_up,
            amount: true,
            detail: data.largestExpense == null
                ? 'No expenses in this period'
                : '${_subjectLabel(data.largestExpense!)} · ${_formatDate(data.largestExpense!.expenseDate)}',
          ),
        ],
      );
    },
  );

  Widget _summaryCard(
    double width,
    String title,
    String value,
    IconData icon, {
    bool amount = false,
    String? detail,
  }) => SizedBox(
    width: width,
    child: _card(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: .3,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: amount
                  ? context.appPalette.expense
                  : Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    ),
  );

  Widget _comparisonCard(AnalyticsDashboardData data) {
    final previous = data.previousTotalPaise;
    final title = switch (previous) {
      null => 'No previous-period comparison for All time',
      0 when data.totalPaise == 0 => 'No spending in either period',
      0 => 'Higher than previous period',
      _ when data.spendingIncreased => 'Higher than previous period',
      _ when data.spendingDecreased => 'Lower than previous period',
      _ => 'Same as previous period',
    };
    final percentage = data.percentageChange;
    final change = data.absoluteChangePaise;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PERIOD COMPARISON',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
            ),
          ),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
          if (previous != null) ...[
            const SizedBox(height: 6),
            Text('Current: ${formatPaise(data.totalPaise)}'),
            Text('Previous: ${formatPaise(previous)}'),
            Text(
              'Difference: ${formatPaise(change?.toInt() ?? 0)}'
              '${percentage == null ? '' : ' · ${percentage.abs().toStringAsFixed(1)}%'}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _trendCard(AnalyticsDashboardData data) {
    final points = data.trend;
    final nonEmpty = points.any((point) => point.expenseCount > 0);
    final selected = _selectedTrendIndex == null || points.isEmpty
        ? (points.isEmpty ? null : points.last)
        : points[_selectedTrendIndex!.clamp(0, points.length - 1)];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPENDING TREND',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 4),
          Text('Grouped by ${_grainLabel(data.trendGrain)}'),
          if (!nonEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text('No spending to chart in this range.')),
            )
          else ...[
            const SizedBox(height: 12),
            Semantics(
              label: 'Interactive spending trend. ${points.length} periods.',
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chartWidth = (points.length * 54.0)
                      .clamp(constraints.maxWidth, 1800.0)
                      .toDouble();
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        const left = 48.0;
                        const right = 10.0;
                        final usable = chartWidth - left - right;
                        final ratio =
                            ((details.localPosition.dx - left) / usable).clamp(
                              0.0,
                              1.0,
                            );
                        setState(() {
                          _selectedTrendIndex = (ratio * (points.length - 1))
                              .round();
                        });
                      },
                      child: SizedBox(
                        width: chartWidth,
                        height: 215,
                        child: CustomPaint(
                          painter: _TrendPainter(
                            points: points,
                            grain: data.trendGrain,
                            lineColor: Theme.of(context).colorScheme.primary,
                            gridColor: context.appPalette.chartGrid,
                            labelColor: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (selected != null)
              Text(
                '${_periodLabel(selected.start, selected.grain)}: '
                '${formatPaise(selected.totalPaise)} · ${selected.expenseCount} '
                '${selected.expenseCount == 1 ? 'expense' : 'expenses'}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _breakdownCard({
    required String title,
    required List<AnalyticsBreakdownItem> items,
    required int totalPaise,
    required AnalyticsDateRange range,
    required String emptyMessage,
  }) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.primary,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(emptyMessage),
          )
        else
          ...items.map((item) {
            final ratio = item.shareOfTotal(totalPaise).clamp(0.0, 1.0);
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openFiltered(
                range: range,
                field: item.filterField,
                value: item.isMissingValue ? null : item.label,
                missing: item.isMissingValue,
                title: item.label,
                largest: false,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.label,
                            softWrap: true,
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: ratio,
                              minHeight: 5,
                              backgroundColor: context.appPalette.iconSurface,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${item.expenseCount} ${item.expenseCount == 1 ? 'expense' : 'expenses'} · ${(ratio * 100).toStringAsFixed(1)}%',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatPaise(item.totalPaise),
                      style: TextStyle(
                        color: context.appPalette.expense,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        if (items.isNotEmpty) ...[
          const Divider(height: 16),
          Text('Tap a row to view matching expenses.'),
        ],
      ],
    ),
  );

  Widget _monthlyCard(AnalyticsDashboardData data) => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MONTHLY SUMMARY',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 4),
        Text('Average uses months with recorded expenses only.'),
        if (data.months.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('No recorded months in this date range.'),
          )
        else ...[
          const SizedBox(height: 8),
          _monthlyHighlight('Highest month', data.highestMonth),
          _monthlyHighlight('Lowest month with spending', data.lowestMonth),
          Text(
            'Average per active month: ${formatPaise(data.activeMonthAveragePaise!)}',
          ),
          Text('${data.months.length} month(s) with expenses'),
          const Divider(height: 16),
          ...data.months.reversed.map(
            (month) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(DateFormat('MMMM yyyy').format(month.start)),
                  ),
                  Text('${month.expenseCount}'),
                  const SizedBox(width: 12),
                  Text(
                    formatPaise(month.totalPaise),
                    style: TextStyle(
                      color: context.appPalette.expense,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _monthlyHighlight(
    String label,
    AnalyticsMonthSummary? month,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(
      month == null
          ? '$label: —'
          : '$label: ${DateFormat('MMMM yyyy').format(month.start)} · ${formatPaise(month.totalPaise)}',
    ),
  );

  Widget _expenseListCard(AnalyticsDashboardData data) {
    final expenses = _showLargest ? data.largestExpenses : data.recentExpenses;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EXPENSES IN THIS PERIOD',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Recent')),
              ButtonSegment(value: true, label: Text('Largest')),
            ],
            selected: {_showLargest},
            onSelectionChanged: (selected) =>
                setState(() => _showLargest = selected.first),
          ),
          if (expenses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('No expenses in this date range.'),
            )
          else ...[
            const SizedBox(height: 6),
            ...expenses.map((expense) => _expenseRow(expense)),
            TextButton.icon(
              onPressed: () => _openFiltered(
                range: data.range,
                title: _showLargest ? 'Largest expenses' : 'Recent expenses',
                largest: _showLargest,
              ),
              icon: const Icon(Icons.open_in_new),
              label: Text('View all'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _expenseRow(Expense expense) => ListTile(
    contentPadding: EdgeInsets.zero,
    onTap: () async {
      await widget.onExpenseSelected(expense);
      if (!mounted) return;
      setState(() => _dashboard = _service.load(_range));
    },
    title: Text(
      _subjectLabel(expense),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(
      '${_formatDate(expense.expenseDate)}${expense.category == null || expense.category!.trim().isEmpty ? '' : ' · ${expense.category}'}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Text(
      formatPaise(expense.amountPaise),
      style: TextStyle(
        color: context.appPalette.expense,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Future<void> _openFiltered({
    required AnalyticsDateRange range,
    required String title,
    required bool largest,
    String? field,
    String? value,
    bool missing = false,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _AnalyticsExpenseListScreen(
          database: widget.database,
          range: range,
          title: title,
          largestFirst: largest,
          filterField: field,
          filterValue: value,
          filterMissing: missing,
          onExpenseSelected: widget.onExpenseSelected,
        ),
      ),
    );
    if (mounted) setState(() => _dashboard = _service.load(_range));
  }

  Future<void> _export(AnalyticsDashboardData data) async {
    try {
      final bytes = createAnalyticsWorkbook(data);
      final directory = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File(
        '${directory.path}/PocketExpense_Analytics_$timestamp.xlsx',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await Share.shareXFiles([
        XFile(
          file.path,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ], text: 'Pocket Expense analytics report');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Analytics export failed. Your expenses are unchanged.',
          ),
        ),
      );
    }
  }

  Widget _card({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: padding,
    decoration: BoxDecoration(
      color: context.appPalette.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.appPalette.border),
    ),
    child: Material(
      color: context.appPalette.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}

class _AnalyticsExpenseListScreen extends StatefulWidget {
  const _AnalyticsExpenseListScreen({
    required this.database,
    required this.range,
    required this.title,
    required this.largestFirst,
    required this.onExpenseSelected,
    this.filterField,
    this.filterValue,
    this.filterMissing = false,
  });

  final AppDatabase database;
  final AnalyticsDateRange range;
  final String title;
  final bool largestFirst;
  final String? filterField;
  final String? filterValue;
  final bool filterMissing;
  final Future<void> Function(Expense expense) onExpenseSelected;

  @override
  State<_AnalyticsExpenseListScreen> createState() =>
      _AnalyticsExpenseListScreenState();
}

class _AnalyticsExpenseListScreenState
    extends State<_AnalyticsExpenseListScreen> {
  late Future<List<Expense>> _expenses;

  Future<List<Expense>> _load() => widget.database.analyticsExpenses(
    startDate: widget.range.start,
    endDate: widget.range.end,
    filterField: widget.filterField,
    filterValue: widget.filterValue,
    filterMissing: widget.filterMissing,
    largestFirst: widget.largestFirst,
  );

  @override
  void initState() {
    super.initState();
    _expenses = _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    appBar: AppBar(
      title: Text(widget.title),
      backgroundColor: Theme.of(context).colorScheme.surface,
      foregroundColor: Theme.of(context).colorScheme.primary,
    ),
    body: FutureBuilder<List<Expense>>(
      future: _expenses,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text('Expenses could not be loaded.'));
        }
        final expenses = snapshot.data ?? const <Expense>[];
        if (expenses.isEmpty) {
          return Center(child: Text('No matching expenses.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: expenses.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final expense = expenses[index];
            return ListTile(
              title: Text(_subjectLabel(expense), maxLines: 2),
              subtitle: Text(
                '${_formatDate(expense.expenseDate)} · ${expense.category?.trim().isNotEmpty == true ? expense.category : 'Uncategorized'}',
              ),
              trailing: Text(
                formatPaise(expense.amountPaise),
                style: TextStyle(
                  color: context.appPalette.expense,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onTap: () async {
                await widget.onExpenseSelected(expense);
                if (mounted) setState(() => _expenses = _load());
              },
            );
          },
        );
      },
    ),
  );
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.points,
    required this.grain,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<AnalyticsTrendPoint> points;
  final TrendGrain grain;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const left = 48.0;
    const right = 10.0;
    const top = 10.0;
    const bottom = 36.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final maximum = points
        .map((point) => point.totalPaise)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final scale = maximum == 0 ? 1.0 : maximum.toDouble();
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    for (var row = 0; row <= 2; row++) {
      final y = chart.top + chart.height * row / 2;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
      final value = maximum * (2 - row) ~/ 2;
      _drawText(canvas, _compactMoney(value), Offset(0, y - 7), 10);
    }

    final path = Path();
    final positions = <Offset>[];
    for (var index = 0; index < points.length; index++) {
      final x = points.length == 1
          ? chart.center.dx
          : chart.left + chart.width * index / (points.length - 1);
      final y =
          chart.bottom -
          chart.height * points[index].totalPaise.toDouble() / scale;
      final point = Offset(x, y);
      positions.add(point);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (positions.length == 1) {
      canvas.drawLine(
        Offset(chart.left, positions.single.dy),
        Offset(chart.right, positions.single.dy),
        linePaint,
      );
    } else {
      canvas.drawPath(path, linePaint);
    }
    for (final point in positions) {
      canvas.drawCircle(point, 3.5, dotPaint);
    }

    const maximumLabels = 6;
    final interval = (points.length / maximumLabels).ceil().clamp(
      1,
      points.length,
    );
    for (var index = 0; index < points.length; index += interval) {
      final x = positions[index].dx;
      _drawText(
        canvas,
        _shortPeriod(points[index].start, grain),
        Offset(x - 22, chart.bottom + 8),
        10,
      );
    }
    if ((points.length - 1) % interval != 0 && points.length > 1) {
      _drawText(
        canvas,
        _shortPeriod(points.last.start, grain),
        Offset(chart.right - 38, chart.bottom + 8),
        10,
      );
    }
  }

  void _drawText(Canvas canvas, String value, Offset offset, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontSize: size, color: labelColor),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 48);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.grain != grain;
}

String _subjectLabel(Expense expense) =>
    expense.subject.trim().isEmpty ? 'Unspecified subject' : expense.subject;

String _formatDate(String value) {
  final date = DateTime.tryParse(value);
  return date == null ? value : DateFormat('d MMM yyyy').format(date);
}

String _grainLabel(TrendGrain grain) => switch (grain) {
  TrendGrain.day => 'day',
  TrendGrain.week => 'week (Monday–Sunday)',
  TrendGrain.month => 'month',
  TrendGrain.year => 'year',
};

String _periodLabel(DateTime date, TrendGrain grain) => switch (grain) {
  TrendGrain.day => DateFormat('EEE, d MMM yyyy').format(date),
  TrendGrain.week => 'Week of ${DateFormat('d MMM yyyy').format(date)}',
  TrendGrain.month => DateFormat('MMMM yyyy').format(date),
  TrendGrain.year => date.year.toString(),
};

String _shortPeriod(DateTime date, TrendGrain grain) => switch (grain) {
  TrendGrain.day || TrendGrain.week => DateFormat('d MMM').format(date),
  TrendGrain.month => DateFormat('MMM yy').format(date),
  TrendGrain.year => date.year.toString(),
};

String _compactMoney(int paise) {
  final rupees = paise / 100;
  if (rupees.abs() >= 10000000) {
    return '₹${(rupees / 10000000).toStringAsFixed(1)}Cr';
  }
  if (rupees.abs() >= 100000) {
    return '₹${(rupees / 100000).toStringAsFixed(1)}L';
  }
  if (rupees.abs() >= 1000) {
    return '₹${(rupees / 1000).toStringAsFixed(1)}k';
  }
  return '₹${rupees.toStringAsFixed(0)}';
}
