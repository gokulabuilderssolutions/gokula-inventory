# Gokula Inventory Mobile

Flutter mobile app source for Android and iOS.

## Included
- App name: Gokula Inventory
- Krishna logo included
- Offline SQLite inventory storage
- Online/offline status
- Pending sync count
- Manual Sync Now button
- Automatic sync when connectivity returns
- Supabase inventory synchronization
- Offline photo storage and later upload

## Configure Supabase
Open `lib/config.dart` and replace:

```dart
static const supabaseUrl = 'YOUR_SUPABASE_URL';
static const supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
```

Run `offline_sync_migration.sql` from the desktop project in Supabase first so the `client_uid` field exists.

## Build Android APK
Install Flutter and Android Studio, then run:

```bash
flutter pub get
flutter pub run flutter_launcher_icons
flutter build apk --release
```

APK output:

`build/app/outputs/flutter-apk/app-release.apk`

## Build iOS
Requires macOS, Xcode, and Apple signing:

```bash
flutter pub get
flutter pub run flutter_launcher_icons
flutter build ios --release
```

## Important
This package is source code. An APK cannot be compiled without the Android SDK and Flutter toolchain.

## Sales module

The app now includes offline sales, customer entry, GST calculation, automatic stock deduction, sales history and PDF invoice sharing.

To sync sales to Supabase, run `supabase_sales_schema.sql` in the Supabase SQL Editor. Until then, sales remain safely stored offline and show as pending.

## Added features
- Image-wise inventory PDF export: open Inventory and tap the PDF icon.
- Edit sales: open Sales, tap the three-dot menu on an invoice, and choose Edit sale.
- Editing a sale automatically restores the old stock and deducts the revised quantities.
