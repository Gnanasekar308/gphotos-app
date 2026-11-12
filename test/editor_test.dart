import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gphotos/editor/crop_overlay.dart';
import 'package:gphotos/editor/edit_ops.dart';
import 'package:image/image.dart' as img;

img.Image solid(int w, int h, int r, int g, int b) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  return im;
}

void main() {
  group('colour matrix', () {
    test('identity adjustments do not change pixels', () {
      final im = solid(4, 4, 10, 120, 240);
      final out = render(im, const Geometry(), const Adjustments());
      final p = out.getPixel(1, 1);
      expect([p.r, p.g, p.b], [10, 120, 240]);
    });

    test('compose applies a then b', () {
      final m = compose(offset(10), scale(2)); // (x + 10) * 2
      final im = solid(1, 1, 5, 5, 5);
      applyMatrix(im, m);
      expect(im.getPixel(0, 0).r, 30);
    });

    test('mono filter makes r = g = b', () {
      final im = solid(2, 2, 200, 50, 10);
      final out = render(im, const Geometry(), const Adjustments(filter: 2));
      final p = out.getPixel(0, 0);
      expect(p.r, p.g);
      expect(p.g, p.b);
    });

    test('brightness +100 brightens, contrast keeps mid grey', () {
      final im = solid(1, 1, 100, 100, 100);
      expect(render(im, const Geometry(), const Adjustments(brightness: 100)).getPixel(0, 0).r, greaterThan(200));
      final mid = solid(1, 1, 128, 128, 128);
      expect(render(mid, const Geometry(), const Adjustments(contrast: 80)).getPixel(0, 0).r, inInclusiveRange(127, 129));
    });

    test('matrix is 4x5 like ColorFilter.matrix', () {
      expect(const Adjustments(saturation: 30, warmth: 20, filter: 1).matrix().length, 20);
    });
  });

  group('geometry', () {
    test('rotate 90 swaps size, crop + resize sizes are exact', () {
      final im = solid(400, 200, 1, 2, 3);
      const g = Geometry(turns: 1, crop: Rect.fromLTRB(0, 0, 0.5, 0.5));
      expect(g.rotatedSize(400, 200), (200, 400));
      expect(g.cropSize(400, 200), (100, 200));
      final out = render(im, g, const Adjustments());
      expect([out.width, out.height], [100, 200]);
      final r = render(im, const Geometry(outWidth: 100), const Adjustments());
      expect([r.width, r.height], [100, 50]);
    });

    test('flip moves pixels', () {
      final im = solid(2, 1, 0, 0, 0)..setPixelRgb(0, 0, 255, 0, 0);
      final out = render(im, const Geometry(flipH: true), const Adjustments());
      expect(out.getPixel(1, 0).r, 255);
      expect(out.getPixel(0, 0).r, 0);
    });

    test('full resolution export keeps every pixel of the crop', () {
      final src = solid(1200, 800, 90, 90, 90);
      final bytes = Uint8List.fromList(img.encodeJpg(src, quality: 95));
      final out = exportImage(bytes, const Geometry(crop: Rect.fromLTRB(0.25, 0.25, 0.75, 0.75)).toMap(), const Adjustments().toMap(), true);
      final dec = img.decodePng(out)!;
      expect([dec.width, dec.height], [600, 400]);
      final args = exportFromArgs([bytes, const Geometry(outWidth: 300).toMap(), const Adjustments().toMap(), false]);
      final d2 = img.decodeJpg(args)!;
      expect([d2.width, d2.height], [300, 200]);
    });

    test('geometry map round trip', () {
      const g = Geometry(turns: 3, flipV: true, crop: Rect.fromLTRB(0.1, 0.2, 0.9, 0.8), outWidth: 50);
      final b = Geometry.fromMap(g.toMap());
      expect(b.turns, 3);
      expect(b.flipV, isTrue);
      expect(b.crop, g.crop);
      expect(b.outWidth, 50);
    });
  });

  group('crop handles', () {
    test('free crop clamps inside the image and keeps a minimum size', () {
      var r = const Rect.fromLTRB(0.2, 0.2, 0.8, 0.8);
      r = dragCrop(r, CropHandle.tl, const Offset(-0.5, -0.5));
      expect(r.left, 0);
      expect(r.top, 0);
      r = dragCrop(r, CropHandle.br, const Offset(-2, -2));
      expect(r.width, closeTo(0.05, 1e-9));
    });

    test('move keeps size and stays inside', () {
      final r = dragCrop(const Rect.fromLTRB(0.5, 0.5, 0.9, 0.9), CropHandle.move, const Offset(0.5, 0.5));
      expect(r.right, closeTo(1, 1e-9));
      expect(r.width, closeTo(0.4, 1e-9));
    });

    test('fixed ratio is kept in pixels', () {
      // 2000 x 1000 image, 1:1 crop -> normalised width is half the normalised height
      final r = dragCrop(const Rect.fromLTRB(0, 0, 1, 1), CropHandle.br, const Offset(-0.1, 0), aspect: 1, imageAspect: 2);
      expect(r.width * 2000 / (r.height * 1000), closeTo(1, 1e-6));
      final c = centeredAspect(16 / 9, 4 / 3);
      expect(c.width * 4 / (c.height * 3), closeTo(16 / 9, 1e-6));
    });
  });

  test('auto enhance stretches a flat image', () {
    final im = img.Image(width: 10, height: 10);
    for (var y = 0; y < 10; y++) {
      for (var x = 0; x < 10; x++) {
        final v = 100 + x * 5;
        im.setPixelRgb(x, y, v, v, v);
      }
    }
    final a = autoEnhance(im);
    expect(a.contrast, greaterThan(0));
  });
}
