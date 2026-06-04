import 'package:fil/index.dart';

Future<String> initSharedPreferences() async {
  var initialRoute = mainPage;
  var instance = await SharedPreferences.getInstance();
  Global.store = instance;
  // Resolve the active network (built-in or user custom) before any RPC call.
  loadSelectedNetwork();
  Global.registerId = Global.store.getString('registerId') ?? "";
  if (instance.getInt('passWrongCount') == null) {
    instance.setInt('passWrongCount', 0);
  }

  /// If the the app was opened for the first time, English is preferred.
  /// If there is a cached lang code in device, set language to that
  var langCode = instance.getString(StoreKeyLanguage);
  if (langCode == null) {
    var locale = WidgetsBinding.instance.window.locale;
    if (locale.toString().toLowerCase().indexOf('en') >= 0) {
      langCode = 'en';
    } else {
      langCode = 'zh';
    }
    instance.setString(StoreKeyLanguage, 'zh');
  }
  if (langCode != null) {
    Global.langCode = langCode;
  } else {
    Global.langCode = 'en';
  }
  
  /// As the app support two mode, set when it's start
  /// Offline mode: mainly for sign message
  var mode = instance.getBool('runMode');
  if (mode != null) {
    Global.onlineMode = mode;
  } else {
    Global.onlineMode = true;
  }
  var walletstr = instance.getString(StoreKeyActiveWallet);
  var activeAddrStr = instance.getString('activeWalletAddress');
  var activeMultiStr = instance.getString('activeMultiAddress');
  /// Compatible historical version
  /// In the original version, all data store in SharedPreferences as string
  if (walletstr != null || activeAddrStr != null) {
    Wallet wallet;
    if (activeAddrStr != null) {
      wallet = OpenedBox.addressInsance.get(activeAddrStr);
      if (wallet == null) {
        // The active pointer didn't match a box key. Older builds saved the
        // network-prefixed address (addrWithNet) here while the box is keyed by
        // the stable address, so after a network switch the pointer goes stale.
        // Recover by matching on the address payload (ignoring the f/t prefix),
        // else fall back to the first stored wallet — never drop a user who has
        // wallets back into the onboarding flow.
        var wallets = OpenedBox.addressInsance.values
            .where((w) => w != null && w.addr != '')
            .toList();
        if (wallets.isNotEmpty) {
          var payload =
              activeAddrStr.length > 1 ? activeAddrStr.substring(1) : '';
          wallet = wallets.firstWhere(
              (w) => w.addr.length > 1 && w.addr.substring(1) == payload,
              orElse: () => wallets[0]);
        }
      }
    } else {
      try {
        var w = jsonDecode(walletstr);
        wallet = Wallet(
            address: w['address'],
            label: w['label'],
            ck: w['ck'],
            type: w['type'],
            walletType: w['walletType'],
            readonly: w['readonly'],
            balance: w['balance'],
            owner: w['owner']);
        instance.remove(StoreKeyActiveWallet);
      } catch (e) {
        print(e);
      }
    }
    if (wallet != null) {
      $store.setWallet(wallet);
      instance.setString('activeWalletAddress', wallet.addr);
    } else {
      initialRoute = initLangPage;
    }
  } else {
    initialRoute = initLangPage;
  }
  /// set current multi-sig wallet
  if (activeMultiStr != null) {
    MultiSignWallet wal = OpenedBox.multiInsance.get(activeMultiStr);
    $store.setMultiWallet(wal);
  }
  return initialRoute;
}
