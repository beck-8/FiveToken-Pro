# FiveToken Pro

<div align="right"><a href="./README_EN.md">English</a></div>

面向 Filecoin 存储矿工（SP）的移动钱包（Android / iOS）。

本仓库是 [FiveToken/FiveToken-Pro](https://github.com/FiveToken/FiveToken-Pro) 的一个 **去后端化的独立分支**：
原版是一个“瘦客户端”，所有链上交互都依赖官方自建后端 `api.fivetoken.io`。该后端已下线，原版无法使用。
本分支把全部链上交互改为 **直连 Filecoin Lotus JSON-RPC 节点**，整个 App 的唯一外部依赖就是一个**用户可配置的 RPC 节点**。

> 数据来源原则：**能走链上的数据都走链上**，只有单个 RPC 节点拿不到的数据（普通账户的转入转出历史）才从 filfox 公开 API 读取。

---

## 最近的改动

### 架构：去后端化，直连链上
- 删除对已下线后端 `api.fivetoken.io` 和法币价格服务的全部依赖。
- `lib/chain/provider.dart` 整体重写为 Lotus JSON-RPC 客户端（`StateGetActor` / `MpoolGetNonce` / `GasEstimateMessageGas` / `MpoolPush` / `StateSearchMsg` / `MsigGetPending` / `StateMinerInfo` / `StateMarketBalance` 等）。
- 新增 `lib/chain/cbor.dart`：在 Dart 内手写 Filecoin CBOR 参数编码器（按 `go-state-types` 实现并用官方测试向量校验），替代原后端负责的“参数 CBOR 序列化”。签名 / CID / 私钥派生仍由仓库内置的 `flotus`(secp256k1) 与 `bls`(BLS) 插件在本地完成。
- 新增网络模型与**运行时网络切换**：内置主网 / 校准网（glif 公共 RPC），并支持自定义 RPC。在 **设置 → 网络管理** 切换，同一私钥按网络前缀（`f` / `t`）重新派生地址。

### 矿工（SP）信息面板：改为链上直读
- owner / worker / control / beneficiary 地址及各自余额。
- 待变更 worker（NewWorker + 生效高度）、待变更 owner（PendingOwnerAddress）。
- 可提现余额、当前算力、扇区大小。
- **新增 market 余额**（Escrow / Locked，类似 `lotus-miner info`）。
- 全部来自 `StateMinerInfo` / `StateMinerAvailableBalance` / `StateMinerPower` / `StateGetActor` / `StateMarketBalance`，手动输入 miner id 即可查询。

### 单签矿工操作（消息构建 → 离线签名 → 推送）
- 矿工提现（method 16）、变更 owner（23）、变更 worker（3）、ConfirmUpdateWorkerKey（21）。
- **market 提现**（f05 上的 method 3）：在节点管理里独立入口，消息构建的操作选项中也已加入；文案与方法号正确区分（不再误显示为“变更 worker”）。
- **CreateMiner（创建节点）**：proof 类型支持 V1_1（13 = 32GiB / 14 = 64GiB，新矿工必须用 V1_1），并按 FIP-0077 要求在最下方填写创建保证金，附带说明。

### 多签：完整且不依赖历史索引
- 创建 / 导入 / 发起提案 / 批准，全部走链上。
- 待批准提案来自 `MsigGetPending`（提案人取 `Approved[0]`），可在 pending 状态下点击跳转区块浏览器查看。

### 重要修复
- **私钥/密码 KEK** 改用稳定的存储地址派生（原先用带网络前缀的地址，导致切到校准网后“密码不对”）。
- **离线签名** 的 From 校验改为按 payload 比对、忽略网络前缀（原先切到主网提示“from 不匹配”；签名本身与网络无关）。
- `buildMessage` 改为获取**真实 nonce**（原先恒为 0，导致推送报“nonce 错误”）。
- gas 估算改为对**真实消息**估算并加 1.25x 安全余量（修复多签/转账手续费为 0 与 `SysErrOutOfGas`）。
- 交易详情页发送/接收地址改用 `ChainGetMessage` 回填（原先非 pending 状态下为空白）。
- 内置 webview 增加“在外部浏览器打开”按钮（便于复制页面文字）。
- 移除已失效的“帮助中心”入口；客服改为 Telegram [@beck_debug](https://t.me/beck_debug)；问题反馈指向本仓库 issues。

---

## 功能特性

- 创建 / 导入钱包（助记词、私钥），本地加密存储私钥。
- FIL 转账与 gas 估算，自定义 method ID 构建消息。
- 存储矿工（SP）链上信息面板 + 单签操作（提现 / 变更 owner / 变更 worker / market 提现 / 创建节点）。
- 完整多签钱包（创建 / 导入 / 发起 / 批准）。
- 离线（冷钱包）签名：在不联网的离线机器上签名，再由联网机器推送上链。
- 二维码跨设备传输；只读钱包；支持 f1 (secp256k1) 与 f3 (BLS)。
- 多语言（中 / 英 / 日 / 韩）。

---

## 编译方式

详见 [BUILD.md](./BUILD.md)。要点：

- 这是一个老 Flutter 工程（**Flutter 1.22.5 / Dart 2.10.x**，无 null-safety、pre-AndroidX），工具链版本必须匹配，新版本无法编译。
- 复制配置：`cp android/gradle.properties.example android/gradle.properties`。
- 编译 debug：

  ```bash
  flutter pub get                 # 拉取 flotus(github.com/beck-8/flotus) + bls
  flutter build apk --debug
  # -> build/app/outputs/flutter-apk/app-debug.apk
  ```

无需 Android NDK 或 Go —— native 库（`flotus` / `bls`）已为 arm64-v8a / armeabi-v7a / x86 / x86_64 预编译。

---

## 关于签名

Android APK 必须签名才能安装，没有“未签名”的可安装包。

- **debug 编译**（`--debug`，以及不配 keystore 的 `--release`）：用本机自动生成的 **debug keystore**（`~/.android/debug.keystore`）签名。所有人的**包名都是 `io.fivetokenpro.fil`**，但每台机器的 debug key **各不相同**。后果：
  - 同一台机器编出的包可以互相覆盖更新（同一 debug key）。
  - **不同 debug key**（不同人/机器）编出的包**无法互相覆盖更新**，Android 会拒绝安装，必须先卸载（卸载会清空钱包数据）。
- **release 编译**（可分发、可更新）：生成一个 release keystore，**自行妥善保管、切勿提交**，然后配置 `key.properties`：

  ```bash
  keytool -genkey -v -keystore ~/fivetoken-release.jks \
    -keyalg RSA -keysize 2048 -validity 10000 -alias fivetoken
  cp android/key.properties.example android/key.properties   # 然后填写
  flutter build apk --release
  ```

  所有官方发布版本都应用**同一个 keystore** 签名，用户才能不卸载、不丢钱包地更新。`android/key.properties` 与 keystore 文件均已 gitignore。

---

## 依赖安装（工具链）

| 工具 | 版本 | 说明 |
|------|------|------|
| Flutter | **1.22.5 (stable)** | 自带 Dart 2.10.x。建议用 [fvm](https://fvm.app) 锁定：`fvm install 1.22.5 && fvm use 1.22.5`。不要单独装 Dart。 |
| JDK | **8**（必须） | AGP 3.5.0 + Gradle 5.6.2 只能在 Java 8 上构建；JDK 11/17 会失败。默认 JDK 可保留新版本，仅让 Gradle 指向 JDK 8（见 BUILD.md）。 |
| Android SDK | Platform **29**、Build-Tools **29.0.3**、Platform-Tools | `sdkmanager "platforms;android-29" "build-tools;29.0.3" "platform-tools"`（注意 cmdline-tools 自身需要 JDK 17 才能运行 sdkmanager）。 |
| Git | 任意 | 拉取 `flotus` / `bls` 插件的 git 依赖。 |

---

## 网络选择

App 内 **设置 → 网络管理**：内置主网与校准网（glif 公共 RPC），可添加自定义 RPC URL。测试请用**校准网**（calibration）配测试币，安全无损失。

---

## 数据来源

- 链上数据（余额、nonce、gas、矿工信息、market 余额、多签提案、推送/查询消息）—— 直连用户配置的 Lotus RPC 节点。
- 普通账户转入转出历史 —— 单个 RPC 节点无法提供，读取 filfox 公开 API（主网 `filfox.info`，校准网 `calibration.filfox.info`）。
- 区块浏览器跳转 —— filfox。

仓库地址：https://github.com/beck-8/FiveToken-Pro

---

## License

[MIT](./LICENSE)
