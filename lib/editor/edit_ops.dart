import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

/// Colour adjustments, all in -100..100.
class Adjustments {
  const Adjustments({this.brightness = 0, this.contrast = 0, this.exposure = 0, this.saturation = 0, this.warmth = 0, this.filter = 0});
  final double brightness, contrast, exposure, saturation, warmth;
  final int filter;

  static const filterNames = ['Original', 'Vivid', 'Mono', 'Sepia', 'Warm', 'Cool', 'Fade'];

  bool get isIdentity => brightness == 0 && contrast == 0 && exposure == 0 && saturation == 0 && warmth == 0 && filter == 0;

  Adjustments copyWith({double? brightness, double? contrast, double? exposure, double? saturation, double? warmth, int? filter}) => Adjustments(
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        exposure: exposure ?? this.exposure,
        saturation: saturation ?? this.saturation,
        warmth: warmth ?? this.warmth,
        filter: filter ?? this.filter,
      );

  /// 4x5 row-major colour matrix (same layout as Flutter's ColorFilter.matrix, 0..255 offsets), so the
  /// on-screen preview and the exported pixels use exactly the same maths.
  List<double> matrix() {
    var m = identity();
    if (exposure != 0) m = compose(m, scale(math.pow(2, exposure / 50).toDouble()));
    if (brightness != 0) m = compose(m, offset(brightness * 1.275));
    if (contrast != 0) {
      final c = 1 + contrast / 100;
      m = compose(m, [c, 0, 0, 0, 128 * (1 - c), 0, c, 0, 0, 128 * (1 - c), 0, 0, c, 0, 128 * (1 - c), 0, 0, 0, 1, 0]);
    }
    if (saturation != 0) m = compose(m, saturate(1 + saturation / 100));
    if (warmth != 0) {
      final w = warmth * 0.3;
      m = compose(m, [1, 0, 0, 0, w, 0, 1, 0, 0, w * 0.2, 0, 0, 1, 0, -w, 0, 0, 0, 1, 0]);
    }
    switch (filter) {
      case 1:
        m = compose(m, saturate(1.35));
        m = compose(m, [1.08, 0, 0, 0, -10, 0, 1.08, 0, 0, -10, 0, 0, 1.08, 0, -10, 0, 0, 0, 1, 0]);
      case 2:
        m = compose(m, saturate(0));
      case 3:
        m = compose(m, [0.393, 0.769, 0.189, 0, 0, 0.349, 0.686, 0.168, 0, 0, 0.272, 0.534, 0.131, 0, 0, 0, 0, 0, 1, 0]);
      case 4:
        m = compose(m, [1, 0, 0, 0, 18, 0, 1, 0, 0, 6, 0, 0, 1, 0, -14, 0, 0, 0, 1, 0]);
      case 5:
        m = compose(m, [1, 0, 0, 0, -12, 0, 1, 0, 0, 2, 0, 0, 1, 0, 18, 0, 0, 0, 1, 0]);
      case 6:
        m = compose(m, saturate(0.8));
        m = compose(m, [0.85, 0, 0, 0, 30, 0, 0.85, 0, 0, 30, 0, 0, 0.85, 0, 30, 0, 0, 0, 1, 0]);
    }
    return m;
  }

  Map<String, Object> toMap() => {'b': brightness, 'c': contrast, 'e': exposure, 's': saturation, 'w': warmth, 'f': filter};

  static Adjustments fromMap(Map m) => Adjustments(
        brightness: (m['b'] as num).toDouble(),
        contrast: (m['c'] as num).toDouble(),
        exposure: (m['e'] as num).toDouble(),
        saturation: (m['s'] as num).toDouble(),
        warmth: (m['w'] as num).toDouble(),
        filter: m['f'] as int,
      );
}

List<double> identity() => [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
List<double> scale(double k) => [k, 0, 0, 0, 0, 0, k, 0, 0, 0, 0, 0, k, 0, 0, 0, 0, 0, 1, 0];
List<double> offset(double o) => [1, 0, 0, 0, o, 0, 1, 0, 0, o, 0, 0, 1, 0, o, 0, 0, 0, 1, 0];

List<double> saturate(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final i = 1 - s;
  return [
    lr * i + s, lg * i, lb * i, 0, 0, //
    lr * i, lg * i + s, lb * i, 0, 0,
    lr * i, lg * i, lb * i + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// Returns the matrix that applies [a] first and then [b].
List<double> compose(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 5; c++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += b[r * 5 + k] * a[k * 5 + c];
      }
      if (c == 4) v += b[r * 5 + 4];
      out[r * 5 + c] = v;
    }
  }
  return out;
}

/// Applies a colour matrix to every pixel in place.
void applyMatrix(img.Image im, List<double> m) {
  for (final p in im) {
    final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble(), a = p.a.toDouble();
    p
      ..r = (m[0] * r + m[1] * g + m[2] * b + m[3] * a + m[4]).clamp(0, 255)
      ..g = (m[5] * r + m[6] * g + m[7] * b + m[8] * a + m[9]).clamp(0, 255)
      ..b = (m[10] * r + m[11] * g + m[12] * b + m[13] * a + m[14]).clamp(0, 255);
  }
}

/// Geometry: quarter turns (clockwise), flips, then a crop rectangle normalised to the rotated / flipped
/// image (0..1), then an optional output size.
class Geometry {
  const Geometry({this.turns = 0, this.flipH = false, this.flipV = false, this.crop = const Rect.fromLTRB(0, 0, 1, 1), this.outWidth, this.outHeight});
  final int turns;
  final bool flipH, flipV;
  final Rect crop;
  final int? outWidth, outHeight;

  /// Size after rotation (before crop) for a source of [w] x [h].
  (int, int) rotatedSize(int w, int h) => turns.isOdd ? (h, w) : (w, h);

  /// Size of the cropped region in source pixels (full resolution).
  (int, int) cropSize(int w, int h) {
    final (rw, rh) = rotatedSize(w, h);
    return (math.max(1, (crop.width * rw).round()), math.max(1, (crop.height * rh).round()));
  }

  /// Final export size.
  (int, int) outputSize(int w, int h) {
    final (cw, ch) = cropSize(w, h);
    if (outWidth != null && outHeight != null) return (outWidth!, outHeight!);
    if (outWidth != null) return (outWidth!, math.max(1, (outWidth! * ch / cw).round()));
    if (outHeight != null) return (math.max(1, (outHeight! * cw / ch).round()), outHeight!);
    return (cw, ch);
  }

  Map<String, Object?> toMap() => {
        't': turns,
        'fh': flipH,
        'fv': flipV,
        'c': [crop.left, crop.top, crop.right, crop.bottom],
        'w': outWidth,
        'h': outHeight,
      };

  static Geometry fromMap(Map m) {
    final c = (m['c'] as List).cast<double>();
    return Geometry(
      turns: m['t'] as int,
      flipH: m['fh'] as bool,
      flipV: m['fv'] as bool,
      crop: Rect.fromLTRB(c[0], c[1], c[2], c[3]),
      outWidth: m['w'] as int?,
      outHeight: m['h'] as int?,
    );
  }
}

/// Applies geometry + colour to a decoded, orientation-baked image.
img.Image render(img.Image src, Geometry g, Adjustments a) {
  var o = src;
  final t = g.turns % 4;
  if (t != 0) o = img.copyRotate(o, angle: t * 90);
  if (g.flipH) o = img.flipHorizontal(o);
  if (g.flipV) o = img.flipVertical(o);
  final c = g.crop;
  if (c != const Rect.fromLTRB(0, 0, 1, 1)) {
    final x = (c.left * o.width).round().clamp(0, o.width - 1);
    final y = (c.top * o.height).round().clamp(0, o.height - 1);
    final w = (c.width * o.width).round().clamp(1, o.width - x);
    final h = (c.height * o.height).round().clamp(1, o.height - y);
    o = img.copyCrop(o, x: x, y: y, width: w, height: h);
  }
  if (g.outWidth != null || g.outHeight != null) {
    final (w, h) = Geometry(outWidth: g.outWidth, outHeight: g.outHeight).outputSize(o.width, o.height);
    if (w != o.width || h != o.height) o = img.copyResize(o, width: w, height: h, interpolation: img.Interpolation.cubic);
  }
  if (identical(o, src)) o = src.clone();
  if (!a.isIdentity) applyMatrix(o, a.matrix());
  return o;
}

/// Full-resolution export, meant to run in a background isolate. Returns encoded bytes.
Uint8List exportImage(Uint8List source, Map<String, Object?> geometry, Map<String, Object> adjust, bool png) {
  final decoded = img.decodeImage(source);
  if (decoded == null) throw const FormatException('Unsupported image');
  final src = img.bakeOrientation(decoded);
  final out = render(src, Geometry.fromMap(geometry), Adjustments.fromMap(adjust));
  return png ? img.encodePng(out) : img.encodeJpg(out, quality: 95);
}

/// [compute] entry point: [source bytes, geometry map, adjustments map, png].
Uint8List exportFromArgs(List<Object?> a) =>
    exportImage(a[0] as Uint8List, (a[1] as Map).cast<String, Object?>(), (a[2] as Map).cast<String, Object>(), a[3] as bool);

/// "Auto enhance": stretches levels to the 0.5 % / 99.5 % luminance percentiles and lifts saturation a
/// little. A classic, deterministic algorithm (not a neural network).
Adjustments autoEnhance(img.Image preview) {
  final hist = List<int>.filled(256, 0);
  var n = 0;
  for (final p in preview) {
    final l = (0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b).round().clamp(0, 255);
    hist[l]++;
    n++;
  }
  if (n == 0) return const Adjustments();
  int pct(double q) {
    var acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= q * n) return i;
    }
    return 255;
  }

  final lo = pct(0.005), hi = pct(0.995);
  final span = math.max(32, hi - lo);
  final c = (255 / span - 1) * 100;
  final mid = (lo + hi) / 2;
  return Adjustments(contrast: c.clamp(0, 60).toDouble(), brightness: ((128 - mid) / 1.275).clamp(-40, 40).toDouble(), saturation: 12);
}
