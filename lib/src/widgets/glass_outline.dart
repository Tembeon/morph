import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/liquid_field.dart';

/// The silhouette a control has fused some of its glass surfaces into.
///
/// A control hands one to `MorphGlassPainter.buildLayer` when its glass
/// surfaces are one body whose edge is not their own shapes - a menu
/// joined to its button by a neck. The package computes it once, by the
/// same law on every quality tier, so a flat fill, frosted glass and
/// liquid glass all draw the same shape.
///
/// [path] is the edge in the layer's local coordinates. An outline the
/// package fused also carries the body's signed distance field, from which
/// the package's own renderer shades the body as liquid glass; an outline
/// created from a path alone is clipped instead.
@immutable
class MorphGlassOutline {
  /// Creates an outline from its edge alone.
  const MorphGlassOutline(this.path) : _field = null;

  const MorphGlassOutline._(this.path, this._field);

  /// The edge of the body, in the layer's local coordinates.
  final Path path;

  final GlassField? _field;

  /// The box the body occupies.
  Rect get bounds => path.getBounds();

  /// The same outline moved by [offset].
  MorphGlassOutline shift(Offset offset) {
    final field = _field?.shift(offset);
    return MorphGlassOutline._(field?.outline ?? path.shift(offset), field);
  }
}

/// The sampled distance field of [outline], or null for an outline built
/// from a path alone.
@internal
GlassField? morphGlassOutlineField(MorphGlassOutline outline) => outline._field;

/// How much larger a corner radius the glass's optical normals turn on
/// than the shape's own: the factor the renderer's analytic shapes use
/// (`kOpticalCornerRadiusScale` in its sdf.glsl, fitted to iOS 27 card
/// corners), so a fused body turns its light at a corner where the same
/// shape drawn alone does.
@internal
const double morphOpticalCornerScale = 1.5;

/// The rounded boxes a fused outline is made of, laid out for the inner
/// loops: per box its center, half extents and clamped corner radius.
@internal
class MorphOutlineBoxes {
  /// Lays out [shapes], whose corners must share one circular radius.
  MorphOutlineBoxes(List<RRect> shapes)
    : length = shapes.length,
      _data = Float64List(shapes.length * 5) {
    for (var i = 0; i < shapes.length; i++) {
      final shape = shapes[i];
      _requireUniform(shape);
      final hx = shape.width / 2;
      final hy = shape.height / 2;
      _data[i * 5] = shape.center.dx;
      _data[i * 5 + 1] = shape.center.dy;
      _data[i * 5 + 2] = hx;
      _data[i * 5 + 3] = hy;
      _data[i * 5 + 4] = math.min(shape.tlRadiusX, math.min(hx, hy));
    }
  }

  /// The number of boxes.
  final int length;

  /// Whether box [i]'s optical normals ever differ from its exact ones:
  /// false for a capsule or a circle, whose corners are already as round
  /// as its thickness allows.
  bool turns(int i) =>
      _data[i * 5 + 4] * morphOpticalCornerScale > _data[i * 5 + 4] &&
      _data[i * 5 + 4] < halfMinor(i);

  final Float64List _data;

  /// The half thickness of box [i].
  double halfMinor(int i) => math.min(_data[i * 5 + 2], _data[i * 5 + 3]);

  /// The signed distance from (x, y) to box [i].
  double distance(int i, double x, double y) {
    final r = _data[i * 5 + 4];
    final qx = (x - _data[i * 5]).abs() - _data[i * 5 + 2] + r;
    final qy = (y - _data[i * 5 + 1]).abs() - _data[i * 5 + 3] + r;
    return morphBoxDistance(qx, qy, r);
  }

  /// Whether (x, y) lies where box [i]'s optical normals can differ from
  /// its exact ones: in the square of a corner of the optical radius.
  bool inOpticalCorner(int i, double x, double y) {
    final hx = _data[i * 5 + 2];
    final hy = _data[i * 5 + 3];
    final optical = math.min(
      _data[i * 5 + 4] * morphOpticalCornerScale,
      math.min(hx, hy),
    );
    return (x - _data[i * 5]).abs() > hx - optical &&
        (y - _data[i * 5 + 1]).abs() > hy - optical;
  }

  /// The rotation from box [i]'s exact normal at (x, y) to its optical
  /// normal, the one a corner [morphOpticalCornerScale] times rounder
  /// gives, as (cos, sin) written into [out] at [at].
  void opticalTurn(int i, double x, double y, Float64List out, int at) {
    final hx = _data[i * 5 + 2];
    final hy = _data[i * 5 + 3];
    final half = math.min(hx, hy);
    final exact = _data[i * 5 + 4];
    final optical = math.min(exact * morphOpticalCornerScale, half);
    out[at] = 1;
    out[at + 1] = 0;
    if (optical <= exact) return;
    final px = x - _data[i * 5];
    final py = y - _data[i * 5 + 1];
    final ax = px.abs() - hx;
    final ay = py.abs() - hy;
    final ox = ax + optical;
    final oy = ay + optical;
    if (ox <= 0 || oy <= 0) return;
    final ex = ax + exact;
    final ey = ay + exact;
    double enx;
    double eny;
    if (ex > 0 && ey > 0) {
      final length = math.sqrt(ex * ex + ey * ey);
      enx = ex / length;
      eny = ey / length;
    } else if (ex > ey) {
      enx = 1;
      eny = 0;
    } else {
      enx = 0;
      eny = 1;
    }
    final length = math.sqrt(ox * ox + oy * oy);
    final onx = ox / length;
    final ony = oy / length;
    final mirrored = (px < 0) != (py < 0);
    out[at] = enx * onx + eny * ony;
    out[at + 1] = (enx * ony - eny * onx) * (mirrored ? -1 : 1);
  }
}

/// The signed distance of a rounded box from its corner-relative offsets
/// [qx], [qy] (the distance past the box's inner rectangle along each
/// axis) and its corner radius [r].
@internal
double morphBoxDistance(double qx, double qy, double r) {
  double outside;
  if (qx > 0) {
    outside = qy > 0 ? math.sqrt(qx * qx + qy * qy) : qx;
  } else {
    outside = qy > 0 ? qy : 0;
  }
  final inner = qx > qy ? qx : qy;
  return outside + (inner < 0 ? inner : 0) - r;
}

/// The outline traced from a trace grid and shaded from a field grid.
///
/// [trace] holds [cols] x [rows] nodes, node (i, j) at ([left] + i [step],
/// [top] + j [step]), negative inside; only its sign matters away from the
/// edge, and only cells of blocks flagged in [near] ([block] cells a side,
/// [blockCols] per row) can hold the edge. The field keeps
/// every [stride]th node: [distance], [halfMinor] and the optical turn
/// [turn] ((cos, sin) per node) on its own grid of `(cols - 1) ~/ stride
/// + 1` x `(rows - 1) ~/ stride + 1` nodes; its gradient is the central
/// difference of [distance], turned by [turn].
@internal
MorphGlassOutline morphGlassOutlineFromFields({
  required Float64List trace,
  required int cols,
  required int rows,
  required Uint8List near,
  required int blockCols,
  required int block,
  required Float64List distance,
  required Float64List halfMinor,
  required Float64List turn,
  required int stride,
  required double left,
  required double top,
  required double step,
}) {
  final fieldCols = (cols - 1) ~/ stride + 1;
  final fieldRows = (rows - 1) ~/ stride + 1;
  final fieldStep = step * stride;
  final samples = Float32List(fieldCols * fieldRows * 4);
  for (var j = 0; j < fieldRows; j++) {
    final up = j > 0 ? j - 1 : 0;
    final down = j < fieldRows - 1 ? j + 1 : fieldRows - 1;
    for (var i = 0; i < fieldCols; i++) {
      final back = i > 0 ? i - 1 : 0;
      final ahead = i < fieldCols - 1 ? i + 1 : fieldCols - 1;
      final at = j * fieldCols + i;
      final gx =
          (distance[j * fieldCols + ahead] - distance[j * fieldCols + back]) /
          ((ahead - back) * fieldStep);
      final gy =
          (distance[down * fieldCols + i] - distance[up * fieldCols + i]) /
          ((down - up) * fieldStep);
      final c = turn[at * 2];
      final s = turn[at * 2 + 1];
      final out = at * 4;
      samples[out] = distance[at];
      samples[out + 1] = gx * c - gy * s;
      samples[out + 2] = gx * s + gy * c;
      samples[out + 3] = halfMinor[at];
    }
  }
  final path = _OutlineTracer.trace(
    trace,
    cols,
    rows,
    near: near,
    blockCols: blockCols,
    block: block,
    left: left,
    top: top,
    step: step,
  );
  return MorphGlassOutline._(
    path,
    GlassField(
      samples: samples,
      cols: fieldCols,
      rows: fieldRows,
      origin: Offset(left, top),
      step: fieldStep,
      outline: path,
    ),
  );
}

/// Marching squares over the near blocks of a trace grid, stitched by the
/// grid edges the contour crosses and smoothed into the quadratic B-spline
/// through the crossings (the limit of Chaikin's corner cutting).
///
/// A saddle cell is resolved by the mean of its corners. The buffers live
/// across calls in [_TracerBuffers]: an outline is traced on the UI
/// thread, one at a time. They retain the largest traced grid until the
/// isolate exits. This tracer follows the sampled optical field's zero
/// contour; LiquidField's tracer evaluates an analytic mass field instead.
/// The B-spline uses the same Chaikin limit without repeated point lists.
class _OutlineTracer {
  factory _OutlineTracer(int edges) {
    final buffers = _TracerBuffers.claim(edges);
    return _OutlineTracer._(
      buffers.stamp,
      buffers.slot,
      buffers.generation,
      buffers.xs,
      buffers.ys,
      buffers.links,
      buffers.seen,
    );
  }

  _OutlineTracer._(
    this._stamp,
    this._slot,
    this._generation,
    this._xs,
    this._ys,
    this._links,
    this._seen,
  );

  final Int32List _stamp;
  final Int32List _slot;
  final int _generation;
  Float64List _xs;
  Float64List _ys;
  Int32List _links;
  Uint8List _seen;
  int _count = 0;

  static Path trace(
    Float64List values,
    int cols,
    int rows, {
    required Uint8List near,
    required int blockCols,
    required int block,
    required double left,
    required double top,
    required double step,
  }) {
    final horizontal = rows * (cols - 1);
    final tracer = _OutlineTracer(horizontal + (rows - 1) * cols);
    final blockRows = near.length ~/ blockCols;
    for (var bj = 0; bj < blockRows; bj++) {
      for (var bi = 0; bi < blockCols; bi++) {
        if (near[bj * blockCols + bi] == 0) continue;
        final jEnd = math.min(bj * block + block, rows - 1);
        final iEnd = math.min(bi * block + block, cols - 1);
        for (var j = bj * block; j < jEnd; j++) {
          final upper = j * cols;
          final lower = upper + cols;
          final y0 = top + j * step;
          for (var i = bi * block; i < iEnd; i++) {
            final tl = values[upper + i];
            final tr = values[upper + i + 1];
            final br = values[lower + i + 1];
            final bl = values[lower + i];
            final mask =
                (tl < 0 ? 8 : 0) |
                (tr < 0 ? 4 : 0) |
                (br < 0 ? 2 : 0) |
                (bl < 0 ? 1 : 0);
            if (mask == 0 || mask == 15) continue;
            final x0 = left + i * step;
            final eTop = j * (cols - 1) + i;
            final eLeft = horizontal + j * cols + i;
            final saddle = mask == 5 || mask == 10;
            final first = saddle && (tl + tr + br + bl < 0) == (mask == 5)
                ? 2
                : 0;
            final last = saddle ? first + 2 : 1;
            for (var k = first; k < last; k++) {
              final pair = saddle ? _saddlePairs[k] : _pairs[mask];
              tracer._link(
                tracer._edge(
                  pair >> 2,
                  eTop,
                  eLeft,
                  cols,
                  x0,
                  y0,
                  step,
                  tl,
                  tr,
                  br,
                  bl,
                ),
                tracer._edge(
                  pair & 3,
                  eTop,
                  eLeft,
                  cols,
                  x0,
                  y0,
                  step,
                  tl,
                  tr,
                  br,
                  bl,
                ),
              );
            }
          }
        }
      }
    }
    return tracer._stitch();
  }

  /// Per corner mask, the two crossed sides of a one-segment cell packed
  /// as `a << 2 | b` (sides: 0 top, 1 right, 2 bottom, 3 left).
  static const List<int> _pairs = [
    0,
    3 << 2 | 2,
    2 << 2 | 1,
    3 << 2 | 1,
    0 << 2 | 1,
    0,
    0 << 2 | 2,
    3 << 2 | 0,
    3 << 2 | 0,
    0 << 2 | 2,
    0,
    0 << 2 | 1,
    3 << 2 | 1,
    2 << 2 | 1,
    3 << 2 | 2,
    0,
  ];

  /// The two ways through a saddle cell: the first two pairs keep the
  /// inside corners apart, the last two join them through the center.
  static const List<int> _saddlePairs = [
    3 << 2 | 2,
    0 << 2 | 1,
    3 << 2 | 0,
    2 << 2 | 1,
  ];

  int _edge(
    int side,
    int eTop,
    int eLeft,
    int cols,
    double x0,
    double y0,
    double step,
    double tl,
    double tr,
    double br,
    double bl,
  ) => switch (side) {
    0 => _crossing(eTop, x0, y0, tl, x0 + step, y0, tr),
    1 => _crossing(eLeft + 1, x0 + step, y0, tr, x0 + step, y0 + step, br),
    2 => _crossing(
      eTop + cols - 1,
      x0,
      y0 + step,
      bl,
      x0 + step,
      y0 + step,
      br,
    ),
    _ => _crossing(eLeft, x0, y0, tl, x0, y0 + step, bl),
  };

  int _crossing(
    int edge,
    double x0,
    double y0,
    double v0,
    double x1,
    double y1,
    double v1,
  ) {
    if (_stamp[edge] == _generation) return _slot[edge];
    final slot = _count++;
    if (slot >= _xs.length) _grow();
    _stamp[edge] = _generation;
    _slot[edge] = slot;
    final denom = v0 - v1;
    var t = denom.abs() < 1e-6 ? 0.5 : v0 / denom;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    _xs[slot] = x0 + (x1 - x0) * t;
    _ys[slot] = y0 + (y1 - y0) * t;
    _links[slot * 2] = -1;
    _links[slot * 2 + 1] = -1;
    _seen[slot] = 0;
    return slot;
  }

  void _grow() {
    _TracerBuffers.grow();
    _xs = _TracerBuffers.xs;
    _ys = _TracerBuffers.ys;
    _links = _TracerBuffers.links;
    _seen = _TracerBuffers.seen;
  }

  void _link(int a, int b) {
    if (_links[a * 2] < 0) {
      _links[a * 2] = b;
    } else {
      _links[a * 2 + 1] = b;
    }
    if (_links[b * 2] < 0) {
      _links[b * 2] = a;
    } else {
      _links[b * 2 + 1] = a;
    }
  }

  Path _stitch() {
    final path = Path();
    path.fillType = PathFillType.evenOdd;
    final loop = <int>[];
    for (var start = 0; start < _count; start++) {
      if (_seen[start] != 0) continue;
      loop.clear();
      var current = start;
      while (current >= 0 && _seen[current] == 0) {
        _seen[current] = 1;
        loop.add(current);
        final a = _links[current * 2];
        final b = _links[current * 2 + 1];
        current = a >= 0 && _seen[a] == 0
            ? a
            : b >= 0 && _seen[b] == 0
            ? b
            : -1;
      }
      final n = loop.length;
      if (n < 3) continue;
      final last = loop[n - 1];
      final first = loop[0];
      path.moveTo((_xs[last] + _xs[first]) / 2, (_ys[last] + _ys[first]) / 2);
      for (var k = 0; k < n; k++) {
        final p = loop[k];
        final q = loop[k + 1 < n ? k + 1 : 0];
        path.quadraticBezierTo(
          _xs[p],
          _ys[p],
          (_xs[p] + _xs[q]) / 2,
          (_ys[p] + _ys[q]) / 2,
        );
      }
      path.close();
    }
    return path;
  }
}

/// The buffers of [_OutlineTracer], kept across calls: per grid edge the
/// generation it was last crossed in and its crossing's slot, per slot
/// the crossing and its two neighbours along the contour.
abstract final class _TracerBuffers {
  static Int32List stamp = Int32List(0);
  static Int32List slot = Int32List(0);
  static int generation = 0;
  static Float64List xs = Float64List(256);
  static Float64List ys = Float64List(256);
  static Int32List links = Int32List(512);
  static Uint8List seen = Uint8List(256);

  /// Readies the buffers for a grid of [edges] edges and starts a new
  /// generation.
  static ({
    Int32List stamp,
    Int32List slot,
    int generation,
    Float64List xs,
    Float64List ys,
    Int32List links,
    Uint8List seen,
  })
  claim(int edges) {
    if (stamp.length < edges) {
      stamp = Int32List(edges + edges ~/ 2);
      slot = Int32List(stamp.length);
      generation = 0;
    }
    generation++;
    if (generation == 0x3FFFFFFF) {
      stamp.fillRange(0, stamp.length, 0);
      generation = 1;
    }
    return (
      stamp: stamp,
      slot: slot,
      generation: generation,
      xs: xs,
      ys: ys,
      links: links,
      seen: seen,
    );
  }

  /// Doubles the per-slot buffers, keeping their contents.
  static void grow() {
    final size = xs.length * 2;
    final nextXs = Float64List(size);
    nextXs.setAll(0, xs);
    xs = nextXs;
    final nextYs = Float64List(size);
    nextYs.setAll(0, ys);
    ys = nextYs;
    final nextLinks = Int32List(size * 2);
    nextLinks.setAll(0, links);
    links = nextLinks;
    final nextSeen = Uint8List(size);
    nextSeen.setAll(0, seen);
    seen = nextSeen;
  }
}

/// Within this much of the spacing the merge moves an outline by less than
/// a hundredth of a point, so surfaces whose layout lands a rounding error
/// under the spacing keep their own shapes.
const double _fusionSlack = 0.5;

/// The grid step of a container's fused outline, in logical pixels.
const double _fusionStep = 2;

/// The groups of [shapes] a glass container with [spacing] fuses: shapes
/// closer than the spacing (less a rounding slack) to a member of a group
/// belong to it. A group of one is a shape the container leaves alone.
@internal
List<List<int>> morphGlassContainerGroups(List<RRect> shapes, double spacing) {
  if (spacing <= _fusionSlack || shapes.length < 2) {
    return [
      for (var i = 0; i < shapes.length; i++) [i],
    ];
  }
  final labels = liquidConnectivityLabels([
    for (final shape in shapes) shape.outerRect,
  ], spacing - _fusionSlack);
  final groups = <int, List<int>>{};
  for (var i = 0; i < shapes.length; i++) {
    (groups[labels[i]] ??= []).add(i);
  }
  return [
    for (final group in groups.values)
      if (group.length < 2 ||
          _fuses([for (final i in group) shapes[i]], spacing))
        group
      else
        for (final i in group) [i],
  ];
}

bool _fuses(List<RRect> group, double spacing) {
  for (var i = 0; i < group.length; i++) {
    for (var j = i + 1; j < group.length; j++) {
      if (liquidRectGap(group[i].outerRect, group[j].outerRect) <
          spacing - _fusionSlack) {
        return true;
      }
    }
  }
  return false;
}

/// The last four outlines retained by the isolate, newest last.
final List<(List<RRect>, double, MorphGlassOutline)> _recentOutlines = [];

/// The outline a glass container with [spacing] fuses [shapes] into, by
/// the skin's merge law ([LiquidField] with blend [spacing], 1:1 the
/// container spacing of UIKit's `UIGlassContainerEffect`).
///
/// The last few outlines are remembered, so a layer that rebuilds without
/// its shapes moving does not fuse them again. Shapes must have uniform
/// circular corner radii; non-uniform corners are rejected in debug builds.
@internal
MorphGlassOutline morphGlassContainerOutline(
  List<RRect> shapes,
  double spacing,
) {
  for (final (recent, recentSpacing, outline) in _recentOutlines) {
    if (recentSpacing == spacing && listEquals(recent, shapes)) return outline;
  }
  final outline = _fuseContainer(shapes, spacing);
  _recentOutlines.add((List.of(shapes), spacing, outline));
  if (_recentOutlines.length > 4) _recentOutlines.removeAt(0);
  return outline;
}

/// Samples the merge law only where the edge can be: the plain minimum of
/// the boxes bounds the merged field (it lies between the minimum less a
/// quarter of the spacing per merge and the minimum), so a block whose
/// corners keep the minimum clear of that range by more than the block's
/// reach holds no edge; the field grid is sampled everywhere.
MorphGlassOutline _fuseContainer(List<RRect> shapes, double spacing) {
  const step = _fusionStep;
  const stride = 2;
  const b = 4;
  final boxes = MorphOutlineBoxes(shapes);
  final sample = liquidFieldSampler(
    LiquidField([
      for (final shape in shapes)
        MorphMass.box(shape.outerRect, radius: _radius(shape)),
    ], k: spacing),
  );
  var area = shapes.first.outerRect;
  for (final shape in shapes.skip(1)) {
    area = area.expandToInclude(shape.outerRect);
  }
  area = area.inflate(spacing + 2 * step);
  final cols = ((area.width / step).ceil() ~/ b) * b + b + 1;
  final rows = ((area.height / step).ceil() ~/ b) * b + b + 1;
  final fieldCols = (cols - 1) ~/ stride + 1;
  final fieldRows = (rows - 1) ~/ stride + 1;
  final trace = Float64List(cols * rows);
  final minimum = Float64List(fieldCols * fieldRows);
  final distance = Float64List(fieldCols * fieldRows);
  final halfMinor = Float64List(fieldCols * fieldRows);
  final turn = Float64List(fieldCols * fieldRows * 2);
  final fold = Float64List(2);
  final turns = [for (var i = 0; i < boxes.length; i++) boxes.turns(i)];
  for (var fj = 0; fj < fieldRows; fj++) {
    final y = area.top + fj * stride * step;
    for (var fi = 0; fi < fieldCols; fi++) {
      final x = area.left + fi * stride * step;
      final at = fj * fieldCols + fi;
      var d = boxes.distance(0, x, y);
      var m = d;
      var half = boxes.halfMinor(0);
      var turned = turns[0] && boxes.inOpticalCorner(0, x, y);
      if (turned) {
        boxes.opticalTurn(0, x, y, turn, at * 2);
      } else {
        turn[at * 2] = 1;
      }
      for (var i = 1; i < boxes.length; i++) {
        final di = boxes.distance(i, x, y);
        final share = 0.5 + (di - d) / (2 * spacing);
        final w = share < 0
            ? 0.0
            : share > 1
            ? 1.0
            : share;
        half = boxes.halfMinor(i) + (half - boxes.halfMinor(i)) * w;
        if (turns[i] && boxes.inOpticalCorner(i, x, y)) {
          boxes.opticalTurn(i, x, y, fold, 0);
          turned = true;
        } else {
          fold[0] = 1;
          fold[1] = 0;
        }
        if (turned) {
          turn[at * 2] = fold[0] + (turn[at * 2] - fold[0]) * w;
          turn[at * 2 + 1] = fold[1] + (turn[at * 2 + 1] - fold[1]) * w;
        }
        final e = math.max(spacing - (d - di).abs(), 0.0);
        d = math.min(d, di) - e * e / (4 * spacing);
        m = math.min(m, di);
      }
      if (turned) morphNormalizeTurn(turn, at * 2);
      final value = sample(x, y);
      distance[at] = value;
      minimum[at] = m;
      halfMinor[at] = half;
      trace[fj * stride * cols + fi * stride] = value;
    }
  }
  final blockCols = (cols - 1) ~/ b;
  final blockRows = (rows - 1) ~/ b;
  final near = Uint8List(blockCols * blockRows);
  final reach = b * step * math.sqrt1_2 + step;
  final depth = (shapes.length - 1) * spacing / 4 + step;
  const span = b ~/ stride;
  for (var bj = 0; bj < blockRows; bj++) {
    for (var bi = 0; bi < blockCols; bi++) {
      final corner = bj * span * fieldCols + bi * span;
      final a = minimum[corner];
      final b2 = minimum[corner + span];
      final c = minimum[corner + span * fieldCols];
      final d = minimum[corner + span * fieldCols + span];
      final lo = math.min(math.min(a, b2), math.min(c, d));
      final hi = math.max(math.max(a, b2), math.max(c, d));
      if (hi + reach >= 0 && lo - reach <= depth) {
        near[bj * blockCols + bi] = 1;
        for (var j = bj * b; j <= bj * b + b; j++) {
          final y = area.top + j * step;
          for (var i = bi * b; i <= bi * b + b; i++) {
            if (i % stride == 0 && j % stride == 0) continue;
            trace[j * cols + i] = sample(area.left + i * step, y);
          }
        }
      }
    }
  }
  return morphGlassOutlineFromFields(
    trace: trace,
    cols: cols,
    rows: rows,
    near: near,
    blockCols: blockCols,
    block: b,
    distance: distance,
    halfMinor: halfMinor,
    turn: turn,
    stride: stride,
    left: area.left,
    top: area.top,
    step: step,
  );
}

/// Normalizes the (cos, sin) pair at [at], blended from several turns.
@internal
void morphNormalizeTurn(Float64List turn, int at) {
  final c = turn[at];
  final s = turn[at + 1];
  final length = math.sqrt(c * c + s * s);
  if (length < 1e-9) {
    turn[at] = 1;
    turn[at + 1] = 0;
  } else {
    turn[at] = c / length;
    turn[at + 1] = s / length;
  }
}

double _radius(RRect shape) {
  _requireUniform(shape);
  return math.min(shape.tlRadiusX, shape.outerRect.shortestSide / 2);
}

void _requireUniform(RRect shape) {
  assert(
    shape.tlRadiusX == shape.tlRadiusY &&
        shape.tlRadius == shape.trRadius &&
        shape.tlRadius == shape.blRadius &&
        shape.tlRadius == shape.brRadius,
    'Glass distance fields require uniform circular corner radii.',
  );
}

/// Clips a shaded body to the package's outline path.
@internal
class MorphGlassOutlineClip extends CustomClipper<Path> {
  /// Creates a clip for [path].
  const MorphGlassOutlineClip(this.path);

  /// The body outline in the layer's coordinates.
  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(MorphGlassOutlineClip oldClipper) =>
      oldClipper.path != path;
}
