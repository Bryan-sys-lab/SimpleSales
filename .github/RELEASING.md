# Releasing Duka POS

The laptop is only a push machine. GitHub Actions does the Android build.

```text
edit code -> git push -> CI (analyze, test, debug APK)
                       -> tag v1.4.0 -> signed APK -> GitHub Release
```

## One-time setup

### 1. Add the secrets

Repo **Settings > Secrets and variables > Actions > New repository secret**.

**Signing (required to publish)**

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 android/duka-pos-release.jks` (see below) |
| `KEYSTORE_PASSWORD` | the `storePassword` in `android/key.properties` |
| `KEY_ALIAS` | the `keyAlias` in `android/key.properties` |
| `KEY_PASSWORD` | optional; falls back to `KEYSTORE_PASSWORD`. This keystore has no separate key password |

Produce the base64 blob **once**, on the machine that holds the keystore:

```bash
base64 -w0 duka_pos_app/android/duka-pos-release.jks
```

macOS uses `base64 < duka_pos_app/android/duka-pos-release.jks` (no `-w0`,
and it wraps lines, which is fine — the decode side tolerates it).

The keystore never enters the repository. The runner rebuilds it in an
ephemeral workspace, builds, and deletes it before the release is published.

> Back up `duka-pos-release.jks` and its passwords somewhere you will not lose
> them. A new signing key means every shop device must uninstall and reinstall
> by hand, losing the local ledger's link to the old identity.

**Runtime configuration (optional — set before you need M-Pesa or online sign-in)**

These are baked into the binary at build time. A value that is **not** set is
simply not injected, so the app falls back to the placeholder in
`lib/services/backend_service.dart`.

A build without `BACKEND_URL` is a valid **offline-only till**: sales are
recorded in the till's own database and staff sign in with their PIN. What does
not work is M-Pesa mobile money, catalogue sync, and online sign-in. The
published release notes say so on the release itself, so nobody installs it
expecting mobile money.

| Secret | Effect if unset |
| --- | --- |
| `OIDC_ISSUER_URL` | Online sign-in inert; staff use PIN sign-in (default in-app issuer is the `example.com` placeholder) |
| `BACKEND_URL` | Sync and M-Pesa inert; default in-app URL is `http://localhost:3000/api`, which on a handset is the phone itself |
| `SENTRY_DSN` | No crash reporting. Builds and warns |
| `OIDC_CLIENT_ID` | Defaults to `duka-pos-mobile` |
| `OIDC_REDIRECT_URL` | Defaults to `dukapos://callback`. Must match the Keycloak client's redirect URI |
| `OIDC_API_SCOPE` | Defaults to `duka-api` |

When one of the first two **is** set it is validated strictly: it must be
`https://` and must not point at `localhost` or `127.0.0.1`. Android blocks
cleartext by default, so an `http://` endpoint would not fail at build time — it
would ship and then leave M-Pesa quietly dead on the till. That is the one case
that still fails the build, because it means the value was meant to work and
does not.

### 2. Pin the expected signing certificate (recommended)

**Settings > Secrets and variables > Actions > Variables** (not Secrets) ->
`EXPECTED_SIGNING_CERT_SHA256`.

The release verifies the built APK's signer against this value, so an unsigned
or debug-signed APK can never be published. Get it with:

```bash
keytool -list -v -keystore duka_pos_app/android/duka-pos-release.jks \
  -alias duka-pos | grep SHA256
```

The current release key is:

```text
E7:0E:79:27:C4:49:E6:39:7E:C3:75:3F:92:96:B8:91:6E:B5:B6:DB:CD:31:47:92:67:31:A3:04:8E:70:9C:69
```

The comparison ignores letter case and colons, so the digest can be pasted with
or without `:` separators.

## Cutting a release

1. Set the version in `duka_pos_app/pubspec.yaml`. **Bump the build number**
   (`+N`) every time — Android refuses to install a build whose `versionCode`
   is not higher than the one already installed, and that check runs before the
   app's own update checker does.

   ```yaml
   version: 1.4.0+42
   ```

2. Commit, push, and let CI go green on `main`.

3. Tag and push:

   ```bash
   git tag v1.4.0
   git push origin v1.4.0
   ```

4. The Release workflow builds, verifies, and publishes
   `duka-pos-v1.4.0.apk` on the Releases page.

The tag must be on a commit already merged to `main`, and must match the
pubspec version exactly. Both are enforced; see Troubleshooting.

## What the pipeline enforces

- Tag is on `main`, so unreviewed commits cannot ship.
- `v1.4.0` matches pubspec `1.4.0`, so the APK cannot disagree with its name.
- Build number is a positive integer.
- `flutter analyze --fatal-infos` and the full test suite pass.
- The APK is signed, and its signer matches `EXPECTED_SIGNING_CERT_SHA256`.
- The APK's own `versionName` is re-read from the built binary and compared to
  the tag, closing the loop on the pubspec check.
- Signing material is deleted from the runner before the release is created.

## Caching

The Flutter SDK (~3 GB), pub packages, and Gradle are all cached. The first run
downloads the SDK and is slow; later runs restore it. The caches are keyed so
that changing `pubspec.lock`, the Gradle wrapper, or any `build.gradle.kts`
invalidates exactly the cache that depends on it — never the wrong one.

If you bump the Flutter version, update the default in
`.github/actions/setup-flutter-android/action.yml` **and** the `revision` in
`duka_pos_app/.metadata` together.

## Upgrading a till that already has data

Schema v11 changed how money is stored: amounts went from REAL shillings to
INTEGER minor units (cents). Existing shops keep their prices, stock and
history — the migration converts every row on first launch and is covered by
`test/migration_test.dart`, which builds a real v10 database and upgrades it.

Two things to know before shipping this to a live till:

- **Back up first.** The migration rebuilds the `products`, `sales` and
  `sale_items` tables. It runs inside a transaction, so a failure rolls back,
  but the pre-upgrade backup is still the only way back if a device is already
  in a bad state.
- **Spreadsheets and the backend still speak shillings.** The conversion to
  cents happens inside the app only; exports, imports and the wire format are
  unchanged, so existing `.xlsx` templates and already-synced products keep
  working.

Nothing needs doing to the keystore or the secrets for this release.

## Troubleshooting

**`LicenceNotAcceptedException`**
The workflow accepts all SDK licences before building, and then verifies that
consent actually landed rather than assuming it. If this appears anyway, the
runner image changed its `cmdline-tools` layout — check that
`$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager` exists.

**`[CXX1101] NDK ... did not have a source.properties file`**
Something on the runner left a half-extracted NDK behind. The workflow
deliberately does **not** pin or pre-fetch an NDK: `path_provider_android`
reaches the `jni` plugin, whose module takes its NDK version from the Flutter
SDK rather than declaring a fixed one, so AGP provisions whatever is needed at
build time. Re-running the job on a fresh runner clears a corrupt cached copy;
if it persists, the cached Gradle/SDK state is the thing to suspect.

This only ever affects local `flutter build apk --release`, never the workflow —
the runner's licence files plus the workflow's consent step are enough. A local
release build additionally needs whatever NDK the `jni` module asks for, which
`flutter build apk --debug` does not.

**`does not match pubspec version`**
The tag and `pubspec.yaml` disagree. Fix the version and retag, or retag if the
version was correct.

**`points at a commit that is not on main`**
Merge the commit first, or tag the merged commit.

**CI passes but the release fails at the signing step**
Usually a typo in the secrets. The keystore is validated with `keytool` before
Gradle runs, so a wrong password or a corrupt base64 blob fails fast with a
readable message rather than deep inside the build.

## Why one universal APK and no obfuscation

A shop installs onto whatever ARM device it already owns, so the release is a
single APK rather than `--split-per-abi`, which would require picking the right
file per device.

`--obfuscate` is deliberately off: it needs its symbol maps uploaded to Sentry
on every build, or release crash reports become unreadable. Turn it on only
together with Sentry source-map upload in the workflow.