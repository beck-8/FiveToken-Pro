# Building FiveToken Pro

This is an old Flutter project (Flutter **1.22.5** / Dart **2.10.x**, pre
null-safety, pre-AndroidX). The toolchain versions matter — newer ones will not
build it. After the backend-decoupling work, the app's only runtime dependency
is a Filecoin Lotus JSON-RPC node (configurable in-app; mainnet and calibration
glif endpoints are built in).

## 1. Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Flutter | **1.22.5 (stable)** | Bundles Dart 2.10.x. Pin it with [fvm](https://fvm.app): `fvm install 1.22.5 && fvm use 1.22.5`. Don't install Dart separately. |
| JDK | **8** (required) | AGP 3.5.0 + Gradle 5.6.2 only work on Java 8. JDK 11/17 will fail the Gradle build. Keep a newer JDK as your default if you like and point only Gradle at JDK 8 (see step 2). |
| Android SDK | Platform **29**, Build-Tools **29.0.3**, Platform-Tools | `sdkmanager "platforms;android-29" "build-tools;29.0.3" "platform-tools"` (the cmdline-tools themselves need JDK 17 to *run* sdkmanager). |
| Git | any | Fetches the `flotus` / `bls` plugin git dependencies. |

You do **not** need the Android NDK or Go — the native libraries (`flotus`,
`bls`) ship prebuilt for arm64-v8a, armeabi-v7a, x86, x86_64.

## 2. Create `android/gradle.properties`

`android/gradle.properties` is gitignored (the repo ignores `*.properties`), so
each machine provides its own:

```bash
cp android/gradle.properties.example android/gradle.properties
```

The template sets `android.useAndroidX=false` (this app uses the legacy support
libraries). If your default `java` is not JDK 8, uncomment and set
`org.gradle.java.home=/path/to/jdk8`. If Gradle needs an HTTP proxy for your
network, uncomment the `systemProp.*.proxy*` lines.

## 3. Build (release)

For everyday installation use `--release` (smaller, optimized, R8-shrunk):

```bash
flutter pub get          # fetches flotus (github.com/beck-8/flotus) + bls
flutter build apk --release
# -> build/app/outputs/flutter-apk/app-release.apk
```

Use `flutter build apk --debug` only while developing (faster incremental builds
and debuggable, but larger and unoptimized).

Install on an emulator/device (the APK includes x86_64, so standard emulators
work):

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## 4. Signing

Android APKs must be signed; "unsigned" APKs can't be installed. The package name
is always `io.fivetokenpro.fil` for everyone — what decides whether two APKs can
update over each other in place (without uninstalling and wiping wallet data) is
the **signing key**, not the package name.

### Default: the committed community shared key

This repo ships a shared keystore at **`android/fivetoken-shared.jks`** (alias
`fivetoken`, all passwords `fivetoken`). **Both** `--debug` and `--release` builds
sign with it by default — no setup needed. Because everyone uses the same key,
APKs built by anyone (you building for someone else, or that person rebuilding
later) **update over each other in place and keep the wallet data**.

```bash
flutter build apk --release    # recommended: shared key, unless key.properties exists
flutter build apk --debug      # dev only: also the shared key
```

> ⚠️ The shared key is **public** — it is for build/update *compatibility*, not
> anti-tampering. A matching signature does **not** prove an APK came from a
> trusted source, since anyone can sign with this key. Only install APKs you
> built yourself or got from a source you trust. Do **not** rely on the shared
> key for public distribution of a wallet app.

### Optional: your own private release key

For a real public release you control, use your own private keystore. If
`android/key.properties` exists, **release** builds use it instead of the shared
key (debug still uses the shared key):

```bash
keytool -genkey -v -keystore ~/fivetoken-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias fivetoken
cp android/key.properties.example android/key.properties   # then edit it
flutter build apk --release
# -> build/app/outputs/flutter-apk/app-release.apk
```

`android/key.properties` is gitignored and the keystore must stay private and
backed up. Sign **all** your official releases with the **same** keystore so
users can update without reinstalling.

## 5. Choosing a network

In the app: **Settings → Network**. Two networks are built in
(Mainnet and Calibration, via public glif RPC) and you can add a custom RPC URL.
Use **Calibration** for safe testing with testnet FIL.

## Notes / known constraints

- **flotus** is pinned to `github.com/beck-8/flotus` (the upstream
  `FiveToken/flotus` lockfile pinned an old commit whose `android/wlib/wlib.aar`
  was missing native functions; this fork also drops the dead `jcenter()` repo).
- **Repositories**: `jcenter()` (shut down in 2021) was replaced with
  `mavenCentral()`. If Maven Central is slow on your network, add a mirror via
  `~/.gradle/init.gradle`.
- **Removed external services**: the dead `api.fivetoken.io` backend and the
  fiat-price endpoint are gone. Data that a single RPC node can't provide
  (transaction history) is read from the filfox public API; everything else
  comes straight from chain.
- **iOS**: the bundled `Wlib.framework` has device (arm64) + x86_64 slices but no
  arm64-simulator slice — use a real device or an x86_64 simulator.
