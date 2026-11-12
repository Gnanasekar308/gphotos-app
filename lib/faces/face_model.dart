import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class FaceRecord {
  FaceRecord({required this.id, required this.assetId, required this.box, required this.sig, this.personId});
  final String id;
  final String assetId;

  /// left, top, width, height normalised to the analysed (orientation-applied) image.
  final List<double> box;
  final List<double> sig;
  String? personId;

  Map<String, Object?> toJson() => {'id': id, 'a': assetId, 'b': box, 's': sig, 'p': personId};
  static FaceRecord fromJson(Map m) => FaceRecord(
        id: m['id'] as String,
        assetId: m['a'] as String,
        box: (m['b'] as List).map((e) => (e as num).toDouble()).toList(),
        sig: (m['s'] as List).map((e) => (e as num).toDouble()).toList(),
        personId: m['p'] as String?,
      );
}

class Person {
  Person({required this.id, this.name = '', this.coverFaceId, this.hidden = false});
  final String id;
  String name;
  String? coverFaceId;
  bool hidden;

  Map<String, Object?> toJson() => {'id': id, 'n': name, 'c': coverFaceId, 'h': hidden};
  static Person fromJson(Map m) => Person(id: m['id'] as String, name: (m['n'] ?? '') as String, coverFaceId: m['c'] as String?, hidden: (m['h'] ?? false) as bool);
}

/// Input for signature extraction (sent to a background isolate).
class FaceGeom {
  FaceGeom(this.left, this.top, this.width, this.height, this.leftEye, this.rightEye, this.roll);
  final double left, top, width, height;
  final List<double>? leftEye, rightEye; // x, y in image pixels
  final double roll; // degrees
}

/// Signature length: 24x24 aligned, normalised grey patch (576) + 4x4 local contrast (16).
const sigPatch = 24;

/// Builds an approximate appearance signature for each face: the face is rotated so the eyes are level
/// (when ML Kit found the eyes), cropped with a margin, resized to 24x24 grey, histogram-normalised
/// (zero mean / unit variance). Faces are compared by cosine distance. This is a classic,
/// lightweight descriptor, NOT a trained face-recognition embedding: grouping is approximate and the
/// user corrects it with merge / split / move.
List<List<double>> faceSignatures(Uint8List encoded, List<FaceGeom> faces) {
  final decoded = img.decodeImage(encoded);
  if (decoded == null) return [for (final _ in faces) const <double>[]];
  final grey = img.grayscale(decoded);
  final out = <List<double>>[];
  for (final f in faces) {
    final m = 0.25;
    final x = (f.left - f.width * m).round().clamp(0, grey.width - 1);
    final y = (f.top - f.height * m).round().clamp(0, grey.height - 1);
    final w = (f.width * (1 + 2 * m)).round().clamp(1, grey.width - x);
    final h = (f.height * (1 + 2 * m)).round().clamp(1, grey.height - y);
    var crop = img.copyCrop(grey, x: x, y: y, width: w, height: h);
    var angle = -f.roll;
    if (f.leftEye != null && f.rightEye != null) {
      angle = -math.atan2(f.rightEye![1] - f.leftEye![1], f.rightEye![0] - f.leftEye![0]) * 180 / math.pi;
      if (angle.abs() > 90) angle += angle > 0 ? -180 : 180;
    }
    if (angle.abs() > 2) crop = img.copyRotate(crop, angle: angle, interpolation: img.Interpolation.linear);
    // centre square = the face itself after rotation
    final side = math.min(crop.width, crop.height);
    final sq = img.copyCrop(crop, x: (crop.width - side) ~/ 2, y: (crop.height - side) ~/ 2, width: side, height: side);
    final small = img.copyResize(sq, width: sigPatch, height: sigPatch, interpolation: img.Interpolation.average);
    final v = <double>[];
    for (var yy = 0; yy < sigPatch; yy++) {
      for (var xx = 0; xx < sigPatch; xx++) {
        v.add(small.getPixel(xx, yy).r.toDouble());
      }
    }
    out.add(normalise(v));
  }
  return out;
}

/// Zero mean, unit length.
List<double> normalise(List<double> v) {
  if (v.isEmpty) return v;
  final mean = v.reduce((a, b) => a + b) / v.length;
  final c = [for (final x in v) x - mean];
  final n = math.sqrt(c.fold<double>(0, (s, x) => s + x * x));
  if (n == 0) return c;
  return [for (final x in c) x / n];
}

double cosineDistance(List<double> a, List<double> b) {
  if (a.isEmpty || a.length != b.length) return 2;
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 2;
  return 1 - dot / math.sqrt(na * nb);
}

List<double> centroid(Iterable<List<double>> sigs) {
  final list = sigs.where((s) => s.isNotEmpty).toList();
  if (list.isEmpty) return const [];
  final c = List<double>.filled(list.first.length, 0);
  for (final s in list) {
    for (var i = 0; i < c.length; i++) {
      c[i] += s[i];
    }
  }
  return normalise(c);
}

/// Assigns a face to the closest existing person if within [threshold], else returns null
/// (caller creates a new person). [centroids] maps personId -> centroid.
String? nearestPerson(List<double> sig, Map<String, List<double>> centroids, {double threshold = 0.32}) {
  String? best;
  var bestD = threshold;
  centroids.forEach((id, c) {
    final d = cosineDistance(sig, c);
    if (d < bestD) {
      bestD = d;
      best = id;
    }
  });
  return best;
}
