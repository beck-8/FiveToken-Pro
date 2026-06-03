import 'package:fil/index.dart';
import 'package:fil/pages/network/main.dart';
import 'package:fil/pages/network/add.dart';

List<GetPage> getNetworkRoutes() {
  var list = <GetPage>[];
  var index =
      GetPage(name: networkListPage, page: () => NetworkListPage());
  var add = GetPage(name: networkAddPage, page: () => NetworkAddPage());
  list..add(index)..add(add);
  return list;
}
