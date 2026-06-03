import 'package:fil/index.dart';
import 'package:hive/hive.dart';
part 'network.g.dart';

/// A Filecoin network the wallet can talk to.
///
/// The app is fully self-contained: its ONLY external dependency is the RPC
/// node configured here. Two networks are built in (mainnet / calibration via
/// the public glif endpoints) and the user may add custom RPC endpoints.
@HiveType(typeId: 20)
class Network {
  /// stable unique key, also the Hive box key
  @HiveField(0)
  String id;

  /// display name
  @HiveField(1)
  String name;

  /// Lotus JSON-RPC endpoint, e.g. https://api.node.glif.io/rpc/v1
  @HiveField(2)
  String rpcUrl;

  /// address prefix: 'f' for mainnet, 't' for testnet/calibration
  @HiveField(3)
  String prefix;

  /// built-in networks cannot be deleted/edited
  @HiveField(4)
  bool builtin;

  Network({this.id, this.name, this.rpcUrl, this.prefix, this.builtin = false});

  Network.fromJson(Map<dynamic, dynamic> json) {
    id = json['id'];
    name = json['name'];
    rpcUrl = json['rpcUrl'];
    prefix = json['prefix'];
    builtin = json['builtin'] ?? false;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'rpcUrl': rpcUrl,
      'prefix': prefix,
      'builtin': builtin
    };
  }

  bool get isMainnet => prefix == 'f';
}

/// id of the SharedPreferences key holding the selected network id
const StoreKeySelectedNetwork = 'selectedNetwork';

/// Built-in network ids
const NetworkIdMainnet = 'mainnet';
const NetworkIdCalibration = 'calibration';

/// The two built-in networks (public glif endpoints, verified reachable).
List<Network> builtinNetworks() {
  return [
    Network(
        id: NetworkIdMainnet,
        name: 'Mainnet',
        rpcUrl: 'https://api.node.glif.io/rpc/v1',
        prefix: 'f',
        builtin: true),
    Network(
        id: NetworkIdCalibration,
        name: 'Calibration',
        rpcUrl: 'https://api.calibration.node.glif.io/rpc/v1',
        prefix: 't',
        builtin: true),
  ];
}

/// Seed the built-in networks into the box on first run, and refresh the
/// rpcUrl of built-ins in case the default endpoints changed across versions.
void seedBuiltinNetworks() {
  var box = OpenedBox.networkInstance;
  builtinNetworks().forEach((n) {
    var existing = box.get(n.id);
    // Seed on first run; for built-ins keep endpoints in sync with the bundled
    // defaults (in case the public endpoint changed across versions).
    if (existing == null || existing.builtin) {
      box.put(n.id, n);
    }
  });
}

/// Resolve and apply the selected network into [Global].
/// Falls back to mainnet when nothing is selected yet.
/// Requires [Global.store] to be ready (call after initSharedPreferences set it).
void loadSelectedNetwork() {
  var box = OpenedBox.networkInstance;
  var selectedId = Global.store.getString(StoreKeySelectedNetwork);
  Network net = selectedId != null ? box.get(selectedId) : null;
  net ??= box.get(NetworkIdMainnet);
  net ??= builtinNetworks().first;
  Global.currentNetwork = net;
}

/// Switch the active network, persist the choice and rebuild the provider so
/// subsequent calls hit the new RPC endpoint.
Future<void> switchNetwork(Network net) async {
  Global.currentNetwork = net;
  await Global.store.setString(StoreKeySelectedNetwork, net.id);
  Global.provider = FilecoinProvider();
}
