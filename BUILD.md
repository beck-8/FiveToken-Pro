# Building FiveToken Pro

This app is an old Flutter project (Flutter **1.22.5** / Dart **2.10.x**, pre
null-safety, pre-AndroidX). The toolchain versions matter — newer ones will not
build it. After the backend-decoupling work, the app's only runtime dependency
is a Filecoin Lotus JSON-RPC node (configurable in-app; ships with mainnet and
calibration glif endpoints built in).

## 1. Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Flutter | **1.22.5 (stable)** | Bundles Dart 2.10.x. Use [fvm](https://fvm.app) to pin it: `fvm install 1.22.5 && fvm use 1.22.5`. Don't install Dart separately. |
| JDK | **8** (required) | AGP 3.5.0 + Gradle 5.6.2 only work on Java 8. JDK 11/17 will fail. (You may keep a newer JDK as your system default and point only Gradle at JDK 8 — see step 2.) |
| Android SDK | Platform **29**, Build-Tools **29.0.3**, Platform-Tools | `sdkmanager "platforms;android-29" "build-tools;29.0.3" "platform-tools"` |
| Git | any | Fetches the `flotus` / `bls` plugin git dependencies. |

You do **not** need the Android NDK or Go — the native libraries (`flotus`,
`bls`) ship as prebuilt `.aar` / `.so` for arm64-v8a, armeabi-v7a, x86, x86_64.

## 2. Create `android/gradle.properties`

`android/gradle.properties` is gitignored (the repo ignores `*.properties`), so
each machine provides its own. Copy the template and adjust:

```bash
cp android/gradle.properties.example android/gradle.properties
```

The template sets `android.useAndroidX=false` (this app uses the legacy support
libraries). If your default `java` is not JDK 8, uncomment and set
`org.gradle.java.home=/path/to/jdk8`. If your network needs an HTTP proxy for
Gradle, uncomment the `systemProp.*.proxy*` lines.

## 3. Build

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

For a release build, create `android/key.properties` + a keystore; without one,
`flutter build apk` falls back to debug signing.

## 4. Choosing a network

In the app: **Settings → Network**. Two networks are built in (Mainnet and
Calibration, via public glif RPC endpoints) and you can add a custom RPC URL.
Use **Calibration** for safe testing with testnet FIL.

## Notes / known constraints

- **flotus dependency**: pinned to `github.com/beck-8/flotus`. The upstream
  `FiveToken/flotus` is fine at HEAD, but this project's lockfile previously
  pinned an older commit whose `android/wlib/wlib.aar` was missing two native
  functions; the fork avoids that and also drops the dead `jcenter()` repo.
- **Repositories**: `jcenter()` (shut down in 2021) was replaced with
  `mavenCentral()`. If Maven Central is slow on your network, configure a mirror
  via `~/.gradle/init.gradle`.
- **Removed external services**: the dead `api.fivetoken.io` backend, the fiat
  price endpoint, and indexer-backed features (full tx history, miner power
  charts) are gone or read directly from chain. Block-explorer links point to
  filfox and are optional.
- **iOS**: the bundled `Wlib.framework` has device (arm64) + x86_64 slices but
  no arm64-simulator slice, so use a real device or an x86_64 simulator.
