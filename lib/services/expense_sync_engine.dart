import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../data/app_database.dart';
import '../models/expense.dart';

abstract interface class ExpenseRemoteStore {
  Future<void> ensureReady();
  Future<void> apply(Expense expense);
}

class SyncFailure implements Exception {
  const SyncFailure(this.userMessage, {required this.retryable});

  final String userMessage;
  final bool retryable;

  static SyncFailure describe(Object error) {
    if (error is SyncFailure) return error;
    _logFailure(error);
    if (error is PlatformException) {
      switch (error.code) {
        case 'sign_in_canceled':
          return const SyncFailure(
            'Google sign-in was cancelled. Connect again when you are ready.',
            retryable: false,
          );
        case 'network_error':
          return const SyncFailure(
            'Unable to reach Google. Check your internet connection and try again.',
            retryable: true,
          );
        case 'sign_in_failed':
          if (_isGoogleConfigurationFailure(error.message)) {
            return const SyncFailure(
              'Google sign-in is not configured for this app build. Contact the app owner.',
              retryable: false,
            );
          }
          return const SyncFailure(
            'Google sign-in failed. Please try connecting again.',
            retryable: true,
          );
      }
    }
    int? status;
    try {
      status = (error as dynamic).status as int?;
    } catch (_) {
      status = null;
    }
    if (status == 401) {
      return const SyncFailure(
        'Google authorization expired. Reconnect your Google account; local expenses remain queued.',
        retryable: false,
      );
    }
    if (status == 403) {
      return const SyncFailure(
        'Google denied access to the saved spreadsheet. Review its permissions and reconnect; local expenses remain queued.',
        retryable: false,
      );
    }
    if (status == 404) {
      return const SyncFailure(
        'The saved spreadsheet was not found. Local expenses remain safe and queued; no replacement spreadsheet was created.',
        retryable: false,
      );
    }
    if (status == 408 || status == 429 || (status != null && status >= 500)) {
      return const SyncFailure(
        'Google Sheets is temporarily unavailable. Local expenses remain queued and will be retried.',
        retryable: true,
      );
    }
    if (status != null) {
      return const SyncFailure(
        'Google Sheets rejected the sync request. Local expenses remain queued; check spreadsheet access and structure.',
        retryable: false,
      );
    }
    if (error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException) {
      return const SyncFailure(
        'Unable to reach Google. Check your internet connection and try again.',
        retryable: true,
      );
    }
    return const SyncFailure(
      'Sync failed. Your local expenses are safe and remain queued. Check your connection and try again.',
      retryable: true,
    );
  }

  static bool _isGoogleConfigurationFailure(String? message) {
    if (message == null) return false;
    return RegExp(r'(?:^|\D)10(?:\D|$)').hasMatch(message) ||
        message.contains('DEVELOPER_ERROR');
  }

  static void _logFailure(Object error) {
    if (!kDebugMode) return;
    final detail = error is PlatformException ? ' code=${error.code}' : '';
    debugPrint('Google sync failure: ${error.runtimeType}$detail');
  }

  @override
  String toString() => userMessage;
}

class ExpenseSyncEngine {
  ExpenseSyncEngine({required this.database, required this.remote});

  final AppDatabase database;
  final ExpenseRemoteStore remote;
  Future<void>? _activeRun;
  bool _retryBlockedRequested = false;

  /// Concurrent triggers join one run. The run re-reads the durable queue after
  /// each batch, so work added during a request is not lost with the second call.
  Future<void> sync({bool retryBlocked = false}) {
    if (retryBlocked) _retryBlockedRequested = true;
    final active = _activeRun;
    if (active != null) return active;
    late final Future<void> run;
    run = _run().whenComplete(() {
      if (identical(_activeRun, run)) _activeRun = null;
    });
    _activeRun = run;
    return run;
  }

  Future<void> _run() async {
    await remote.ensureReady();
    while (true) {
      if (_retryBlockedRequested) {
        _retryBlockedRequested = false;
        await database.releaseBlockedOperations();
      }
      final pending = await database.pending();
      final now = DateTime.now().toUtc();
      final ready = pending.where((operation) {
        if (operation['blocked'] == 1) return false;
        final retryAt = operation['next_attempt'] as String?;
        if (retryAt == null) return true;
        try {
          return !DateTime.parse(retryAt).isAfter(now);
        } on FormatException {
          // Corrupt retry metadata must not strand an otherwise valid operation.
          return true;
        }
      }).toList();
      if (ready.isEmpty) {
        if (_retryBlockedRequested) continue;
        break;
      }

      for (final operation in ready) {
        final operationId = operation['id'] as int;
        final expenseId = operation['expense_id'] as String;
        final expense = await database.byId(expenseId);
        if (expense == null) {
          const failure = SyncFailure(
            'A queued expense is missing from local storage. Its sync operation was kept for recovery.',
            retryable: false,
          );
          await database.recordSyncFailure(
            operationId,
            message: failure.userMessage,
            retryable: failure.retryable,
          );
          throw failure;
        }

        try {
          // Apply the latest local state, not a stale serialized queue payload.
          // A tombstone therefore wins over any older queued upsert.
          await remote.apply(expense);
          await database.acknowledgeSyncOperation(operationId, expense);
        } catch (error) {
          final failure = SyncFailure.describe(error);
          await database.recordSyncFailure(
            operationId,
            message: failure.userMessage,
            retryable: failure.retryable,
          );
          throw failure;
        }
      }
    }

    if (await database.pendingCount() == 0) {
      await database.setSetting(
        'last_successful_sync',
        DateTime.now().toUtc().toIso8601String(),
      );
    }
  }
}
