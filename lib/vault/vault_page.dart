import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/file_ops.dart';
import '../core/media_library.dart';
import 'vault_crypto.dart';
import 'vault_store.dart';

/// Unlocking: PIN (PBKDF2-hashed, lockout after 5 wrong tries) or biometrics when the user turned it on.
/// The vault locks again when the app goes to the background.
class VaultGate {
  static final store = VaultStore(KeystoreSecretStore());
  static AppLifecycleListener? _life;

  static void _watch() {
    _life ??= AppLifecycleListener(onHide: () {
      store.lock();
      SecureWindow.set(false);
    });
  }

  /// Returns the unlocked store, or null if the user cancelled.
  static Future<VaultStore?> unlockFlow(BuildContext context) async {
    _watch();
    if (store.unlocked) return store;
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const _UnlockPage()));
    return ok == true ? store : null;
  }
}

class _UnlockPage extends StatefulWidget {
  const _UnlockPage();
  @override
  State<_UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<_UnlockPage> {
  final s = VaultGate.store;
  final tc = TextEditingController();
  bool? hasPin;
  String? firstPin; // during setup
  bool bio = false, bioAvailable = false, busy = false;
  String msg = '';
  Timer? _tick;
  int wait = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final has = await s.hasPin();
    final auth = LocalAuthentication();
    var avail = false;
    try {
      avail = await auth.canCheckBiometrics && await auth.isDeviceSupported();
    } catch (_) {}
    final on = await s.biometricsEnabled();
    await _updateWait();
    if (!mounted) return;
    setState(() {
      hasPin = has;
      bioAvailable = avail;
      bio = on && avail;
    });
    if (has && bio) _biometric();
  }

  Future<void> _updateWait() async {
    final fails = await s.failedAttempts();
    final lock = VaultStore.lockoutSeconds(fails);
    _tick?.cancel();
    if (lock == 0) {
      wait = 0;
      return;
    }
    wait = lock;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => wait--);
      if (wait <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    tc.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    await s.unlock();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _biometric() async {
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Unlock the Private Vault',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (ok) await _open();
    } on PlatformException catch (e) {
      if (mounted) setState(() => msg = 'Biometrics unavailable: ${e.message ?? e.code}');
    }
  }

  Future<void> _submit() async {
    final pin = tc.text;
    tc.clear();
    if (!PinHasher.validPin(pin)) {
      setState(() => msg = 'Use 4 to 8 digits');
      return;
    }
    setState(() => busy = true);
    try {
      if (hasPin == false) {
        if (firstPin == null) {
          setState(() {
            firstPin = pin;
            msg = 'Enter the same PIN again';
          });
          return;
        }
        if (firstPin != pin) {
          setState(() {
            firstPin = null;
            msg = 'PINs did not match, start again';
          });
          return;
        }
        await s.setPin(pin);
        if (bioAvailable && mounted) {
          final use = await confirm(context,
              title: 'Use biometrics?', message: 'Unlock the vault with your fingerprint or face as well as the PIN.', action: 'Use', destructive: false);
          await s.setBiometricsEnabled(use);
        }
        await _open();
        return;
      }
      if (wait > 0) return;
      if (await s.checkPin(pin)) {
        await _open();
      } else {
        HapticFeedback.heavyImpact();
        final fails = await s.failedAttempts();
        await _updateWait();
        setState(() => msg = 'Wrong PIN ($fails failed)');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = hasPin == false;
    return Scaffold(
      appBar: AppBar(title: const Text('Private Vault')),
      body: hasPin == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock, size: 64),
                  const SizedBox(height: 12),
                  Text(setup ? (firstPin == null ? 'Create a PIN (4-8 digits)' : 'Confirm your PIN') : 'Enter your PIN',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: tc,
                      autofocus: true,
                      obscureText: true,
                      enabled: wait <= 0 && !busy,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24, letterSpacing: 8),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: wait > 0 || busy ? null : _submit, child: Text(setup ? 'Next' : 'Unlock')),
                  if (wait > 0) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Too many wrong PINs. Try again in $wait s')),
                  if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(msg)),
                  if (!setup && bio) IconButton(iconSize: 52, tooltip: 'Use biometrics', icon: const Icon(Icons.fingerprint), onPressed: _biometric),
                  const SizedBox(height: 16),
                  if (setup)
                    const Text('The PIN cannot be recovered. Without it the vault cannot be opened.', textAlign: TextAlign.center),
                ]),
              ),
            ),
    );
  }
}

/// The vault contents (opened only through [VaultGate]).
class VaultPage extends StatefulWidget {
  const VaultPage({super.key});
  static Future<void> open(BuildContext c) async {
    final s = await VaultGate.unlockFlow(c);
    if (s != null && c.mounted) await Navigator.push(c, MaterialPageRoute(builder: (_) => const VaultPage()));
  }

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  final s = VaultGate.store;
  final _thumbs = <String, Future<Uint8List?>>{};

  @override
  void initState() {
    super.initState();
    SecureWindow.set(true);
  }

  @override
  void dispose() {
    SecureWindow.set(false);
    s.lock();
    super.dispose();
  }

  Future<void> _restore(VaultItem it) async {
    final ok = await confirm(context,
        title: 'Restore to gallery?', message: '"${it.name}" is decrypted and saved back to the gallery, then removed from the vault.', action: 'Restore', destructive: false);
    if (!ok) return;
    try {
      final bytes = await s.read(it);
      final saved = await PhotoManager.editor.saveImage(bytes, filename: it.name, title: it.name);
      if (saved.id.isEmpty) throw StateError('save failed');
      await s.remove(it);
      MediaLibrary.instance.reload();
      if (mounted) snack(context, 'Restored to the gallery');
    } catch (e) {
      if (mounted) snack(context, 'Restore failed, the vault copy was kept ($e)');
    }
    if (mounted) setState(() {});
  }

  Future<void> _delete(VaultItem it) async {
    final ok = await confirm(context, title: 'Delete forever?', message: '"${it.name}" is permanently deleted from the vault. It cannot be recovered.', action: 'Delete');
    if (!ok) return;
    await s.remove(it);
    if (mounted) setState(() {});
  }

  void _view(VaultItem it) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(it.name)),
          body: FutureBuilder<Uint8List>(
            future: s.read(it),
            builder: (_, f) => f.hasError
                ? Center(child: Text('Cannot decrypt: ${f.error}', style: const TextStyle(color: Colors.white)))
                : f.data == null
                    ? const Center(child: CircularProgressIndicator())
                    : InteractiveViewer(maxScale: 8, child: Center(child: Image.memory(f.data!))),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!s.unlocked) {
      return const Scaffold(body: Center(child: Text('Vault locked')));
    }
    final items = s.items.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: Text('Private Vault (${items.length})'), actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'pin') {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const _ChangePinPage()));
            }
          },
          itemBuilder: (_) => const [PopupMenuItem(value: 'pin', child: Text('Change PIN / biometrics'))],
        ),
      ]),
      body: items.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('The vault is empty. Select photos in the gallery and tap the lock icon.', textAlign: TextAlign.center)))
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final it = items[i];
                return GestureDetector(
                  onTap: () => _view(it),
                  onLongPress: () => showModalBottomSheet(
                    context: context,
                    builder: (sc) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        ListTile(leading: const Icon(Icons.restore), title: const Text('Restore to gallery'), onTap: () {
                          Navigator.pop(sc);
                          _restore(it);
                        }),
                        ListTile(leading: const Icon(Icons.delete_forever), title: const Text('Delete forever'), onTap: () {
                          Navigator.pop(sc);
                          _delete(it);
                        }),
                      ]),
                    ),
                  ),
                  child: FutureBuilder<Uint8List?>(
                    future: _thumbs[it.id] ??= s.thumb(it),
                    builder: (_, f) => f.data == null ? const ColoredBox(color: Colors.black26, child: Icon(Icons.lock)) : Image.memory(f.data!, fit: BoxFit.cover),
                  ),
                );
              },
            ),
    );
  }
}

class _ChangePinPage extends StatefulWidget {
  const _ChangePinPage();
  @override
  State<_ChangePinPage> createState() => _ChangePinPageState();
}

class _ChangePinPageState extends State<_ChangePinPage> {
  final oldC = TextEditingController(), newC = TextEditingController();
  bool bio = false;
  String msg = '';

  @override
  void initState() {
    super.initState();
    VaultGate.store.biometricsEnabled().then((v) => mounted ? setState(() => bio = v) : null);
  }

  @override
  Widget build(BuildContext context) {
    final s = VaultGate.store;
    return Scaffold(
      appBar: AppBar(title: const Text('Vault security')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: oldC, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Current PIN')),
        TextField(controller: newC, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'New PIN (4-8 digits)')),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            if (!await s.checkPin(oldC.text)) {
              setState(() => msg = 'Current PIN is wrong');
              return;
            }
            if (!PinHasher.validPin(newC.text)) {
              setState(() => msg = 'New PIN must be 4-8 digits');
              return;
            }
            await s.setPin(newC.text);
            setState(() => msg = 'PIN changed');
          },
          child: const Text('Change PIN'),
        ),
        if (msg.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(msg)),
        SwitchListTile(
          title: const Text('Unlock with biometrics'),
          value: bio,
          onChanged: (v) async {
            await s.setBiometricsEnabled(v);
            setState(() => bio = v);
          },
        ),
      ]),
    );
  }
}
