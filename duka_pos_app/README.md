# SimpleSales — Developer and Operations Guide

SimpleSales is an offline-first point-of-sale app for African retail. Every sale,
stock movement, payment and receipt is recorded locally on the handset and keeps
working when the internet is down. When connectivity returns, data syncs to the
backend.

## Product profiles

SimpleSales ships in four profiles, selected at build time:

| Profile | Intended for | Key difference |
|---|---|---|
| **Duka** | General retail dukas | Full product catalogue, variants, stock |
| **Drinks** | Bottle stores and bars | Measured pours, shots, bottle decomposition |
| **Fashion** | Clothing and footwear | Size/colour variants, style matrix |
| **Open** | Custom retail | Configurable tax, credit, ledger behaviour |

All profiles share the same codebase; the profile is a compile-time choice that
adjusts defaults, visible screens and terminology.

## Architecture

- **Flutter app** (`lib/`) — UI and business logic in Dart
- **Local SQLite database** — system of record, one encrypted file per workspace
  (shop). SQLCipher 256-bit encryption at rest; keys live in Android Keystore /
  iOS Keychain via `flutter_secure_storage`
- **Workspace/profile model** — each till runs one workspace; shops with
  multiple tills run multiple workspaces, isolated from one another
- **Backend/API integration** — optional, configured at build time via
  `--dart-define`; identity, sync, M-Pesa and tax features require a connected
  backend
- **Encrypted backup** — automatic and owner-triggered, device-bound or
  portable (passphrase-protected) formats
- **Local network** — camera barcode scanning, Bluetooth ESC/POS printing
- **Error reporting** — Sentry (configured per-release)

## Feature status

| Feature | Status | Notes |
|---|---|---|
| Offline-first sales | Available | Core path; no backend required |
| Stock management | Available | Atomic decrement on sale commit |
| Staff PIN login | Available | Owner + cashier roles, permissions |
| Reports and dashboards | Available | Sales by staff, shift summaries |
| Encrypted local database | Available | SQLCipher, per-workspace keys |
| Automatic encrypted backup | Available | Six-hourly, timestamped filenames |
| Owner-triggered portable backup | Available | Passphrase-protected, restores on any device |
| Backend identity (login/link/verify) | Configuration-required | Needs `--dart-define=BACKEND_URL=...` |
| Backend sync | Configuration-required | Needs connected backend |
| M-Pesa payments | Configuration-required | Needs provider credentials |
| eTIMS / KRA receipts | Disabled | Explicitly off in this release; not claimed |
| LAN multi-till sync | Not planned | One till per workspace |
| Web / desktop | Not supported | Android and iOS only |

## Supported platforms

| Platform | Minimum OS | Notes |
|---|---|---|
| Android phones | Android 8.0 / API 26+ | Primary POS target |
| Android tablets | Android 8.0 / API 26+ | Compact and expanded layouts |
| iPhone | iOS 15.0+ | Feature parity under verification |
| iPad | iPadOS 15.0+ | Split/landscape layouts under verification |
| Web / desktop | Not supported | See "Platform decision" below |

Google Play submissions target Android 16 / API 36+. CI asserts this on every
built release artifact.

## Toolchain (pinned)

| Tool | Version |
|---|---|
| Flutter | >=3.47.0 |
| Dart | >=3.13.0 |
| Java | 17 |
| Android Gradle Plugin | 9.1.0 |
| Kotlin Gradle Plugin | 2.4.0 |
| NDK | As pinned by Flutter 3.47 |

CI prints and records exact `flutter --version`, `dart --version`, Java,
Gradle wrapper, AGP and Kotlin versions on every run.

## Setup

### Local development (local-only mode)

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
flutter run
```

A local-only build needs no backend — the till sells, stocks and reports
offline. Connected features (identity, sync, M-Pesa, tax) report "under
maintenance" at the point of use.

### Connected build

```bash
flutter build apk --release \
  --dart-define=DEPLOYMENT_MODE=connected \
  --dart-define=BACKEND_URL=https://api.example-shop.co.ke/api
```

A connected build without a real `BACKEND_URL` is a configuration error — CI
rejects it before publication.

### Release build (signed)

Signing material is never in the repository. CI reconstructs the keystore from
protected secrets (`ANDROID_KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`)
for every release build and deletes it before the job ends.

## Configuration

Build-time configuration goes in `--dart-define`, never in committed source:

| Define | Values | Purpose |
|---|---|---|
| `DEPLOYMENT_MODE` | `local_only` (default), `connected` | Whether the build expects a backend |
| `BACKEND_URL` | `https://<host>/api` | Required when `DEPLOYMENT_MODE=connected` |

`local_only` is the default so development keeps working without a backend.
`connected` requires a valid HTTPS URL — placeholder, localhost, HTTP and
local-dev hosts are rejected by CI.

## Database encryption

Every workspace database is encrypted at rest with SQLCipher:

1. A random 256-bit key is generated per workspace on first open
2. The key is stored in `flutter_secure_storage` (Android Keystore / iOS Keychain)
3. Keys are device-local — never synced between tills, never in logs
4. Portable backups use a separate passphrase and can restore to a new device
   with a fresh device-local key
5. Losing the device-local key means losing access to that workspace's data —
   there is no backdoor

## Backup and restore

- **Automatic backups** run on a six-hourly timer while the till is open, using
  timestamped filenames so same-day backups never overwrite each other
- **Portable backups** are encrypted with an owner-chosen passphrase and can be
  restored on a replacement phone
- Keys are device-local; a portable restore creates a new local key on the new
  device

## Release process

1. CI runs on every push and PR: `flutter analyze --fatal-infos`, full test
   suite, and a signed release APK build
2. CI asserts target API >= 36 on every release artifact
3. `.github/workflows/auto-release.yml` computes the release tag and bumps the
   build number when needed
4. `.github/workflows/release.yml` builds the signed APK and publishes it to a
   GitHub Release
5. Signing keys live only in GitHub Actions secrets — never in source

## App identity

- Android `applicationId`: `com.dukapos.simplepos` (locked in Gradle)
- iOS `PRODUCT_BUNDLE_IDENTIFIER`: `com.dukapos.simplepos`
- Version: `2.0.0+67` (see `pubspec.yaml`)

The application ID is frozen. A different ID is a different app to Android —
existing installs cannot be updated across an ID change. No customer migration
is planned.

## Privacy and security

- Database files are encrypted at rest (SQLCipher)
- Keys live in the OS keystore/keychain, never in `SharedPreferences` or source
- `allowBackup=false` and `fullBackupContent=false` on Android
- No `READ_SMS` / `RECEIVE_SMS` permissions
- No `REQUEST_INSTALL_PACKAGES` on Play Store builds (sideload builds only)
- Sentry crash reports do not include passwords, PINs, tokens or customer data

## Troubleshooting

**App won't open after upgrade:** the signing certificate must match the
previous install. A different certificate requires uninstalling first (which
deletes local data — back up first).

**Wrong database key:** if secure storage is cleared, the workspace database
cannot be opened. Restore from a portable backup with the owner's passphrase,
or accept data loss for that workspace.

**Backup won't run:** check available storage (150 MB headroom required for
automatic updates) and that the till is not in battery-saver mode during the
backup window.

## CI / CD

- `.github/workflows/ci.yml` — analyze, test, build release APK on every push
  and PR
- `.github/workflows/auto-release.yml` — tag and bump build numbers
- `.github/workflows/release.yml` — build and publish signed release APK

All workflows are path-sensitive: changes to `.github/` or `duka_pos_app/`
trigger the gate.
