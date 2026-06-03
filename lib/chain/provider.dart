import 'package:fil/index.dart';
import 'package:oktoast/oktoast.dart';

/// Storage market actor id (f05 / t05). Used to disambiguate method-3 messages
/// (miner ChangeWorkerAddress vs market WithdrawBalance).
String get marketActorAddress => Global.netPrefix + '05';

class FilecoinResponse {
  int code;
  dynamic data;
  String message;
  String detail;
  FilecoinResponse({this.code, this.data, this.message, this.detail});
  FilecoinResponse.fromJson(Map<String, dynamic> map) {
    code = map['code'];
    data = map['data'];
    message = map['message'];
    detail = map['detail'];
  }
}

/// Talks directly to a Lotus JSON-RPC node (the wallet's only external
/// dependency). All signing/CID/CBOR happens locally (Flotus/Bls + Cbor).
class FilecoinProvider {
  Dio client;
  FilecoinProvider({Dio httpClient}) {
    client = httpClient ?? Dio();
    client.options.connectTimeout = 30000;
    client.options.headers = {'Content-Type': 'application/json'};
  }

  int _rpcId = 0;

  /// Perform a single Lotus JSON-RPC call against the active network endpoint.
  /// Returns the `result` field, or throws with the RPC error message.
  Future<dynamic> _call(String method, List<dynamic> params) async {
    Response result;
    try {
      result = await client.post(Global.rpcUrl, data: {
        'jsonrpc': '2.0',
        'id': ++_rpcId,
        'method': 'Filecoin.$method',
        'params': params,
      });
    } on DioError catch (e) {
      if (e.type == DioErrorType.CONNECT_TIMEOUT ||
          e.type == DioErrorType.RECEIVE_TIMEOUT) {
        throw Exception('timeout');
      }
      // surface RPC error body if present
      if (e.response != null && e.response.data is Map) {
        var err = (e.response.data as Map)['error'];
        if (err is Map && err['message'] != null) {
          throw Exception(err['message']);
        }
      }
      rethrow;
    }
    var data = result.data;
    if (data is String) {
      data = jsonDecode(data);
    }
    if (data is Map && data['error'] != null) {
      var err = data['error'];
      throw Exception(err is Map ? (err['message'] ?? 'rpc error') : 'rpc error');
    }
    return (data as Map)['result'];
  }

  /// Empty TipSetKey => chain head (verified accepted by glif nodes).
  List<dynamic> get _head => <dynamic>[];

  /// Map a human method name to its actor method number (for gas estimation).
  int _methodNum(String methodName) {
    switch (methodName) {
      case 'Send':
      case 'transfer':
        return 0;
      case 'Exec':
      case 'CreateMiner':
        return 2;
      case 'ChangeWorkerAddress':
        return 3;
      case 'WithdrawBalance':
        return 16;
      case 'ConfirmUpdateWorkerKey':
        return 21;
      case 'ChangeOwnerAddress':
        return 23;
      default:
        return 0;
    }
  }

  Future<String> getActorId(String addr) async {
    try {
      var result = await _call('StateLookupID', [addr, _head]);
      if (result is String && result != '') {
        return result;
      }
      throw Exception('get actor id fail');
    } catch (e) {
      print(e);
      throw (e);
    }
  }

  /// Push an already-signed (Lotus-shaped) message via MpoolPush.
  Future sendSignedMessage(
    Map<String, dynamic> message, {
    SingleParamCallback<String> callback,
  }) async {
    showCustomLoading('sending'.tr);
    try {
      var result = await _call('MpoolPush', [message]);
      dismissAllToast();
      var cid = _cidString(result);
      if (cid != '') {
        showCustomToast('tradeSucc'.tr);
        if (callback != null) {
          callback(cid);
        }
      } else {
        throw Exception('push fail');
      }
    } catch (e) {
      dismissAllToast();
      rethrow;
    }
  }

  /// Extract a CID string from an MpoolPush `{"/":"bafy.."}` result.
  String _cidString(dynamic result) {
    if (result is Map && result['/'] != null) {
      return result['/'].toString();
    }
    if (result is String) {
      return result;
    }
    return '';
  }

  Future<void> sendMessage({
    @required TMessage message,
    @required String private,
    String multiId = '',
    String methodName = 'transfer',
    String multiTo,
    SingleParamCallback<String> callback,
    bool increaseNonce = false,
    CacheMultiMessage multiMessage,
  }) async {
    try {
      String sign = '';
      num signType;
      if (increaseNonce) {
        var nonce = message.nonce;
        OpenedBox.pushInsance.values
            .where((mes) => mes.from == $store.wal.addrWithNet)
            .forEach((mes) {
          if (mes.nonce != null && mes.nonce > nonce) {
            nonce = mes.nonce;
          }
        });
        message.nonce = nonce + 1;
      }
      var cid = await Flotus.messageCid(msg: jsonEncode(message));
      if (message.from[1] == '1') {
        signType = SignTypeSecp;
        sign = await Flotus.secpSign(ck: private, msg: cid);
      } else {
        signType = SignTypeBls;
        sign = await Bls.cksign(num: "$private $cid");
      }
      var from = message.from;
      var to = message.to;
      var nonce = message.nonce;
      var value = message.value;
      var sm = SignedMessage(message, Signature(signType, sign));
      String res = '';
      showCustomLoading('sending'.tr);
      dynamic pushResult;
      try {
        pushResult = await _call('MpoolPush', [sm.toLotusSignedMessage()]);
      } finally {
        dismissAllToast();
      }
      res = _cidString(pushResult);
      if (res != '') {
        showCustomToast('tradeSucc'.tr);
        var cacheGas = CacheGas(
            cid: res,
            feeCap: message.gasFeeCap,
            gasLimit: message.gasLimit,
            premium: message.gasPremium);
        OpenedBox.gasInsance.put('$from\_$nonce', cacheGas);
        $store.setGas(Gas());
        $store.setNonce(-1);
        var now = getSecondSinceEpoch();
        var m = message.method;
        var isCreate = message.to == FilecoinAccount.f01;
        if (m == 0 || (m == 2 && isCreate)) {
          await OpenedBox.messageInsance.put(
              res,
              StoreMessage(
                  pending: 1,
                  from: from,
                  to: to,
                  value: value,
                  owner: from,
                  nonce: nonce,
                  methodName: methodName,
                  signedCid: res,
                  blockTime: now));
        }
        OpenedBox.pushInsance.put(
            res,
            StoreSignedMessage(
                time: now.toString(),
                message: sm,
                cid: res,
                pending: 1,
                nonce: sm.message.nonce));
        OpenedBox.nonceInsance.put(from,
            Nonce(value: nonce + 1, time: DateTime.now().millisecondsSinceEpoch));
        if (callback != null) {
          callback(res);
        }
      } else {
        throw Exception('push fail');
      }
    } on DioError catch (e) {
      if (e.type == DioErrorType.CONNECT_TIMEOUT) {
        throw Exception('timeout');
      } else {
        throw (e);
      }
    } catch (e) {
      dismissAllToast();
      print(e);
      throw (e);
    }
  }

  void checkSpeedUpOrMakeNew(
      {@required BuildContext context,
      @required SingleParamCallback<bool> onNew,
      @required Noop onSpeedup,
      int nonce,
      String multiId = ''}) {
    bool shouldSpeed = false;
    shouldSpeed = OpenedBox.pushInsance.values
        .where((mes) =>
            mes.message.message.from == $store.wal.addrWithNet &&
            mes.nonce == nonce)
        .isNotEmpty;

    if (shouldSpeed) {
      showCustomModalBottomSheet(
          shape: RoundedRectangleBorder(borderRadius: CustomRadius.top),
          context: context,
          builder: (BuildContext context) {
            return ConstrainedBox(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: 30),
                child: SpeedupSheet(
                  onNew: () {
                    onNew(true);
                  },
                  onSpeedUp: onSpeedup,
                ),
              ),
              constraints: BoxConstraints(maxHeight: 800),
            );
          });
    } else {
      onNew(false);
    }
  }

  TMessage getIncreaseGasMessage({Gas gas, int nonce}) {
    if (nonce == null) {
      nonce = $store.nonce;
    }

    var pushList = OpenedBox.pushInsance.values
        .where(
            (mes) => mes.from == $store.wal.addrWithNet && mes.nonce == nonce)
        .toList();
    if (pushList.isNotEmpty) {
      var last = pushList.last;
      var msg = last.message.message;
      var caculatePremium = (int.tryParse(msg.gasPremium) * 1.3).truncate();
      var chainPremium =
          int.tryParse(gas != null ? gas.premium : msg.gasPremium) ?? 0;
      var chainFeeCap =
          int.tryParse(gas != null ? gas.feeCap : msg.gasFeeCap) ?? 0;
      var realPremium = max(chainPremium, caculatePremium);
      msg.gasPremium = realPremium.toString();
      msg.gasFeeCap = max(chainFeeCap, realPremium + 100).toString();
      return msg;
    } else {
      throw Exception('get message fail');
    }
  }

  Future<void> speedup(
      {@required String private,
      @required Gas gas,
      String methodName = '',
      String multiId = ''}) async {
    TMessage msg;
    var isApprove = methodName == FilecoinMethod.approve;
    var isPropose = methodName == FilecoinMethod.propose;
    try {
      msg = getIncreaseGasMessage(gas: gas);
    } catch (e) {
      print(e);
      showCustomError('opFail'.tr);
      return '';
    }
    CacheMultiMessage multiMessage;
    MultiApproveMessage approveMessage;
    if (isPropose) {
      var list = OpenedBox.multiProposeInstance.values
          .where((mes) => mes.from == msg.from && mes.nonce == msg.nonce)
          .toList();
      if (list.isNotEmpty) {
        multiMessage = list[0];
      }
    }
    if (isApprove) {
      var list = OpenedBox.multiApproveInstance.values
          .where((mes) => mes.from == msg.from && mes.nonce == msg.nonce)
          .toList();
      if (list.isNotEmpty) {
        approveMessage = list[0];
      }
    }
    try {
      await sendMessage(
          message: msg,
          private: private,
          multiId: multiId,
          multiMessage: multiMessage,
          callback: (res) {
            var keys = OpenedBox.pushInsance.values
                .where((mes) => mes.nonce == msg.nonce && mes.from == msg.from)
                .toList();
            if (keys.isNotEmpty) {
              OpenedBox.pushInsance.delete(keys[0].cid);
            }
            if (isPropose && multiMessage != null) {
              multiMessage.cid = res;
              multiMessage.blockTime = getSecondSinceEpoch();
              OpenedBox.multiProposeInstance.put(res, multiMessage);
            }
            if (isApprove && approveMessage != null) {
              OpenedBox.multiApproveInstance.put(
                  res,
                  MultiApproveMessage(
                      from: approveMessage.from,
                      fee: msg.maxFee.toString(),
                      time: getSecondSinceEpoch(),
                      proposeCid: approveMessage.proposeCid,
                      cid: res,
                      txId: approveMessage.txId,
                      nonce: approveMessage.nonce));
            }
          });
    } catch (e) {
      print(e);
      throw (e);
    }
  }

  Future<bool> getGas({String to, String methodName = 'Send'}) async {
    to = to ?? $store.addr;
    try {
      var gas = await getGasDetail(to: to, methodName: methodName);
      $store.setGas(gas);
      $store.setChainGas(gas);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Gas estimation via GasEstimateMessageGas. Builds a representative message
  /// (zero gas) and lets the node fill GasLimit/FeeCap/Premium.
  Future<Gas> getGasDetail({String to, String methodName = 'Send'}) async {
    to = to ?? $store.addr;
    var from = $store.wal != null ? $store.wal.addrWithNet : to;
    try {
      var msg = <String, dynamic>{
        'Version': 0,
        'To': to,
        'From': from,
        'Value': '0',
        'GasLimit': 0,
        'GasFeeCap': '0',
        'GasPremium': '0',
        'Params': '',
        'Nonce': 0,
        'Method': _methodNum(methodName),
      };
      var res = await _call('GasEstimateMessageGas', [msg, null, _head]);
      if (res is Map) {
        return Gas(
            feeCap: (res['GasFeeCap'] ?? '0').toString(),
            gasLimit: res['GasLimit'] ?? 0,
            premium: (res['GasPremium'] ?? '0').toString());
      }
      throw Exception('get gas fail');
    } catch (e) {
      throw (e);
    }
  }

  Future<MultiWalletInfo> getMultiInfo(String addr) async {
    try {
      var rs = await _call('StateReadState', [addr, _head]);
      if (rs is Map && rs['State'] is Map) {
        var state = rs['State'] as Map;
        var info = MultiWalletInfo(
            signerMap: {},
            balance: (rs['Balance'] ?? '0').toString(),
            robustAddress: addr,
            approveRequired: state['NumApprovalsThreshold']);
        var signers = state['Signers'];
        if (signers is List) {
          signers.forEach((s) {
            // signers are id-addresses (f0..); map id->id (robust resolved lazily)
            info.signerMap[s.toString()] = s.toString();
          });
        }
        return info;
      }
      throw Exception('get multisig fail');
    } catch (e) {
      throw (e);
    }
  }

  /// Message status via StateSearchMsg (degraded: confirmation + exit code).
  Future<MessageDetail> getMessageDetail(String cid) async {
    try {
      var res = await _call('StateSearchMsg', [
        _head,
        {'/': cid},
        -1,
        true
      ]);
      var detail = MessageDetail(signedCid: cid);
      if (res is Map) {
        if (res['Receipt'] is Map) {
          detail.exitCode = res['Receipt']['ExitCode'];
        }
        if (res['Height'] != null) {
          detail.height = res['Height'];
        }
        detail.pending = res['Height'] != null && res['Height'] != -1 ? 0 : 1;
      } else {
        detail.pending = 1;
      }
      return detail;
    } catch (e) {
      // not yet on chain
      return MessageDetail(signedCid: cid)..pending = 1;
    }
  }

  Future<bool> getNonceAndGas(
      {num method, String to, String from, String methodName = 'Send'}) async {
    var wal = $store.wal;
    var address = wal.addrWithNet;
    to = to ?? address;
    try {
      var res = await Future.wait([
        getNonce(from ?? $store.addr),
        getGas(to: to, methodName: methodName)
      ]);
      if (res[0] != -1 && (res[1] as bool) == true) {
        var nonce = res[0] as int;
        $store.setNonce(nonce);
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  Future<int> getNonce(String addr) async {
    try {
      var n = await _call('MpoolGetNonce', [addr]);
      if (n is int) return n;
    } catch (e) {
      // actor may not exist yet, fall back to on-chain actor nonce
      try {
        var actor = await _call('StateGetActor', [addr, _head]);
        if (actor is Map && actor['Nonce'] != null) {
          return actor['Nonce'];
        }
      } catch (_) {}
    }
    return 0;
  }

  Future<String> getBalance(String addr) async {
    try {
      var actor = await _call('StateGetActor', [addr, _head]);
      if (actor is Map && actor['Balance'] != null) {
        return actor['Balance'].toString();
      }
      return '0';
    } catch (e) {
      // unfunded / non-existent actor has no balance
      if (e.toString().contains('not found') ||
          e.toString().contains('actor not found')) {
        return '0';
      }
      throw Exception(e);
    }
  }

  Future<BalanceNonce> getBalanceNonce(String addr) async {
    var balanceNonce = BalanceNonce(balance: '0', nonce: 0);
    try {
      var actor = await _call('StateGetActor', [addr, _head]);
      if (actor is Map) {
        balanceNonce.balance = (actor['Balance'] ?? '0').toString();
        balanceNonce.nonce = actor['Nonce'] ?? 0;
      }
    } catch (e) {
      if (!e.toString().contains('not found')) {
        throw Exception(e);
      }
    }
    return balanceNonce;
  }

  /// Build an unsigned message with estimated gas. `data['params']` must be the
  /// final, pre-encoded params string (base64 CBOR), or empty for a plain send.
  /// Param CBOR encoding is done by the call site via [FilParams]/[Flotus].
  Future<TMessage> buildMessage(Map<String, dynamic> data) async {
    try {
      var from = data['from'].toString();
      var to = data['to'].toString();
      var value = (data['value'] ?? '0').toString();
      var method = data['method'] is int
          ? data['method']
          : int.parse(data['method'].toString());
      var params = data['params'];
      var paramStr = params is String ? params : '';
      var estMsg = <String, dynamic>{
        'Version': 0,
        'To': to,
        'From': from,
        'Value': value,
        'GasLimit': 0,
        'GasFeeCap': '0',
        'GasPremium': '0',
        'Params': paramStr,
        'Nonce': 0,
        'Method': method,
      };
      var res = await _call('GasEstimateMessageGas', [estMsg, null, _head]);
      if (res is Map) {
        return TMessage(
            version: 0,
            to: to,
            from: from,
            value: value,
            method: method,
            params: paramStr,
            nonce: res['Nonce'] ?? 0,
            gasFeeCap: (res['GasFeeCap'] ?? '0').toString(),
            gasPremium: (res['GasPremium'] ?? '0').toString(),
            gasLimit: res['GasLimit'] ?? 0);
      }
      throw Exception('build message fail');
    } catch (e) {
      throw (e);
    }
  }

  /// Multisig constructor params, encoded locally by Flotus (replaces the dead
  /// backend `/message/msig/construct`).
  Future<String> getSerializeParams(Map<String, dynamic> data) async {
    try {
      return await Flotus.genConstructorParamV3(jsonEncode(data));
    } catch (e) {
      print(e);
      rethrow;
    }
  }

  Future<String> getAddressType(String addr) async {
    // Probe-based classification (no code-cid table needed):
    // storage miner -> StateMinerInfo succeeds; multisig -> state has Signers.
    try {
      await _call('StateMinerInfo', [addr, _head]);
      return FilecoinAddressType.miner;
    } catch (_) {}
    try {
      var rs = await _call('StateReadState', [addr, _head]);
      if (rs is Map && rs['State'] is Map &&
          (rs['State'] as Map).containsKey('Signers')) {
        return FilecoinAddressType.multisig;
      }
    } catch (_) {}
    return FilecoinAddressType.account;
  }

  // ---------------------------------------------------------------------------
  // The methods below depend on the dead indexing backend or are pending a
  // dedicated on-chain migration pass. Kept as compile-safe stubs so callers
  // build; the corresponding UI entry points are being removed/redirected.
  // ---------------------------------------------------------------------------

  /// Transaction history list — removed (needs an indexer). Local cache only.
  Future<List<Map<String, dynamic>>> getMessageList(
      {@required String actor,
      String direction = 'down',
      String mid = '',
      int limit = 20}) async {
    return <Map<String, dynamic>>[];
  }

  /// Pending multisig proposals — TODO: source from MsigGetPending.
  Future<List<Map<String, dynamic>>> getMultiMessageList(
      {@required String actor,
      String direction = 'down',
      String mid = '',
      int limit = 20}) async {
    return <Map<String, dynamic>>[];
  }

  Future<CacheMultiMessage> getMultiMessageDetail(String cid) async {
    throw Exception('not supported');
  }

  Future<MinerMeta> getMinerMeta(String addr) async {
    throw Exception('not supported');
  }

  Future<MinerHistoricalStats> getMinerYesterdayInfo(String addr) async {
    throw Exception('not supported');
  }

  /// Miner related-address balances — TODO: source from StateMinerInfo.
  Future<List<MinerAddress>> getMinerRelatedAddressBalance(String actor) async {
    throw Exception('not supported');
  }

  /// Miner self balance — TODO: source from StateMinerAvailableBalance.
  Future<MinerSelfBalance> getMinerBalanceInfo(String address) async {
    throw Exception('not supported');
  }

  /// Multisig deposit history — removed (needs an indexer).
  Future<List<Map<String, dynamic>>> getMultiReceiveMessages(
      {@required String actor,
      String direction = 'down',
      String mid = '',
      int limit = 20}) async {
    return <Map<String, dynamic>>[];
  }

  /// owner -> active miners reverse lookup — removed (needs an indexer).
  /// Users enter the miner id manually instead.
  Future<List<String>> getActiveMiners(String actor) async {
    return <String>[];
  }
}

String getErrorMessage(String message) {
  if (message.contains('nonce')) {
    return 'wrongNonce'.tr;
  } else if (message.contains('cap')) {
    return 'lowFeeCap'.tr;
  } else if (message.contains('signature')) {
    return 'wrongSignature'.tr;
  } else if (message.contains('funds')) {
    return 'errorLowBalance'.tr;
  } else {
    return message;
  }
}
