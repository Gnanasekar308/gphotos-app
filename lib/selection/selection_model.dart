import 'package:flutter/foundation.dart';

/// Multi-selection with slide-to-select / slide-to-deselect.
///
/// A drag starts on an item: if that item was not selected the drag selects, otherwise it deselects.
/// While dragging, the range anchor..current is applied on top of the selection as it was when the drag
/// started, so sliding back shrinks the range again (items return to their earlier state).
class SelectionModel extends ChangeNotifier {
  final Set<String> _ids = {};
  Set<String> _baseline = {};
  int? _anchor;
  int? _last;
  bool _selecting = true;

  Set<String> get ids => Set.unmodifiable(_ids);
  int get count => _ids.length;
  bool get active => _ids.isNotEmpty;
  bool get dragging => _anchor != null;
  bool contains(String id) => _ids.contains(id);

  void toggle(String id) {
    if (!_ids.remove(id)) _ids.add(id);
    notifyListeners();
  }

  void clear() {
    _ids.clear();
    _anchor = null;
    notifyListeners();
  }

  void selectAll(Iterable<String> all) {
    _ids.addAll(all);
    notifyListeners();
  }

  void removeAll(Iterable<String> ids) {
    _ids.removeAll(ids);
    notifyListeners();
  }

  /// Starts a drag on [index]. [idAt] maps grid index -> id. Returns true if the selection changed.
  bool startDrag(int index, String Function(int) idAt) {
    _baseline = Set.of(_ids);
    _anchor = index;
    _last = null;
    _selecting = !_ids.contains(idAt(index));
    return updateDrag(index, idAt);
  }

  /// Moves the drag end to [index]. Returns true if the selection changed (caller gives haptic feedback).
  bool updateDrag(int index, String Function(int) idAt) {
    final a = _anchor;
    if (a == null || index == _last) return false;
    _last = index;
    final next = Set.of(_baseline);
    final lo = index < a ? index : a;
    final hi = index < a ? a : index;
    for (var i = lo; i <= hi; i++) {
      final id = idAt(i);
      if (_selecting) {
        next.add(id);
      } else {
        next.remove(id);
      }
    }
    final changed = !setEquals(next, _ids);
    if (changed) {
      _ids
        ..clear()
        ..addAll(next);
      notifyListeners();
    }
    return changed;
  }

  void endDrag() {
    _anchor = null;
    _last = null;
    _baseline = {};
  }
}

/// Maps a point inside a fixed-column grid to an item index (null when outside any item).
int? gridIndexAt({
  required double dx,
  required double dy,
  required double scrollOffset,
  required double width,
  required int columns,
  required double spacing,
  required double childAspectRatio,
  required int itemCount,
  double paddingTop = 0,
  bool clampToEdges = false,
}) {
  if (itemCount == 0 || width <= 0) return null;
  final cellW = (width - spacing * (columns - 1)) / columns;
  final cellH = cellW / childAspectRatio;
  final x = dx.clamp(0, width - 0.001).toDouble();
  final y = dy + scrollOffset - paddingTop;
  if (y < 0) return clampToEdges ? 0 : null;
  final col = (x / (cellW + spacing)).floor().clamp(0, columns - 1);
  final row = (y / (cellH + spacing)).floor();
  final i = row * columns + col;
  if (i >= itemCount) return clampToEdges ? itemCount - 1 : null;
  return i;
}
