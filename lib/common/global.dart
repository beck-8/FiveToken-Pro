import 'package:event_bus/event_bus.dart';
import 'package:fil/index.dart';
import 'package:dio/dio.dart';

const StoreKeyActiveWallet = "act-wallet";
const StoreKeyLanguage = "language";
const SignSecp = "secp";
const SignBls = "bls";
const SignTypeBls = 2;
const SignTypeSecp = 1;
/// Default address prefix, used only as a fallback before a network is loaded.
const String NetPrefix = 'f';

/// Default RPC endpoint, used only as a fallback before a network is loaded.
const String DefaultRpcUrl = 'https://api.node.glif.io/rpc/v1';

/// Block explorer base, derived from the active network prefix.
/// Explorer is external infrastructure and only used for optional "view on
/// explorer" links; the wallet itself never depends on it.
String get filscanWeb =>
    Global.netPrefix == 'f' ? 'https://filfox.info' : 'https://calibration.filfox.info';

/// Optional "view on explorer" links (filfox). The wallet never depends on
/// these; they just open a public explorer in a webview.
String explorerMessageUrl(String cid) => '$filscanWeb/en/message/$cid';
String explorerAddressUrl(String addr) => '$filscanWeb/en/address/$addr';

/// filfox public explorer API base, for the few pieces of data a single RPC
/// node cannot provide (historical message list, miner aggregate metrics).
/// Null for networks filfox does not index (custom RPCs) -> those features stay
/// empty rather than depending on anything. Everything else comes from chain.
String get filfoxApi {
  if (Global.netPrefix == 'f') return 'https://filfox.info/api/v1';
  if (Global.netPrefix == 't') return 'https://calibration.filfox.info/api/v1';
  return null;
}
class Global {
  static String version = "v2.2.0";

  static bool get isRelease => bool.fromEnvironment("dart.vm.product");

  static SharedPreferences store;

  static Wallet activeWallet;
  static EventBus eventBus = EventBus();
  static String selectWalletType = '1';
  static String uuid;
  static bool online = false;
  static String platform;
  static String os;
  static String registerId;
  static MultiSignWallet currrentMultiSignWallet;

  /// The active network. Set during startup (see loadSelectedNetwork) and
  /// when the user switches networks (see switchNetwork).
  static Network currentNetwork;

  /// Address prefix of the active network ('f' mainnet, 't' calibration).
  static String get netPrefix =>
      currentNetwork != null ? currentNetwork.prefix : NetPrefix;

  /// Lotus JSON-RPC endpoint of the active network. The wallet's ONLY external
  /// dependency. Read dynamically so a network switch takes effect immediately.
  static String get rpcUrl =>
      currentNetwork != null ? currentNetwork.rpcUrl : DefaultRpcUrl;
  static String activeWalletAddress;
  static String langCode;
  static String mode;
  static Wallet cacheWallet;
  static FilPrice price;
  static bool onlineMode = false;
  static Dio defaultClient = Dio();
  static FilecoinProvider provider = FilecoinProvider();
}
