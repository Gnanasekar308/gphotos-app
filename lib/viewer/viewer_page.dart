import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/app_settings.dart';
import '../core/file_ops.dart';
import '../editor/editor_page.dart';
import '../vault/vault_import.dart';
import 'tiled_image.dart';

class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key, required this.items, required this.start});
  final List<AssetEntity> items;
  final int start;

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  late final pc = PageController(initialPage: widget.start);
  late int i = widget.start;
  bool zoomed = false;
  bool chrome = true;
  final _paths = <String, Future<File?>>{};

  Future<File?> _file(AssetEntity a) => _paths[a.id] ??= a.originFile;

  AssetEntity get cur => widget.items[i];

  void _removeCurrent(List<String> ids) {
    if (ids.isEmpty) return;
    widget.items.removeWhere((a) => ids.contains(a.id));
    if (widget.items.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => i = i.clamp(0, widget.items.length - 1));
  }

  Future<void> _info() async {
    final a = cur;
    final f = await _file(a);
    final len = f == null ? 0 : await f.length();
    final ll = await a.latlngAsync();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
        ListTile(title: const Text('Name'), subtitle: Text(a.title ?? '-')),
        ListTile(title: const Text('Date'), subtitle: Text(a.createDateTime.toString())),
        ListTile(title: const Text('Size'), subtitle: Text('${a.width} x ${a.height} px  •  ${(len / 1048576).toStringAsFixed(2)} MB')),
        ListTile(title: const Text('Path'), subtitle: Text(f?.path ?? a.relativePath ?? '-')),
        if (ll != null && (ll.latitude != 0 || ll.longitude != 0))
          ListTile(title: const Text('Location'), subtitle: Text('${ll.latitude}, ${ll.longitude}')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final items = widget.items;
    Widget pages = PageView.builder(
      controller: pc,
      physics: zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
      itemCount: items.length,
      onPageChanged: (n) => setState(() {
        i = n;
        zoomed = false;
      }),
      itemBuilder: (_, n) => FutureBuilder<File?>(
        future: _file(items[n]),
        builder: (_, f) {
          if (f.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (f.data == null) return const Center(child: Text('Cannot open this photo', style: TextStyle(color: Colors.white)));
          return GestureDetector(
            onTap: () => setState(() => chrome = !chrome),
            child: TiledImage(
              key: ValueKey(items[n].id),
              path: f.data!.path,
              onZoomChanged: (z) {
                if (n == i && z != zoomed) setState(() => zoomed = z);
              },
            ),
          );
        },
      ),
    );
    if (s.swipeDownToClose && !zoomed) {
      pages = GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 700) Navigator.pop(context);
        },
        child: pages,
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: chrome
          ? AppBar(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              title: Text('${i + 1} / ${items.length}'),
              actions: [IconButton(tooltip: 'Info', icon: const Icon(Icons.info_outline), onPressed: _info)],
            )
          : null,
      body: pages,
      bottomNavigationBar: chrome
          ? BottomAppBar(
              color: Colors.black54,
              child: IconTheme(
                data: const IconThemeData(color: Colors.white),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  IconButton(tooltip: 'Share', icon: const Icon(Icons.share), onPressed: () => sharePhotos([cur])),
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditorPage(asset: cur))),
                  ),
                  IconButton(
                    tooltip: 'Move to vault',
                    icon: const Icon(Icons.lock_outline),
                    onPressed: () async => _removeCurrent(await moveToVault(context, [cur])),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async => _removeCurrent(await deletePhotos(context, [cur])),
                  ),
                ]),
              ),
            )
          : null,
    );
  }
}
