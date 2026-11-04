# SpendWise

Offline personal Android expense tracker, built with Flutter, SQLite, Provider and Material 3. The appearance screen is one part of the application.

## Features

- Home: overall account balance, total expenses/income, individual Cash/bank/e-wallet balances, spending snapshot and quick actions.
- Transactions: month navigation, income/expense/balance summary, entries grouped by date with daily net totals, category icons and account names.
- Accounts: create/edit Cash, bank and e-wallet accounts with opening balances. Transfers move funds between accounts without changing income or expense totals.
- Add and edit income/expense transactions in RM, with category, local calendar date and optional description. Tap a record to edit; use the trash button or hold a record to delete with confirmation.
- Transactions filters: description/category search, type/category/date-range filters and newest/oldest ordering.
- Categories: create, rename, delete unused categories, or explicitly reassign all transactions/rules to another category of the same type before deletion.
- Analytics: day/week/month category pie charts, percentages, amounts and six-month expense bars, including empty states.
- Recurring expenses: daily, weekly or monthly, optional end date, edit, pause/resume or cancel future generation. Due records are generated at startup/resume and refresh. Paused rules catch up on resume. Monthly dates clamp to shorter months, then return to their original day (Jan 31 -> Feb 28/29 -> Mar 31). Schedule edits take effect today or later and retain recorded occurrences. Cancellation deactivates the rule; it never deletes its transactions.
- Appearance: Baby Blue or Soft Purple; Light, Dark or System mode; saved preferences and instant updates.
- Encrypted manual backup/import of financial records, including recurring rules.
- Optional six-digit PIN, enrolled device biometrics, manual lock and background timeout (immediate, 30 seconds, 1 minute or 5 minutes).

## Run on your phone using wireless debugging

Connect the PC and phone to the same Wi-Fi. Enable Developer options > Wireless debugging. Pair using the pairing-screen port/code, then connect using the separate port from the main Wireless debugging screen:

```powershell
adb pair PHONE_IP:PAIRING_PORT
adb connect PHONE_IP:DEBUGGING_PORT
flutter devices
flutter run -d "DEVICE_ID_FROM_FLUTTER_DEVICES"
```

If adb is not on PATH, use `C:\Users\gohch\AppData\Local\Android\Sdk\platform-tools\adb.exe`.

## APK and updates

Build with `flutter build apk --release`. The APK is at `build/app/outputs/flutter-apk/app-release.apk`.

This personal-use project currently signs release builds with the same local debug key as development builds so updates can preserve the existing installation. Keep that signing key and the application ID (`com.example.spendwise`) stable. This is not a Play Store signing setup. A different certificate will prevent an in-place update; do not uninstall to work around that before exporting your data.

Before every update, open Settings > Backup and restore, enter and confirm a passphrase of at least 12 characters, create the encrypted backup and save it somewhere you control through the share sheet. Verify that the saved `.swbackup` file exists. Keep the passphrase separately. Install an update over the existing app; do not clear storage or uninstall.

Example wireless installation:

```powershell
adb -s "DEVICE_ID_FROM_FLUTTER_DEVICES" install -r build/app/outputs/flutter-apk/app-release.apk
```

## Backup and recovery

Backups use AES-256-GCM with a random salt/nonce and a PBKDF2-HMAC-SHA256 key (600,000 iterations). The version-1 encrypted envelope now carries schema-2 accounts, transfers and financial records. Legacy schema-1 backups remain supported and place records under Main ledger with a zero opening balance. Backups contain a consistent logical snapshot taken inside a SQLite transaction, not a copied live database file. Passphrases are never stored in backups. Backup files are limited to 32 MB and 200,000 records per table during import.

The app writes and re-reads the encrypted cache file before opening the share sheet. The receiving app controls the final external save; confirm that it finished. Encrypted export copies may remain in the private cache until Android clears it.

Import requires the original passphrase. Authentication, format, schema, dates, foreign keys, constraints and SQLite integrity are checked in a separate staging database before asking to replace financial records. Live replacement is a single SQLite transaction, with rollback if any insertion/integrity check fails. Appearance and app-lock preferences are excluded. Importing overdue active rules may generate additional due occurrences when the application refreshes.

PIN access is protected by a salted PBKDF2 hash with a random pepper stored using Android Keystore-backed secure storage. Failed attempts cause increasing delays, up to five minutes, persisted across app restarts. Secure-storage errors fail closed. Biometrics are optional and never fall back to the Android device PIN. App lock protects the interface, not full database encryption. Android FLAG_SECURE prevents screenshots/recent-app preview capture where the OS honors it; Android automatic app backup is disabled.

There is no hidden forgotten-PIN bypass. If both PIN and biometrics are unavailable, recovery requires a previously exported encrypted backup and its passphrase, followed by an explicit Android app-data reset/reinstallation. This erases local data; the app never does it automatically. Restore the backup into the fresh installation. Lost passphrases cannot be recovered.

## Data and architecture

- `lib/database/app_database.dart`: schema version 2, safe migration entry point and foreign keys enabled on each connection. No automatic reset/downgrade deletion.
- `lib/repositories/finance_repository.dart`: typed CRUD and atomic category reassignment.
- `lib/providers/finance_store.dart`: ChangeNotifier state loaded from SQLite; local period calculations.
- `lib/services/`: recurrence, encrypted backup and secure app lock.
- `lib/screens/`: navigation, forms, history, analytics and settings.
- `lib/theme.dart`: centralized Material 3 palettes and saved appearance.

Amounts are integer sen; RM input is parsed without floating point. Transaction dates are local `YYYY-MM-DD` values and audit timestamps are UTC. Overall account balance includes opening balances plus recorded income minus expenses; transfers cancel across accounts. Individual balances include transfers. All recorded entries, including future-dated entries, count toward balances; today's/week/month-to-date totals exclude future dates. Weeks begin Monday. Charts use actual records. Individual amounts are limited to RM 9,999,999,999.99.

## Verification

```powershell
flutter analyze
flutter test
flutter test integration_test/persistence_test.dart -d emulator-5554
flutter test integration_test/app_flow_test.dart -d emulator-5554
flutter test integration_test/native_services_test.dart -d emulator-5554
flutter build apk --release
```

Unit tests cover money/calendar totals, database CRUD/constraints/reopen persistence, schema protection, recurrence idempotency, encrypted backup authentication/restore/rollback and PIN hashing/cooldown. Android integration tests use separate test databases or memory databases, never the live `spendwise.db` file. Run integration tests on an emulator: Flutter's test-app deployment can replace/reset the test installation.

Run Flutter commands sequentially. In particular, do not run analysis/package resolution alongside a release build: Flutter can rewrite generated plugin registration during compilation.

On your phone, verify the production app by adding a sample transaction, closing it, force-stopping it from Android Settings and opening it from the launcher. Verify the same amount, category and date; repeat after a phone reboot. Also test the native share/file pickers and your enrolled fingerprint/face on your device. These hardware interactions cannot be established by the mocked security tests.

Implementation references: [sqflite](https://pub.dev/packages/sqflite), [local_auth](https://pub.dev/packages/local_auth), [share_plus](https://pub.dev/packages/share_plus).

The schema-2 migration preserves existing records and assigns them to Main ledger. Rename that account or create accounts and reassign transactions through Edit; no balances are fabricated for banks or e-wallets.
