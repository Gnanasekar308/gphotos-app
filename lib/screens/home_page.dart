import 'package:flutter/material.dart';

import '../core/media_library.dart';
import '../faces/face_store.dart';
import '../vault/vault_page.dart';
import '../widgets/thumb.dart';
import 'settings_page.dart';
import 'slideshow_page.dart';
import 'storage_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.go});
  final void Function(int) go;

  @override
  Widget build(BuildContext context) {
    void push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final lib = MediaLibrary.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([lib, FaceStore.instance]),
      builder: (_, __) => ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset('assets/icon/gphotos_icon.png', width: 36, height: 36, errorBuilder: (_, __, ___) => const Icon(Icons.photo)),
          ),
          const SizedBox(width: 10),
          const Text('Gphotos', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings), onPressed: () => push(const SettingsPage())),
        ]),
        const SizedBox(height: 12),
        if (lib.all.isNotEmpty)
          GestureDetector(
            onTap: () => push(const SlideshowPage()),
            child: SizedBox(
              height: 170,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(fit: StackFit.expand, children: [
                  PhotoThumb(lib.all.first, size: 720),
                  const ColoredBox(color: Colors.black38),
                  const Center(child: Icon(Icons.play_circle, size: 56, color: Colors.white)),
                  const Positioned(left: 12, bottom: 10, child: Text('Slideshow of recent photos', style: TextStyle(color: Colors.white))),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 8),
        _tile(context, 'Photos', lib.complete ? '${lib.all.length}' : 'Loading ${lib.all.length} / ${lib.total}', Icons.photo, () => go(1)),
        _tile(context, 'Albums', '${lib.albums.length}', Icons.folder, () => go(2)),
        _tile(context, 'People', '${FaceStore.instance.sortedPeople().length} people', Icons.face, () => go(3)),
        _tile(context, 'Private Vault', 'Encrypted, PIN / biometrics', Icons.lock, () => VaultPage.open(context)),
        _tile(context, 'Storage & Cleanup', 'Possible duplicates, large files, screenshots', Icons.cleaning_services, () => push(const StoragePage())),
      ]),
    );
  }

  Widget _tile(BuildContext c, String t, String sub, IconData ic, VoidCallback f) =>
      Card(child: ListTile(leading: Icon(ic), title: Text(t), subtitle: Text(sub), trailing: const Icon(Icons.chevron_right), onTap: f));
}
