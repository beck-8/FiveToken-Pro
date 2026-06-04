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

## 3. Build (debug)

```bash
flutter pub get          # fetches flotus (github.com/beck-8/flotus) + bls
flutter build apk --debug
# -> build/app/outputs/flutter-apk/app-debug.apk
```

Install on an emulator/device (the APK includes x86_64, so standard emulators
work):

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## 4. Signing (important)

Android APKs must be signed; "unsigned" APKs can't be installed.

- **Debug build** (`--debug`, and `--release` without a keystore): signed with
  your machine's auto-generated **debug keystore** (`~/.android/debug.keystore`).
  The **package name is always `io.fivetokenpro.fil`** for everyone, but every
  machine's debug key is **different**. Consequence:
  - APKs you build on one machine update over each other fine (same debug key).
  - APKs from **different** debug keys (different people/machines) **cannot**
    update over each other — Android rejects the install; you must uninstall
    first, which wipes wallet data.
- **Release build** (signed, shareable, updatable): create a release keystore
  once, keep it **private** (never commit it), and configure `key.properties`:

  ```bash
  keytool -genkey -v -keystore ~/fivetoken-release.jks \
    -keyalg RSA -keysize 2048 -validity 10000 -alias fivetoken
  cp android/key.properties.example android/key.properties   # then edit it
  flutter build apk --release
  # -> build/app/outputs/flutter-apk/app-release.apk
  ```

  `android/key.properties` is gitignored. Sign **all** official releases with the
  **same** keystore so users can update without reinstalling (and without losing
  their wallets).

## 5. Choosing a network

In the app: **Settings → Network** (设置 → 网络管理). Two networks are built in
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
