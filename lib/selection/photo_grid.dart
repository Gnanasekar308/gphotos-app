import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../core/app_settings.dart';
import '../core/file_ops.dart';
import '../vault/vault_import.dart';
import '../viewer/viewer_page.dart';
import '../widgets/thumb.dart';
import 'selection_model.dart';

/// Photo grid with tap / long-press selection, slide-to-select and slide-to-deselect (long-press then
/// drag), edge auto-scroll while dragging, haptic feedback, pinch to change the column count and a
/// selection action bar (share, vault, delete).
class PhotoGrid extends StatefulWidget {
  const PhotoGrid({super.key, required this.items, this.header, this.onChanged});
  final List<AssetEntity> items;
  final Widget? header;
  final VoidCallback? onChanged;

  @override
  State<PhotoGrid> createState() => _PhotoGridState();
}

class _PhotoGridState extends State<PhotoGrid> {
  final sel = SelectionModel();
  final sc = ScrollController();
  Timer? _autoScroll;
  Offset? _lastLocal;
  Size _size = Size.zero;
  final _pointers = <int, Offset>{};
  double? _pinchStart;
  bool _pinchUsed = false;

  static const _edge = 72.0;

  @override
  void initState() {
    super.initState();
    sel.addListener(_onSel);
  }

  void _onSel() => setState(() {});

  @override
  void dispose() {
    _autoScroll?.cancel();
    sel.dispose();
    sc.dispose();
    super.dispose();
  }

  AppSettings get _s => SettingsScope.of(context);

  String _idAt(int i) => widget.items[i].id;

  int? _indexAt(Offset local, {bool clamp = false}) => gridIndexAt(
        dx: local.dx,
        dy: local.dy,
        scrollOffset: sc.hasClients ? sc.offset : 0,
        width: _size.width,
        columns: _s.gridColumns,
        spacing: _s.gridSpacing,
        childAspectRatio: 1,
        itemCount: widget.items.length,
        clampToEdges: clamp,
      );

  void _haptic() {
    if (_s.haptics) HapticFeedback.selectionClick();
  }

  void _dragStart(Offset local) {
    final i = _indexAt(local);
    if (i == null) return;
    _lastLocal = local;
    if (_s.haptics) HapticFeedback.mediumImpact();
    if (_s.dragToSelect) {
      sel.startDrag(i, _idAt);
    } else {
      sel.toggle(_idAt(i));
    }
  }

  void _dragUpdate(Offset local) {
    if (!sel.dragging) return;
    _lastLocal = local;
    _applyAt(local);
    final nearTop = local.dy < _edge;
    final nearBottom = local.dy > _size.height - _edge;
    if (nearTop || nearBottom) {
      _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tickScroll());
    } else {
      _autoScroll?.cancel();
      _autoScroll = null;
    }
  }

  void _tickScroll() {
    final p = _lastLocal;
    if (p == null || !sc.hasClients) return;
    double v = 0;
    if (p.dy < _edge) v = -(1 - (p.dy.clamp(0, _edge) / _edge));
    if (p.dy > _size.height - _edge) v = 1 - ((_size.height - p.dy).clamp(0, _edge) / _edge);
    if (v == 0) return;
    final max = sc.position.maxScrollExtent;
    final next = (sc.offset + v * 24).clamp(0.0, max);
    if (next == sc.offset) return;
    sc.jumpTo(next);
    _applyAt(p);
  }

  void _applyAt(Offset local) {
    final i = _indexAt(local, clamp: true);
    if (i != null && sel.updateDrag(i, _idAt)) _haptic();
  }

  void _dragEnd() {
    _autoScroll?.cancel();
    _autoScroll = null;
    sel.endDrag();
  }

  List<AssetEntity> get _selected => widget.items.where((a) => sel.contains(a.id)).toList();

  Future<void> _share() async {
    final n = await sharePhotos(_selected);
    if (mounted && n == 0) snack(context, 'Nothing to share');
  }

  Future<void> _delete() async {
    final done = await deletePhotos(context, _selected);
    if (done.isEmpty) return;
    sel.removeAll(done);
    widget.items.removeWhere((a) => done.contains(a.id));
    widget.onChanged?.call();
    if (mounted) setState(() {});
  }

  Future<void> _vault() async {
    final moved = await moveToVault(context, _selected);
    sel.removeAll(moved);
    if (moved.isNotEmpty) {
      widget.items.removeWhere((a) => moved.contains(a.id));
      widget.onChanged?.call();
      if (mounted) setState(() {});
    }
  }

  // two-finger pinch on the grid changes the column count (raw pointers, so it does not fight scrolling)
  void _pointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      _pinchStart = _spread();
      _pinchUsed = false;
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final start = _pinchStart;
    if (_pointers.length != 2 || start == null || start < 1 || _pinchUsed || !_s.pinchToChangeColumns) return;
    final r = _spread() / start;
    if (r > 1.35 && _s.gridColumns > 2) {
      _pinchUsed = true;
      _s.setGridColumns(_s.gridColumns - 1);
      _haptic();
    } else if (r < 0.7 && _s.gridColumns < 6) {
      _pinchUsed = true;
      _s.setGridColumns(_s.gridColumns + 1);
      _haptic();
    }
  }

  void _pointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _pinchStart = null;
  }

  double _spread() {
    final v = _pointers.values.toList();
    return (v[0] - v[1]).distance;
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !sel.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) sel.clear();
      },
      child: Column(children: [
        if (sel.active)
          Material(
            color: cs.surfaceContainerHigh,
            child: Row(children: [
              IconButton(tooltip: 'Clear selection', onPressed: sel.clear, icon: const Icon(Icons.close)),
              Text('${sel.count} selected', style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(tooltip: 'Select all', icon: const Icon(Icons.select_all), onPressed: () => sel.selectAll(widget.items.map((e) => e.id))),
              IconButton(tooltip: 'Share', icon: const Icon(Icons.share), onPressed: _share),
              IconButton(tooltip: 'Move to vault', icon: const Icon(Icons.lock), onPressed: _vault),
              IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
            ]),
          )
        else if (widget.header != null)
          widget.header!,
        Expanded(
          child: LayoutBuilder(builder: (_, bc) {
            _size = Size(bc.maxWidth, bc.maxHeight);
            return Listener(
              onPointerDown: _pointerDown,
              onPointerMove: _pointerMove,
              onPointerUp: _pointerUp,
              onPointerCancel: _pointerUp,
              child: GestureDetector(
                onLongPressStart: (d) => _dragStart(d.localPosition),
                onLongPressMoveUpdate: (d) => _dragUpdate(d.localPosition),
                onLongPressEnd: (_) => _dragEnd(),
                onLongPressCancel: _dragEnd,
                child: GridView.builder(
                  key: const PageStorageKey('grid'),
                  controller: sc,
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: s.gridColumns,
                    mainAxisSpacing: s.gridSpacing,
                    crossAxisSpacing: s.gridSpacing,
                  ),
                  itemCount: widget.items.length,
                  itemBuilder: (_, i) {
                    final a = widget.items[i];
                    final on = sel.contains(a.id);
                    final px = (bc.maxWidth / s.gridColumns * MediaQuery.devicePixelRatioOf(context)).clamp(128, 512).round();
                    return GestureDetector(
                      onTap: () {
                        if (sel.active) {
                          sel.toggle(a.id);
                          _haptic();
                        } else {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ViewerPage(items: widget.items, start: i)))
                              .then((_) {
                            widget.onChanged?.call();
                            if (mounted) setState(() {});
                          });
                        }
                      },
                      child: Stack(fit: StackFit.expand, children: [
                        AnimatedPadding(
                          duration: const Duration(milliseconds: 120),
                          padding: EdgeInsets.all(on ? 8 : 0),
                          child: PhotoThumb(a, size: px, fit: s.squareThumbs ? BoxFit.cover : BoxFit.contain),
                        ),
                        if (sel.active)
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Icon(on ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: on ? cs.primary : Colors.white70, size: 22),
                          ),
                      ]),
                    );
                  },
                ),
              ),
            );
          }),
        ),
      ]),
    );
  }
}
