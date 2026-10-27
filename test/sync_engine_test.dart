import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_expense_tracker/data/app_database.dart';
import 'package:pocket_expense_tracker/models/expense.dart';
import 'package:pocket_expense_tracker/services/expense_sync_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late AppDatabase database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('expense_sync_test_');
    database = AppDatabase(pathOverride: '${directory.path}/expenses.db');
    await database.open();
  });

  test('Google sign-in configuration failure is actionable', () {
    final failure = SyncFailure.describe(
      PlatformException(code: 'sign_in_failed', message: 'ApiException: 10'),
    );

    expect(failure.retryable, isFalse);
    expect(failure.userMessage, contains('not configured'));
  });

  test('Google sign-in network failure is retryable', () {
    final failure = SyncFailure.describe(
      PlatformException(code: 'network_error'),
    );

    expect(failure.retryable, isTrue);
    expect(failure.userMessage, contains('internet connection'));
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  Expense record(String id) => Expense(
    id: id,
    subject: 'Lunch',
    amountPaise: 8050,
    expenseDate: '2026-10-21',
    createdAt: '2026-10-21T12:00:00Z',
    updatedAt: '2026-10-21T12:00:00Z',
  );

  test(
    'repeat sync applies one stable remote record and acknowledges queue',
    () async {
      final remote = _FakeRemoteStore();
      final engine = ExpenseSyncEngine(database: database, remote: remote);
      await database.add(record('stable-id'));

      await engine.sync();
      await engine.sync();

      expect(remote.active.keys, ['stable-id']);
      expect(remote.applyCount, 1);
      expect(await database.pendingCount(), 0);
      expect(await database.setting('last_successful_sync'), isNotNull);
    },
  );

  test('editing a synced expense updates the same remote ID', () async {
    final remote = _FakeRemoteStore();
    final engine = ExpenseSyncEngine(database: database, remote: remote);
    final original = record('edit-stable-id');
    await database.add(original);
    await engine.sync();

    final edited = Expense(
      id: original.id,
      subject: 'Updated lunch',
      amountPaise: 12550,
      expenseDate: '2026-10-20',
      createdAt: original.createdAt,
      updatedAt: '2026-10-22T12:00:00Z',
      description: 'Edited offline then synced',
      paymentMethod: 'UPI',
      category: 'Food',
    );
    await database.updateExpense(edited);
    await engine.sync();

    expect(remote.active.keys, ['edit-stable-id']);
    expect(remote.active['edit-stable-id']?.toMap(), edited.toMap());
    expect(remote.applyCount, 2);
    expect(await database.pendingCount(), 0);
  });

  test(
    'network failure leaves operation pending with retry metadata',
    () async {
      final remote = _FakeRemoteStore()..failure = TimeoutException('offline');
      final engine = ExpenseSyncEngine(database: database, remote: remote);
      await database.add(record('retry-id'));

      await expectLater(engine.sync(), throwsA(isA<SyncFailure>()));
      final pending = (await database.pending()).single;
      expect(pending['attempts'], 1);
      expect(pending['next_attempt'], isNotNull);
      expect(pending['last_error'], contains('remain queued'));
      expect(await database.pendingCount(), 1);

      remote.failure = null;
      await database.db.update('sync_queue', {
        'next_attempt': DateTime(2000).toIso8601String(),
      });
      await engine.sync();
      expect(await database.pendingCount(), 0);
      expect(remote.active.keys, ['retry-id']);
    },
  );

  test('permanent failure stays blocked until explicit user retry', () async {
    final remote = _FakeRemoteStore()
      ..failure = const SyncFailure('permission denied', retryable: false);
    final engine = ExpenseSyncEngine(database: database, remote: remote);
    await database.add(record('blocked-id'));

    await expectLater(engine.sync(), throwsA(isA<SyncFailure>()));
    expect((await database.pending()).single['blocked'], 1);
    remote.failure = null;
    await engine.sync();
    expect(remote.applyCount, 1);
    expect(await database.pendingCount(), 1);

    await engine.sync(retryBlocked: true);
    expect(remote.applyCount, 2);
    expect(await database.pendingCount(), 0);
  });

  test(
    'delete supersedes stale upsert and remains deleted on repeated sync',
    () async {
      final remote = _FakeRemoteStore();
      final engine = ExpenseSyncEngine(database: database, remote: remote);
      final expense = record('delete-id');
      await database.add(expense);
      await database.delete(expense);

      await engine.sync();
      await engine.sync();

      expect(remote.active, isEmpty);
      expect(remote.tombstones.keys, ['delete-id']);
      expect(await database.pendingCount(), 0);
    },
  );

  test(
    'overlapping triggers share one run and drain newly queued work',
    () async {
      final remote = _FakeRemoteStore()..gateFirstApply = true;
      final engine = ExpenseSyncEngine(database: database, remote: remote);
      await database.add(record('first-id'));

      final firstRun = engine.sync();
      await remote.firstApplyStarted.future;
      final overlappingRun = engine.sync();
      await database.add(record('second-id'));
      remote.releaseFirstApply.complete();
      await Future.wait([firstRun, overlappingRun]);

      expect(remote.active.keys.toSet(), {'first-id', 'second-id'});
      expect(remote.maxConcurrentApplies, 1);
      expect(await database.pendingCount(), 0);
    },
  );

  test(
    'a local delete during a remote upsert is not acknowledged as synced',
    () async {
      final remote = _FakeRemoteStore()..gateFirstApply = true;
      final engine = ExpenseSyncEngine(database: database, remote: remote);
      final expense = record('racing-delete');
      await database.add(expense);

      final run = engine.sync();
      await remote.firstApplyStarted.future;
      await database.delete(expense);
      remote.releaseFirstApply.complete();
      await run;

      expect(remote.active, isEmpty);
      expect(remote.tombstones.keys, ['racing-delete']);
      expect(await database.pendingCount(), 0);
    },
  );

  test('partial remote failure leaves only unfinished work queued', () async {
    final remote = _FakeRemoteStore()..failId = 'second';
    final engine = ExpenseSyncEngine(database: database, remote: remote);
    await database.add(record('first'));
    await database.add(record('second'));

    await expectLater(engine.sync(), throwsA(isA<SyncFailure>()));

    expect(remote.active.keys, ['first']);
    expect((await database.pending()).map((row) => row['expense_id']), [
      'second',
    ]);
  });
}

class _FakeRemoteStore implements ExpenseRemoteStore {
  final Map<String, Expense> active = {};
  final Map<String, String> tombstones = {};
  final Completer<void> firstApplyStarted = Completer<void>();
  final Completer<void> releaseFirstApply = Completer<void>();
  Object? failure;
  String? failId;
  bool gateFirstApply = false;
  int applyCount = 0;
  int _concurrentApplies = 0;
  int maxConcurrentApplies = 0;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<void> apply(Expense expense) async {
    _concurrentApplies++;
    if (_concurrentApplies > maxConcurrentApplies) {
      maxConcurrentApplies = _concurrentApplies;
    }
    try {
      applyCount++;
      if (gateFirstApply && applyCount == 1) {
        firstApplyStarted.complete();
        await releaseFirstApply.future;
      }
      if (failure != null) throw failure!;
      if (failId == expense.id) throw StateError('simulated rejection');
      if (expense.deletedAt != null) {
        active.remove(expense.id);
        tombstones[expense.id] = expense.deletedAt!;
      } else {
        active[expense.id] = expense;
        tombstones.remove(expense.id);
      }
    } finally {
      _concurrentApplies--;
    }
  }
}
