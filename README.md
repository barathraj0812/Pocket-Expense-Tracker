# Pocket Expense Tracker

An offline-first Flutter app for recording and reviewing personal expenses. Records are stored locally in SQLite, with optional Google Sheets synchronization, Excel export, analytics, and user-initiated backups.

> [!IMPORTANT]
> **Coming soon — APK publication pending**
>
> **[Download Pocket Expense Tracker v1 for Android (.apk)](https://github.com/barathraj0812/Pocket-Expense-Tracker/releases/latest/download/pocket_expense_trackerv1.apk)**
>
> This direct download works only after a GitHub Release publishes an asset named exactly <code>pocket_expense_trackerv1.apk</code>. The release and asset have not been verified from this environment; no APK is being offered as available here.

## Features

- **Expense tracking:** Add, edit, and delete expenses with a subject and amount. Description, category, and payment method can be saved with a record. Amounts are stored as integer paise.
- **Local-first use:** SQLite is the primary data store. Expense entry, browsing, and Excel export work without an internet connection.
- **Calendar and reports:** Browse daily expenses and calendar totals; review monthly totals by category, payment method, and day.
- **Analytics:** Select preset or custom date ranges, compare periods, explore spending trends and subject/category/payment-method breakdowns, and export an analytics report.
- **Saved subjects:** Add, rename, or delete reusable subjects. A one-off subject can be entered without saving it.
- **Appearance:** The app supports a saved light/dark mode preference.
- **Google Sheets:** Optionally connect a Google account to synchronize expenses to a spreadsheet. Sync runs in the foreground at app startup, after saving an expense, or when requested from the app.
- **Excel export:** Generate and share an <code>.xlsx</code> workbook for all expenses, a selected month, or an inclusive date range.
- **Backup and restore:** Save a SQLite backup to a location chosen through Android’s document picker, or manually upload/list/restore app-created backups in Google Drive.

## Screenshots

No verified app-screen screenshots are included in the repository. The existing <code>pocket_screen.png</code> is blank, so it is not presented as an app screenshot.

## Install on Android

1. Open the [Pocket Expense Tracker repository](https://github.com/barathraj0812/Pocket-Expense-Tracker) and use the APK link near the top once the release asset is published.
2. Wait for the APK download to finish, then open it from the browser’s download notification or the Downloads folder.
3. If Android asks, allow installation from that specific source and confirm installation. The wording and settings location vary by Android version and manufacturer.
4. Open Pocket Expense Tracker.

Install APKs only from sources you trust. Android may warn about installing outside the Play Store; do not disable security protections globally. Installing over an existing copy may fail if the APK is incompatible or signed with a different certificate. No Google Play listing is configured in this project.

## Build from source

### Requirements

- Git
- A Flutter SDK compatible with the Dart constraint in <code>pubspec.yaml</code> (<code>^3.13.5</code>)
- Android Studio or another working Android SDK/build-tools installation

### Debug build

~~~powershell
git clone https://github.com/barathraj0812/Pocket-Expense-Tracker.git
cd Pocket-Expense-Tracker
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
~~~

### Release APK

Release builds use a dedicated release key and fail safely when the key is not configured. This checkout does not currently contain the required keystore or `android/key.properties`, so create and configure them before building a release.

Create the keystore outside the repository. `keytool` prompts for passwords; do not add passwords to the command:

~~~powershell
New-Item -ItemType Directory -Force "C:\Users\Murugan\AndroidSigning"
& "C:\Program Files\Android\Android Studio1\jbr\bin\keytool.exe" -genkeypair -v `
  -keystore "C:\Users\Murugan\AndroidSigning\pocket-expense-release.jks" `
  -storetype JKS `
  -keyalg RSA `
  -keysize 4096 `
  -validity 10000 `
  -alias pocket-expense
~~~

Create `android\key.properties` with the real values (the sample values below are placeholders and must be replaced):

~~~properties
storePassword=REPLACE_WITH_KEYSTORE_PASSWORD
keyPassword=REPLACE_WITH_KEY_PASSWORD
keyAlias=pocket-expense
storeFile=C:/Users/Murugan/AndroidSigning/pocket-expense-release.jks
~~~

The Android ignore rules exclude this properties file and keystore formats. Keep both the keystore and its passwords backed up securely, separate from source control. Losing the key can prevent future updates signed with it. Google Play App Signing may require a separate upload key; this project does not configure Play Console.

~~~powershell
flutter build apk --release
~~~

Flutter writes the APK to <code>build\app\outputs\flutter-apk\app-release.apk</code>. Verify the APK signature against the certificate in the configured release keystore before distributing it. Renaming the APK does not change its signing certificate. Do not overwrite older APKs when preparing a release asset.

## Google services setup

Google sign-in and API access require your own Google Cloud project and OAuth configuration. The project does not include user credentials or secrets, and live account/API behavior still needs verification with the intended project.

1. In Google Cloud Console, create or select a project and enable **Google Sheets API**. Enable **Google Drive API** too if using Drive backups.
2. Configure the OAuth consent screen for the intended users. For Drive backups, allow the <code>https://www.googleapis.com/auth/drive.file</code> scope.
3. Create an Android OAuth client for package <code>dev.pages.barath.pocketexpense</code> using the SHA-1 fingerprint for the signing certificate used by the build. The current release keystore SHA-1 is <code>D8:5C:BF:F2:3F:76:D7:9B:47:76:F2:2C:6B:F5:FD:97:73:17:A6:9C</code>. Register the debug certificate separately if testing a debug build.
4. Make sure the Google account is permitted by the consent-screen/test-user configuration.
5. Install the configured app. In **Misc.**, choose **Connect Google / Create sheet** to create and connect a spreadsheet.

Do not place OAuth secrets, tokens, or signing credentials in this repository. Google Sheets synchronization requires connectivity for sign-in and API requests. It is foreground-triggered; the app does not implement continuous background synchronization or a network-recovery monitor. Durable queued changes are retried when sync runs. A spreadsheet that becomes inaccessible is not silently replaced; use the app’s explicit destination/retry actions after resolving access.

## Android application identity

The Android application ID is <code>dev.pages.barath.pocketexpense</code>. Future APK releases must keep this ID and use the same signing certificate to install as updates. The former <code>com.example.pocket_expense_tracker</code> installation is a separate Android app with separate private storage; export or back up its data and verify the backup before removing it.

The sheet’s visible columns are **Date**, **Subject**, **Amount (₹)**, **Category**, **Description**, and **Payment Method**. Stable record IDs and deletion timestamps are kept in hidden columns. A deletion is synchronized as a tombstone so a retry does not recreate a removed row.

## Export, backup, and restore

### Excel

From **Misc. → Excel export**, choose all records, a month, or an inclusive date range. The generated workbook contains date-first columns: Date, Subject, Amount (₹), Category, Description, and Payment Method. The app shares the <code>.xlsx</code> file through Android’s share sheet; choose a destination there to keep it. Export is generated locally and works offline.

### Local SQLite backup

From **Misc. → Backup and Restore**, create a database snapshot and save it with Android’s system document picker. Local backup and restore do not require Google sign-in or connectivity. Restore validates the selected database and asks for confirmation before replacing current local data.

### Google Drive backup

Drive backup upload, history listing, and restore are user-initiated in the same **Backup and Restore** screen and require Google sign-in, the Drive API, and network access. The app requests the <code>drive.file</code> scope and manages its tagged backups in its dedicated folder; this scope is not unrestricted access to Drive files.

Restoring an older snapshot can discard expenses and settings created after that backup. The app creates a safety copy before replacement and pauses Sheets sync after restore until you review the data and choose how to proceed. Backups and exported files are not end-to-end encrypted by the app; protect any destination where you save them.

## Technology

| Component | Use |
| --- | --- |
| Flutter and Dart | Android application and UI |
| SQLite (<code>sqflite</code>) | On-device expense database, settings, subjects, and sync queue |
| Google Sign-In and Google APIs | Optional Sheets synchronization and Drive backup |
| <code>excel</code> | Local <code>.xlsx</code> workbook generation |
| Android document picker and share sheet | User-selected backup files and export destinations |

## Privacy and data handling

Expense details, custom subjects, app settings, and synchronization queue metadata are stored in the app’s SQLite database on the device. Google receives expense fields and record metadata only when the user connects and synchronizes a spreadsheet. Drive files are uploaded only when the user starts a backup and authorizes access. Exported files are shared only through the destination selected by the user.

The current implementation has no app-operated backend, advertising, or analytics collection. Google processes information sent to its services under Google’s own terms. The in-app **Privacy Policy**, **Data Storage and Synchronization**, and **Backup and Restore Policy** pages describe these flows. No standalone hosted privacy-policy URL or support email is configured in the repository. Treat spreadsheets, backups, and exports as personal financial data.

## Limitations

- The GitHub Release and required APK asset could not be verified from this environment. The direct download is marked pending until the exact asset is uploaded.
- Live Google OAuth, Sheets, and Drive operations require project-specific configuration and have not been verified against the publisher’s Google Cloud project.
- Sheets synchronization is foreground-triggered; it is not a background service.
- Release signing requires the dedicated external keystore and ignored <code>android/key.properties</code> file described above; they are not present in this checkout yet.
- Restoring a historical database replaces local state and pauses Sheets synchronization for review.

## License and copyright

No license file or license terms are specified in this repository. Unless the copyright holder grants permission, the source should not be assumed to be available for reuse, modification, or redistribution.

Copyright © 2026 Barath M · Chennai, Tamil Nadu, India.

## Links

- [GitHub repository](https://github.com/barathraj0812/Pocket-Expense-Tracker)
- [Latest release page](https://github.com/barathraj0812/Pocket-Expense-Tracker/releases/latest)
- [Direct APK download](https://github.com/barathraj0812/Pocket-Expense-Tracker/releases/latest/download/pocket_expense_trackerv1.apk) — pending publication of the correctly named release asset.
