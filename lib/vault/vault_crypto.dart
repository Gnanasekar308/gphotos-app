import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Vault file format (all integers big-endian):
///   "GPV1" | u32 chunkSize | repeated chunks: u32 cipherLen | 12-byte nonce | cipher | 16-byte GCM tag
/// Each chunk is AES-256-GCM with a fresh random nonce and the chunk index as associated data, so
/// chunks cannot be reordered, truncated chunks fail, and large files never need one huge buffer.
class VaultCrypto {
  VaultCrypto(this._key);
  final SecretKey _key;

  static final _aes = AesGcm.with256bits();
  static const magic = [0x47, 0x50, 0x56, 0x31];
  static const chunkSize = 1 << 20;

  static Uint8List randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  static Future<VaultCrypto> fromKeyBytes(List<int> key) async {
    if (key.length != 32) throw ArgumentError('Vault key must be 32 bytes');
    return VaultCrypto(SecretKey(key));
  }

  Future<Uint8List> encrypt(Uint8List plain, {int chunk = chunkSize}) async {
    final out = BytesBuilder(copy: false)
      ..add(magic)
      ..add(_u32(chunk));
    var index = 0;
    for (var off = 0; off < plain.length; off += chunk) {
      final end = min(off + chunk, plain.length);
      final box = await _aes.encrypt(plain.sublist(off, end), secretKey: _key, nonce: _aes.newNonce(), aad: _u32(index++));
      out
        ..add(_u32(box.cipherText.length))
        ..add(box.nonce)
        ..add(box.cipherText)
        ..add(box.mac.bytes);
    }
    // end marker: an authenticated empty record bound to the chunk count, so truncation is detected
    final fin = await _aes.encrypt(const <int>[], secretKey: _key, nonce: _aes.newNonce(), aad: utf8.encode('end:$index'));
    out
      ..add(_u32(0))
      ..add(fin.nonce)
      ..add(fin.mac.bytes);
    return out.takeBytes();
  }

  /// Throws [SecretBoxAuthenticationError] / [FormatException] if the data was modified or truncated.
  Future<Uint8List> decrypt(Uint8List data) async {
    if (data.length < 8 || !_eq(data.sublist(0, 4), magic)) throw const FormatException('Not a vault file');
    var p = 8;
    var index = 0;
    final out = BytesBuilder(copy: false);
    while (true) {
      if (p + 4 + 12 + 16 > data.length) throw const FormatException('Truncated vault file');
      final len = _readU32(data, p);
      p += 4;
      final nonce = data.sublist(p, p + 12);
      p += 12;
      if (len == 0) {
        final mac = data.sublist(p, p + 16);
        p += 16;
        await _aes.decrypt(SecretBox(const <int>[], nonce: nonce, mac: Mac(mac)), secretKey: _key, aad: utf8.encode('end:$index'));
        if (p != data.length) throw const FormatException('Trailing data in vault file');
        return out.takeBytes();
      }
      if (p + len + 16 > data.length) throw const FormatException('Truncated vault file');
      final cipher = data.sublist(p, p + len);
      p += len;
      final mac = data.sublist(p, p + 16);
      p += 16;
      final plain = await _aes.decrypt(SecretBox(cipher, nonce: nonce, mac: Mac(mac)), secretKey: _key, aad: _u32(index++));
      out.add(plain);
    }
  }

  static Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);
  static int _readU32(Uint8List b, int o) => b.buffer.asByteData(b.offsetInBytes).getUint32(o);
  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// PIN hashing: PBKDF2-HMAC-SHA256 with a random 16-byte salt. Stored as "pbkdf2$iter$salt$hash"
/// (base64). Comparison is constant-time.
class PinHasher {
  static const defaultIterations = 120000;

  static Future<String> hash(String pin, {int iterations = defaultIterations, List<int>? salt}) async {
    final s = salt ?? VaultCrypto.randomBytes(16);
    final k = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256).deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: s);
    final h = await k.extractBytes();
    return 'pbkdf2\$$iterations\$${base64Encode(s)}\$${base64Encode(h)}';
  }

  static Future<bool> verify(String pin, String stored) async {
    final parts = stored.split('\$');
    if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
    final it = int.tryParse(parts[1]);
    if (it == null) return false;
    final again = await hash(pin, iterations: it, salt: base64Decode(parts[2]));
    final a = utf8.encode(again), b = utf8.encode(stored);
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static bool validPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);
}

Future<List<int>> sha256Of(List<int> data) async => (await Sha256().hash(data)).bytes;
