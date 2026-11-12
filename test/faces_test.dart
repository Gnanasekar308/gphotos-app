import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gphotos/faces/face_model.dart';
import 'package:gphotos/faces/face_store.dart';
import 'package:image/image.dart' as img;

void main() {
  test('normalise / cosine distance', () {
    final a = normalise([1, 2, 3, 4]);
    expect(cosineDistance(a, a), closeTo(0, 1e-9));
    expect(cosineDistance(a, [for (final x in a) -x]), closeTo(2, 1e-9));
    expect(cosineDistance(a, const []), 2);
  });

  test('nearestPerson uses the threshold', () {
    final p1 = normalise([1, 0, 0, 1]), p2 = normalise([0, 1, 1, 0]);
    final c = {'p1': p1, 'p2': p2};
    expect(nearestPerson(normalise([1, 0.1, 0, 1]), c), 'p1');
    expect(nearestPerson(normalise([1, 1, 1, 1.01]), c, threshold: 0.01), isNull);
  });

  test('signatures: the same face crop matches itself, a different one less', () {
    final im = img.Image(width: 200, height: 200);
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 200; x++) {
        final v = (x * 7 + y * 3) % 255;
        im.setPixelRgb(x, y, v, v, v);
      }
    }
    final other = img.Image(width: 200, height: 200);
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 200; x++) {
        final v = ((x - 100) * (x - 100) + (y - 100) * (y - 100)) % 255;
        other.setPixelRgb(x, y, v, v, v);
      }
    }
    final g = [FaceGeom(50, 50, 100, 100, null, null, 0)];
    final s1 = faceSignatures(Uint8List.fromList(img.encodePng(im)), g).single;
    final s2 = faceSignatures(Uint8List.fromList(img.encodePng(im)), g).single;
    final s3 = faceSignatures(Uint8List.fromList(img.encodePng(other)), g).single;
    expect(s1.length, sigPatch * sigPatch);
    expect(cosineDistance(s1, s2), closeTo(0, 1e-6));
    expect(cosineDistance(s1, s3), greaterThan(0.1));
  });

  group('FaceStore', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('faces_test'));
    tearDown(() async => dir.delete(recursive: true));

    List<double> v(int k) => normalise([for (var i = 0; i < 8; i++) i == k ? 1.0 : 0.0]);

    test('grouping, rename, merge, split, move, remove, persistence', () async {
      final s = FaceStore(dir: dir);
      await s.load();
      final cents = s.centroids();
      s.addDetected('img1', [(box: [0, 0, .1, .1], sig: v(0)), (box: [.5, .5, .1, .1], sig: v(1))], cents);
      s.addDetected('img2', [(box: [0, 0, .1, .1], sig: v(0))], cents);
      expect(s.people.length, 2, reason: 'two different faces, the repeated one joins its person');
      final a = s.faces.values.firstWhere((f) => f.assetId == 'img2').personId!;
      final b = s.people.keys.firstWhere((k) => k != a);
      expect(s.countOf(a), 2);

      s.rename(a, 'Anu');
      s.merge(a, b);
      expect(s.people.containsKey(b), isFalse);
      expect(s.countOf(a), 3);

      final one = s.facesOf(a).first.id;
      final c = s.split([one], name: 'Babu');
      expect(s.countOf(c), 1);
      expect(s.countOf(a), 2);

      s.moveFaces([one], a);
      expect(s.countOf(a), 3);
      s.removeFaces([one]);
      expect(s.countOf(a), 2);
      await s.save();

      final again = FaceStore(dir: dir);
      await again.load();
      expect(again.people[a]!.name, 'Anu');
      expect(again.countOf(a), 2);
      expect(again.scanned, containsAll(['img1', 'img2']));
      expect(again.sortedPeople().first.id, a);

      again.prune({'img1'});
      expect(again.faces.values.every((f) => f.assetId == 'img1'), isTrue);
    });
  });
}
