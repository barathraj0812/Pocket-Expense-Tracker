import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../models/expense.dart';
import 'analytics_screen.dart';
import 'backup_restore_screen.dart';
import 'custom_subjects_screen.dart';
import 'expense_search_screen.dart';
import 'policy_screen.dart';
import '../services/expense_sync_engine.dart';
import '../services/excel_export_service.dart';
import '../services/sheets_sync.dart';
import '../theme/app_theme.dart';
import '../widgets/app_footer.dart';
import '../widgets/custom_subject_field.dart';

const categories = [
  'Food',
  'Transport',
  'Education',
  'Shopping',
  'Bills',
  'Health',
  'Entertainment',
  'Groceries',
  'Travel',
  'Personal Care',
  'Other',
];
const methods = [
  'Cash',
  'UPI',
  'Debit Card',
  'Credit Card',
  'Bank Transfer',
  'Other',
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.database,
    this.isDarkMode = false,
    this.onDarkModeChanged,
  });
  final AppDatabase database;
  final bool isDarkMode;
  final Future<void> Function(bool value)? onDarkModeChanged;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  bool? _localDarkMode;
  DateTime selected = DateTime.now(),
      month = DateTime(DateTime.now().year, DateTime.now().month);
  int refresh = 0;
  late final SheetsSync sync = SheetsSync(widget.database);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await widget.database.setting('google_connected') == 'true' &&
          await widget.database.setting('backup_restore_sync_paused') !=
              'true' &&
          mounted) {
        await _runSync();
      }
    });
  }

  void changed() {
    setState(() => refresh++);
  }

  bool get _darkMode => _localDarkMode ?? widget.isDarkMode;

  Future<void> _setDarkMode(bool value) async {
    final callback = widget.onDarkModeChanged;
    if (callback == null) {
      setState(() => _localDarkMode = value);
    } else {
      await callback(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appPalette;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Pocket Expense Tracker',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: false,
        actions: (tab == 0 || tab == 2)
            ? [
                IconButton(
                  tooltip: 'Search all expenses',
                  onPressed: _openSearch,
                  icon: const Icon(Icons.search),
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: tab,
              children: [
                _daily(),
                _calendar(),
                _daily(),
                _report(),
                _analytics(),
                _misc(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: (tab == 0 || tab == 2)
          ? FloatingActionButton.extended(
              onPressed: _add,
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              icon: const Icon(Icons.add),
              label: Text('Add expense'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() {
          tab = i;
          if (i == 2) selected = DateTime.now();
        }),
        backgroundColor: colors.navigation,
        indicatorColor: colors.raisedSurface,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Expense',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Report',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            label: 'Analytics',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'Misc.'),
        ],
      ),
    );
  }

  Widget _analytics() => AnalyticsScreen(
    database: widget.database,
    refreshToken: refresh,
    onExpenseSelected: _details,
  );

  Widget _daily() => FutureBuilder<List<Expense>>(
    key: ValueKey('d$refresh${dateKey(selected)}'),
    future: widget.database.day(selected),
    builder: (c, s) {
      final rows = s.data ?? [];
      final sum = rows.fold<int>(0, (a, e) => a + e.amountPaise);
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
        children: [
          _dateHeader(),
          const SizedBox(height: 14),
          _card(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL SPENT',
                        style: TextStyle(
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatPaise(sum),
                        style: TextStyle(
                          color: context.appPalette.expense,
                          fontWeight: FontWeight.w800,
                          fontSize: 28,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${rows.length} ${rows.length == 1 ? 'expense' : 'expenses'}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (s.connectionState == ConnectionState.waiting)
            Center(child: CircularProgressIndicator())
          else if (rows.isEmpty)
            _empty(
              'No expenses for this day',
              'Add your first expense to start your book.',
            )
          else
            ...rows.map(_expenseTile),
        ],
      );
    },
  );
  Widget _dateHeader() => _card(
    child: Row(
      children: [
        IconButton(
          onPressed: () => setState(
            () => selected = selected.subtract(const Duration(days: 1)),
          ),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: InkWell(
            onTap: _pickDate,
            child: Column(
              children: [
                Text(
                  DateFormat('EEEE').format(selected),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  DateFormat('d MMMM yyyy').format(selected),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          onPressed: DateUtils.isSameDay(selected, DateTime.now())
              ? null
              : () => setState(
                  () => selected = selected.add(const Duration(days: 1)),
                ),
          icon: const Icon(Icons.chevron_right),
        ),
        IconButton(
          tooltip: 'Choose date',
          onPressed: _pickDate,
          icon: const Icon(Icons.edit_calendar_outlined),
        ),
      ],
    ),
  );
  Widget _expenseTile(Expense e) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: _card(
      child: ListTile(
        onTap: () => _details(e),
        leading: CircleAvatar(
          backgroundColor: context.appPalette.iconSurface,
          child: Icon(
            _icon(e.category),
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(e.subject, style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          [
                if ((e.category ?? '').isNotEmpty) e.category!,
                if ((e.paymentMethod ?? '').isNotEmpty) e.paymentMethod!,
                if ((e.description ?? '').trim().isNotEmpty)
                  e.description!.trim(),
              ].join(' · ').isEmpty
              ? 'Expense'
              : [
                  if ((e.category ?? '').isNotEmpty) e.category!,
                  if ((e.paymentMethod ?? '').isNotEmpty) e.paymentMethod!,
                  if ((e.description ?? '').trim().isNotEmpty)
                    e.description!.trim(),
                ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatPaise(e.amountPaise),
              style: TextStyle(
                color: context.appPalette.expense,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Expense actions',
              onSelected: (action) =>
                  action == 'edit' ? _editExpense(e) : _deleteExpense(e),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  Widget _calendar() => FutureBuilder<List<Expense>>(
    key: ValueKey('c$refresh${month.year}'),
    future: widget.database.year(month.year),
    builder: (c, s) {
      final rows = s.data ?? [];
      final totals = List<int>.filled(12, 0);
      for (final e in rows) {
        final m = int.parse(e.expenseDate.substring(5, 7));
        totals[m - 1] += e.amountPaise;
      }
      final yearTotal = totals.fold<int>(0, (a, b) => a + b);
      return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => setState(
                  () => month = DateTime(month.year - 1, month.month),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '${month.year}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              IconButton(
                onPressed: () => setState(
                  () => month = DateTime(month.year + 1, month.month),
                ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YEARLY EXPENSES',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  formatPaise(yearTotal),
                  style: TextStyle(
                    fontSize: 27,
                    color: context.appPalette.expense,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 12,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 120,
            ),
            itemBuilder: (c, i) => InkWell(
              onTap: () {
                setState(() {
                  final target = DateTime(month.year, i + 1);
                  month = DateTime(month.year, i + 1);
                  selected =
                      selected.year == target.year &&
                          selected.month == target.month
                      ? selected
                      : target.isAfter(DateTime.now())
                      ? DateTime.now()
                      : target;
                  tab = 0;
                });
              },
              child: _card(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('MMMM').format(DateTime(month.year, i + 1)),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatPaise(totals[i]),
                      style: TextStyle(
                        color: context.appPalette.expense,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  Widget _report() {
    return FutureBuilder<List<Expense>>(
      key: ValueKey('r$refresh${month.year}-${month.month}'),
      future: widget.database.month(month.year, month.month),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? <Expense>[];
        final total = rows.fold<int>(
          0,
          (sum, expense) => sum + expense.amountPaise,
        );
        final categories = <String, int>{};
        final payments = <String, int>{};
        final days = <String, int>{};
        for (final expense in rows) {
          final category = expense.category ?? 'Uncategorized';
          categories.update(
            category,
            (value) => value + expense.amountPaise,
            ifAbsent: () => expense.amountPaise,
          );
          if (expense.paymentMethod != null) {
            payments.update(
              expense.paymentMethod!,
              (value) => value + expense.amountPaise,
              ifAbsent: () => expense.amountPaise,
            );
          }
          days.update(
            expense.expenseDate,
            (value) => value + expense.amountPaise,
            ifAbsent: () => expense.amountPaise,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(
                    () => month = DateTime(month.year, month.month - 1),
                  ),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(month),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(
                    () => month = DateTime(month.year, month.month + 1),
                  ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MONTHLY SPENDING',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    formatPaise(total),
                    style: TextStyle(
                      color: context.appPalette.expense,
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                    ),
                  ),
                  Text('${rows.length} expenses'),
                ],
              ),
            ),
            if (rows.isEmpty)
              _empty(
                'Nothing to report yet',
                'Expenses recorded in this month appear here.',
              ),
            if (categories.isNotEmpty) ...[
              _section('By category', categories),
              _section('By payment method', payments),
              _section('Daily spending', days),
            ],
          ],
        );
      },
    );
  }

  Widget _section(String title, Map<String, int> values) => _card(
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
        Divider(color: context.appPalette.border),
        ...values.entries.map(
          (x) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(child: Text(x.key)),
                Text(
                  formatPaise(x.value),
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
    ),
  );
  Widget _misc() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text(
        'Tools & settings',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(height: 12),
      _card(
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            _darkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
          ),
          title: Text('Dark Mode'),
          subtitle: Text('Use a darker appearance throughout the app'),
          value: _darkMode,
          onChanged: _setDarkMode,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Text(
          'Backup and Restore',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
      ),
      _card(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.backup_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('Backup and Restore'),
          subtitle: const Text('Local SQLite and Google Drive backups'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BackupRestoreScreen(
                database: widget.database,
                sheetsSync: sync,
                onRestored: changed,
              ),
            ),
          ),
        ),
      ),
      _card(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.bookmark_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text('Customized Subject Drop-down Menu'),
          subtitle: Text('Save subjects for quicker expense entry'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CustomSubjectsScreen(database: widget.database),
            ),
          ),
        ),
      ),
      FutureBuilder<int>(
        future: widget.database.pendingCount(),
        builder: (c, s) => _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Google Sheets',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              FutureBuilder<String?>(
                future: widget.database.setting('spreadsheet_id'),
                builder: (c, id) => FutureBuilder<String?>(
                  future: widget.database.setting('google_connected'),
                  builder: (c, status) {
                    if (status.data != 'true' || id.data == null) {
                      return const Text('Google account not connected');
                    }
                    return Row(
                      children: [
                        const Icon(Icons.check_circle_outline, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Connected · ${id.data}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy spreadsheet ID',
                          visualDensity: VisualDensity.compact,
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: id.data!),
                            );
                            if (mounted) _message('Spreadsheet ID copied.');
                          },
                          icon: const Icon(Icons.copy_outlined, size: 18),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              Text('${s.data ?? 0} changes waiting in the local sync queue'),
              FutureBuilder<String?>(
                future: widget.database.setting('last_successful_sync'),
                builder: (context, snapshot) => Text(
                  snapshot.data == null
                      ? 'Last successful sync: never'
                      : 'Last successful sync: ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.parse(snapshot.data!).toLocal())}',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _connect,
                icon: const Icon(Icons.account_circle_outlined),
                label: Text('Connect Google / Create sheet'),
              ),
              OutlinedButton.icon(
                onPressed: () => _runSync(retryBlocked: true),
                icon: const Icon(Icons.sync),
                label: Text('Sync now'),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    await sync.disconnect();
                    if (!mounted) return;
                    changed();
                    _message(
                      'Google account disconnected. Local expenses are unchanged.',
                    );
                  } catch (_) {
                    _message(
                      'Could not disconnect Google right now. Try again.',
                    );
                  }
                },
                child: Text('Disconnect account'),
              ),
              TextButton(
                onPressed: _replaceSpreadsheet,
                child: Text('Create a new spreadsheet destination'),
              ),
            ],
          ),
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Excel export',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _action('Export all expenses', () => _export('all')),
            _action('Export selected month', () => _export('month')),
            _action('Export date range', () => _export('range')),
          ],
        ),
      ),
      const ListTile(
        title: Text('Pocket Expense'),
        subtitle: Text('Offline-first expense tracker · v1.0.0'),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Text(
          'App Information & Policies',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
      ),
      _policyLink(
        'Privacy Policy',
        Icons.privacy_tip_outlined,
        PolicyPage.privacy,
      ),
      _policyLink(
        'Data Storage and Synchronization',
        Icons.storage_outlined,
        PolicyPage.storage,
      ),
      _policyLink(
        'Backup and Restore Policy',
        Icons.policy_outlined,
        PolicyPage.backup,
      ),
      _policyLink(
        'Application Information',
        Icons.info_outline,
        PolicyPage.information,
      ),
      const SizedBox(height: 8),
      const AppFooter(),
    ],
  );

  Widget _policyLink(String label, IconData icon, PolicyPage page) => _card(
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => PolicyScreen(page: page))),
    ),
  );
  Future<void> _connect() async {
    try {
      final ok = await sync.connect();
      if (ok) {
        _message(
          'Pocket Expense spreadsheet connected. Syncing queued expenses…',
        );
        await _runSync(retryBlocked: true);
        changed();
      }
    } catch (e) {
      _message('Google connection failed: ${_safeSyncMessage(e)}');
    }
  }

  Future<void> _runSync({bool retryBlocked = false}) async {
    try {
      await sync.sync(retryBlocked: retryBlocked);
      if (mounted) {
        changed();
        final pending = await widget.database.pendingCount();
        if (mounted) {
          _message(
            pending == 0
                ? 'Synchronization completed.'
                : 'Sync paused with $pending changes still waiting to retry.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        changed();
        _message(_safeSyncMessage(e));
      }
    }
  }

  Future<void> _replaceSpreadsheet() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Create a new spreadsheet?'),
        content: Text(
          'This keeps the current spreadsheet unchanged and creates a new destination. All local expenses and deletion tombstones will be queued for the new sheet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final connected = await sync.connect(createNewSpreadsheet: true);
      if (!connected || !mounted) return;
      changed();
      _message('New spreadsheet created. Sending queued local changes…');
      await _runSync(retryBlocked: true);
    } catch (error) {
      _message(
        'Could not create the new spreadsheet: ${_safeSyncMessage(error)}',
      );
    }
  }

  String _safeSyncMessage(Object error) => error is SyncFailure
      ? error.userMessage
      : 'Your local expenses are safe. Check your connection and try again.';

  Widget _action(String label, VoidCallback fn) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Icon(
      Icons.ios_share,
      color: Theme.of(context).colorScheme.primary,
    ),
    onTap: fn,
  );
  Future<void> _export(String mode) async {
    try {
      DateTime? a, b;
      if (mode == 'range') {
        a = await showDatePicker(
          context: context,
          initialDate: selected,
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
        );
        if (a == null) return;
        if (!mounted) return;
        b = await showDatePicker(
          context: context,
          initialDate: a,
          firstDate: a,
          lastDate: DateTime.now(),
        );
        if (b == null) return;
      }
      final rows = mode == 'all'
          ? await widget.database.all()
          : mode == 'month'
          ? await widget.database.month(month.year, month.month)
          : await widget.database.range(a!, b!);
      final bytes = createExpenseWorkbook(rows);
      final dir = await getTemporaryDirectory();
      final suffix = mode == 'month'
          ? DateFormat('yyyy-MM').format(month)
          : mode == 'range'
          ? '${dateKey(a!)}_${dateKey(b!)}'
          : dateKey(DateTime.now());
      var file = '${dir.path}/PocketExpense_$suffix.xlsx';
      if (await File(file).exists()) {
        final time = DateFormat('HHmmss').format(DateTime.now());
        file = '${dir.path}/PocketExpense_${suffix}_$time.xlsx';
      }
      await XFile.fromData(
        bytes,
        name: file.split(Platform.pathSeparator).last,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ).saveTo(file);
      await Share.shareXFiles([
        XFile(
          file,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ], text: 'Pocket Expense export');
    } catch (e) {
      _message(
        'Export failed. Local expenses are unchanged; check storage and try again.',
      );
    }
  }

  Future<void> _add() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (c) => ExpenseForm(date: selected, database: widget.database),
    );
    if (result == true) {
      changed();
      if (await widget.database.setting('google_connected') == 'true' &&
          mounted) {
        await _runSync();
      }
    }
  }

  Future<void> _openSearch() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ExpenseSearchScreen(
          database: widget.database,
          onEdit: _editExpense,
          onDelete: _deleteExpense,
        ),
      ),
    );
  }

  Future<bool> _editExpense(Expense expense) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => ExpenseForm(
        date: DateTime.parse(expense.expenseDate),
        database: widget.database,
        expense: expense,
      ),
    );
    if (result != true || !mounted) return false;
    changed();
    if (await widget.database.setting('google_connected') == 'true' &&
        mounted) {
      await _runSync();
    }
    return true;
  }

  Future<bool> _deleteExpense(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete expense?'),
        content: const Text(
          'This expense will be removed from your views and marked for sync deletion.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    try {
      await widget.database.delete(expense);
      if (!mounted) return false;
      changed();
      if (await widget.database.setting('google_connected') == 'true' &&
          mounted) {
        await _runSync();
      }
      return true;
    } catch (_) {
      if (mounted) {
        _message('Could not delete this expense. It remains saved locally.');
      }
      return false;
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => selected = d);
  }

  Future<void> _details(Expense e) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(e.subject),
        content: Text(
          'Amount: ${formatPaise(e.amountPaise)}\nDate: ${e.expenseDate}\nCategory: ${e.category ?? '—'}\nPayment: ${e.paymentMethod ?? '—'}\nDescription: ${e.description?.isNotEmpty == true ? e.description : '—'}\nCreated: ${e.createdAt}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('Close')),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              await _editExpense(e);
            },
            child: const Text('Edit'),
          ),
          TextButton(
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: c,
                builder: (d) => AlertDialog(
                  title: Text('Delete expense?'),
                  content: Text(
                    'This expense will be removed from your views and marked for sync deletion.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: Text('Delete'),
                    ),
                  ],
                ),
              );
              if (yes == true) {
                try {
                  await widget.database.delete(e);
                  if (!context.mounted) return;
                  Navigator.pop(c);
                  changed();
                } catch (_) {
                  if (context.mounted) {
                    _message(
                      'Could not delete this expense. It remains saved locally.',
                    );
                  }
                }
              }
            },
            child: Text(
              'Delete',
              style: TextStyle(color: context.appPalette.expense),
            ),
          ),
        ],
      ),
    );
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Widget _empty(String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 55),
    child: Column(
      children: [
        Icon(
          Icons.menu_book_outlined,
          color: Theme.of(context).colorScheme.primary,
          size: 46,
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
      ],
    ),
  );
  Widget _card({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: padding,
    decoration: BoxDecoration(
      color: context.appPalette.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.appPalette.border),
      boxShadow: [
        BoxShadow(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .05),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Material(
      color: context.appPalette.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
  IconData _icon(String? category) => switch (category) {
    'Food' => Icons.restaurant_outlined,
    'Transport' => Icons.directions_bus_outlined,
    'Education' => Icons.menu_book_outlined,
    'Shopping' => Icons.shopping_bag_outlined,
    'Bills' => Icons.receipt_long_outlined,
    'Health' => Icons.health_and_safety_outlined,
    'Entertainment' => Icons.movie_outlined,
    'Groceries' => Icons.shopping_basket_outlined,
    'Travel' => Icons.flight_outlined,
    _ => Icons.savings_outlined,
  };
}

class ExpenseForm extends StatefulWidget {
  const ExpenseForm({
    super.key,
    required this.date,
    required this.database,
    this.expense,
  });
  final DateTime date;
  final AppDatabase database;
  final Expense? expense;
  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  final form = GlobalKey<FormState>();
  final subject = TextEditingController(),
      amount = TextEditingController(),
      description = TextEditingController();
  final subjectFocus = FocusNode();
  late Future<List<String>> savedSubjects;
  String? category, payment;
  late DateTime date;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final existing = widget.expense;
    date = existing == null
        ? widget.date
        : DateTime.parse(existing.expenseDate);
    if (existing != null) {
      subject.text = existing.subject;
      amount.text =
          (existing.amountPaise ~/ 100).toString() +
          (existing.amountPaise % 100 == 0
              ? ''
              : '.${(existing.amountPaise % 100).toString().padLeft(2, '0')}');
      description.text = existing.description ?? '';
      category = existing.category;
      payment = existing.paymentMethod;
    }
    savedSubjects = widget.database.customSubjects();
  }

  @override
  void dispose() {
    subject.dispose();
    subjectFocus.dispose();
    amount.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.expense == null ? 'New expense' : 'Edit expense',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                FutureBuilder<List<String>>(
                  future: savedSubjects,
                  builder: (context, snapshot) => CustomSubjectField(
                    controller: subject,
                    focusNode: subjectFocus,
                    savedSubjects: snapshot.data ?? const <String>[],
                  ),
                ),
                TextFormField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Amount (₹)'),
                  validator: (v) {
                    try {
                      parseAmountPaise(v ?? '');
                      return null;
                    } catch (e) {
                      return e is FormatException
                          ? e.message
                          : 'Enter a valid amount';
                    }
                  },
                ),
                TextFormField(
                  controller: description,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: payment,
                  decoration: const InputDecoration(
                    labelText: 'Mode of Payment (optional)',
                  ),
                  items: {...methods, ?payment}
                      .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                      .toList(),
                  onChanged: (v) => setState(() => payment = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                  ),
                  items: {...categories, ?category}
                      .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                      .toList(),
                  onChanged: (v) => setState(() => category = v),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Expense date'),
                  subtitle: Text(DateFormat('EEE, d MMM yyyy').format(date)),
                  trailing: Icon(
                    Icons.calendar_month,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setState(() => date = d);
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.pop(context, false),
                        child: Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving ? _noop : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary,
                        ),
                        child: saving
                            ? SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimary,
                                ),
                              )
                            : Text(
                                widget.expense == null
                                    ? 'Save expense'
                                    : 'Save changes',
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _noop() {}

  Future<void> _save() async {
    if (!form.currentState!.validate() || saving) return;
    setState(() => saving = true);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final existing = widget.expense;
      final expense = Expense(
        id: existing?.id ?? const Uuid().v4(),
        subject: subject.text.trim(),
        amountPaise: parseAmountPaise(amount.text),
        expenseDate: dateKey(date),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        description: description.text.trim().isEmpty
            ? null
            : description.text.trim(),
        paymentMethod: payment,
        category: category,
      );
      if (existing == null) {
        await widget.database.add(expense);
      } else {
        await widget.database.updateExpense(expense);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save locally. No expense was saved; check device storage and try again.',
          ),
        ),
      );
    }
  }
}
