# FiveToken Pro

<div align="right"><a href="./README.md">中文</a></div>

A mobile wallet (Android / iOS) for Filecoin storage providers (SPs).

This repo is a **backend-decoupled, self-contained fork** of
[FiveToken/FiveToken-Pro](https://github.com/FiveToken/FiveToken-Pro). The
original was a thin client: every chain interaction went through the official
hosted backend `api.fivetoken.io`, which is now offline, leaving the original
app unusable. This fork rewrites all chain interaction to talk **directly to a
Filecoin Lotus JSON-RPC node**. The app's only external dependency is a
**user-configurable RPC node**.

> Data-sourcing principle: **anything available on-chain is read from chain.**
> Only data a single RPC node cannot provide (a plain account's transfer
> history) is read from the public filfox API.

---

## Recent changes

### Architecture: backend removed, talk to chain directly
- Dropped all dependencies on the dead backend `api.fivetoken.io` and the fiat
  price service.
- `lib/chain/provider.dart` rewritten as a Lotus JSON-RPC client
  (`StateGetActor` / `MpoolGetNonce` / `GasEstimateMessageGas` / `MpoolPush` /
  `StateSearchMsg` / `MsigGetPending` / `StateMinerInfo` / `StateMarketBalance`,
  etc.).
- New `lib/chain/cbor.dart`: a hand-written Filecoin CBOR parameter encoder in
  Dart (implemented per `go-state-types` and checked against the official test
  vectors), replacing the parameter serialization the backend used to do.
  Signing / CID / private-key derivation still happen locally via the bundled
  `flotus` (secp256k1) and `bls` (BLS) plugins.
- New network model with **runtime network switching**: mainnet and calibration
  (public glif RPC) are built in, plus custom RPC. Switch under
  **Settings → Network**; the same private key re-derives its address per
  network prefix (`f` / `t`).

### Miner (SP) panel: now read straight from chain
- owner / worker / control / beneficiary addresses with their balances.
- Pending worker change (NewWorker + effective epoch), pending owner change
  (PendingOwnerAddress).
- Available (withdrawable) balance, current power, sector size.
- **New: market balance** (Escrow / Locked, like `lotus-miner info`).
- All from `StateMinerInfo` / `StateMinerAvailableBalance` / `StateMinerPower` /
  `StateGetActor` / `StateMarketBalance` — just enter a miner id.

### Single-sig miner ops (build message → offline sign → push)
- Miner withdraw (method 16), change owner (23), change worker (3),
  ConfirmUpdateWorkerKey (21).
- **Market withdraw** (method 3 on f05): its own entry in miner management and
  also added to the message-builder's op list; label and method number are
  disambiguated correctly (no longer mislabeled "change worker").
- **CreateMiner**: proof type supports V1_1 (13 = 32GiB / 14 = 64GiB; new miners
  must use V1_1), with the FIP-0077 creation deposit field at the bottom plus an
  explanation.

### Multisig: complete, no history-index dependency
- Create / import / propose / approve, all on-chain.
- Pending proposals come from `MsigGetPending` (proposer = `Approved[0]`) and can
  be opened in a block explorer while pending.

### Notable fixes
- **Private-key/password KEK** now derived from the stable stored address (it
  used the network-prefixed address before, causing "wrong password" after
  switching to calibration).
- **Offline signing** From-check now compares by payload, ignoring the network
  prefix (it reported "from mismatch" on mainnet before; the signature itself is
  network-agnostic).
- `buildMessage` now fetches the **real nonce** (was hardcoded 0, causing "nonce
  error" on push).
- Gas is estimated on the **real message** with a 1.25x safety margin (fixes
  zero fees and `SysErrOutOfGas` on multisig/transfer).
- Transaction detail page backfills from/to via `ChainGetMessage` (was blank
  when not pending).
- The in-app webview gained an "open in external browser" button (to copy page
  text easily).
- Removed the dead "Help Center" entry; support is now Telegram
  [@beck_debug](https://t.me/beck_debug); issue reports point to this repo's
  issues.

---

## Features

- Create / import wallet (mnemonic, private key); private key encrypted and
  stored locally.
- FIL transfer with gas estimation; build messages with a custom method ID.
- On-chain SP info panel + single-sig ops (withdraw / change owner / change
  worker / market withdraw / create miner).
- Full multisig wallet (create / import / propose / approve).
- Offline (cold-wallet) signing: sign on an air-gapped machine, push from an
  online one.
- QR transfer across devices; watch-only wallet; f1 (secp256k1) and f3 (BLS).
- Multilingual (Chinese / English / Japanese / Korean).

---

## Building

See [BUILD.md](./BUILD.md). Key points:

- This is an old Flutter project (**Flutter 1.22.5 / Dart 2.10.x**, pre
  null-safety, pre-AndroidX). Toolchain versions must match — newer ones won't
  build it.
- Copy the config: `cp android/gradle.properties.example android/gradle.properties`.
- Release build (**use this for everyday installs** — smaller and optimized):

  ```bash
  flutter pub get                 # fetches flotus(github.com/beck-8/flotus) + bls
  flutter build apk --release
  # -> build/app/outputs/flutter-apk/app-release.apk
  ```

  Use `flutter build apk --debug` only while developing (faster, debuggable, but
  larger and unoptimized).

No Android NDK or Go needed — the native libs (`flotus` / `bls`) ship prebuilt
for arm64-v8a / armeabi-v7a / x86 / x86_64.

---

## On signing

Android APKs must be signed to install; there is no installable "unsigned" APK.
The package name is always `io.fivetokenpro.fil` for everyone — what decides
whether two APKs can **update over each other in place** (without uninstalling
and wiping wallet data) is the **signing key**, not the package name.

### Default: the committed community shared key

This repo ships a shared keystore at **`android/fivetoken-shared.jks`** (alias
`fivetoken`, all passwords `fivetoken`). **Both** debug and release builds sign
with it by default, no setup required. Because everyone uses the same key, APKs
built by **anyone** (you building for someone, or that person rebuilding later)
update over each other in place and keep the wallet data.

```bash
flutter build apk --release    # recommended: shared key, unless key.properties exists
flutter build apk --debug      # dev only: also the shared key
```

> ⚠️ The shared key is **public** — it exists for build/update *compatibility*,
> not anti-tampering. A matching signature does **not** prove an APK came from a
> trusted source, since anyone can sign with it. Only install APKs you built
> yourself or got from a source you trust. Do **not** use the shared key for
> public distribution of a wallet app.

### Optional: your own private release key

For a release you control, use your own private keystore. If
`android/key.properties` exists, **release** builds use it instead of the shared
key (debug still uses the shared key):

```bash
keytool -genkey -v -keystore ~/fivetoken-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias fivetoken
cp android/key.properties.example android/key.properties   # then edit it
flutter build apk --release
```

Keep the private keystore **private and backed up**; sign **all** your official
releases with the **same** keystore so users can update without reinstalling.
`android/key.properties` is gitignored.

---

## Toolchain

| Tool | Version | Notes |
|------|---------|-------|
| Flutter | **1.22.5 (stable)** | Bundles Dart 2.10.x. Pin with [fvm](https://fvm.app): `fvm install 1.22.5 && fvm use 1.22.5`. Don't install Dart separately. |
| JDK | **8** (required) | AGP 3.5.0 + Gradle 5.6.2 only build on Java 8; JDK 11/17 fail. Keep a newer default JDK if you like and point only Gradle at JDK 8 (see BUILD.md). |
| Android SDK | Platform **29**, Build-Tools **29.0.3**, Platform-Tools | `sdkmanager "platforms;android-29" "build-tools;29.0.3" "platform-tools"` (cmdline-tools need JDK 17 to *run* sdkmanager). |
| Git | any | Fetches the `flotus` / `bls` plugin git dependencies. |

---

## Choosing a network

In-app: **Settings → Network**. Mainnet and Calibration (public glif RPC) are
built in, and you can add a custom RPC URL. Use **Calibration** for safe testing
with testnet FIL.

---

## Data sources

- On-chain data (balance, nonce, gas, miner info, market balance, multisig
  proposals, push/query) — directly from your configured Lotus RPC node.
- Plain account transfer history — not available from a single RPC node, read
  from the public filfox API (mainnet `filfox.info`, calibration
  `calibration.filfox.info`).
- Block-explorer links — filfox.

Repo: https://github.com/beck-8/FiveToken-Pro

---

## License

[MIT](./LICENSE)
