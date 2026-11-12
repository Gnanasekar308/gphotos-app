import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';

import '../core/file_ops.dart';
import '../core/media_library.dart';
import 'crop_overlay.dart';
import 'edit_ops.dart';

/// Non-destructive editor: rotate / flip, interactive free or fixed-ratio crop, output size,
/// colour adjustments and filters. The preview uses the same colour matrix as the export; the export
/// decodes the original at full resolution in a background isolate and is saved as a NEW photo.
/// The original is never modified or deleted.
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.asset});
  final AssetEntity asset;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  img.Image? _src; // preview-sized, orientation applied
  ui.Image? _shown; // preview after rotate / flip
  int _fullW = 0, _fullH = 0;
  Geometry g = const Geometry();
  Adjustments a = const Adjustments();
  int tab = 0;
  int ratio = 0;
  bool before = false;
  bool busy = true;
  bool png = false;
  final wc = TextEditingController(), hc = TextEditingController();
  bool keepAspect = true;

  static const ratioNames = ['Free', 'Original', '1:1', '4:3', '3:4', '16:9', '9:16', '3:2'];

  double? _ratioValue(int i) {
    final (w, h) = g.rotatedSize(_fullW, _fullH);
    return switch (i) {
      1 => w / h,
      2 => 1,
      3 => 4 / 3,
      4 => 3 / 4,
      5 => 16 / 9,
      6 => 9 / 16,
      7 => 3 / 2,
      _ => null,
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final size = widget.asset.orientatedSize;
    _fullW = size.width.round();
    _fullH = size.height.round();
    png = (widget.asset.mimeType ?? '').contains('png');
    final bytes = await widget.asset.thumbnailDataWithSize(const ThumbnailSize(1600, 1600), quality: 92);
    final decoded = bytes == null ? null : img.decodeImage(bytes);
    if (decoded == null) {
      if (mounted) {
        snack(context, 'Cannot open this photo for editing');
        Navigator.pop(context);
      }
      return;
    }
    _src = decoded;
    await _rebuildPreview();
  }

  Future<void> _rebuildPreview() async {
    var o = _src!;
    if (g.turns % 4 != 0) o = img.copyRotate(o, angle: (g.turns % 4) * 90);
    if (g.flipH) o = img.flipHorizontal(o);
    if (g.flipV) o = img.flipVertical(o);
    final rgba = o.convert(numChannels: 4);
    final buf = await ui.ImmutableBuffer.fromUint8List(rgba.toUint8List());
    final desc = ui.ImageDescriptor.raw(buf, width: rgba.width, height: rgba.height, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _shown?.dispose();
      _shown = frame.image;
      busy = false;
    });
    _syncSizeFields();
  }

  void _syncSizeFields() {
    final (w, h) = g.outputSize(_fullW, _fullH);
    wc.text = '$w';
    hc.text = '$h';
  }

  void _setGeometry(Geometry n, {bool rebuild = false}) {
    setState(() => g = n);
    if (rebuild) {
      _rebuildPreview();
    } else {
      _syncSizeFields();
    }
  }

  void _rotate(int d) {
    // rotating swaps the axes: map the crop rect into the rotated frame
    final c = (g.flipH || g.flipV) ? const Rect.fromLTRB(0, 0, 1, 1) : g.crop;
    final r = d > 0 ? Rect.fromLTRB(1 - c.bottom, c.left, 1 - c.top, c.right) : Rect.fromLTRB(c.top, 1 - c.right, c.bottom, 1 - c.left);
    _setGeometry(Geometry(turns: (g.turns + d + 4) % 4, flipH: g.flipH, flipV: g.flipV, crop: r), rebuild: true);
  }

  void _flip(bool h) {
    final c = g.crop;
    final r = h ? Rect.fromLTRB(1 - c.right, c.top, 1 - c.left, c.bottom) : Rect.fromLTRB(c.left, 1 - c.bottom, c.right, 1 - c.top);
    _setGeometry(Geometry(turns: g.turns, flipH: h ? !g.flipH : g.flipH, flipV: h ? g.flipV : !g.flipV, crop: r), rebuild: true);
  }

  void _setRatio(int i) {
    setState(() => ratio = i);
    final v = _ratioValue(i);
    if (v == null) return;
    final (w, h) = g.rotatedSize(_fullW, _fullH);
    _setGeometry(Geometry(turns: g.turns, flipH: g.flipH, flipV: g.flipV, crop: centeredAspect(v, w / h)));
  }

  void _applySize({required bool fromWidth}) {
    final (cw, ch) = g.cropSize(_fullW, _fullH);
    var w = int.tryParse(wc.text), h = int.tryParse(hc.text);
    if (w == null || h == null || w < 1 || h < 1) return;
    if (keepAspect) {
      if (fromWidth) {
        h = (w * ch / cw).round().clamp(1, 1 << 15);
      } else {
        w = (h * cw / ch).round().clamp(1, 1 << 15);
      }
    }
    w = w.clamp(1, 16000);
    h = h.clamp(1, 16000);
    final same = w == cw && h == ch;
    setState(() => g = Geometry(turns: g.turns, flipH: g.flipH, flipV: g.flipV, crop: g.crop, outWidth: same ? null : w, outHeight: same ? null : h));
    wc.text = '$w';
    hc.text = '$h';
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final f = await widget.asset.originFile;
      if (f == null) throw Exception('Original file not available');
      final bytes = await f.readAsBytes();
      final geo = g.toMap(), adj = a.toMap();
      final asPng = png;
      final out = await compute(exportFromArgs, [bytes, geo, adj, asPng]);
      final name = 'Gphotos_${DateTime.now().millisecondsSinceEpoch}.${asPng ? 'png' : 'jpg'}';
      final saved = await PhotoManager.editor.saveImage(out, filename: name, title: name);
      MediaLibrary.instance.reload();
      if (!mounted) return;
      final (w, h) = g.outputSize(_fullW, _fullH);
      snack(context, 'Saved as a new photo ($w x $h). The original is unchanged.');
      HapticFeedback.mediumImpact();
      if (saved.id.isNotEmpty) Navigator.pop(context);
    } catch (e) {
      if (mounted) snack(context, 'Save failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    _shown?.dispose();
    wc.dispose();
    hc.dispose();
    super.dispose();
  }

  Widget _slider(String n, double v, Adjustments Function(double) set) => Row(children: [
        SizedBox(width: 92, child: Text(n)),
        Expanded(child: Slider(min: -100, max: 100, value: v, onChanged: (x) => setState(() => a = set(x)))),
        SizedBox(width: 36, child: Text(v.round().toString(), textAlign: TextAlign.end)),
      ]);

  Widget _panel() {
    switch (tab) {
      case 0:
        return Column(children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < ratioNames.length; i++) ChoiceChip(label: Text(ratioNames[i]), selected: ratio == i, onSelected: (_) => _setRatio(i)),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton(tooltip: 'Rotate left', icon: const Icon(Icons.rotate_90_degrees_ccw), onPressed: () => _rotate(-1)),
            IconButton(tooltip: 'Rotate right', icon: const Icon(Icons.rotate_90_degrees_cw), onPressed: () => _rotate(1)),
            IconButton(tooltip: 'Flip horizontal', icon: const Icon(Icons.flip), onPressed: () => _flip(true)),
            IconButton(
                tooltip: 'Flip vertical', icon: const RotatedBox(quarterTurns: 1, child: Icon(Icons.flip)), onPressed: () => _flip(false)),
            TextButton(
                onPressed: () {
                  setState(() => ratio = 0);
                  _setGeometry(Geometry(turns: g.turns, flipH: g.flipH, flipV: g.flipV));
                },
                child: const Text('Reset crop')),
          ]),
        ]);
      case 1:
        final (cw, ch) = g.cropSize(_fullW, _fullH);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Crop size: $cw x $ch px (original $_fullW x $_fullH)'),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: wc,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Width px'),
                    onSubmitted: (_) => _applySize(fromWidth: true))),
            const SizedBox(width: 12),
            Expanded(
                child: TextField(
                    controller: hc,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Height px'),
                    onSubmitted: (_) => _applySize(fromWidth: false))),
          ]),
          Row(children: [
            Checkbox(value: keepAspect, onChanged: (v) => setState(() => keepAspect = v ?? true)),
            const Text('Keep aspect ratio'),
            const Spacer(),
            FilledButton.tonal(onPressed: () => _applySize(fromWidth: true), child: const Text('Apply')),
          ]),
          Row(children: [
            const Text('Format:'),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('JPEG'), selected: !png, onSelected: (_) => setState(() => png = false)),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('PNG'), selected: png, onSelected: (_) => setState(() => png = true)),
          ]),
        ]);
      case 2:
        return Column(children: [
          _slider('Exposure', a.exposure, (x) => a.copyWith(exposure: x)),
          _slider('Brightness', a.brightness, (x) => a.copyWith(brightness: x)),
          _slider('Contrast', a.contrast, (x) => a.copyWith(contrast: x)),
          _slider('Saturation', a.saturation, (x) => a.copyWith(saturation: x)),
          _slider('Warmth', a.warmth, (x) => a.copyWith(warmth: x)),
          Row(children: [
            TextButton.icon(
                icon: const Icon(Icons.auto_fix_high),
                onPressed: _src == null ? null : () => setState(() => a = autoEnhance(_src!).copyWith(filter: a.filter)),
                label: const Text('Auto enhance (levels)')),
            const Spacer(),
            TextButton(onPressed: () => setState(() => a = Adjustments(filter: a.filter)), child: const Text('Reset')),
          ]),
        ]);
      default:
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < Adjustments.filterNames.length; i++)
            ChoiceChip(label: Text(Adjustments.filterNames[i]), selected: a.filter == i, onSelected: (_) => setState(() => a = a.copyWith(filter: i))),
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final im = _shown;
    return Scaffold(
      appBar: AppBar(title: const Text('Edit'), actions: [
        TextButton(onPressed: busy ? null : _save, child: const Text('Save copy')),
      ]),
      body: Column(children: [
        Expanded(
          child: im == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (_, bc) {
                  final k = [(bc.maxWidth - 24) / im.width, (bc.maxHeight - 24) / im.height].reduce((x, y) => x < y ? x : y);
                  final w = im.width * k, h = im.height * k;
                  final rect = Rect.fromLTWH((bc.maxWidth - w) / 2, (bc.maxHeight - h) / 2, w, h);
                  final cropping = tab == 0;
                  return Stack(children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onLongPressStart: (_) => setState(() => before = true),
                        onLongPressEnd: (_) => setState(() => before = false),
                        child: CustomPaint(
                          painter: _PreviewPainter(im, rect, cropping ? null : g.crop, before ? null : a.matrix()),
                        ),
                      ),
                    ),
                    if (cropping)
                      Positioned.fill(
                        child: CropOverlay(
                          imageRect: rect,
                          crop: g.crop,
                          aspect: _ratioValue(ratio),
                          imageAspect: im.width / im.height,
                          onChanged: (r) => _setGeometry(Geometry(turns: g.turns, flipH: g.flipH, flipV: g.flipV, crop: r)),
                        ),
                      ),
                    if (busy) const Center(child: CircularProgressIndicator()),
                  ]);
                }),
        ),
        Text(tab == 0 ? 'Drag the corners, edges or the frame' : 'Long-press the photo to compare with the original',
            style: Theme.of(context).textTheme.bodySmall),
        SizedBox(height: 190, child: SingleChildScrollView(padding: const EdgeInsets.all(10), child: _panel())),
        NavigationBar(
          height: 64,
          selectedIndex: tab,
          onDestinationSelected: (n) => setState(() => tab = n),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.crop_rotate), label: 'Crop'),
            NavigationDestination(icon: Icon(Icons.photo_size_select_large), label: 'Resize'),
            NavigationDestination(icon: Icon(Icons.tune), label: 'Adjust'),
            NavigationDestination(icon: Icon(Icons.filter), label: 'Filters'),
          ],
        ),
      ]),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.image, this.rect, this.crop, this.matrix);
  final ui.Image image;
  final Rect rect;
  final Rect? crop; // null = show the full frame (crop tab)
  final List<double>? matrix;

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..filterQuality = FilterQuality.medium;
    if (matrix != null) p.colorFilter = ColorFilter.matrix(matrix!);
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    if (crop == null) {
      c.drawImageRect(image, Rect.fromLTWH(0, 0, iw, ih), rect, p);
      return;
    }
    final src = Rect.fromLTRB(crop!.left * iw, crop!.top * ih, crop!.right * iw, crop!.bottom * ih);
    final k = [rect.width / src.width, rect.height / src.height].reduce((x, y) => x < y ? x : y);
    final dw = src.width * k, dh = src.height * k;
    final dst = Rect.fromCenter(center: rect.center, width: dw, height: dh);
    c.drawImageRect(image, src, dst, p);
  }

  @override
  bool shouldRepaint(_PreviewPainter o) => o.image != image || o.rect != rect || o.crop != crop || o.matrix != matrix;
}
