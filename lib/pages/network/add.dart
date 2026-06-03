import 'package:fil/index.dart';

/// Add or edit a custom RPC network.
class NetworkAddPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return NetworkAddPageState();
  }
}

class NetworkAddPageState extends State<NetworkAddPage> {
  TextEditingController nameCtrl = TextEditingController();
  TextEditingController urlCtrl = TextEditingController();
  String prefix = 'f';
  Network network;
  var box = OpenedBox.networkInstance;

  @override
  void initState() {
    super.initState();
    if (Get.arguments != null && Get.arguments['mode'] != null) {
      network = Get.arguments['network'] as Network;
      nameCtrl.text = network.name;
      urlCtrl.text = network.rpcUrl;
      prefix = network.prefix;
    }
  }

  bool get edit {
    return network != null;
  }

  bool checkValid() {
    var name = nameCtrl.text.trim();
    var url = urlCtrl.text.trim();
    if (name == '' || name.length > 30) {
      showCustomError('enterNetworkName'.tr);
      return false;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      showCustomError('enterRpcUrl'.tr);
      return false;
    }
    return true;
  }

  void handleConfirm() {
    if (!checkValid()) {
      return;
    }
    var name = nameCtrl.text.trim();
    var url = urlCtrl.text.trim();
    var id = edit
        ? network.id
        : 'custom_' + DateTime.now().millisecondsSinceEpoch.toString();
    box.put(
        id,
        Network(
            id: id, name: name, rpcUrl: url, prefix: prefix, builtin: false));
    // If editing the currently active network, apply the change immediately.
    if (edit && Global.currentNetwork != null &&
        Global.currentNetwork.id == id) {
      Global.currentNetwork = box.get(id);
      Global.provider = FilecoinProvider();
    }
    showCustomToast(edit ? 'opSucc'.tr : 'addNetworkSucc'.tr);
    Get.back();
  }

  Widget _prefixOption(String label, String value) {
    var active = prefix == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            prefix = value;
          });
        },
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              borderRadius: CustomRadius.b8,
              color: active ? CustomColor.primary : Color(0xffEEF1F5)),
          child: active
              ? CommonText.white(label, size: 14)
              : CommonText(label, size: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: edit ? 'editNetwork'.tr : 'addNetwork'.tr,
      footerText: edit ? 'save'.tr : 'add'.tr,
      onPressed: handleConfirm,
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Field(
              controller: nameCtrl,
              label: 'networkName'.tr,
            ),
            SizedBox(height: 20),
            Field(
              controller: urlCtrl,
              label: 'rpcUrl'.tr,
            ),
            SizedBox(height: 20),
            Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: CommonText.grey('networkType'.tr, size: 14),
            ),
            Row(
              children: [
                _prefixOption('mainnet'.tr, 'f'),
                SizedBox(width: 12),
                _prefixOption('calibration'.tr, 't'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
