import 'dart:math' as math;

import 'package:flutter/material.dart';

enum CropHandle { tl, tr, bl, br, l, r, t, b, move }

/// Moves / resizes a normalised crop rect. [aspect] is width / height in *pixels* of the crop
/// (null = free); [imageAspect] is the image's width / height so the ratio can be kept in normalised
/// space. Pure function, unit-tested.
Rect dragCrop(Rect r, CropHandle h, Offset deltaNorm, {double? aspect, double imageAspect = 1, double minSize = 0.05}) {
  if (h == CropHandle.move) {
    final dx = deltaNorm.dx.clamp(-r.left, 1 - r.right).toDouble();
    final dy = deltaNorm.dy.clamp(-r.top, 1 - r.bottom).toDouble();
    return r.shift(Offset(dx, dy));
  }
  var l = r.left, t = r.top, rr = r.right, b = r.bottom;
  switch (h) {
    case CropHandle.tl:
      l += deltaNorm.dx;
      t += deltaNorm.dy;
    case CropHandle.tr:
      rr += deltaNorm.dx;
      t += deltaNorm.dy;
    case CropHandle.bl:
      l += deltaNorm.dx;
      b += deltaNorm.dy;
    case CropHandle.br:
      rr += deltaNorm.dx;
      b += deltaNorm.dy;
    case CropHandle.l:
      l += deltaNorm.dx;
    case CropHandle.r:
      rr += deltaNorm.dx;
    case CropHandle.t:
      t += deltaNorm.dy;
    case CropHandle.b:
      b += deltaNorm.dy;
    case CropHandle.move:
      break;
  }
  // keep inside the image, then enforce the minimum size by moving only the dragged edge
  l = l.clamp(0.0, 1.0 - minSize);
  t = t.clamp(0.0, 1.0 - minSize);
  rr = rr.clamp(minSize, 1.0);
  b = b.clamp(minSize, 1.0);
  final movesLeft = h == CropHandle.tl || h == CropHandle.bl || h == CropHandle.l;
  final movesTop = h == CropHandle.tl || h == CropHandle.tr || h == CropHandle.t;
  if (rr - l < minSize) {
    if (movesLeft) {
      l = rr - minSize;
    } else {
      rr = l + minSize;
    }
  }
  if (b - t < minSize) {
    if (movesTop) {
      t = b - minSize;
    } else {
      b = t + minSize;
    }
  }
  var out = Rect.fromLTRB(l, t, rr, b);
  if (aspect != null) out = fitAspect(out, aspect, imageAspect, h);
  return out;
}

/// Adjusts [r] to the pixel aspect [aspect], keeping the edge opposite to the dragged handle fixed, and
/// keeps it inside 0..1.
Rect fitAspect(Rect r, double aspect, double imageAspect, [CropHandle h = CropHandle.br]) {
  final na = aspect / imageAspect; // aspect in normalised units
  var w = r.width, hgt = r.height;
  if (w / hgt > na) {
    w = hgt * na;
  } else {
    hgt = w / na;
  }
  // anchor: the corner / edge opposite to the handle
  final anchorRight = h == CropHandle.tl || h == CropHandle.bl || h == CropHandle.l;
  final anchorBottom = h == CropHandle.tl || h == CropHandle.tr || h == CropHandle.t;
  var left = anchorRight ? r.right - w : r.left;
  var top = anchorBottom ? r.bottom - hgt : r.top;
  if (h == CropHandle.t || h == CropHandle.b) left = r.center.dx - w / 2;
  if (h == CropHandle.l || h == CropHandle.r) top = r.center.dy - hgt / 2;
  // keep inside, shrinking if needed
  final scale = math.min(1.0, math.min(1 / w, 1 / hgt));
  w *= scale;
  hgt *= scale;
  left = left.clamp(0.0, 1 - w);
  top = top.clamp(0.0, 1 - hgt);
  return Rect.fromLTWH(left, top, w, hgt);
}

/// Centered rect with pixel aspect [aspect] as large as possible.
Rect centeredAspect(double aspect, double imageAspect) {
  final na = aspect / imageAspect;
  double w = 1, h = 1;
  if (na > 1) {
    h = 1 / na;
  } else {
    w = na;
  }
  return Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
}

/// Interactive crop frame drawn over an image that fills [imageRect] (widget coordinates).
class CropOverlay extends StatefulWidget {
  const CropOverlay({super.key, required this.imageRect, required this.crop, required this.onChanged, this.aspect, required this.imageAspect});
  final Rect imageRect;
  final Rect crop;
  final ValueChanged<Rect> onChanged;
  final double? aspect;
  final double imageAspect;

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  CropHandle? _h;
  static const _grab = 28.0;

  Rect get _px => Rect.fromLTRB(
        widget.imageRect.left + widget.crop.left * widget.imageRect.width,
        widget.imageRect.top + widget.crop.top * widget.imageRect.height,
        widget.imageRect.left + widget.crop.right * widget.imageRect.width,
        widget.imageRect.top + widget.crop.bottom * widget.imageRect.height,
      );

  CropHandle? _hit(Offset p) {
    final r = _px;
    bool near(Offset a) => (a - p).distance < _grab;
    if (near(r.topLeft)) return CropHandle.tl;
    if (near(r.topRight)) return CropHandle.tr;
    if (near(r.bottomLeft)) return CropHandle.bl;
    if (near(r.bottomRight)) return CropHandle.br;
    final inY = p.dy > r.top && p.dy < r.bottom;
    final inX = p.dx > r.left && p.dx < r.right;
    if (inY && (p.dx - r.left).abs() < _grab) return CropHandle.l;
    if (inY && (p.dx - r.right).abs() < _grab) return CropHandle.r;
    if (inX && (p.dy - r.top).abs() < _grab) return CropHandle.t;
    if (inX && (p.dy - r.bottom).abs() < _grab) return CropHandle.b;
    if (r.contains(p)) return CropHandle.move;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => _h = _hit(d.localPosition),
      onPanUpdate: (d) {
        final h = _h;
        if (h == null) return;
        final dn = Offset(d.delta.dx / widget.imageRect.width, d.delta.dy / widget.imageRect.height);
        widget.onChanged(dragCrop(widget.crop, h, dn, aspect: widget.aspect, imageAspect: widget.imageAspect));
      },
      onPanEnd: (_) => _h = null,
      child: CustomPaint(painter: _CropPainter(_px, widget.imageRect, Theme.of(context).colorScheme.primary), size: Size.infinite),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.r, this.img, this.accent);
  final Rect r, img;
  final Color accent;

  @override
  void paint(Canvas c, Size s) {
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.55);
    c.drawPath(Path.combine(PathOperation.difference, Path()..addRect(img), Path()..addRect(r)), shade);
    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    c.drawRect(r, line);
    final grid = Paint()
      ..color = Colors.white54
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = r.left + r.width * i / 3, y = r.top + r.height * i / 3;
      c.drawLine(Offset(x, r.top), Offset(x, r.bottom), grid);
      c.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
    }
    final h = Paint()
      ..color = accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const k = 18.0;
    for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final sx = p.dx == r.left ? 1.0 : -1.0, sy = p.dy == r.top ? 1.0 : -1.0;
      c.drawLine(p, p + Offset(k * sx, 0), h);
      c.drawLine(p, p + Offset(0, k * sy), h);
    }
  }

  @override
  bool shouldRepaint(_CropPainter o) => o.r != r || o.img != img || o.accent != accent;
}
