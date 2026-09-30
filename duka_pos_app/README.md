# Duka POS — Setup & Build Guide

This is a real Flutter project (Dart source, not a demo page) implementing everything in the dev spec: offline-first SQLite storage, owner/staff PIN login, sales/inventory/reports, and hybrid sync to Google Sheets (online) with automatic fallback to Excel export (offline).

It has been written by hand against the current Flutter/Dart package APIs but **has not been compiled** — there's no Flutter/Android/iOS toolchain available in the environment that wrote it. Expect to fix a handful of small issues (a renamed API, a missing import) the first time it's actually built — this is normal for hand-written code and usually a 15–30 minute pass for anyone who knows Flutter, not a rewrite.

## What you get an app that installs when this is done
- Owner account creation on first launch
- Staff PIN login, owner-only permissions (delete products, manage staff, restore backups)
- Sell screen with cart checkout, atomic stock deduction
- Inventory with stock adjustments (restock/breakage) logged separately from sales
- Reports: sales log, sales-by-staff, shift summaries
- **Hybrid sync**: "Sync now" tries Google Sheets first; if there's no internet or the owner hasn't linked Google, it automatically saves and shares an Excel (.xlsx) file instead
- Manual Excel export/import for inventory, for fully offline transfer between devices

## Not yet included (see the dev spec for design, not yet built)
- LAN host/client sync between multiple physical tills — this is the multi-till piece and is the most involved remaining feature; the app currently assumes one till per device with manual/Sheets sync between them
- Bluetooth thermal receipt printing (currently: on-screen receipt only)

---

## Part 1 — One-time Google Cloud setup (needed for the Sheets half of sync)

This can't be done from code — it's account configuration in Google's console, done once by whoever owns the Google account the shop will use:

1. Go to console.cloud.google.com and create a new project (e.g. "Duka POS").
2. Under **APIs & Services > Library**, search for and enable the **Google Sheets API**.
3. Under **APIs & Services > OAuth consent screen**: choose "External," fill in the app name and support email. You can leave it in "Testing" mode and add the owner's Google account as a test user — no need to publish it for a single-shop app.
4. Under **APIs & Services > Credentials > Create Credentials > OAuth client ID**:
   - For Android: choose "Android," provide the app's package name (default `com.dukapos.app` — change it in `android/app/build.gradle` if you rename it) and its SHA-1 signing fingerprint (get this by running `./gradlew signingReport` inside `android/` once the project is set up, or from Codemagic's build settings if signing there).
   - For iOS: choose "iOS," provide the bundle ID (set in `ios/Runner.xcodeproj`).
5. No client secret or server key needs to go into the app's code — `google_sign_in` handles the OAuth flow using the platform-specific client ID configuration above (Android: via the SHA-1 + package name pairing; iOS: via a `GoogleService-Info.plist` or `CFBundleURLTypes` entry — the `google_sign_in` package docs have the exact file, since this changes with package versions).

Without this setup, the app still works completely — "Sync now" will just always fall back to the Excel path, which is a legitimate permanent mode to run in if you never want Google involved.

---

## Part 1.5 — Running the tests

`test/database_helper_test.dart` covers the database layer, especially the checkout transaction (the part where a bug would silently corrupt real stock/sales data — prioritized over UI tests for that reason). Run it with:

```
flutter test
```

It uses `sqflite_common_ffi` to run against a real SQLite engine on whatever machine runs the tests — no Android/iOS device or emulator needed, so this can run in CI (including a Codemagic build step) on every commit.

---

## Part 3 — Turning on crash reporting (Firebase Crashlytics)

Crash capture hooks already exist in `main.dart`, currently disabled behind a `firebaseConfigured = false` flag. To turn them on:

1. Go to console.firebase.google.com, create a project (e.g. "Duka POS").
2. Install the FlutterFire CLI (`dart pub global activate flutterfire_cli`) and run `flutterfire configure` from this project's root — it walks you through linking the Android/iOS app to the Firebase project and generates `lib/firebase_options.dart` automatically.
3. In `lib/main.dart`: uncomment the `import 'firebase_options.dart';` line, uncomment `await Firebase.initializeApp(...)`, and flip `firebaseConfigured` to `true`.
4. Rebuild. Crashes now appear in the Firebase console within a few minutes, from any phone running the app anywhere.

This is a separate Google account/project from the Sheets integration in Part 1 — they don't have to be the same project, though they can be if it's simpler to manage one console.

---

## Part 2 — Getting this compiled into an installed app, with nothing installed locally

**Recommended: Codemagic (free tier covers this).**

1. Push this project to a GitHub repository (create one, then `git init`, `git add .`, `git commit`, `git remote add origin <your repo url>`, `git push`).
2. Go to codemagic.io, sign up free, and connect that GitHub repo.
3. Codemagic auto-detects it as a Flutter project. Choose the default Flutter workflow.
4. For Android: Codemagic can generate a signing keystore for you automatically for testing (look for "Android code signing" in workflow settings — enable "Automatic" for an unsigned/test build first to confirm it compiles).
5. Click **Start new build**. When it finishes, Codemagic gives you a downloadable `.apk` — send that file to an Android phone (e.g. via WhatsApp/email/Google Drive) and open it to install (the phone will ask you to allow installs from unknown sources the first time — that's expected for an app not from the Play Store).
6. For iOS, Codemagic can build an `.ipa`, but Apple requires the phone to be enrolled via an Apple Developer account ($99/year) and the device's UDID registered before it can be installed outside the App Store (or use Codemagic's own ad-hoc/TestFlight distribution, which they document). Budget extra setup time for iOS specifically — Android is meaningfully simpler for a first build with no developer account.

**Alternative: hire a Flutter developer for a fixed-scope task.**
Given this codebase already exists, "compile this Flutter project, fix any build errors, and produce a signed Android APK (and iOS build if needed)" is a well-scoped, quick task to post on Upwork/Fiverr — most Flutter developers can turn this around in a day since the app logic is already written, not being designed from scratch.

**If you want to try locally instead:**
Install Flutter (flutter.dev/docs/get-started/install), run `flutter pub get` in this folder, connect an Android phone with USB debugging enabled (or an emulator), and run `flutter run`. For a release `.apk`: `flutter build apk --release`, found afterward in `build/app/outputs/flutter-apk/`.

---

## Project structure

```
lib/
  main.dart                    — app entry, routes to setup/login/home
  models/models.dart           — Product, Sale, SaleItem, Staff, Owner, StockAdjustment
  db/database_helper.dart      — SQLite schema + all queries, atomic checkout
  services/
    auth_service.dart          — PIN hashing
    app_state.dart             — current session (who's signed in)
    excel_service.dart         — offline .xlsx export/import
    sheets_service.dart        — Google Sheets live sync
    sync_service.dart          — hybrid decision: try Sheets, fall back to Excel
  screens/
    owner_setup_screen.dart
    login_screen.dart
    home_shell.dart            — bottom nav
    dashboard_screen.dart
    sell_screen.dart
    inventory_screen.dart
    reports_screen.dart
    settings_screen.dart       — owner-only: staff, sync, backup
```

## Next build priorities (in order)
1. Compile, fix any package-version mismatches, confirm on a real Android phone.
2. Wire up the Google Cloud OAuth config from Part 1 and test a real Sheets sync.
3. LAN multi-till sync (see the dev spec's Section 2 for the host/client design) — the biggest remaining piece.
4. Thermal receipt printer support.
