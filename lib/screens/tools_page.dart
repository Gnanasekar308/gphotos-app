import 'package:flutter/material.dart';

import '../vault/vault_page.dart';
import 'settings_page.dart';
import 'slideshow_page.dart';
import 'storage_page.dart';

/// Tools. Features that need a trained AI model (background removal, AI upscaling, colourisation,
/// object erasing) are listed honestly as not available instead of being faked.
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    void push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final small = Theme.of(context).textTheme.bodySmall;
    return ListView(padding: const EdgeInsets.all(8), children: [
      _t('Private Vault', 'AES-256 encrypted, PIN / biometrics', Icons.lock, () => VaultPage.open(context)),
      _t('Storage & Cleanup', 'Exact duplicates, large photos, screenshots', Icons.cleaning_services, () => push(const StoragePage())),
      _t('Slideshow', 'Recent photos', Icons.slideshow, () => push(const SlideshowPage())),
      _t('Photo editor', 'Open a photo, then tap Edit: crop, rotate, flip, resize, adjust, filters, auto enhance', Icons.edit, null),
      _t('Settings', 'Theme, colours, grid, navigation, gestures', Icons.settings, () => push(const SettingsPage())),
      const Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text('Not available in this version', style: TextStyle(fontWeight: FontWeight.w600))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'AI background removal, AI upscaling, AI colourisation and object eraser need trained models that are '
          'not included. They are not shown as working buttons. "Auto enhance" in the editor is a classic levels '
          'adjustment, not AI.',
          style: small,
        ),
      ),
      for (final n in ['AI background removal', 'AI upscale', 'AI colourise', 'Object eraser'])
        ListTile(dense: true, leading: const Icon(Icons.block), title: Text(n), subtitle: const Text('Not supported'), enabled: false),
    ]);
  }

  Widget _t(String t, String s, IconData i, VoidCallback? f) => Card(child: ListTile(leading: Icon(i), title: Text(t), subtitle: Text(s), onTap: f));
}
