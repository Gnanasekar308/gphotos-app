import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/media_library.dart';
import 'face_model.dart';
import 'face_store.dart';

List<List<double>> _sigEntry(List<Object> a) => faceSignatures(a[0] as Uint8List, (a[1] as List).cast<FaceGeom>());

/// Scans the whole library for faces with on-device ML Kit, page by page, while the app is open.
/// Progress is saved continuously, so a scan can be paused, the app closed, and the scan resumed
/// later from where it stopped. Detection runs natively; signatures are computed in a background
/// isolate so the UI stays smooth.
class FaceScanner extends ChangeNotifier {
  FaceScanner._();
  static final instance = FaceScanner._();

  bool running = false;
  bool _stop = false;
  int done = 0;
  int total = 0;
  int facesFound = 0;
  String? error;

  double get progress => total == 0 ? 0 : done / total;

  Future<void> start() async {
    if (running) return;
    final store = FaceStore.instance;
    await store.load();
    final lib = MediaLibrary.instance;
    running = true;
    _stop = false;
    error = null;
    notifyListeners();
    final detector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate, enableLandmarks: true, minFaceSize: 0.08),
    );
    final tmpDir = await getTemporaryDirectory();
    final tmp = File('${tmpDir.path}/gphotos_face_scan.jpg');
    final cents = store.centroids();
    var sinceSave = 0;
    try {
      // wait for the library to finish loading so "complete library" really is complete
      while (!lib.complete && !_stop) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      final todo = lib.all.where((a) => !store.scanned.contains(a.id)).toList();
      total = store.scanned.length + todo.length;
      done = store.scanned.length;
      notifyListeners();
      for (final a in todo) {
        if (_stop) break;
        await _scanOne(a, detector, tmp, store, cents);
        done++;
        if (++sinceSave >= 20) {
          sinceSave = 0;
          await store.save();
          store.notify();
        }
        notifyListeners();
      }
    } catch (e) {
      error = '$e';
    } finally {
      await detector.close();
      if (await tmp.exists()) await tmp.delete();
      await store.save();
      store.notify();
      running = false;
      notifyListeners();
    }
  }

  Future<void> _scanOne(AssetEntity a, FaceDetector det, File tmp, FaceStore store, Map<String, List<double>> cents) async {
    final bytes = await a.thumbnailDataWithSize(const ThumbnailSize(1024, 1024), quality: 90);
    if (bytes == null) {
      store.scanned.add(a.id);
      return;
    }
    await tmp.writeAsBytes(bytes, flush: true);
    final faces = await det.processImage(InputImage.fromFilePath(tmp.path));
    if (faces.isEmpty) {
      store.scanned.add(a.id);
      return;
    }
    // analysed image size (needed to normalise boxes): read from the JPEG via the decoder isolate
    final geoms = <FaceGeom>[];
    for (final f in faces) {
      final b = f.boundingBox;
      List<double>? p(FaceLandmarkType t) {
        final l = f.landmarks[t];
        return l == null ? null : [l.position.x.toDouble(), l.position.y.toDouble()];
      }

      geoms.add(FaceGeom(b.left, b.top, b.width, b.height, p(FaceLandmarkType.leftEye), p(FaceLandmarkType.rightEye), f.headEulerAngleZ ?? 0));
    }
    final sigs = await compute(_sigEntry, <Object>[bytes, geoms]);
    final size = await compute(_jpegSize, bytes);
    final w = size[0] <= 0 ? 1 : size[0], h = size[1] <= 0 ? 1 : size[1];
    final found = <({List<double> box, List<double> sig})>[];
    for (var i = 0; i < geoms.length; i++) {
      final g = geoms[i];
      found.add((box: [g.left / w, g.top / h, g.width / w, g.height / h], sig: sigs[i]));
    }
    store.addDetected(a.id, found, cents);
    facesFound += found.length;
  }

  void stop() {
    _stop = true;
  }
}

List<int> _jpegSize(Uint8List b) {
  // decodes only the header when possible
  final dec = _findSize(b);
  return dec;
}

List<int> _findSize(Uint8List b) {
  // JPEG SOFn scan
  if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final m = b[i + 1];
      final len = (b[i + 2] << 8) | b[i + 3];
      if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
        final h = (b[i + 5] << 8) | b[i + 6];
        final w = (b[i + 7] << 8) | b[i + 8];
        return [w, h];
      }
      i += 2 + len;
    }
  }
  return [0, 0];
}
