import 'package:fil/index.dart';

/// Fiat price was served by a hosted FiveToken endpoint that is now offline.
/// To keep the wallet self-contained (only dependency = the RPC node), the
/// price feed is disabled and returns a zero price (the UI renders it as "--").
Future<FilPrice> getFilPrice() async {
  return FilPrice();
}
