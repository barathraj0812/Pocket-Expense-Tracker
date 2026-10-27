import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/expense.dart';

class AppDatabase {
  AppDatabase({this.pathOverride});

  final String? pathOverride;
  Database? _db;
  String? _databasePath;
  Database get db => _db!;
  String get databasePath => _databasePath!;

  Future<void> open({bool recoverInterruptedRestore = true}) async {
    if (_db?.isOpen == true) return;
    final path =
        pathOverride ?? p.join(await getDatabasesPath(), 'pocket_expense.db');
    if (recoverInterruptedRestore) await _recoverInterruptedRestore(path);
    _databasePath = path;
    _db = await openDatabase(
      path,
      version: 4,
      onCreate: (d, v) async {
        await d.execute(
          'CREATE TABLE expenses(id TEXT PRIMARY KEY, subject TEXT NOT NULL, amount_paise INTEGER NOT NULL CHECK(amount_paise > 0), expense_date TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, description TEXT, payment_method TEXT, category TEXT, deleted_at TEXT, sync_status TEXT NOT NULL DEFAULT \'pending\')',
        );
        await d.execute(
          'CREATE INDEX expenses_date_idx ON expenses(expense_date)',
        );
        await d.execute(
          'CREATE TABLE sync_queue(id INTEGER PRIMARY KEY AUTOINCREMENT, expense_id TEXT NOT NULL, operation TEXT NOT NULL, created_at TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, next_attempt TEXT, last_error TEXT, blocked INTEGER NOT NULL DEFAULT 0, UNIQUE(expense_id, operation))',
        );
        await d.execute(
          'CREATE INDEX sync_queue_ready_idx ON sync_queue(next_attempt, id)',
        );
        await d.execute(
          'CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await d.execute(
          'CREATE TABLE custom_subjects(subject TEXT PRIMARY KEY)',
        );
      },
      onUpgrade: (d, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await d.execute('ALTER TABLE sync_queue ADD COLUMN last_error TEXT');
          await d.execute(
            'CREATE INDEX sync_queue_ready_idx ON sync_queue(next_attempt, id)',
          );
        }
        if (oldVersion < 3) {
          await d.execute(
            'ALTER TABLE sync_queue ADD COLUMN blocked INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 4) {
          await d.execute(
            'CREATE TABLE custom_subjects(subject TEXT PRIMARY KEY)',
          );
        }
      },
    );
  }

  Future<void> _recoverInterruptedRestore(String path) async {
    final marker = File('$path.restore_marker');
    final live = File(path);
    final previous = File('$path.restore_previous');
    final safety = File('$path.restore_safety');
    final candidate = File('$path.restore_candidate');
    if (!await marker.exists()) {
      // A crash before marking left only disposable staging files, or a crash
      // after commit left a verified live database plus stale recovery files.
      for (final file in [candidate, safety, previous]) {
        if (await file.exists()) await file.delete();
      }
      return;
    }
    if (await previous.exists()) {
      if (await live.exists()) await live.delete();
      await previous.rename(path);
    } else if (!await live.exists() && await safety.exists()) {
      await safety.rename(path);
    }
    if (await candidate.exists()) await candidate.delete();
    if (await safety.exists()) await safety.delete();
    await marker.delete();
  }

  /// Writes a transactionally consistent SQLite file. VACUUM INTO reads from
  /// the live connection and includes committed WAL contents in the snapshot.
  Future<void> createSqliteSnapshot(String destinationPath) async {
    await db.execute('VACUUM INTO ?', [destinationPath]);
  }

  Future<String> integrityCheck() async {
    final rows = await db.rawQuery('PRAGMA integrity_check');
    if (rows.length != 1) throw StateError('SQLite integrity check failed.');
    final result = rows.single.values.single;
    if (result != 'ok') throw StateError('SQLite integrity check failed.');
    return result as String;
  }

  Future<int> schemaVersion() async =>
      Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version')) ?? 0;

  Future<void> restoreSqliteSnapshot(String candidatePath) async {
    final livePath = databasePath;
    final live = File(livePath);
    final candidate = File(candidatePath);
    final previous = File('$livePath.restore_previous');
    final safety = File('$livePath.restore_safety');
    final marker = File('$livePath.restore_marker');
    if (!await candidate.exists()) {
      throw const FileSystemException('Validated restore file is missing.');
    }
    if (await previous.exists() ||
        await safety.exists() ||
        await marker.exists()) {
      throw const FileSystemException(
        'A previous restore recovery file needs attention before restoring again.',
      );
    }

    await createSqliteSnapshot(safety.path);
    await marker.writeAsString('restore-in-progress', flush: true);
    try {
      await close();
      if (await live.exists()) await live.rename(previous.path);
      await candidate.rename(live.path);
      await open(recoverInterruptedRestore: false);
      await integrityCheck();
      final foreignKeyViolations = await db.rawQuery(
        'PRAGMA foreign_key_check',
      );
      if (foreignKeyViolations.isNotEmpty) {
        throw const FormatException(
          'The restored database has invalid references.',
        );
      }
      if (await safety.exists()) await safety.delete();
      await marker.delete();
    } catch (_) {
      await close();
      if (await live.exists()) await live.delete();
      if (await previous.exists()) {
        await previous.rename(live.path);
      } else if (await safety.exists()) {
        await safety.rename(live.path);
      }
      if (await candidate.exists()) await candidate.delete();
      if (await safety.exists()) await safety.delete();
      if (await marker.exists()) await marker.delete();
      await open(recoverInterruptedRestore: false);
      await integrityCheck();
      rethrow;
    }
    // The new file is verified and the recovery marker is committed. A stale
    // previous file is harmless if filesystem cleanup itself fails.
    if (await previous.exists()) {
      try {
        await previous.delete();
      } on FileSystemException {
        // It is no longer needed for recovery after marker removal.
      }
    }
  }

  Future<void> add(Expense expense) async => db.transaction((t) async {
    await t.insert('expenses', {...expense.toMap(), 'sync_status': 'pending'});
    await _queue(t, expense.id, 'upsert');
  });

  /// Updates the existing stable identity and replaces any older queued
  /// operation with one upsert of the latest row state.
  Future<void> updateExpense(Expense expense) async =>
      db.transaction((t) async {
        final rows = await t.query(
          'expenses',
          columns: ['id', 'deleted_at'],
          where: 'id=?',
          whereArgs: [expense.id],
          limit: 1,
        );
        if (rows.isEmpty || rows.single['deleted_at'] != null) {
          throw StateError('Expense no longer exists.');
        }
        final changed = await t.update(
          'expenses',
          {...expense.toMap(), 'deleted_at': null, 'sync_status': 'pending'},
          where: 'id=? AND deleted_at IS NULL',
          whereArgs: [expense.id],
        );
        if (changed != 1) throw StateError('Expense could not be updated.');
        await t.delete(
          'sync_queue',
          where: 'expense_id=?',
          whereArgs: [expense.id],
        );
        await _queue(t, expense.id, 'upsert');
      });

  Future<void> _queue(Transaction t, String id, String operation) async {
    await t.insert('sync_queue', {
      'expense_id': id,
      'operation': operation,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'attempts': 0,
      'next_attempt': null,
      'last_error': null,
      'blocked': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Expense>> day(DateTime d) async =>
      _query('expense_date=?', [dateKey(d)]);

  Future<List<Expense>> month(int year, int month) async {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    return _query('expense_date>=? AND expense_date<?', [
      dateKey(start),
      dateKey(end),
    ]);
  }

  Future<List<Expense>> year(int year) => _query(
    'expense_date>=? AND expense_date<?',
    ['$year-01-01', '${year + 1}-01-01'],
  );

  Future<List<Expense>> all() => _query('1=1', []);

  Future<List<Expense>> range(DateTime start, DateTime end) => _query(
    'expense_date>=? AND expense_date<=?',
    [dateKey(start), dateKey(end)],
  );

  Future<List<Expense>> searchExpenses({
    DateTime? startDate,
    DateTime? endDate,
    String? subject,
    String? category,
    String? paymentMethod,
    String query = '',
  }) async {
    if (startDate != null && endDate != null && startDate.isAfter(endDate)) {
      throw ArgumentError('Start date must not come after end date.');
    }
    final conditions = <String>['deleted_at IS NULL'];
    final args = <Object?>[];
    if (startDate != null) {
      conditions.add('expense_date>=?');
      args.add(dateKey(startDate));
    }
    if (endDate != null) {
      conditions.add('expense_date<=?');
      args.add(dateKey(endDate));
    }
    if (subject != null) {
      conditions.add('subject=?');
      args.add(subject);
    }
    if (category != null) {
      conditions.add('category=?');
      args.add(category);
    }
    if (paymentMethod != null) {
      conditions.add('payment_method=?');
      args.add(paymentMethod);
    }
    final term = query.trim();
    if (term.isNotEmpty) {
      conditions.add(
        '(instr(lower(COALESCE(subject,\'\')),lower(?))>0 OR '
        'instr(lower(COALESCE(description,\'\')),lower(?))>0 OR '
        'instr(lower(COALESCE(category,\'\')),lower(?))>0 OR '
        'instr(lower(COALESCE(payment_method,\'\')),lower(?))>0 OR '
        'amount_paise=? OR expense_date=?)',
      );
      args.addAll([
        term,
        term,
        term,
        term,
        _searchAmountPaise(term) ?? -1,
        _searchDateKey(term) ?? '',
      ]);
    }
    final rows = await db.query(
      'expenses',
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: 'expense_date DESC, created_at DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  int? _searchAmountPaise(String term) {
    final normalized = term
        .replaceAll(',', '')
        .replaceFirst(RegExp(r'^₹\s*'), '');
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
    try {
      return parseAmountPaise(normalized);
    } on FormatException {
      return null;
    }
  }

  String? _searchDateKey(String term) {
    final numeric =
        RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(term) ??
        RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(term);
    if (numeric != null) {
      final isIso = term.contains('-') && numeric.group(1)!.length == 4;
      return _checkedDateKey(
        int.parse(numeric.group(isIso ? 1 : 3)!),
        int.parse(numeric.group(isIso ? 2 : 2)!),
        int.parse(numeric.group(isIso ? 3 : 1)!),
      );
    }
    final human = RegExp(r'^(\d{1,2})\s+([a-zA-Z]+)\s+(\d{4})$')
        .firstMatch(term.toLowerCase());
    if (human == null) return null;
    const months = <String>[
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    ];
    final monthName = human.group(2)!;
    final month =
        months.indexWhere(
          (name) => name == monthName || name.substring(0, 3) == monthName,
        ) +
        1;
    if (month == 0) return null;
    return _checkedDateKey(
      int.parse(human.group(3)!),
      month,
      int.parse(human.group(1)!),
    );
  }

  String? _checkedDateKey(int year, int month, int day) {
    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      return null;
    }
    return dateKey(value);
  }

  Future<List<String>> distinctExpenseValues(String field) async {
    if (!const {'subject', 'category', 'payment_method'}.contains(field)) {
      throw ArgumentError.value(field, 'field', 'Unsupported expense field');
    }
    final rows = await db.rawQuery(
      'SELECT DISTINCT $field AS value FROM expenses WHERE deleted_at IS NULL AND $field IS NOT NULL AND $field != \'\' ORDER BY value COLLATE NOCASE',
    );
    final values = rows.map((row) => row['value']! as String).toList();
    if (field == 'subject') {
      for (final saved in await customSubjects()) {
        if (!values.any(
          (value) => value.toLowerCase() == saved.toLowerCase(),
        )) {
          values.add(saved);
        }
      }
      values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    return values;
  }

  /// Summary queries use the same date-only bounds as the expense form and
  /// intentionally include pending-sync records while excluding tombstones.
  Future<Map<String, Object?>> analyticsTotals({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final (where, args) = _analyticsWhere(startDate, endDate);
    return (await db.rawQuery(
      'SELECT COALESCE(SUM(amount_paise), 0) AS total_paise, '
      'COUNT(*) AS expense_count FROM expenses WHERE $where',
      args,
    )).single;
  }

  Future<List<Map<String, Object?>>> analyticsBreakdown({
    required String field,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final missingLabel = switch (field) {
      'subject' => 'Unspecified subject',
      'category' => 'Uncategorized',
      'payment_method' => 'No payment method',
      _ => throw ArgumentError.value(field, 'field', 'Unsupported dimension'),
    };
    final (where, args) = _analyticsWhere(startDate, endDate);
    final value = "NULLIF(trim($field), '')";
    return db.rawQuery(
      'SELECT COALESCE($value, ?) AS label, '
      'CASE WHEN $value IS NULL THEN 1 ELSE 0 END AS is_missing, '
      'SUM(amount_paise) AS total_paise, COUNT(*) AS expense_count '
      'FROM expenses WHERE $where GROUP BY is_missing, label '
      'ORDER BY total_paise DESC, label COLLATE NOCASE ASC',
      [missingLabel, ...args],
    );
  }

  /// Returns grouped trend rows. `grain` is validated before it is embedded in
  /// the SQL expression; all user-controlled values remain bound parameters.
  Future<List<Map<String, Object?>>> analyticsTrend({
    required String grain,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final expression = switch (grain) {
      'day' => 'expense_date',
      'week' => "date(expense_date, '-' || ((CAST(strftime('%w', expense_date) AS INTEGER) + 6) % 7) || ' days')",
      'month' => 'substr(expense_date, 1, 7)',
      'year' => 'substr(expense_date, 1, 4)',
      _ => throw ArgumentError.value(grain, 'grain', 'Unsupported trend grain'),
    };
    final (where, args) = _analyticsWhere(startDate, endDate);
    return db.rawQuery(
      'SELECT $expression AS bucket, SUM(amount_paise) AS total_paise, '
      'COUNT(*) AS expense_count FROM expenses WHERE $where '
      'GROUP BY bucket ORDER BY bucket ASC',
      args,
    );
  }

  Future<List<Map<String, Object?>>> analyticsMonthlySummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final (where, args) = _analyticsWhere(startDate, endDate);
    return db.rawQuery(
      'SELECT substr(expense_date, 1, 7) AS month, '
      'SUM(amount_paise) AS total_paise, COUNT(*) AS expense_count '
      'FROM expenses WHERE $where GROUP BY month ORDER BY month ASC',
      args,
    );
  }

  Future<Map<String, Object?>?> analyticsDateBounds() async {
    final rows = await db.rawQuery(
      'SELECT MIN(expense_date) AS first_date, MAX(expense_date) AS last_date '
      'FROM expenses WHERE deleted_at IS NULL',
    );
    final row = rows.single;
    if (row['first_date'] == null) return null;
    return row;
  }

  Future<List<Expense>> analyticsExpenses({
    DateTime? startDate,
    DateTime? endDate,
    String? filterField,
    String? filterValue,
    bool filterMissing = false,
    bool largestFirst = false,
    int? limit,
  }) async {
    final (baseWhere, args) = _analyticsWhere(startDate, endDate);
    final conditions = [baseWhere];
    if (filterField != null) {
      if (!const {
        'subject',
        'category',
        'payment_method',
      }.contains(filterField)) {
        throw ArgumentError.value(
          filterField,
          'filterField',
          'Unsupported expense field',
        );
      }
      if (filterMissing) {
        conditions.add("NULLIF(trim($filterField), '') IS NULL");
      } else {
        conditions.add("trim($filterField)=?");
        args.add(filterValue);
      }
    }
    final rows = await db.query(
      'expenses',
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy: largestFirst
          ? 'amount_paise DESC, expense_date DESC, created_at DESC, id ASC'
          : 'expense_date DESC, created_at DESC, id ASC',
      limit: limit,
    );
    return rows.map(Expense.fromMap).toList();
  }

  (String, List<Object?>) _analyticsWhere(
    DateTime? startDate,
    DateTime? endDate,
  ) {
    if (startDate != null && endDate != null && startDate.isAfter(endDate)) {
      throw ArgumentError('Start date must not come after end date.');
    }
    final conditions = <String>['deleted_at IS NULL'];
    final args = <Object?>[];
    if (startDate != null) {
      conditions.add('expense_date>=?');
      args.add(dateKey(startDate));
    }
    if (endDate != null) {
      conditions.add('expense_date<=?');
      args.add(dateKey(endDate));
    }
    return (conditions.join(' AND '), args);
  }

  Future<Map<String, Object?>> backupSnapshot() async => {
    'expenses': await db.query('expenses', orderBy: 'expense_date, created_at'),
    'custom_subjects': await customSubjects(),
    'sync_queue': await pending(),
  };

  /// Atomically merges validated backup records without clearing current data.
  /// Tombstones win ID conflicts so an older active backup cannot revive a
  /// locally deleted expense. Imported/replaced records are queued for sync.
  Future<void> mergeBackup({
    required List<Map<String, Object?>> expenses,
    required List<String> subjects,
  }) async => db.transaction((t) async {
    for (final backup in expenses) {
      final id = backup['id']! as String;
      final localRows = await t.query(
        'expenses',
        where: 'id=?',
        whereArgs: [id],
        limit: 1,
      );
      if (localRows.isEmpty) {
        await t.insert('expenses', {...backup, 'sync_status': 'pending'});
        await _queue(t, id, backup['deleted_at'] == null ? 'upsert' : 'delete');
        continue;
      }

      final local = Expense.fromMap(localRows.single);
      final incoming = Expense.fromMap(backup);
      final useBackup = _backupRecordWins(local, incoming);
      if (!useBackup) continue;
      await t.update(
        'expenses',
        {...incoming.toMap(), 'sync_status': 'pending'},
        where: 'id=?',
        whereArgs: [id],
      );
      await t.delete('sync_queue', where: 'expense_id=?', whereArgs: [id]);
      await _queue(t, id, incoming.deletedAt == null ? 'upsert' : 'delete');
    }

    final savedRows = await t.query('custom_subjects', columns: ['subject']);
    final saved = savedRows
        .map((row) => (row['subject']! as String).toLowerCase())
        .toSet();
    for (final subject in subjects) {
      if (saved.add(subject.toLowerCase())) {
        await t.insert('custom_subjects', {'subject': subject});
      }
    }
  });

  bool _backupRecordWins(Expense local, Expense incoming) {
    if (local.deletedAt != null) {
      return incoming.deletedAt != null &&
          incoming.deletedAt!.compareTo(local.deletedAt!) > 0;
    }
    if (incoming.deletedAt != null) return true;
    return incoming.updatedAt.compareTo(local.updatedAt) > 0;
  }

  Future<List<Expense>> _query(String where, List<Object?> args) async =>
      (await db.query(
        'expenses',
        where: '$where AND deleted_at IS NULL',
        whereArgs: args,
        orderBy: 'expense_date DESC, created_at DESC',
      )).map(Expense.fromMap).toList();

  int total(List<Expense> expenses) =>
      expenses.fold<int>(0, (sum, expense) => sum + expense.amountPaise);

  Future<void> delete(Expense expense) async => db.transaction((t) async {
    final rows = await t.query(
      'expenses',
      columns: ['deleted_at'],
      where: 'id=?',
      whereArgs: [expense.id],
    );
    if (rows.isEmpty) throw StateError('Expense no longer exists.');
    if (rows.single['deleted_at'] != null) return;

    final now = DateTime.now().toUtc().toIso8601String();
    await t.update(
      'expenses',
      {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
      where: 'id=?',
      whereArgs: [expense.id],
    );
    // Deletion supersedes queued creates/updates for this same identity.
    await t.delete(
      'sync_queue',
      where: 'expense_id=? AND operation=?',
      whereArgs: [expense.id, 'upsert'],
    );
    await _queue(t, expense.id, 'delete');
  });

  Future<int> pendingCount() async =>
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM sync_queue'),
      ) ??
      0;

  Future<List<Map<String, Object?>>> pending() =>
      db.query('sync_queue', orderBy: 'id');

  Future<Expense?> byId(String id) async {
    final rows = await db.query('expenses', where: 'id=?', whereArgs: [id]);
    return rows.isEmpty ? null : Expense.fromMap(rows.first);
  }

  /// Acknowledge only the operation whose remote write was confirmed.
  /// A newer local change remains pending even if an older snapshot just synced.
  Future<void> acknowledgeSyncOperation(int queueId, Expense synced) async =>
      db.transaction((t) async {
        await t.delete('sync_queue', where: 'id=?', whereArgs: [queueId]);
        final rows = await t.query(
          'expenses',
          columns: ['updated_at', 'deleted_at'],
          where: 'id=?',
          whereArgs: [synced.id],
        );
        if (rows.isEmpty) return;
        final queued = await t.query(
          'sync_queue',
          columns: ['id'],
          where: 'expense_id=?',
          whereArgs: [synced.id],
          limit: 1,
        );
        final current = rows.single;
        final sameVersion =
            current['updated_at'] == synced.updatedAt &&
            current['deleted_at'] == synced.deletedAt;
        await t.update(
          'expenses',
          {'sync_status': queued.isEmpty && sameVersion ? 'synced' : 'pending'},
          where: 'id=?',
          whereArgs: [synced.id],
        );
      });

  Future<void> recordSyncFailure(
    int queueId, {
    required String message,
    required bool retryable,
  }) async {
    final rows = await db.query(
      'sync_queue',
      columns: ['attempts'],
      where: 'id=?',
      whereArgs: [queueId],
    );
    if (rows.isEmpty) return;
    final attempts = (rows.single['attempts'] as int) + 1;
    final retryAt = retryable
        ? DateTime.now().toUtc().add(
            Duration(seconds: 1 << (attempts - 1).clamp(0, 10)),
          )
        : null;
    await db.update(
      'sync_queue',
      {
        'attempts': attempts,
        'next_attempt': retryAt?.toIso8601String(),
        'last_error': message,
        'blocked': retryable ? 0 : 1,
      },
      where: 'id=?',
      whereArgs: [queueId],
    );
  }

  /// Explicit user action can retry authorization/permission/structure failures
  /// after the user has corrected the underlying issue.
  Future<void> releaseBlockedOperations() => db.update('sync_queue', {
    'blocked': 0,
    'next_attempt': null,
  }, where: 'blocked=1');

  Future<void> setSetting(String key, String value) async => db.insert(
    'app_settings',
    {'key': key, 'value': value},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> removeSetting(String key) =>
      db.delete('app_settings', where: 'key=?', whereArgs: [key]);

  Future<List<String>> customSubjects() async => (await db.query(
    'custom_subjects',
    columns: ['subject'],
    orderBy: 'subject COLLATE NOCASE',
  )).map((row) => row['subject']! as String).toList();

  Future<void> addCustomSubject(String value) async {
    final subject = value.trim();
    if (subject.isEmpty) throw const FormatException('Enter a subject.');
    await db.transaction((t) async {
      final rows = await t.query('custom_subjects', columns: ['subject']);
      if (rows.any(
        (row) =>
            (row['subject']! as String).toLowerCase() == subject.toLowerCase(),
      )) {
        throw const FormatException('That subject is already saved.');
      }
      await t.insert('custom_subjects', {'subject': subject});
    });
  }

  Future<void> renameCustomSubject(String oldValue, String newValue) async {
    final subject = newValue.trim();
    if (subject.isEmpty) throw const FormatException('Enter a subject.');
    await db.transaction((t) async {
      final rows = await t.query('custom_subjects', columns: ['subject']);
      final exists = rows.any(
        (row) =>
            (row['subject']! as String).toLowerCase() == oldValue.toLowerCase(),
      );
      if (!exists) throw StateError('Saved subject no longer exists.');
      if (rows.any(
        (row) =>
            (row['subject']! as String).toLowerCase() ==
                subject.toLowerCase() &&
            (row['subject']! as String).toLowerCase() != oldValue.toLowerCase(),
      )) {
        throw const FormatException('That subject is already saved.');
      }
      await t.update(
        'custom_subjects',
        {'subject': subject},
        where: 'subject=?',
        whereArgs: [oldValue],
      );
    });
  }

  Future<void> deleteCustomSubject(String subject) =>
      db.delete('custom_subjects', where: 'subject=?', whereArgs: [subject]);

  /// Switches to a user-selected destination and queues a complete local
  /// snapshot, including tombstones, before any later sync can acknowledge it.
  Future<void> switchSpreadsheet(String id, String accountEmail) async =>
      db.transaction((t) async {
        await t.insert('app_settings', {
          'key': 'spreadsheet_id',
          'value': id,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await t.insert('app_settings', {
          'key': 'google_account_email',
          'value': accountEmail,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await t.insert('app_settings', {
          'key': 'google_connected',
          'value': 'true',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await t.delete('sync_queue');
        await t.delete(
          'app_settings',
          where: 'key=?',
          whereArgs: ['last_successful_sync'],
        );
        // A new destination receives a complete local snapshot, so it is a
        // safe explicit way to resume sync after restoring an older backup.
        await t.delete(
          'app_settings',
          where: 'key=?',
          whereArgs: ['backup_restore_sync_paused'],
        );
        final rows = await t.query('expenses');
        for (final row in rows) {
          final expense = Expense.fromMap(row);
          await t.update(
            'expenses',
            {'sync_status': 'pending'},
            where: 'id=?',
            whereArgs: [expense.id],
          );
          await _queue(
            t,
            expense.id,
            expense.deletedAt == null ? 'upsert' : 'delete',
          );
        }
      });

  Future<String?> setting(String key) async {
    final rows = await db.query(
      'app_settings',
      where: 'key=?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> close() async {
    final current = _db;
    _db = null;
    if (current?.isOpen == true) await current!.close();
  }
}
