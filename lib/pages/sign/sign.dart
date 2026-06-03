import 'package:fil/index.dart';
import './unsigned.dart';

/// sign message
class SignIndexPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return SignIndexPageState();
  }
}

class SignIndexPageState extends State<SignIndexPage> {
  TMessage message;
  SignedMessage signedMessage;
  bool showSigned = false;
  void handleScan() {
    Get.toNamed(scanPage, arguments: {'scene': ScanScene.UnSignedMessage})
        .then((res) {
      if (res != '') {
        try {
          var mes = jsonDecode(res);
          setState(() {
            var message = TMessage.fromJson(mes);
            this.message = message;
          });
        } catch (e) {
          showCustomError('errorMesFormat'.tr);
        }
      }
    });
  }

  void signMessage(String pass) async {
    var wallet = $store.wal;
    var signMode = Global.store.getInt('signMode');
    // Compare ignoring the network prefix (f/t): a signature is network-agnostic
    // (the address bytes carry protocol+payload, not the f/t prefix), so the
    // offline signer can be on a different network than the built message and
    // still sign for the same key.
    var fromPayload =
        message.from.isNotEmpty ? message.from.substring(1) : message.from;
    var walletPayload = wallet.addrWithNet.isNotEmpty
        ? wallet.addrWithNet.substring(1)
        : wallet.addrWithNet;
    if (fromPayload != walletPayload) {
      showCustomError('fromNotMatch'.tr);
      return;
    }
    var now = (DateTime.now().millisecondsSinceEpoch / 1000).truncate();
    String sign = '';
    num signType;
    var cid =
        await Flotus.messageCid(msg: jsonEncode(message.toLotusMessage()));
    var wal = $store.wal;
    var ck = await getPrivateKey(wal.addrWithNet, pass, wal.skKek);
    if (message.from[1] == '1') {
      signType = SignTypeSecp;
      sign = await Flotus.secpSign(ck: ck, msg: cid);
    } else {
      signType = SignTypeBls;
      sign = await Bls.cksign(num: "$ck $cid");
    }
    var signedMessage = SignedMessage(message, Signature(signType, sign));
    if (signMode == 1) {
      OpenedBox.nonceInsance
          .put(message.from, Nonce(time: now, value: message.nonce + 1));
    }
    setState(() {
      showSigned = true;
      this.signedMessage = signedMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    var kH = MediaQuery.of(context).viewInsets.bottom;
    return CommonScaffold(
      title: 'second'.tr,
      footerText: showSigned ? 'close'.tr : 'signBtn'.tr,
      grey: true,
      hasFooter: kH == 0,
      resizeToAvoidBottomInset: kH != 0,
      onPressed: () {
        if (showSigned) {
          Get.back();
        } else {
          if (message == null) {
            return;
          }
          showPassDialog(context, (String pass) {
            signMessage(pass);
          });
        }
      },
      actions: [ScanAction(handleScan: handleScan)],
      body: Column(
        children: [
          Expanded(
              child: SingleChildScrollView(
            child: showSigned
                ? SignedMessageBody(signedMessage)
                : UnsignedMessage(
                    onTap: handleScan,
                    message: message,
                    edit: (TMessage message) {
                      setState(() {
                        this.message = message;
                      });
                    },
                  ),
            padding: EdgeInsets.fromLTRB(12, 20, 12, 20),
          )),
          SizedBox(
            height: 120,
          )
        ],
      ),
    );
  }
}
