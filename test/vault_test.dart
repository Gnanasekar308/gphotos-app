import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gphotos/vault/vault_crypto.dart';
import 'package:gphotos/vault/vault_store.dart';
import 'package:image/image.dart' as img;

class MemSecrets implements SecretStore {
  final m = <String, String>{};
  @override
  Future<void> delete(String k) async => m.remove(k);
  @override
  Future<String?> read(String k) async => m[k];
  @override
  Future<void> write(String k, String v) async => m[k] = v;
}

Uint8List jpeg() {
  final im = img.Image(width: 64, height: 48);
  img.fill(im, color: img.ColorRgb8(200, 30, 90));
  return Uint8List.fromList(img.encodeJpg(im));
}

void main() {
  group('VaultCrypto', () {
    test('round trip, several chunks', () async {
      final c = await VaultCrypto.fromKeyBytes(VaultCrypto.randomBytes(32));
      final data = VaultCrypto.randomBytes(10000);
      final enc = await c.encrypt(data, chunk: 1024);
      expect(enc.length, greaterThan(data.length));
      expect(await c.decrypt(enc), data);
    });

    test('empty input', () async {
      final c = await VaultCrypto.fromKeyBytes(VaultCrypto.randomBytes(32));
      expect(await c.decrypt(await c.encrypt(Uint8List(0))), isEmpty);
    });

    test('tampering, truncation and the wrong key are detected', () async {
      final c = await VaultCrypto.fromKeyBytes(VaultCrypto.randomBytes(32));
      final data = VaultCrypto.randomBytes(5000);
      final enc = await c.encrypt(data, chunk: 1000);
      final bad = Uint8List.fromList(enc)..[100] ^= 1;
      await expectLater(c.decrypt(bad), throwsA(isA<SecretBoxAuthenticationError>()));
      // drop the last data chunk + end marker -> truncated
      final cut = enc.sublist(0, enc.length - 40);
      await expectLater(c.decrypt(cut), throwsA(anything));
      final other = await VaultCrypto.fromKeyBytes(VaultCrypto.randomBytes(32));
      await expectLater(other.decrypt(enc), throwsA(isA<SecretBoxAuthenticationError>()));
    });

    test('ciphertext does not contain the plaintext', () async {
      final c = await VaultCrypto.fromKeyBytes(VaultCrypto.randomBytes(32));
      final j = jpeg();
      final enc = await c.encrypt(j);
      expect(enc.sublist(0, 4), [0x47, 0x50, 0x56, 0x31]);
      expect(enc.indexOf(0xD8) == 1 && enc[0] == 0xFF, isFalse);
    });
  });

  group('PinHasher', () {
    test('verifies the right PIN only, salted', () async {
      final h = await PinHasher.hash('2468', iterations: 2000);
      expect(h.startsWith('pbkdf2\$2000\$'), isTrue);
      expect(h.contains('2468'), isFalse);
      expect(await PinHasher.verify('2468', h), isTrue);
      expect(await PinHasher.verify('2469', h), isFalse);
      expect(await PinHasher.hash('2468', iterations: 2000) == h, isFalse, reason: 'random salt');
      expect(PinHasher.validPin('12'), isFalse);
      expect(PinHasher.validPin('1234'), isTrue);
      expect(PinHasher.validPin('12a4'), isFalse);
    });
  });

  group('VaultStore', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('vault_test'));
    tearDown(() async => dir.delete(recursive: true));

    test('add, read back, no plaintext on disk, index survives relock, remove', () async {
      final secrets = MemSecrets();
      final s = VaultStore(secrets, root: dir);
      await s.setPin('1234');
      expect(secrets.m.values.any((v) => v.contains('1234')), isFalse, reason: 'PIN is never stored in clear');
      expect(await s.checkPin('1234'), isTrue);
      await s.unlock();
      final j = jpeg();
      final it = await s.add(bytes: j, thumb: j, name: 'p.jpg', mime: 'image/jpeg', created: 1);
      expect(await s.read(it), j);
      expect(await s.thumb(it), j);
      expect(await s.containsPlaintextImages(), isFalse);
      s.lock();
      expect(() => s.read(it), throwsStateError);
      final s2 = VaultStore(secrets, root: dir);
      await s2.unlock();
      expect(s2.items.single.name, 'p.jpg');
      await s2.remove(s2.items.single);
      expect(s2.items, isEmpty);
      expect(File('${dir.path}/media/${it.id}.bin').existsSync(), isFalse);
    });

    test('wrong PINs count up and trigger a lockout', () async {
      final s = VaultStore(MemSecrets(), root: dir);
      await s.setPin('1234');
      for (var i = 0; i < 5; i++) {
        expect(await s.checkPin('0000'), isFalse);
      }
      expect(await s.failedAttempts(), 5);
      expect(VaultStore.lockoutSeconds(5), greaterThan(0));
      expect(VaultStore.lockoutSeconds(4), 0);
      expect(await s.checkPin('1234'), isTrue);
      expect(await s.failedAttempts(), 0);
    });
  });
}
