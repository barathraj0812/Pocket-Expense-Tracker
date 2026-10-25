import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pocket_expense_tracker/data/app_database.dart';
import 'package:pocket_expense_tracker/models/expense.dart';

void main() {
  late Directory directory;
  late AppDatabase database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pocket_expense_test_');
    database = AppDatabase(pathOverride: '${directory.path}/expenses.db');
    await database.open();
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  Expense expense({String date = '2026-01-31'}) => Expense(
    id: 'test-expense-1',
    subject: 'Lunch',
    amountPaise: 5075,
    expenseDate: date,
    createdAt: '2026-02-01T02:00:00Z',
    updatedAt: '2026-02-01T02:00:00Z',
  );

  test('stores locally and filters by day, month, and year', () async {
    await database.add(expense());
    expect((await database.day(DateTime(2026, 1, 31))).single.subject, 'Lunch');
    expect((await database.month(2026, 1)).single.amountPaise, 5075);
    expect((await database.year(2026)).length, 1);
    expect(await database.pendingCount(), 1);
  });

  test('an expense may be stored without a subject', () async {
    final record = expense();
    await database.add(
      Expense(
        id: record.id,
        subject: '',
        amountPaise: record.amountPaise,
        expenseDate: record.expenseDate,
        createdAt: record.createdAt,
        updatedAt: record.updatedAt,
      ),
    );
    expect((await database.all()).single.subject, '');
  });

  test('persists optional fields and exact paise values', () async {
    final record = Expense(
      id: 'complete-expense',
      subject: 'Train ticket',
      amountPaise: 8050,
      expenseDate: '2026-03-04',
      createdAt: '2026-03-04T23:50:00Z',
      updatedAt: '2026-03-04T23:50:00Z',
      description: 'Historical local date',
      paymentMethod: 'UPI',
      category: 'Travel',
    );
    await database.add(record);
    await database.close();
    database = AppDatabase(pathOverride: '${directory.path}/expenses.db');
    await database.open();

    final stored = (await database.all()).single;
    expect(stored.toMap(), record.toMap());
    expect(stored.amountPaise, 8050);
    expect(stored.expenseDate, '2026-03-04');
  });

  test(
    'identical visible expenses with different IDs remain distinct',
    () async {
      final first = expense();
      final second = Expense(
        id: 'test-expense-2',
        subject: first.subject,
        amountPaise: first.amountPaise,
        expenseDate: first.expenseDate,
        createdAt: first.createdAt,
        updatedAt: first.updatedAt,
      );
      await database.add(first);
      await database.add(second);

      expect(await database.all(), hasLength(2));
      expect(await database.pendingCount(), 2);
    },
  );

  test(
    'expense and queue insert roll back together on queue failure',
    () async {
      await database.db.execute('''
      CREATE TRIGGER reject_queue_insert BEFORE INSERT ON sync_queue
      BEGIN SELECT RAISE(ABORT, 'test queue failure'); END
    ''');

      await expectLater(database.add(expense()), throwsA(isA<Exception>()));
      expect(await database.byId('test-expense-1'), isNull);
      expect(await database.pendingCount(), 0);
    },
  );

  test(
    'version one database upgrades without losing expenses or queue',
    () async {
      await database.close();
      final path = '${directory.path}/expenses.db';
      await File(path).delete();
      final oldDb = await openDatabase(
        path,
        version: 1,
        onCreate: (d, version) async {
          await d.execute(
            'CREATE TABLE expenses(id TEXT PRIMARY KEY, subject TEXT NOT NULL, amount_paise INTEGER NOT NULL CHECK(amount_paise > 0), expense_date TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, description TEXT, payment_method TEXT, category TEXT, deleted_at TEXT, sync_status TEXT NOT NULL DEFAULT \'pending\')',
          );
          await d.execute(
            'CREATE INDEX expenses_date_idx ON expenses(expense_date)',
          );
          await d.execute(
            'CREATE TABLE sync_queue(id INTEGER PRIMARY KEY AUTOINCREMENT, expense_id TEXT NOT NULL, operation TEXT NOT NULL, created_at TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, next_attempt TEXT, UNIQUE(expense_id, operation))',
          );
          await d.execute(
            'CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await d.insert('expenses', expense().toMap());
          await d.insert('sync_queue', {
            'expense_id': 'test-expense-1',
            'operation': 'upsert',
            'created_at': '2026-02-01T02:00:00Z',
          });
        },
      );
      await oldDb.close();

      database = AppDatabase(pathOverride: path);
      await database.open();

      expect((await database.byId('test-expense-1'))?.amountPaise, 5075);
      expect(await database.pendingCount(), 1);
      expect((await database.pending()).single['last_error'], isNull);
    },
  );

  test(
    'data persists after reopening and uses expense date, not entry time',
    () async {
      await database.add(expense());
      await database.close();
      database = AppDatabase(pathOverride: '${directory.path}/expenses.db');
      await database.open();
      expect((await database.day(DateTime(2026, 1, 31))).length, 1);
      expect((await database.day(DateTime(2026, 2, 1))).length, 0);
    },
  );

  test('deletion hides the record and creates a sync tombstone', () async {
    final record = expense();
    await database.add(record);
    await database.delete(record);
    expect(await database.day(DateTime(2026, 1, 31)), isEmpty);
    expect((await database.byId(record.id))!.deletedAt, isNotNull);
    expect(await database.pendingCount(), 1);
  });

  test(
    'custom subjects trim whitespace and reject case-insensitive duplicates',
    () async {
      await database.addCustomSubject('  Stationery  ');
      expect(await database.customSubjects(), ['Stationery']);
      await expectLater(
        database.addCustomSubject('stationery'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        database.addCustomSubject('   '),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'custom subjects persist, rename, and delete without changing history',
    () async {
      final savedExpense = expense();
      await database.add(savedExpense);
      await database.addCustomSubject('Lunch');
      await database.renameCustomSubject('Lunch', '  Office Lunch  ');

      await database.close();
      database = AppDatabase(pathOverride: '${directory.path}/expenses.db');
      await database.open();
      expect(await database.customSubjects(), ['Office Lunch']);
      expect((await database.all()).single.subject, 'Lunch');

      await database.deleteCustomSubject('Office Lunch');
      expect(await database.customSubjects(), isEmpty);
      expect((await database.all()).single.subject, 'Lunch');
    },
  );

  test(
    'delete supersedes pending upsert and remains durable after reopen',
    () async {
      final record = expense();
      await database.add(record);
      await database.delete(record);
      expect(await database.pendingCount(), 1);
      expect((await database.pending()).single['operation'], 'delete');

      await database.close();
      database = AppDatabase(pathOverride: '${directory.path}/expenses.db');
      await database.open();
      expect((await database.byId(record.id))?.deletedAt, isNotNull);
      expect((await database.pending()).single['operation'], 'delete');
    },
  );
}
