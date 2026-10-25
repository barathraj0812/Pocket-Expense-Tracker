# Pocket Expense

An offline-first, expense-only Flutter app. Expenses are stored on-device in SQLite; amounts are stored as integer paise. Google Sheets is an optional user-authorized copy. Excel exports are generated locally as `.xlsx` workbooks.

## Run

1. Install Flutter and Android Studio, then open this directory.
2. Run `flutter pub get` and `flutter run` with an Android device or emulator.
3. Tap **Add expense**, optionally select a saved subject or type one, enter an amount, and save. The record is committed to the local database before the form closes. It remains available after restart and without a network connection.
4. Use Calendar to browse yearly and monthly totals, Report for monthly category/payment/day totals, and Misc. to export.

## Excel

Misc. → Excel export offers all records, the selected month, or an inclusive date range. The app builds a workbook with columns **Date**, **Subject**, **Amount (₹)**, **Category**, **Description**, and **Payment Method**, including typed date and numeric rupee cells, then shares the `.xlsx` file through Android's share sheet. The file is first staged in the app's temporary directory; choose a destination in the share sheet to keep it. Export works offline.

Misc. → **Customized Subject Drop-down Menu** lets you add, rename, and delete frequently used subjects. The list is local to this device and persists in SQLite. Rename and deletion only affect future selections; existing expense records are unchanged. Subjects remain optional, and **Enter a different subject…** lets you use a one-off value without adding it to the saved list.

## Google Sheets setup

The code requests Google sign-in and the Google Sheets scope. After explicit sign-in, it creates a spreadsheet named **Pocket Expense** and synchronizes rows by stable expense ID. The visible columns are **Date**, **Subject**, **Amount (₹)**, **Category**, **Description**, and **Payment Method**. Expense IDs and deletion timestamps are stored in hidden columns G:H. A deletion clears the visible expense cells while retaining its hidden tombstone, so later retries cannot restore a deleted expense. A recognized existing sheet with the previous six-column order is remapped in one range update by its headers, retaining metadata in G:H; unknown layouts or missing ID/tombstone headers are left untouched and require recovery.

An existing spreadsheet tab created by the earlier app schema is preserved as a hidden `__PocketExpenseLegacy` archive; a new `Expenses` tab is created and populated from that archive. If a saved spreadsheet becomes inaccessible, the app keeps local data and queued changes and does not silently create a replacement. Misc. → **Create a new spreadsheet destination** explicitly creates another destination and queues a complete local snapshot, including tombstones. Sync operations are durable, acknowledged individually, and retried with exponential delay. Permanent authorization or structure failures remain blocked until a user retries after correcting access or choosing a destination. The Misc. page shows the last successful sync time and pending count.

Sync runs in the foreground on app startup when a spreadsheet is configured, after saving an expense, and when you tap **Sync now**. There is no background worker or network-recovery monitor. Local expense entry, browsing, and Excel export continue to work offline.

Before connecting an account:

1. In Google Cloud Console create/select a project and enable **Google Sheets API**.
2. Configure the OAuth consent screen for the intended users.
3. Create an **Android OAuth client** with package name `com.example.pocket_expense_tracker` and the SHA-1 signing certificate fingerprint for the debug keystore used by this machine. On Windows, retrieve the debug fingerprint with `keytool -list -v -alias androiddebugkey -keystore %USERPROFILE%\.android\debug.keystore -storepass android -keypass android`. For a release build, register a separate client using the release signing certificate.
4. Ensure the account is allowed by the consent screen/test-user settings. No client secret is embedded in this app.
5. Build and install the app, open Misc., and choose **Connect Google / Create sheet**.

The available environment has no user's Google project credentials or signing configuration, so live sign-in and real API synchronization have not been verified. The implementation requires a network connection when creating/syncing a spreadsheet. Account changes and revoked access require a user-initiated reconnect or retry.

### Google Drive backups

Misc. → **Backup and Restore** supports manual SQLite backup upload and restore. Enable **Google Drive API** in the same Google Cloud project and add `https://www.googleapis.com/auth/drive.file` to the OAuth consent screen's allowed scopes/test configuration. This least-privilege scope lets the app create and access files it created or files explicitly opened for it; it does not grant unrestricted access to the user's Drive. The app creates a tagged **Pocket Expense Backups** folder and lists only its own tagged backup files. Drive backup and restore use the existing Google sign-in account, request the Drive scope when needed, and require network access. Real-account OAuth, upload, and restore still need verification with the configured Google project.

## Data and permissions

Financial entries and saved subjects remain in the app's SQLite database. The optional remote destination is only the spreadsheet created after an explicit Google sign-in. The local database uses schema version 4 and upgrades earlier versions in place, preserving expenses, tombstones, settings, and queued work while adding retry metadata and the custom-subject list. Internet permission is used for Google's sign-in/API traffic. Excel data is shared only after the user chooses an Android share destination. The app does not collect analytics.

## Development checks

Run `flutter analyze`, `flutter test`, and `flutter build apk --debug` from this folder. Tests cover paise parsing/formatting, date keys, SQLite persistence, restart and migration, transaction rollback, tombstones, durable retries, concurrent sync triggers, sheet row formatting, and workbook structure/typed cells. Google integration requires user OAuth configuration and cannot be verified without it.
