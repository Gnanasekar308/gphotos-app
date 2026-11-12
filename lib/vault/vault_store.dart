import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'vault_crypto.dart';

/// Small key-value secret store (Android Keystore-backed in the app, in-memory in tests).
abstract class SecretStore {
  Future<String?> read(String k);
  Future<void> write(String k, String v);
  Future<void> delete(String k);
}

class KeystoreSecretStore implements SecretStore {
  // encryptedSharedPreferences: values are encrypted with a key held by the Android Keystore
  static const _s = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  @override
  Future<String?> read(String k) => _s.read(key: k);
  @override
  Future<void> write(String k, String v) => _s.write(key: k, value: v);
  @override
  Future<void> delete(String k) => _s.delete(key: k);
}

class VaultItem {
  VaultItem({required this.id, required this.name, required this.mime, required this.created, required this.size, required this.width, required this.height});
  final String id;
  final String name;
  final String mime;
  final int created;
  final int size;
  final int width, height;

  Map<String, Object> toJson() => {'id': id, 'name': name, 'mime': mime, 'created': created, 'size': size, 'w': width, 'h': height};
  static VaultItem fromJson(Map m) => VaultItem(
      id: m['id'] as String,
      name: m['name'] as String,
      mime: m['mime'] as String,
      created: m['created'] as int,
      size: m['size'] as int,
      width: (m['w'] ?? 0) as int,
      height: (m['h'] ?? 0) as int);
}

/// Encrypted vault in the app's private storage. Media, thumbnails and the index are all encrypted;
/// no plaintext copy of a private photo is ever written to disk by the vault.
class VaultStore {
  VaultStore(this.secrets, {Directory? root}) : _rootOverride = root;
  final SecretStore secrets;
  final Directory? _rootOverride;

  static const _kKey = 'vault_key_v1';
  static const _kPin = 'vault_pin_v1';
  static const _kFails = 'vault_fails_v1';
  static const _kBio = 'vault_bio_v1';

  VaultCrypto? _crypto;
  List<VaultItem> items = [];

  bool get unlocked => _crypto != null;

  Future<Directory> _dir([String sub = '']) async {
    final base = _rootOverride ?? Directory('${(await getApplicationSupportDirectory()).path}/vault');
    final d = Directory(sub.isEmpty ? base.path : '${base.path}/$sub');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<bool> hasPin() async => (await secrets.read(_kPin)) != null;
  Future<bool> biometricsEnabled() async => (await secrets.read(_kBio)) == '1';
  Future<void> setBiometricsEnabled(bool on) => on ? secrets.write(_kBio, '1') : secrets.delete(_kBio);

  Future<int> failedAttempts() async => int.tryParse(await secrets.read(_kFails) ?? '') ?? 0;

  /// Seconds the user must wait after repeated wrong PINs (0 = may try now).
  static int lockoutSeconds(int fails) => fails < 5 ? 0 : 30 * (1 << (fails - 5).clamp(0, 6));

  Future<void> setPin(String pin) async {
    if (!PinHasher.validPin(pin)) throw ArgumentError('PIN must be 4-8 digits');
    await secrets.write(_kPin, await PinHasher.hash(pin));
    await secrets.write(_kFails, '0');
  }

  Future<bool> checkPin(String pin) async {
    final stored = await secrets.read(_kPin);
    if (stored == null) return false;
    final ok = await PinHasher.verify(pin, stored);
    await secrets.write(_kFails, ok ? '0' : '${await failedAttempts() + 1}');
    return ok;
  }

  /// Loads (or on first use creates) the 256-bit vault key and decrypts the index.
  Future<void> unlock() async {
    var k = await secrets.read(_kKey);
    if (k == null) {
      k = base64Encode(VaultCrypto.randomBytes(32));
      await secrets.write(_kKey, k);
    }
    _crypto = await VaultCrypto.fromKeyBytes(base64Decode(k));
    items = await _readIndex();
  }

  void lock() {
    _crypto = null;
    items = [];
  }

  VaultCrypto get _c {
    final c = _crypto;
    if (c == null) throw StateError('Vault is locked');
    return c;
  }

  Future<List<VaultItem>> _readIndex() async {
    final f = File('${(await _dir()).path}/index.bin');
    if (!await f.exists()) return [];
    final plain = await _c.decrypt(await f.readAsBytes());
    return (jsonDecode(utf8.decode(plain)) as List).map((e) => VaultItem.fromJson(e as Map)).toList();
  }

  Future<void> _writeIndex() async {
    final d = await _dir();
    final enc = await _c.encrypt(Uint8List.fromList(utf8.encode(jsonEncode(items.map((e) => e.toJson()).toList()))));
    await _atomicWrite(File('${d.path}/index.bin'), enc);
  }

  static Future<void> _atomicWrite(File f, Uint8List bytes) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
  }

  /// Encrypts [bytes] into the vault and verifies the stored file decrypts back to the same SHA-256
  /// before it is added to the index. Returns the new item (the caller may then delete the original).
  Future<VaultItem> add({required Uint8List bytes, required Uint8List? thumb, required String name, required String mime, required int created, int width = 0, int height = 0}) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}_${base64Url.encode(VaultCrypto.randomBytes(6))}';
    final media = File('${(await _dir('media')).path}/$id.bin');
    final enc = await _c.encrypt(bytes);
    await _atomicWrite(media, enc);
    final check = await _c.decrypt(await media.readAsBytes());
    final same = _listEq(await sha256Of(check), await sha256Of(bytes));
    if (!same) {
      await media.delete();
      throw StateError('Verification failed for $name');
    }
    if (thumb != null) await _atomicWrite(File('${(await _dir('thumbs')).path}/$id.bin'), await _c.encrypt(thumb));
    final item = VaultItem(id: id, name: name, mime: mime, created: created, size: bytes.length, width: width, height: height);
    items.add(item);
    await _writeIndex();
    return item;
  }

  Future<Uint8List> read(VaultItem it) async => _c.decrypt(await File('${(await _dir('media')).path}/${it.id}.bin').readAsBytes());

  Future<Uint8List?> thumb(VaultItem it) async {
    final f = File('${(await _dir('thumbs')).path}/${it.id}.bin');
    if (!await f.exists()) return null;
    return _c.decrypt(await f.readAsBytes());
  }

  Future<void> remove(VaultItem it) async {
    items.removeWhere((e) => e.id == it.id);
    await _writeIndex();
    for (final sub in ['media', 'thumbs']) {
      final f = File('${(await _dir(sub)).path}/${it.id}.bin');
      if (await f.exists()) await f.delete();
    }
  }

  /// Plain-text check used by tests: no file in the vault starts with a JPEG / PNG signature.
  Future<bool> containsPlaintextImages() async {
    final d = await _dir();
    await for (final e in d.list(recursive: true)) {
      if (e is! File) continue;
      final raf = await e.open();
      final head = await raf.read(8);
      await raf.close();
      if (head.length >= 3 && head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF) return true;
      if (head.length >= 4 && head[0] == 0x89 && head[1] == 0x50 && head[2] == 0x4E && head[3] == 0x47) return true;
    }
    return false;
  }

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Hides the app content in Recents / screenshots while the vault is open (FLAG_SECURE).
class SecureWindow {
  static const _ch = MethodChannel('gphotos/region');
  static Future<void> set(bool on) async {
    try {
      await _ch.invokeMethod('secure', {'on': on});
    } catch (_) {}
  }
}
