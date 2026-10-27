# Pocket Expense Tracker

**Pocket Expense Tracker v2.0.0** is an offline-first Flutter Android app for recording, organizing, searching, and reviewing personal expenses. Expense data is stored locally in SQLite. Optional Google Sheets synchronization, Excel export, analytics, and user-initiated backups help you manage and protect your records.

## Latest Version: v2.0.0

- **Version:** 2.0.0
- **Build number:** 2
- **Android application ID:** `dev.pages.barath.pocketexpense`

**Download:** Visit the [GitHub Releases page](https://github.com/barathraj0812/Pocket-Expense-Tracker/releases/latest) and download the v2.0.0 Android APK from its Assets section.

**[Download V2](https://github.com/barathraj0812/Pocket-Expense-Tracker/releases/download/v2.0.0/pocket_expense_trackerv2.apk)**

> **Installation note:** v2 uses the application ID `dev.pages.barath.pocketexpense`. An older installation using `com.example.pocket_expense_tracker` is treated as a separate app and has separate private storage. Export or back up your old expenses and verify the backup before switching or removing the older app.

## What's New in v2.0.0

- Added expense search.
- Improved expense database functionality.
- Improved Google Sheets synchronization and sync handling.
- Refined the application theme and interface.
- Updated the Android application ID to `dev.pages.barath.pocketexpense`.
- Updated project documentation and tests.

## Features

- **Expense tracking:** Add, edit, and delete expenses using a subject and amount. Description, category, and payment method can also be saved. Amounts are stored as integer paise.
- **Expense search:** Find expense records using the app's search screen.
- **Local-first use:** SQLite is the primary data store. Expense entry, browsing, search, and Excel export work without an internet connection.
- **Calendar and reports:** Browse daily expenses and calendar totals; review monthly totals by category, payment method, and day.
- **Analytics:** Select preset or custom date ranges, compare periods, explore spending trends and subject/category/payment-method breakdowns, and export an analytics report.
- **Saved subjects:** Add, rename, or delete reusable subjects. A one-off subject can be entered without saving it.
- **Appearance:** Save a light or dark mode preference.
- **Google Sheets:** Optionally connect a Google account to synchronize expenses to a spreadsheet. Sync is triggered in the foreground at app startup, after saving an expense, or when requested from the app. Changes queued while synchronization cannot complete can be retried when sync runs again.
- **Excel export:** Generate and share an `.xlsx` workbook for all expenses, a selected month, or an inclusive date range.
- **Backup and restore:** Save a SQLite backup to a location chosen through Android's document picker, or manually upload, list, and restore app-created backups in Google Drive.

## Screenshots

Add genuine screenshots of the v2.0.0 app to the repository before listing them here. Do not use placeholder or blank images as app screenshots.

## Install on Android

1. Open the [GitHub Releases page](https://github.com/barathraj0812/Pocket-Expense-Tracker/releases/latest).
2. Download the APK attached to the v2.0.0 release.
3. Wait for the download to finish, then open the APK from the browser's download notification or the Downloads folder.
4. If Android asks, allow installation from that specific source and confirm installation. The wording and settings location vary by Android version and manufacturer.
5. Open Pocket Expense Tracker.

Install APKs only from sources you trust. Android may warn about installing outside the Play Store; do not disable security protections globally. Installing over an existing copy may fail if the APK is incompatible or signed with a different certificate. No Google Play listing is configured in this project.

## Build from Source

### Requirements

- Git
- A Flutter SDK compatible with the Dart constraint in `pubspec.yaml` (`^3.13.5`)
- Android Studio or another working Android SDK/build-tools installation

### Debug build

```powershell
git clone https://github.com/barathraj0812/Pocket-Expense-Tracker.git
cd Pocket-Expense-Tracker
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

### Release APK

Release builds require the dedicated release keystore and `android/key.properties`. These signing credentials should remain outside source control. If you are building from a fresh clone, configure your own signing setup before building a release.

Create the keystore outside the repository. `keytool` prompts for passwords; do not put passwords directly in the command:

```powershell
New-Item -ItemType Directory -Force "C:\Users\<YourUser>\AndroidSigning"
keytool -genkeypair -v `
  -keystore "C:\Users\<YourUser>\AndroidSigning\pocket-expense-release.jks" `
  -storetype JKS `
  -keyalg RSA `
  -keysize 4096 `
  -validity 10000 `
  -alias pocket-expense
```

Create `android\key.properties` with your real values:

```properties
storePassword=REPLACE_WITH_KEYSTORE_PASSWORD
keyPassword=REPLACE_WITH_KEY_PASSWORD
keyAlias=pocket-expense
storeFile=C:/Users/<YourUser>/AndroidSigning/pocket-expense-release.jks
```

Replace every placeholder with your actual configuration. Keep the keystore and passwords backed up securely and separate from source control. Losing the key can prevent future APK updates from installing over the existing app.

Build the release APK:

```powershell
flutter build apk --release
```

Flutter writes the APK to `build\app\outputs\flutter-apk\app-release.apk`. Verify the APK signature against the certificate in the configured release keystore before distributing it. Renaming an APK does not change its signing certificate. Do not overwrite older release assets when preparing a new release.

## Google Services Setup

Google sign-in and API access require a Google Cloud project and OAuth configuration.

1. In Google Cloud Console, create or select a project and enable **Google Sheets API**. Enable **Google Drive API** if you plan to use Drive backups.
2. Configure the OAuth consent screen for the intended users. For Drive backups, allow the `https://www.googleapis.com/auth/drive.file` scope.
3. Create an Android OAuth client for package `dev.pages.barath.pocketexpense`, using the SHA-1 fingerprint for the certificate that signs the APK. The release certificate SHA-1 used for this project is `D8:5C:BF:F2:3F:76:D7:9B:47:76:F2:2C:6B:F5:FD:97:73:17:A6:9C`. Register the debug certificate separately if testing a debug build.
4. Ensure the Google account is permitted by the consent-screen and test-user configuration.
5. Install the configured app. In **Misc.**, choose **Connect Google / Create sheet** to create and connect a spreadsheet.

Do not place OAuth secrets, tokens, or signing credentials in this repository. Google Sheets synchronization requires connectivity for sign-in and API requests. Sync is foreground-triggered; the app does not implement continuous background synchronization or a network-recovery monitor. A spreadsheet that becomes inaccessible is not silently replaced; use the app's explicit destination or retry actions after resolving access.

## Android Application Identity

The Android application ID is `dev.pages.barath.pocketexpense`. Future APK releases must keep this ID and use the same signing certificate to install as updates.

The former `com.example.pocket_expense_tracker` installation is a separate Android app with separate private storage. Export or back up its data and verify the backup before removing it.

The Google Sheet's visible columns are **Date**, **Subject**, **Amount (₹)**, **Category**, **Description**, and **Payment Method**. Stable record IDs and deletion timestamps are stored in hidden columns. A deletion is synchronized as a tombstone so a retry does not recreate a removed row.

## Export, Backup, and Restore

### Excel export

From **Misc. → Excel export**, choose all records, a month, or an inclusive date range. The generated workbook contains date-first columns: Date, Subject, Amount (₹), Category, Description, and Payment Method. The app shares the `.xlsx` file through Android's share sheet; choose a destination there to keep it. Export is generated locally and works offline.

### Local SQLite backup

From **Misc. → Backup and Restore**, create a database snapshot and save it with Android's system document picker. Local backup and restore do not require Google sign-in or connectivity. Restore validates the selected database and asks for confirmation before replacing current local data.

### Google Drive backup

Drive backup upload, history listing, and restore are user-initiated in the same **Backup and Restore** screen and require Google sign-in, the Drive API, and network access. The app requests the `drive.file` scope and manages its tagged backups in its dedicated folder; this scope does not provide unrestricted access to all Drive files.

Restoring an older snapshot can discard expenses and settings created after that backup. The app creates a safety copy before replacement and pauses Sheets sync after restore until you review the data and choose how to proceed. Backups and exported files are not end-to-end encrypted by the app; protect any destination where you save them.

## Technology

| Component | Use |
| --- | --- |
| Flutter and Dart | Android application and UI |
| SQLite (`sqflite`) | On-device expense database, settings, subjects, and sync queue |
| Google Sign-In and Google APIs | Optional Sheets synchronization and Drive backup |
| `excel` | Local `.xlsx` workbook generation |
| Android document picker and share sheet | User-selected backup files and export destinations |

## Privacy and Data Handling

Expense details, custom subjects, app settings, and synchronization queue metadata are stored in the app's SQLite database on the device. Google receives expense fields and record metadata when the user connects and synchronizes a spreadsheet. Drive files are uploaded only when the user starts a backup and authorizes access. Exported files are shared through the destination selected by the user.

The app has no app-operated backend, advertising, or analytics collection. Google processes information sent to its services under Google's own terms. The in-app **Privacy Policy**, **Data Storage and Synchronization**, and **Backup and Restore Policy** pages describe these flows. Treat spreadsheets, backups, and exports as personal financial data.

## Known Limitations

- Google Sheets and Drive operations require the publisher's Google Cloud OAuth configuration, API access, and network connectivity.
- Sheets synchronization is foreground-triggered; it is not a continuous background service.
- Release signing requires the dedicated external keystore and ignored `android/key.properties` file.
- Restoring a historical database replaces local state and pauses Sheets synchronization for review.
- No Google Play listing is configured in this project.

## License and Copyright

No license file or license terms are specified in this repository. Unless the copyright holder grants permission, the source should not be assumed to be available for reuse, modification, or redistribution.

Copyright © 2026 Barath M · Chennai, Tamil Nadu, India.

## Links

- [GitHub repository](https://github.com/barathraj0812/Pocket-Expense-Tracker)
- [GitHub Releases](https://github.com/barathraj0812/Pocket-Expense-Tracker/releases)
- [Latest release](https://github.com/barathraj0812/Pocket-Expense-Tracker/releases/latest)
