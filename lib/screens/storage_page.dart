import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/media_library.dart';
import '../selection/photo_grid.dart';

/// Scans the whole library (with progress, cancellable): exact duplicates (same size + same SHA-256),
/// large photos, screenshots.
class StoragePage extends StatefulWidget {
  const StoragePage({super.key});
  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  final sizes = <String, int>{};
  List<AssetEntity> dups = [], big = [], shots = [];
  int done = 0, total = 0;
  bool running = false, cancel = false, finished = false;

  Future<void> _scan() async {
    final all = List.of(MediaLibrary.instance.all);
    setState(() {
      running = true;
      cancel = false;
      done = 0;
      total = all.length;
    });
    final bySize = <String, List<AssetEntity>>{};
    final b = <AssetEntity>[], s = <AssetEntity>[];
    for (final a in all) {
      if (cancel || !mounted) break;
      final File? f = await a.originFile;
      final len = f == null ? 0 : await f.length();
      sizes[a.id] = len;
      if (len > 5 * 1024 * 1024) b.add(a);
      if ((a.relativePath ?? '').toLowerCase().contains('screenshot')) s.add(a);
      if (len > 0) (bySize['${a.width}x${a.height}:$len'] ??= []).add(a);
      done++;
      if (done % 50 == 0) setState(() {});
    }
    // confirm candidates by content hash
    final d = <AssetEntity>[];
    for (final g in bySize.values.where((g) => g.length > 1)) {
      if (cancel || !mounted) break;
      final byHash = <String, List<AssetEntity>>{};
      for (final a in g) {
        final f = await a.originFile;
        if (f == null) continue;
        final h = (await Sha256().hash(await f.readAsBytes())).bytes.join(',');
        (byHash[h] ??= []).add(a);
      }
      for (final same in byHash.values.where((x) => x.length > 1)) {
        d.addAll(same);
      }
    }
    if (!mounted) return;
    setState(() {
      dups = d;
      big = b..sort((x, y) => (sizes[y.id] ?? 0).compareTo(sizes[x.id] ?? 0));
      shots = s;
      running = false;
      finished = !cancel;
    });
  }

  String _mb(List<AssetEntity> l) => '${(l.fold<int>(0, (s, a) => s + (sizes[a.id] ?? 0)) / 1048576).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final groups = {'Exact duplicates': dups, 'Large photos (5 MB+)': big, 'Screenshots': shots};
    return Scaffold(
      appBar: AppBar(title: const Text('Storage & Cleanup')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: running
              ? Column(children: [
                  LinearProgressIndicator(value: total == 0 ? null : done / total),
                  const SizedBox(height: 8),
                  Text('Checked $done of $total photos'),
                  TextButton(onPressed: () => setState(() => cancel = true), child: const Text('Cancel')),
                ])
              : FilledButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.search),
                  label: Text(finished ? 'Scan again' : 'Scan all ${MediaLibrary.instance.all.length} photos'),
                ),
        ),
        if (finished)
          for (final e in groups.entries)
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text(e.key),
              subtitle: e.key.startsWith('Exact') ? const Text('Same size and identical content. Keep one of each.') : null,
              trailing: Text('${e.value.length} • ${_mb(e.value)}'),
              onTap: e.value.isEmpty
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(appBar: AppBar(title: Text(e.key)), body: PhotoGrid(items: List.of(e.value))),
                      )),
            ),
      ]),
    );
  }
}
