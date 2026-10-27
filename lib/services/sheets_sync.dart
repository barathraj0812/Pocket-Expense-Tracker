import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../data/app_database.dart';
import 'expense_sync_engine.dart';
import 'google_sheets_expense_store.dart';

/// Foreground, user-consented synchronization. Access tokens are used only for
/// API requests and are never persisted.
class SheetsSync {
  SheetsSync(this.db, {GoogleSignIn? googleSignIn})
    : _google =
          googleSignIn ??
          GoogleSignIn(scopes: [sheets.SheetsApi.spreadsheetsScope]);

  final AppDatabase db;
  final GoogleSignIn _google;
  Future<void>? _activeSync;
  bool _connecting = false;
  bool _driveOperation = false;
  bool _retryBlockedRequested = false;

  bool get isBusy => _connecting || _activeSync != null || _driveOperation;

  Future<T?> withDriveBackupAccess<T>(
    Future<T> Function(String accessToken) operation,
  ) async {
    if (isBusy) {
      throw const SyncFailure(
        'Wait for the current Google operation to finish before accessing Drive.',
        retryable: false,
      );
    }
    _driveOperation = true;
    try {
      final account = await _google.signInSilently() ?? await _google.signIn();
      if (account == null) return null;
      final granted = await _google.requestScopes([
        drive.DriveApi.driveFileScope,
      ]);
      if (!granted) {
        throw const SyncFailure(
          'Google Drive permission was not granted. Local expenses were not uploaded.',
          retryable: false,
        );
      }
      final token = (await account.authentication).accessToken;
      if (token == null) {
        throw const SyncFailure(
          'Google Drive authorization is unavailable. Reconnect and try again.',
          retryable: false,
        );
      }
      return await operation(token);
    } catch (error) {
      throw SyncFailure.describe(error);
    } finally {
      _driveOperation = false;
    }
  }

  Future<bool> connect({bool createNewSpreadsheet = false}) async {
    if (_connecting || _activeSync != null || _driveOperation) {
      throw const SyncFailure(
        'Wait for the current Google operation to finish before changing spreadsheet settings.',
        retryable: false,
      );
    }
    _connecting = true;
    try {
      return await _connect(createNewSpreadsheet: createNewSpreadsheet);
    } finally {
      _connecting = false;
    }
  }

  Future<bool> _connect({required bool createNewSpreadsheet}) async {
    try {
      final account = await _google.signIn();
      if (account == null) return false;

      final savedId = await db.setting('spreadsheet_id');
      final savedEmail = await db.setting('google_account_email');
      if (savedId != null &&
          savedEmail != null &&
          savedEmail.toLowerCase() != account.email.toLowerCase() &&
          !createNewSpreadsheet) {
        throw const SyncFailure(
          'This spreadsheet is connected to a different Google account. Reconnect with the original account; no new spreadsheet was created.',
          retryable: false,
        );
      }

      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null) {
        throw const SyncFailure(
          'Google authorization is unavailable. Reconnect your account; local expenses remain safe.',
          retryable: false,
        );
      }

      final client = _AuthorizedClient(token);
      try {
        final api = sheets.SheetsApi(client);
        var spreadsheetId = savedId;
        final isChangingDestination =
            createNewSpreadsheet ||
            spreadsheetId == null ||
            spreadsheetId.isEmpty;
        if (isChangingDestination) {
          spreadsheetId = await db.setting('pending_spreadsheet_id');
        }
        if (isChangingDestination &&
            (spreadsheetId == null || spreadsheetId.isEmpty)) {
          final created = await api.spreadsheets.create(
            sheets.Spreadsheet(
              properties: sheets.SpreadsheetProperties(title: 'Pocket Expense'),
              sheets: [
                sheets.Sheet(
                  properties: sheets.SheetProperties(
                    title: GoogleSheetsExpenseStore.expenseSheet,
                  ),
                ),
              ],
            ),
            $fields: 'spreadsheetId',
          );
          spreadsheetId = created.spreadsheetId;
          if (spreadsheetId == null || spreadsheetId.isEmpty) {
            throw const SyncFailure(
              'Google did not return a spreadsheet ID. Local expenses remain safe.',
              retryable: true,
            );
          }
          // Keep a recoverable candidate so a retry after interrupted setup does
          // not create another spreadsheet.
          await db.setSetting('pending_spreadsheet_id', spreadsheetId);
        }

        final targetSpreadsheetId = spreadsheetId;
        if (targetSpreadsheetId == null || targetSpreadsheetId.isEmpty) {
          throw const SyncFailure(
            'No spreadsheet destination is available. Local expenses remain safe.',
            retryable: false,
          );
        }
        final store = GoogleSheetsExpenseStore(
          api: api,
          spreadsheetId: targetSpreadsheetId,
        );
        await store.ensureReady();
        if (isChangingDestination) {
          await db.switchSpreadsheet(targetSpreadsheetId, account.email);
          await db.removeSetting('pending_spreadsheet_id');
        } else {
          await db.setSetting('google_account_email', account.email);
          await db.setSetting('google_connected', 'true');
        }
        return true;
      } finally {
        client.close();
      }
    } catch (error) {
      throw SyncFailure.describe(error);
    }
  }

  Future<void> disconnect() async {
    if (_driveOperation) {
      throw const SyncFailure(
        'Wait for the Google Drive operation to finish before disconnecting.',
        retryable: false,
      );
    }
    await _google.signOut();
    await db.setSetting('google_connected', 'false');
  }

  Future<void> sync({bool retryBlocked = false}) {
    if (_driveOperation) {
      return Future<void>.error(
        const SyncFailure(
          'Wait for the Google Drive operation to finish before syncing.',
          retryable: false,
        ),
      );
    }
    if (retryBlocked) _retryBlockedRequested = true;
    final active = _activeSync;
    if (active != null) return active;
    late final Future<void> run;
    run = _syncAuthenticated().whenComplete(() {
      if (identical(_activeSync, run)) _activeSync = null;
    });
    _activeSync = run;
    return run;
  }

  Future<void> _syncAuthenticated() async {
    try {
      if (await db.setting('backup_restore_sync_paused') == 'true') {
        throw const SyncFailure(
          'Sheets sync is paused after restoring a backup. Review the restored records first, then create a new spreadsheet destination to safely sync a complete snapshot.',
          retryable: false,
        );
      }
      if (_connecting) {
        throw const SyncFailure(
          'Wait for Google account setup to finish before syncing.',
          retryable: false,
        );
      }
      final account = await _google.signInSilently();
      if (account == null) {
        throw const SyncFailure(
          'Connect the Google account associated with the saved spreadsheet. Local expenses remain queued.',
          retryable: false,
        );
      }
      final savedEmail = await db.setting('google_account_email');
      if (savedEmail != null &&
          savedEmail.toLowerCase() != account.email.toLowerCase()) {
        throw const SyncFailure(
          'The signed-in Google account does not match the account connected to this spreadsheet. Reconnect the original account.',
          retryable: false,
        );
      }
      final token = (await account.authentication).accessToken;
      if (token == null) {
        throw const SyncFailure(
          'Google authorization expired. Reconnect your Google account; local expenses remain queued.',
          retryable: false,
        );
      }
      final spreadsheetId = await db.setting('spreadsheet_id');
      if (spreadsheetId == null || spreadsheetId.isEmpty) {
        throw const SyncFailure(
          'No spreadsheet is connected. Connect Google before syncing.',
          retryable: false,
        );
      }

      final client = _AuthorizedClient(token);
      try {
        final remote = GoogleSheetsExpenseStore(
          api: sheets.SheetsApi(client),
          spreadsheetId: spreadsheetId,
        );
        final engine = ExpenseSyncEngine(database: db, remote: remote);
        do {
          final retryBlocked = _retryBlockedRequested;
          _retryBlockedRequested = false;
          await engine.sync(retryBlocked: retryBlocked);
        } while (_retryBlockedRequested);
      } finally {
        client.close();
      }
    } catch (error) {
      throw SyncFailure.describe(error);
    }
  }
}

class _AuthorizedClient extends http.BaseClient {
  _AuthorizedClient(this.token);

  final String token;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $token';
    return _inner.send(request).timeout(const Duration(seconds: 30));
  }

  @override
  void close() => _inner.close();
}
