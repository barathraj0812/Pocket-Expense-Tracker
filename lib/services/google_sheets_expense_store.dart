import 'package:googleapis/sheets/v4.dart' as sheets;

import '../models/expense.dart';
import 'expense_sync_engine.dart';

class GoogleSheetsExpenseStore implements ExpenseRemoteStore {
  GoogleSheetsExpenseStore({required this.api, required this.spreadsheetId});

  static const expenseSheet = 'Expenses';
  static const legacySheet = '__PocketExpenseLegacy';
  static const headers = [
    'Date',
    'Subject',
    'Amount (₹)',
    'Category',
    'Description',
    'Payment Method',
    'Expense ID',
    'Deleted At',
  ];
  static const _legacyHeaders = [
    'id',
    'subject',
    'amount_paise',
    'expense_date',
    'created_at',
    'updated_at',
    'description',
    'payment_method',
    'category',
    'deleted_at',
  ];
  static const _previousCurrentHeaders = [
    'Subject',
    'Amount (₹)',
    'Category',
    'Date',
    'Description',
    'Payment Method',
  ];

  final sheets.SheetsApi api;
  final String spreadsheetId;
  bool _ready = false;

  static List<Object?> cellsFor(Expense expense) {
    final deleted = expense.deletedAt != null;
    return [
      if (deleted) '' else _displayDate(expense.expenseDate),
      if (deleted) '' else expense.subject,
      if (deleted) '' else expense.amountPaise / 100.0,
      if (deleted) '' else expense.category ?? '',
      if (deleted) '' else expense.description ?? '',
      if (deleted) '' else expense.paymentMethod ?? '',
      expense.id,
      expense.deletedAt ?? '',
    ];
  }

  static String _displayDate(String value) {
    final date = value.length >= 10 ? value.substring(0, 10) : value;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
    if (match == null) return date;
    return '${match[3]}-${match[2]}-${match[1]}';
  }

  static List<List<Object?>> remapPreviousCurrentRows(
    List<List<Object?>> rows,
  ) {
    if (rows.isEmpty) return [headers.cast<Object?>()];
    const sourceForTarget = [3, 0, 1, 2, 4, 5, 6, 7];
    return [
      headers.cast<Object?>(),
      for (final row in rows.skip(1))
        List<Object?>.generate(sourceForTarget.length, (target) {
          final source = sourceForTarget[target];
          return source < row.length ? row[source] : '';
        }),
    ];
  }

  @override
  Future<void> ensureReady() async {
    if (_ready) return;
    var spreadsheet = await _getSpreadsheet();
    var byTitle = _sheetsByTitle(spreadsheet);
    var expenseTab = byTitle[expenseSheet];
    var legacyTab = byTitle[legacySheet];
    List<List<Object?>>? legacyRows;

    if (expenseTab != null) {
      final header = await _values('$expenseSheet!A1:J1');
      if (GoogleSheetsExpenseStore._isLegacyHeader(
        header.firstOrNull ?? const [],
      )) {
        if (legacyTab != null) {
          throw const SyncFailure(
            'The spreadsheet contains both an old Expenses tab and a migration archive. No tabs were changed; review the spreadsheet before retrying.',
            retryable: false,
          );
        }
        legacyRows = await _values('$expenseSheet!A:J');
        await api.spreadsheets.batchUpdate(
          sheets.BatchUpdateSpreadsheetRequest(
            requests: [
              sheets.Request(
                updateSheetProperties: sheets.UpdateSheetPropertiesRequest(
                  properties: sheets.SheetProperties(
                    sheetId: expenseTab.properties!.sheetId,
                    title: legacySheet,
                    hidden: true,
                  ),
                  fields: 'title,hidden',
                ),
              ),
              sheets.Request(
                addSheet: sheets.AddSheetRequest(
                  properties: sheets.SheetProperties(title: expenseSheet),
                ),
              ),
            ],
          ),
          spreadsheetId,
        );
        spreadsheet = await _getSpreadsheet();
        byTitle = _sheetsByTitle(spreadsheet);
        expenseTab = byTitle[expenseSheet];
        legacyTab = byTitle[legacySheet];
      }
    }

    if (expenseTab == null) {
      await api.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(
          requests: [
            sheets.Request(
              addSheet: sheets.AddSheetRequest(
                properties: sheets.SheetProperties(title: expenseSheet),
              ),
            ),
          ],
        ),
        spreadsheetId,
      );
      spreadsheet = await _getSpreadsheet();
      byTitle = _sheetsByTitle(spreadsheet);
      expenseTab = byTitle[expenseSheet];
      legacyTab = byTitle[legacySheet];
    }

    final sheetId = expenseTab?.properties?.sheetId;
    if (sheetId == null) {
      throw const SyncFailure(
        'The saved spreadsheet has no usable Expenses tab. Local expenses remain queued.',
        retryable: false,
      );
    }

    final header = await _values('$expenseSheet!A1:H1');
    final row = header.firstOrNull ?? const [];
    if (row.isEmpty || row.firstOrNull == null || row.first == '') {
      final existingRows = await _values('$expenseSheet!A:H');
      if (existingRows.length > 1) {
        throw const SyncFailure(
          'The Expenses tab contains data without a recognized header. No data was changed; back up or review the tab before retrying.',
          retryable: false,
        );
      }
      final archiveRows =
          legacyRows ??
          (legacyTab == null ? null : await _values('$legacySheet!A:J'));
      final converted = archiveRows == null
          ? <List<Object?>>[]
          : _convertLegacy(archiveRows);
      await _writeInitialRows(sheetId, converted);
    } else if (GoogleSheetsExpenseStore._hasPreviousCurrentHeaders(row)) {
      final previousRows = await _values('$expenseSheet!A:H');
      final previousMeta = await _values('$expenseSheet!G1:H1');
      final meta = previousMeta.firstOrNull ?? const [];
      if (meta.length < 2 || meta[0] != headers[6] || meta[1] != headers[7]) {
        throw const SyncFailure(
          'The older Expenses tab is missing its stable ID or deletion metadata headers. No data was changed; restore those headers or create a new destination to preserve reliable synchronization.',
          retryable: false,
        );
      }
      final reordered = remapPreviousCurrentRows(previousRows);
      // One range write keeps each expense and its hidden ID/tombstone paired.
      // If the response is lost after commit, the new header makes retry safe.
      await _updateValues('$expenseSheet!A1:H${reordered.length}', reordered);
    } else if (!GoogleSheetsExpenseStore._hasCurrentHeaders(row)) {
      throw const SyncFailure(
        'The saved spreadsheet has an unrecognized Expenses layout. No existing data was changed; review or back up the tab before retrying.',
        retryable: false,
      );
    } else {
      final metaHeaders = await _values('$expenseSheet!G1:H1');
      final meta = metaHeaders.firstOrNull ?? const [];
      if (meta.length < 2 || meta[0] != headers[6] || meta[1] != headers[7]) {
        if (meta.any((value) => value.toString().isNotEmpty)) {
          throw const SyncFailure(
            'The Expenses tab already uses columns reserved for sync metadata. No cells were changed; review or back up the sheet before retrying.',
            retryable: false,
          );
        }
        await _updateValues('$expenseSheet!G1:H1', [headers.skip(6).toList()]);
      }
      // Resume an interrupted legacy migration only when the new tab has no
      // expense rows yet; never overwrite a populated current-format tab.
      final currentIds = await _values('$expenseSheet!G2:G');
      if (currentIds.isEmpty && legacyRows == null && legacyTab != null) {
        final archived = await _values('$legacySheet!A:J');
        if (archived.length > 1) {
          await _writeInitialRows(sheetId, _convertLegacy(archived));
        }
      }
    }

    await _formatAndHideInternalColumns(sheetId);
    if (legacyTab?.properties?.sheetId case final int oldSheetId) {
      await api.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(
          requests: [
            sheets.Request(
              updateSheetProperties: sheets.UpdateSheetPropertiesRequest(
                properties: sheets.SheetProperties(
                  sheetId: oldSheetId,
                  hidden: true,
                ),
                fields: 'hidden',
              ),
            ),
          ],
        ),
        spreadsheetId,
      );
    }
    _ready = true;
  }

  @override
  Future<void> apply(Expense expense) async {
    await ensureReady();
    final ids = await _values('$expenseSheet!G:G');
    final matches = <int>[];
    for (var i = 1; i < ids.length; i++) {
      if (ids[i].isNotEmpty && ids[i][0].toString() == expense.id) {
        matches.add(i + 1);
      }
    }
    final rowNumber = matches.isEmpty ? ids.length + 1 : matches.first;
    await _updateValues('$expenseSheet!A$rowNumber:H$rowNumber', [
      cellsFor(expense),
    ]);
    // Repair duplicate legacy rows for this stable identity without matching
    // on user-editable fields such as subject, amount, or date.
    for (final duplicateRow in matches.skip(1)) {
      await _updateValues('$expenseSheet!A$duplicateRow:H$duplicateRow', [
        List<Object?>.filled(headers.length, ''),
      ]);
    }
  }

  Future<sheets.Spreadsheet> _getSpreadsheet() => api.spreadsheets.get(
    spreadsheetId,
    $fields: 'spreadsheetId,sheets(properties(sheetId,title,hidden))',
  );

  Map<String, sheets.Sheet> _sheetsByTitle(sheets.Spreadsheet spreadsheet) => {
    for (final sheet in spreadsheet.sheets ?? <sheets.Sheet>[])
      if (sheet.properties?.title != null) sheet.properties!.title!: sheet,
  };

  Future<List<List<Object?>>> _values(String range) async {
    final response = await api.spreadsheets.values.get(spreadsheetId, range);
    return (response.values ?? const <List<Object?>>[])
        .map((row) => row.cast<Object?>())
        .toList();
  }

  Future<void> _updateValues(String range, List<List<Object?>> values) async {
    await api.spreadsheets.values.update(
      sheets.ValueRange(values: values),
      spreadsheetId,
      range,
      valueInputOption: 'RAW',
    );
  }

  List<List<Object?>> _convertLegacy(List<List<Object?>> rows) {
    final converted = <List<Object?>>[
      headers.map<Object?>((value) => value).toList(),
    ];
    final byId = <String, List<Object?>>{};
    for (final row in rows.skip(1)) {
      if (row.isEmpty || row.first.toString().isEmpty) continue;
      final paise = _asInt(row.elementAtOrNull(2));
      final deletedAt = row.elementAtOrNull(9)?.toString() ?? '';
      final id = row.first.toString();
      final convertedRow = <Object?>[
        if (deletedAt.isNotEmpty)
          ''
        else
          GoogleSheetsExpenseStore._displayDate(
            row.elementAtOrNull(3)?.toString() ?? '',
          ),
        if (deletedAt.isNotEmpty)
          ''
        else
          row.elementAtOrNull(1)?.toString() ?? '',
        if (deletedAt.isNotEmpty) '' else paise / 100.0,
        if (deletedAt.isNotEmpty)
          ''
        else
          row.elementAtOrNull(8)?.toString() ?? '',
        if (deletedAt.isNotEmpty)
          ''
        else
          row.elementAtOrNull(6)?.toString() ?? '',
        if (deletedAt.isNotEmpty)
          ''
        else
          row.elementAtOrNull(7)?.toString() ?? '',
        id,
        deletedAt,
      ];
      final previous = byId[id];
      // If an old retry already created duplicate rows, retain one logical row
      // by stable ID. A tombstone always wins so migration cannot resurrect it.
      if (previous == null ||
          (previous[7].toString().isEmpty && deletedAt.isNotEmpty) ||
          (previous[7].toString().isEmpty && deletedAt.isEmpty)) {
        byId[id] = convertedRow;
      }
    }
    converted.addAll(byId.values);
    return converted;
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null && parsed >= 0) return parsed;
    throw const SyncFailure(
      'Legacy spreadsheet contains an invalid paise amount. Its archived data was preserved; correct the value before retrying migration.',
      retryable: false,
    );
  }

  Future<void> _writeInitialRows(int sheetId, List<List<Object?>> rows) async {
    final values = rows.isEmpty
        ? [headers.map<Object?>((value) => value).toList()]
        : rows;
    // Empty string values clear the active cells for tombstoned rows while
    // retaining IDs and deletion timestamps in the hidden metadata columns.
    await _updateValues('$expenseSheet!A1:H${values.length}', values);
  }

  Future<void> _formatAndHideInternalColumns(int sheetId) async {
    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests: [
          sheets.Request(
            updateDimensionProperties: sheets.UpdateDimensionPropertiesRequest(
              range: sheets.DimensionRange(
                sheetId: sheetId,
                dimension: 'COLUMNS',
                startIndex: 6,
                endIndex: 8,
              ),
              properties: sheets.DimensionProperties(hiddenByUser: true),
              fields: 'hiddenByUser',
            ),
          ),
          sheets.Request(
            repeatCell: sheets.RepeatCellRequest(
              range: sheets.GridRange(
                sheetId: sheetId,
                startColumnIndex: 2,
                endColumnIndex: 3,
                startRowIndex: 1,
              ),
              cell: sheets.CellData(
                userEnteredFormat: sheets.CellFormat(
                  numberFormat: sheets.NumberFormat(
                    type: 'NUMBER',
                    pattern: '0.00',
                  ),
                ),
              ),
              fields: 'userEnteredFormat.numberFormat',
            ),
          ),
          sheets.Request(
            repeatCell: sheets.RepeatCellRequest(
              range: sheets.GridRange(
                sheetId: sheetId,
                startColumnIndex: 0,
                endColumnIndex: 1,
                startRowIndex: 1,
              ),
              cell: sheets.CellData(
                userEnteredFormat: sheets.CellFormat(
                  numberFormat: sheets.NumberFormat(
                    type: 'DATE',
                    pattern: 'dd-mm-yyyy',
                  ),
                ),
              ),
              fields: 'userEnteredFormat.numberFormat',
            ),
          ),
        ],
      ),
      spreadsheetId,
    );
  }

  static bool _isLegacyHeader(List<Object?> row) =>
      row.length >= _legacyHeaders.length &&
      _legacyHeaders.asMap().entries.every(
        (entry) => row[entry.key].toString() == entry.value,
      );

  static bool _hasCurrentHeaders(List<Object?> row) =>
      row.length >= 6 &&
      List.generate(
        6,
        (i) => row[i].toString(),
      ).asMap().entries.every((entry) => entry.value == headers[entry.key]);

  static bool _hasPreviousCurrentHeaders(List<Object?> row) =>
      row.length >= _previousCurrentHeaders.length &&
      List.generate(_previousCurrentHeaders.length, (i) => row[i].toString())
          .asMap()
          .entries
          .every((entry) => entry.value == _previousCurrentHeaders[entry.key]);
}
