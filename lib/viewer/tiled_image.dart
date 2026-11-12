import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'region_decoder.dart';

/// High-resolution zoomable image: a screen-sized preview is shown first; when zoomed in, full-detail
/// tiles for the visible region are decoded natively (BitmapRegionDecoder) at the sample size the zoom
/// needs, so every region of a large photo can be viewed at full resolution without decoding the
/// whole bitmap into memory.
class TiledImage extends StatefulWidget {
  const TiledImage({super.key, required this.path, required this.onZoomChanged, this.maxScale = 12});
  final String path;
  final ValueChanged<bool> onZoomChanged;
  final double maxScale;

  @override
  State<TiledImage> createState() => _TiledImageState();
}

class _Tile {
  _Tile(this.rect, this.sample, this.bytes);
  final Rect rect;
  final int sample;
  final Uint8List bytes;
}

class _TiledImageState extends State<TiledImage> {
  final tc = TransformationController();
  ImageInfoSize? _size;
  bool _nativeFailed = false;
  Size _viewport = Size.zero;
  Timer? _debounce;
  bool _zoomed = false;
  int _gen = 0;

  static const _maxTiles = 40;
  final _tiles = LinkedHashMap<String, _Tile>();
  final _loading = <String>{};
  int _sample = 0;

  @override
  void initState() {
    super.initState();
    tc.addListener(_onTransform);
    RegionDecoder.info(widget.path).then((s) {
      if (!mounted) return;
      setState(() {
        _size = s;
        _nativeFailed = s == null;
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    tc.dispose();
    super.dispose();
  }

  double get _scale => tc.value.getMaxScaleOnAxis();

  void _onTransform() {
    final z = _scale > 1.01;
    if (z != _zoomed) {
      _zoomed = z;
      widget.onZoomChanged(z);
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _updateTiles);
  }

  Rect _fitRect() {
    final s = _size!;
    final k = (_viewport.width / s.width).clamp(0, double.infinity).toDouble();
    final k2 = _viewport.height / s.height;
    final fit = k < k2 ? k : k2;
    final w = s.width * fit, h = s.height * fit;
    return Rect.fromLTWH((_viewport.width - w) / 2, (_viewport.height - h) / 2, w, h);
  }

  void _updateTiles() {
    final s = _size;
    if (s == null || !mounted || _viewport.isEmpty) return;
    final scale = _scale;
    final fit = _fitRect();
    final fitScale = fit.width / s.width; // child px per image px
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final imagePxPerScreenPx = 1 / (fitScale * scale * dpr);
    final sample = sampleFor(imagePxPerScreenPx);
    // the preview is ~ screen-sized: no tiles needed until we need more detail than it has
    final previewSample = sampleFor(1 / (fitScale * dpr));
    if (scale <= 1.01 || sample >= previewSample) {
      if (_sample != 0) setState(() => _sample = 0);
      return;
    }
    // visible viewport -> child space -> image space
    final inv = Matrix4.inverted(tc.value);
    final tl = MatrixUtils.transformPoint(inv, Offset.zero);
    final br = MatrixUtils.transformPoint(inv, Offset(_viewport.width, _viewport.height));
    final visChild = Rect.fromPoints(tl, br).intersect(fit);
    if (visChild.isEmpty) return;
    final vis = Rect.fromLTRB(
      (visChild.left - fit.left) / fitScale,
      (visChild.top - fit.top) / fitScale,
      (visChild.right - fit.left) / fitScale,
      (visChild.bottom - fit.top) / fitScale,
    );
    final gen = ++_gen;
    setState(() => _sample = sample);
    for (final r in tilesFor(vis, sample, s.width, s.height)) {
      final key = '$sample:${r.left.toInt()}:${r.top.toInt()}';
      final hit = _tiles.remove(key);
      if (hit != null) {
        _tiles[key] = hit;
        continue;
      }
      if (_loading.contains(key)) continue;
      _loading.add(key);
      RegionDecoder.region(widget.path, r, sample).then((b) {
        _loading.remove(key);
        if (!mounted || b == null) return;
        _tiles[key] = _Tile(r, sample, b);
        while (_tiles.length > _maxTiles) {
          _tiles.remove(_tiles.keys.first);
        }
        if (gen == _gen || sample == _sample) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, bc) {
      _viewport = Size(bc.maxWidth, bc.maxHeight);
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final previewW = (bc.maxWidth * dpr).round().clamp(256, 2560);
      Widget child;
      if (_size == null) {
        child = Center(
          child: _nativeFailed
              ? Image.file(File(widget.path), cacheWidth: previewW * 2, fit: BoxFit.contain, filterQuality: FilterQuality.high)
              : const CircularProgressIndicator(),
        );
      } else {
        final fit = _fitRect();
        final fitScale = fit.width / _size!.width;
        final tiles = _tiles.values.where((t) => t.sample == _sample).toList();
        child = Stack(children: [
          Positioned.fromRect(
            rect: fit,
            child: Image.file(File(widget.path),
                cacheWidth: _size!.width >= _size!.height ? previewW : null,
                cacheHeight: _size!.width < _size!.height ? (bc.maxHeight * dpr).round().clamp(256, 2560) : null,
                fit: BoxFit.fill,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium),
          ),
          for (final t in tiles)
            Positioned(
              left: fit.left + t.rect.left * fitScale,
              top: fit.top + t.rect.top * fitScale,
              width: t.rect.width * fitScale,
              height: t.rect.height * fitScale,
              child: Image.memory(t.bytes, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.high),
            ),
        ]);
      }
      return GestureDetector(
        onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
        onDoubleTap: _toggleZoom,
        child: InteractiveViewer(
          transformationController: tc,
          minScale: 1,
          maxScale: widget.maxScale,
          panEnabled: _zoomed,
          clipBehavior: Clip.none,
          child: SizedBox(width: bc.maxWidth, height: bc.maxHeight, child: child),
        ),
      );
    });
  }

  Offset _doubleTapAt = Offset.zero;

  void _toggleZoom() {
    if (_scale > 1.01) {
      tc.value = Matrix4.identity();
    } else {
      const z = 3.0;
      final p = _doubleTapAt;
      tc.value = Matrix4.diagonal3Values(z, z, 1)..setTranslationRaw(-p.dx * (z - 1), -p.dy * (z - 1), 0);
    }
  }
}
