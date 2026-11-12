import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/media_library.dart';
import '../selection/photo_grid.dart';
import '../widgets/thumb.dart';

class AlbumsPage extends StatelessWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = MediaLibrary.instance;
    return ListenableBuilder(
      listenable: lib,
      builder: (_, __) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 12, crossAxisSpacing: 12),
        itemCount: lib.albums.length,
        itemBuilder: (_, i) {
          final p = lib.albums[i];
          return GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumPage(path: p))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(fit: StackFit.expand, children: [
                FutureBuilder<List<AssetEntity>>(
                  future: p.getAssetListRange(start: 0, end: 1),
                  builder: (_, f) => (f.data == null || f.data!.isEmpty) ? const ColoredBox(color: Colors.black26) : Thumb(f.data!.first, size: 400),
                ),
                const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]))),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 8,
                  child: FutureBuilder<int>(
                    future: p.assetCountAsync,
                    builder: (_, c) => Text('${p.name}\n${c.data ?? ''}',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.path});
  final AssetPathEntity path;
  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  final items = <AssetEntity>[];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final total = await widget.path.assetCountAsync;
    for (var s = 0; s < total; s += 500) {
      final page = await widget.path.getAssetListRange(start: s, end: s + 500);
      if (!mounted) return;
      if (page.isEmpty) break;
      setState(() => items.addAll(page));
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.path.name), bottom: loading ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator()) : null),
        body: PhotoGrid(items: items, onChanged: () => setState(() {})),
      );
}
