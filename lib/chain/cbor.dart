import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/digests/blake2b.dart';

/// Self-contained CBOR encoder for Filecoin actor message parameters.
///
/// Background: the wallet used to send JSON params to the (now dead) backend
/// `/message/build`, which CBOR-encoded them. The Flotus native plugin only
/// exposes the multisig-proposal variants. To stay a fully independent repo
/// (only dependency = the configured RPC node), we encode the params for
/// single-sig miner/market operations here, mirroring `go-state-types`.
///
/// Encodings are verified against go-state-types reference vectors, e.g.:
///   miner WithdrawBalanceParams{1 FIL}        = 81 49 00 0DE0B6B3A7640000
///   market WithdrawBalanceParams{f01000,1FIL} = 82 43 00E807 49 00 0DE0B6B3A7640000
///
/// The final message `Params` field expects base64 of these bytes.
class Cbor {
  // ---- CBOR major types ----
  static const int _majUnsignedInt = 0;
  static const int _majByteString = 2;
  static const int _majArray = 4;

  /// Encode a CBOR major-type header for [value] (length or unsigned int).
  static List<int> header(int major, int value) {
    final m = major << 5;
    if (value < 24) {
      return [m | value];
    } else if (value < 0x100) {
      return [m | 24, value];
    } else if (value < 0x10000) {
      return [m | 25, (value >> 8) & 0xff, value & 0xff];
    } else if (value < 0x100000000) {
      return [
        m | 26,
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff
      ];
    } else {
      return [
        m | 27,
        (value >> 56) & 0xff,
        (value >> 48) & 0xff,
        (value >> 40) & 0xff,
        (value >> 32) & 0xff,
        (value >> 24) & 0xff,
        (value >> 16) & 0xff,
        (value >> 8) & 0xff,
        value & 0xff
      ];
    }
  }

  static List<int> uint(int value) => header(_majUnsignedInt, value);

  static List<int> byteString(List<int> bytes) {
    return [...header(_majByteString, bytes.length), ...bytes];
  }

  static List<int> arrayHeader(int n) => header(_majArray, n);

  // ---- Filecoin primitives ----

  /// Unsigned LEB128 varint (used for ID-address payloads).
  static List<int> _uvarint(BigInt v) {
    if (v < BigInt.zero) {
      throw ArgumentError('uvarint requires non-negative value');
    }
    final out = <int>[];
    var n = v;
    final mask = BigInt.from(0x7f);
    final cont = BigInt.from(0x80);
    do {
      var b = (n & mask).toInt();
      n = n >> 7;
      if (n > BigInt.zero) b |= cont.toInt();
      out.add(b);
    } while (n > BigInt.zero);
    return out;
  }

  /// Filecoin base32 alphabet (RFC 4648 lowercase, no padding).
  static const String _b32Alphabet = 'abcdefghijklmnopqrstuvwxyz234567';

  static List<int> _base32Decode(String s) {
    var bits = 0;
    var value = 0;
    final out = <int>[];
    for (var i = 0; i < s.length; i++) {
      final idx = _b32Alphabet.indexOf(s[i]);
      if (idx < 0) {
        throw FormatException('invalid base32 char: ${s[i]}');
      }
      value = (value << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((value >> bits) & 0xff);
      }
    }
    return out;
  }

  /// Raw address bytes: protocol byte || payload (matches address.Bytes()).
  /// - protocol 0 (ID):   0x00 + uvarint(decimal id)
  /// - protocol 1/2/3:    proto + base32-decoded payload (checksum stripped)
  static List<int> addressBytes(String addr) {
    final a = addr.trim().toLowerCase();
    if (a.length < 3) {
      throw FormatException('invalid address: $addr');
    }
    final protocol = int.parse(a[1]);
    if (protocol == 0) {
      final id = BigInt.parse(a.substring(2));
      return [0x00, ..._uvarint(id)];
    }
    // protocol 1 (secp, 20B), 2 (actor, 20B), 3 (bls, 48B): base32 of
    // payload||checksum(4B). Strip the trailing 4 checksum bytes.
    final decoded = _base32Decode(a.substring(2));
    final payloadLen = protocol == 3 ? 48 : 20;
    final payload = decoded.sublist(0, payloadLen);
    return [protocol, ...payload];
  }

  /// CBOR-encode an address (byte string of its raw bytes).
  static List<int> address(String addr) => byteString(addressBytes(addr));

  /// Base32 encode with the Filecoin alphabet (no padding) — inverse of
  /// [_base32Decode].
  static String _base32Encode(List<int> bytes) {
    var bits = 0;
    var value = 0;
    final out = StringBuffer();
    for (final b in bytes) {
      value = (value << 8) | (b & 0xff);
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_b32Alphabet[(value >> bits) & 0x1f]);
      }
    }
    if (bits > 0) {
      out.write(_b32Alphabet[(value << (5 - bits)) & 0x1f]);
    }
    return out.toString();
  }

  /// Inverse of [addressBytes]: turn raw address bytes (protocol || payload)
  /// back into a string address for the given network prefix ('f' / 't').
  /// - protocol 0 (ID):  net + '0' + decimal(uvarint payload)
  /// - protocol 1/2/3:   net + proto + base32(payload || blake2b-4(checksum))
  static String addressFromBytes(List<int> bytes, String net) {
    if (bytes == null || bytes.isEmpty) return '';
    final protocol = bytes[0];
    final payload = bytes.sublist(1);
    if (protocol == 0) {
      // uvarint -> decimal id
      var result = BigInt.zero;
      var shift = 0;
      for (final b in payload) {
        result |= BigInt.from(b & 0x7f) << shift;
        if ((b & 0x80) == 0) break;
        shift += 7;
      }
      return '${net}0$result';
    }
    final digest = Blake2bDigest(digestSize: 4);
    final input = Uint8List.fromList([protocol, ...payload]);
    digest.update(input, 0, input.length);
    final checksum = Uint8List(4);
    digest.doFinal(checksum, 0);
    return '$net$protocol${_base32Encode([...payload, ...checksum])}';
  }

  /// Minimal big-endian magnitude bytes of a non-negative BigInt (empty for 0).
  static List<int> _bigEndianMagnitude(BigInt v) {
    if (v == BigInt.zero) return <int>[];
    final out = <int>[];
    var n = v;
    final mask = BigInt.from(0xff);
    while (n > BigInt.zero) {
      out.insert(0, (n & mask).toInt());
      n = n >> 8;
    }
    return out;
  }

  /// CBOR-encode a TokenAmount given as a decimal attoFIL string.
  /// Layout = byte string of [signByte] + big-endian magnitude; 0 => empty.
  static List<int> tokenAmount(String attoFil) {
    final v = BigInt.parse((attoFil == null || attoFil.isEmpty) ? '0' : attoFil);
    if (v == BigInt.zero) {
      return byteString(<int>[]);
    }
    final sign = v < BigInt.zero ? 1 : 0;
    final mag = _bigEndianMagnitude(v.abs());
    return byteString([sign, ...mag]);
  }

  // ---- helpers ----
  static String toHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static String toBase64(List<int> bytes) => base64.encode(Uint8List.fromList(bytes));

  // ---- minimal decoding (for displaying withdraw amounts on detail pages) ----

  /// Decode a CBOR byte string holding a Filecoin TokenAmount
  /// (sign byte + big-endian magnitude; empty => 0) into a decimal attoFIL
  /// string.
  static String decodeTokenAmount(List<int> bytes) {
    if (bytes == null || bytes.isEmpty) return '0';
    final negative = bytes[0] == 1;
    var v = BigInt.zero;
    for (var i = 1; i < bytes.length; i++) {
      v = (v << 8) | BigInt.from(bytes[i] & 0xff);
    }
    if (negative) v = -v;
    return v.toString();
  }

  /// Decode miner `WithdrawBalance` params `[AmountRequested]` (base64) into a
  /// decimal attoFIL string. Returns null if it can't be parsed.
  static String decodeMinerWithdrawAmount(String b64) {
    try {
      final r = _CborReader(base64.decode(b64));
      if (r.readArrayHeader() < 1) return null;
      return decodeTokenAmount(r.readByteString());
    } catch (_) {
      return null;
    }
  }

  /// Decode market `WithdrawBalance` params `[ProviderOrClient, Amount]`
  /// (base64) into a decimal attoFIL string. Returns null if unparseable.
  static String decodeMarketWithdrawAmount(String b64) {
    try {
      final r = _CborReader(base64.decode(b64));
      if (r.readArrayHeader() < 2) return null;
      r.readByteString(); // address — not needed for display
      return decodeTokenAmount(r.readByteString());
    } catch (_) {
      return null;
    }
  }

  /// Decode `ChangeOwnerAddress` params (a single bare address byte string,
  /// base64) into a string address. Returns null if unparseable.
  static String decodeChangeOwner(String b64, String net) {
    try {
      final r = _CborReader(base64.decode(b64));
      return addressFromBytes(r.readByteString(), net);
    } catch (_) {
      return null;
    }
  }

  /// Decode `ChangeWorkerAddress` params `[NewWorker, [ControlAddrs...]]`
  /// (base64) into {'NewWorker': addr, 'NewControlAddrs': [addr,...]}.
  /// Returns null if unparseable.
  static Map<String, dynamic> decodeChangeWorker(String b64, String net) {
    try {
      final r = _CborReader(base64.decode(b64));
      if (r.readArrayHeader() < 2) return null;
      final worker = addressFromBytes(r.readByteString(), net);
      final n = r.readArrayHeader();
      final controls = <String>[];
      for (var i = 0; i < n; i++) {
        controls.add(addressFromBytes(r.readByteString(), net));
      }
      return {'NewWorker': worker, 'NewControlAddrs': controls};
    } catch (_) {
      return null;
    }
  }
}

/// Tiny sequential CBOR reader — only what the withdraw-amount decoders above
/// need (definite-length arrays and byte strings). NOT a general decoder.
class _CborReader {
  final List<int> _b;
  int _i = 0;
  _CborReader(this._b);

  int _readByte() => _b[_i++];

  /// Returns [major, argument].
  List<int> _readHeader() {
    final h = _readByte();
    final major = h >> 5;
    final low = h & 0x1f;
    int arg;
    if (low < 24) {
      arg = low;
    } else if (low == 24) {
      arg = _readByte();
    } else if (low == 25) {
      arg = (_readByte() << 8) | _readByte();
    } else if (low == 26) {
      arg = (_readByte() << 24) |
          (_readByte() << 16) |
          (_readByte() << 8) |
          _readByte();
    } else {
      throw FormatException('unsupported cbor header arg: $low');
    }
    return [major, arg];
  }

  int readArrayHeader() {
    final h = _readHeader();
    if (h[0] != 4) throw FormatException('expected cbor array');
    return h[1];
  }

  List<int> readByteString() {
    final h = _readHeader();
    if (h[0] != 2) throw FormatException('expected cbor byte string');
    final len = h[1];
    final out = _b.sublist(_i, _i + len);
    _i += len;
    return out;
  }
}

/// Builders for the specific actor method params the app needs to send
/// directly (single-sig). Each returns base64 of the CBOR params, ready to
/// drop into a message's `Params` field.
class FilParams {
  /// Miner Actor `WithdrawBalance` (method 16): [AmountRequested]
  static String minerWithdraw(String amountAtto) {
    final bytes = [
      ...Cbor.arrayHeader(1),
      ...Cbor.tokenAmount(amountAtto),
    ];
    return Cbor.toBase64(bytes);
  }

  /// Storage Market Actor `WithdrawBalance` (method 3 on f05):
  /// [ProviderOrClientAddress, Amount]
  static String marketWithdraw(String providerAddr, String amountAtto) {
    final bytes = [
      ...Cbor.arrayHeader(2),
      ...Cbor.address(providerAddr),
      ...Cbor.tokenAmount(amountAtto),
    ];
    return Cbor.toBase64(bytes);
  }

  /// Miner Actor `ChangeOwnerAddress` (method 23): a single address param.
  static String changeOwner(String newOwner) {
    return Cbor.toBase64(Cbor.address(newOwner));
  }

  /// Storage Power Actor `CreateMiner` (method 2 on f04):
  /// [Owner, Worker, WindowPoStProofType, Peer, [Multiaddrs...]]
  static String createMiner(String owner, String worker, int postProofType,
      {List<int> peer, List<List<int>> multiaddrs}) {
    final p = peer ?? <int>[];
    final ma = multiaddrs ?? <List<int>>[];
    final bytes = <int>[
      ...Cbor.arrayHeader(5),
      ...Cbor.address(owner),
      ...Cbor.address(worker),
      ...Cbor.uint(postProofType),
      ...Cbor.byteString(p),
      ...Cbor.arrayHeader(ma.length),
    ];
    for (final m in ma) {
      bytes.addAll(Cbor.byteString(m));
    }
    return Cbor.toBase64(bytes);
  }

  /// Miner Actor `ChangeWorkerAddress` (method 3):
  /// [NewWorker, [ControlAddresses...]]
  static String changeWorker(String newWorker, List<String> controlAddrs) {
    final ctrl = controlAddrs ?? <String>[];
    final bytes = <int>[
      ...Cbor.arrayHeader(2),
      ...Cbor.address(newWorker),
      ...Cbor.arrayHeader(ctrl.length),
    ];
    for (final c in ctrl) {
      bytes.addAll(Cbor.address(c));
    }
    return Cbor.toBase64(bytes);
  }
}
