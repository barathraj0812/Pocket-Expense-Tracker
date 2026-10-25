import 'package:flutter/material.dart';

enum PolicyPage { privacy, storage, backup, information }

class PolicyScreen extends StatelessWidget {
  const PolicyScreen({super.key, required this.page});

  final PolicyPage page;

  @override
  Widget build(BuildContext context) {
    final content = switch (page) {
      PolicyPage.privacy => _privacy,
      PolicyPage.storage => _storage,
      PolicyPage.backup => _backup,
      PolicyPage.information => _information,
    };
    final title = switch (page) {
      PolicyPage.privacy => 'Privacy Policy',
      PolicyPage.storage => 'Data Storage and Synchronization',
      PolicyPage.backup => 'Backup and Restore Policy',
      PolicyPage.information => 'Application Information',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewPaddingOf(context).bottom + 24,
        ),
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Effective October 25, 2026',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          for (final section in content) ...[
            Text(
              section.$1,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(section.$2, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }

  static const _privacy = <(String, String)>[
    (
      'Information stored on this device',
      'Expense subjects, amounts, dates, descriptions, categories, payment methods, stable record identifiers, timestamps, deletion records, synchronization queue and retry state, saved subjects, and app settings are stored in the app’s SQLite database. Amounts are stored as integer paise.',
    ),
    (
      'Google Sheets',
      'Sheets is optional. When connected, the app synchronizes in the foreground at startup, after saving an expense, or when you request a sync. Google receives the expense fields and record metadata needed to keep the selected spreadsheet synchronized. Sign-in and Sheets API access use Google authentication and the Sheets scope.',
    ),
    (
      'Google Drive backups',
      'A Drive backup is uploaded only after you start it and grant the Google Drive file permission. The app creates and lists its own tagged backup files in Pocket Expense Backups. Restoring downloads the selected file to this device. You control your Google account and Drive files. These backup files are not end-to-end encrypted by this app.',
    ),
    (
      'Exported files and security',
      'SQLite backups and Excel exports are written or shared to a destination you choose. Other apps or people with access to that location may be able to read them. App-private local data benefits from Android’s application sandbox, but no storage method can guarantee absolute security. Treat unencrypted exports as personal financial information.',
    ),
    (
      'Sharing, retention and deletion',
      'The app has no app-operated backend, analytics, or advertising in its current implementation. Google processes data sent to Sheets or Drive under Google’s services. Deleting an expense locally queues a Sheets deletion when sync is enabled; this does not erase previously exported files or Drive backups. Manage spreadsheet rows and Drive backup files in those services.',
    ),
    (
      'Contact and external policy',
      'No support email or externally hosted privacy policy is configured in this project. A distribution channel that requires a public policy URL will need one to be published before distribution.',
    ),
  ];

  static const _storage = <(String, String)>[
    (
      'Local database',
      'SQLite is the primary source of truth. The database stores expenses in integer paise, custom subjects, settings, stable IDs, timestamps, deletion tombstones, and queued/retryable Sheets operations. Local entry, browsing, and exports work offline.',
    ),
    (
      'Google Sheets synchronization',
      'After a user connects Google, foreground sync may run on app startup and after saving an expense; a manual Sync now action is also available. Sync queue entries, retries, and tombstones are retained until acknowledged. Google authentication tokens are used for API requests and are not included in backup files.',
    ),
    (
      'Google Drive',
      'Drive access is user initiated and requests the restricted-to-app-files drive.file scope. The app creates a dedicated folder and only lists files it tags as its backups. It does not manage unrelated Drive files.',
    ),
  ];

  static const _backup = <(String, String)>[
    (
      'Local SQL backup',
      'The app creates a consistent SQLite snapshot and asks Android’s system document picker where to save it. Local backup and restore do not require Google or an internet connection.',
    ),
    (
      'Drive backup',
      'Drive upload is manual and starts only when you choose Back Up to Google Drive and approve the requested permission. Backup history is limited to files identified as created by this app.',
    ),
    (
      'Restore and synchronization',
      'Restore replaces the current local database with a validated backup after explicit confirmation. Changes made after that snapshot may be lost. A safety copy is made before replacement, and the database is verified after reopening. Sheets synchronization is paused after restore because a historical snapshot may omit newer records or deletion tombstones. Review the restored data; creating a new spreadsheet destination queues a complete local snapshot for that new destination.',
    ),
    (
      'Keep an independent copy',
      'Retain a separate backup before destructive operations. The app cannot recover a file deleted from a user-selected location or reverse changes made outside the app. Restoring an older backup may discard newer local changes and may not match the current spreadsheet.',
    ),
    (
      'Disclaimer',
      'Pocket Expense is intended for personal expense recording. You are responsible for retaining backups of records that are important to you.',
    ),
  ];

  static const _information = <(String, String)>[
    (
      'Pocket Expense Tracker',
      'Offline-first personal expense tracker. Application version 1.0.0. SQLite schema version 4. Expenses are stored locally in integer paise; optional Google Sheets synchronization and user-initiated Google Drive backups use Google services.',
    ),
    (
      'Limitations',
      'Restoring a historical backup replaces current local records and can make local data differ from an existing spreadsheet. Sync remains paused until you review the restore and explicitly configure a safe destination. No regulatory certification or externally hosted policy is asserted.',
    ),
  ];
}
