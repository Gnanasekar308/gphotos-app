import 'package:flutter/material.dart';

import '../core/media_library.dart';
import '../selection/photo_grid.dart';

class PhotosPage extends StatefulWidget {
  const PhotosPage({super.key});
  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> {
  String f = 'All';
  static const filters = ['All', 'Camera', 'Screenshots', 'WhatsApp', 'Downloads'];

  bool _match(String path) {
    final p = path.toLowerCase();
    return switch (f) {
      'Camera' => p.contains('dcim/camera') || p.contains('/camera'),
      'Screenshots' => p.contains('screenshot'),
      'WhatsApp' => p.contains('whatsapp'),
      'Downloads' => p.contains('download'),
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final lib = MediaLibrary.instance;
    return ListenableBuilder(
      listenable: lib,
      builder: (_, __) {
        final list = lib.all.where((a) => _match(a.relativePath ?? '')).toList();
        return Column(children: [
          SizedBox(
            height: 52,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), children: [
              for (final n in filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(n), selected: f == n, onSelected: (_) => setState(() => f = n)),
                ),
            ]),
          ),
          Expanded(
            child: PhotoGrid(
              key: ValueKey(f),
              items: list,
              header: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Row(children: [
                  Text('${list.length} photos'),
                  if (lib.loading) ...[const SizedBox(width: 8), const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))],
                  const Spacer(),
                  Text('Long-press + slide to select', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
