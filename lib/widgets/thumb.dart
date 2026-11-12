import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// Small LRU cache of encoded thumbnail bytes so scrolling back does not hit the platform again.
/// Bounded by byte size to keep memory flat on large libraries.
class ThumbCache {
  ThumbCache._();
  static final instance = ThumbCache._();
  static const maxBytes = 40 * 1024 * 1024;

  final _map = LinkedHashMap<String, Uint8List>();
  final _pending = <String, Future<Uint8List?>>{};
  int _bytes = 0;

  Future<Uint8List?> get(AssetEntity a, int size) {
    final key = '${a.id}@$size@${a.modifiedDateSecond}';
    final hit = _map.remove(key);
    if (hit != null) {
      _map[key] = hit;
      return Future.value(hit);
    }
    return _pending[key] ??= a.thumbnailDataWithSize(ThumbnailSize.square(size), quality: 80).then((b) {
      _pending.remove(key);
      if (b != null) {
        _map[key] = b;
        _bytes += b.length;
        while (_bytes > maxBytes && _map.isNotEmpty) {
          final first = _map.keys.first;
          _bytes -= _map.remove(first)!.length;
        }
      }
      return b;
    });
  }

  void clear() {
    _map.clear();
    _bytes = 0;
  }
}

class PhotoThumb extends StatefulWidget {
  const PhotoThumb(this.asset, {super.key, this.size = 256, this.fit = BoxFit.cover});
  final AssetEntity asset;
  final int size;
  final BoxFit fit;

  @override
  State<PhotoThumb> createState() => _ThumbState();
}

class _ThumbState extends State<PhotoThumb> {
  late Future<Uint8List?> _f;

  @override
  void initState() {
    super.initState();
    _f = ThumbCache.instance.get(widget.asset, widget.size);
  }

  @override
  void didUpdateWidget(PhotoThumb old) {
    super.didUpdateWidget(old);
    if (old.asset.id != widget.asset.id || old.size != widget.size) {
      _f = ThumbCache.instance.get(widget.asset, widget.size);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surfaceContainerHighest;
    return FutureBuilder<Uint8List?>(
      future: _f,
      builder: (_, s) => s.data == null
          ? ColoredBox(color: bg)
          : Image.memory(s.data!, fit: widget.fit, gaplessPlayback: true, cacheWidth: widget.size, filterQuality: FilterQuality.medium),
    );
  }
}
