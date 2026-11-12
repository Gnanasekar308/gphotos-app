import 'package:flutter/services.dart';

/// Image size (already rotated by EXIF orientation).
class ImageInfoSize {
  const ImageInfoSize(this.width, this.height);
  final int width;
  final int height;
}

/// Android BitmapRegionDecoder bridge (see MainActivity.kt). Coordinates are in the displayed
/// (EXIF-rotated) image space; [sample] is a power of two (1 = full resolution).
class RegionDecoder {
  static const _ch = MethodChannel('gphotos/region');

  static Future<ImageInfoSize?> info(String path) async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('info', {'path': path});
      if (m == null) return null;
      return ImageInfoSize(m['width'] as int, m['height'] as int);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<Uint8List?> region(String path, Rect r, int sample) async {
    try {
      return await _ch.invokeMethod<Uint8List>('region', {
        'path': path,
        'left': r.left.floor(),
        'top': r.top.floor(),
        'right': r.right.ceil(),
        'bottom': r.bottom.ceil(),
        'sample': sample,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Largest power-of-two sample size that still gives at least one image pixel per screen pixel.
int sampleFor(double imagePxPerScreenPx) {
  var s = 1;
  while (s * 2 <= imagePxPerScreenPx) {
    s *= 2;
  }
  return s;
}

/// Tile rectangles (image space) covering [visible] at [sample]; tiles are aligned to a fixed grid so
/// they can be cached and reused while panning.
List<Rect> tilesFor(Rect visible, int sample, int imageW, int imageH, {int tilePx = 512}) {
  final size = (tilePx * sample).toDouble();
  final out = <Rect>[];
  final c0 = (visible.left / size).floor().clamp(0, 1 << 20);
  final r0 = (visible.top / size).floor().clamp(0, 1 << 20);
  final c1 = ((visible.right - 0.001) / size).floor();
  final r1 = ((visible.bottom - 0.001) / size).floor();
  for (var r = r0; r <= r1; r++) {
    for (var c = c0; c <= c1; c++) {
      final l = c * size, t = r * size;
      if (l >= imageW || t >= imageH) continue;
      out.add(Rect.fromLTRB(l, t, (l + size).clamp(0, imageW.toDouble()), (t + size).clamp(0, imageH.toDouble())));
    }
  }
  return out;
}
