import 'package:fil/index.dart';
import 'package:flutter_swipe_action_cell/flutter_swipe_action_cell.dart';

/// List of networks (built-in mainnet/calibration + user custom RPC).
/// Tap to switch the active network; swipe a custom one to edit/delete.
class NetworkListPage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return NetworkListPageState();
  }
}

class NetworkListPageState extends State<NetworkListPage> {
  var box = OpenedBox.networkInstance;
  List<Network> list = [];

  void setList() {
    setState(() {
      list = box.values.toList();
    });
  }

  @override
  void initState() {
    super.initState();
    setList();
  }

  bool isCurrent(Network net) {
    return Global.currentNetwork != null && Global.currentNetwork.id == net.id;
  }

  void handleSwitch(Network net) async {
    if (isCurrent(net)) {
      return;
    }
    await switchNetwork(net);
    showCustomToast('switchNetworkSucc'.tr);
    // Rebuild from home so the new prefix/RPC takes effect everywhere.
    Get.offAllNamed(mainPage);
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      title: 'networkManage'.tr,
      hasFooter: false,
      actions: [
        GestureDetector(
          child: Padding(
            padding: EdgeInsets.only(right: 12),
            child: Icon(
              Icons.add_circle_outline,
              color: Colors.black,
            ),
          ),
          onTap: () {
            Get.toNamed(networkAddPage).then((value) {
              setList();
            });
          },
        )
      ],
      body: SingleChildScrollView(
        child: Column(
          children: List.generate(list.length, (index) {
            var net = list[index];
            var cell = NetworkCell(
              net: net,
              selected: isCurrent(net),
              onTap: () {
                handleSwitch(net);
              },
            );
            if (net.builtin) {
              return cell;
            }
            return SwipeActionCell(
              key: ValueKey(net.id),
              trailingActions: [
                SwipeAction(
                    color: Colors.transparent,
                    content: _getIconButton(
                        CustomColor.red,
                        Image(
                          image: AssetImage('images/delete.png'),
                        )),
                    onTap: (handler) async {
                      handler(false);
                      showDeleteDialog(context,
                          title: 'deleteNetwork'.tr,
                          content: 'confirmDelete'.tr, onDelete: () {
                        box.delete(net.id);
                        setList();
                        showCustomToast('deleteSucc'.tr);
                      });
                    }),
                SwipeAction(
                    content: _getIconButton(
                        Color(0xffE8CC5C),
                        Image(
                          image: AssetImage('images/set.png'),
                        )),
                    color: Colors.transparent,
                    onTap: (handler) {
                      handler(false);
                      Get.toNamed(networkAddPage,
                          arguments: {'mode': 1, 'network': net}).then((value) {
                        setList();
                      });
                    }),
              ],
              child: cell,
            );
          }),
        ),
      ),
    );
  }
}

Widget _getIconButton(Color color, Widget icon) {
  return Container(
    width: 50,
    height: 50,
    padding: EdgeInsets.all(12),
    margin: EdgeInsets.only(top: 20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(25),
      color: color,
    ),
    child: icon,
  );
}

class NetworkCell extends StatelessWidget {
  final Network net;
  final bool selected;
  final Noop onTap;
  NetworkCell({this.net, this.selected = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(15, 15, 15, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
              borderRadius: CustomRadius.b8,
              color: selected ? CustomColor.primary : Color(0xff8297B0)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CommonText.white(net.name, size: 16),
                  Visibility(
                    visible: selected,
                    child: Icon(Icons.check, color: Colors.white, size: 18),
                  )
                ],
              ),
              SizedBox(height: 8),
              CommonText.white(net.rpcUrl, size: 12),
            ],
          ),
        ),
      ),
    );
  }
}
