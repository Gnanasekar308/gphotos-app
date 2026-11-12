import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

/// The device photo library. Loads the whole library page by page (first page fast, the rest in the
/// background) and keeps only lightweight [AssetEntity] handles in memory, never image bytes.
class MediaLibrary extends ChangeNotifier {
  MediaLibrary._();
  static final MediaLibrary instance = MediaLibrary._();

  static const pageSize = 500;

  final List<AssetEntity> all = [];
  List<AssetPathEntity> albums = [];
  AssetPathEntity? _root;
  bool loading = false;
  bool complete = false;
  int total = 0;
  int _generation = 0;

  Future<bool> requestAccess() async {
    final p = await PhotoManager.requestPermissionExtend();
    return p.hasAccess;
  }

  Future<void> reload() async {
    final gen = ++_generation;
    loading = true;
    complete = false;
    notifyListeners();
    final paths = await PhotoManager.getAssetPathList(type: RequestType.image, hasAll: true);
    if (gen != _generation) return;
    _root = paths.where((p) => p.isAll).firstOrNull ?? paths.firstOrNull;
    albums = paths.where((p) => !p.isAll).toList();
    all.clear();
    total = _root == null ? 0 : await _root!.assetCountAsync;
    notifyListeners();
    var start = 0;
    while (_root != null && start < total) {
      final page = await _root!.getAssetListRange(start: start, end: start + pageSize);
      if (gen != _generation) return;
      if (page.isEmpty) break;
      all.addAll(page);
      start += page.length;
      notifyListeners();
    }
    loading = false;
    complete = true;
    notifyListeners();
  }

  /// Removes entries locally after a verified delete / move.
  void removeIds(Iterable<String> ids) {
    final s = ids.toSet();
    all.removeWhere((a) => s.contains(a.id));
    total = all.length;
    notifyListeners();
  }

  AssetEntity? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }
}
