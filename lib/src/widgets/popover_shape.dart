import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/widgets/alert_motion.dart';
import 'package:morph/src/widgets/glass_outline.dart';

/// The outline of an iOS 27 popover: its content box and its arrow as one
/// shape, the path UIKit's popover chrome draws and shades as one glass
/// (read from UIKit, notes private).
///
/// The arrow is [MorphPopoverTuning.arrowBase] wide where its sides meet
/// the content's edge and [MorphPopoverTuning.arrowLength] long. Each side
/// leaves the edge through a fillet that starts
/// [MorphPopoverTuning.arrowFilletReach] outside the base, runs straight
/// to within 2 of the axis and 1 of the tip, and the tip is one cubic
/// whose controls both sit on the tip. The corners are continuous, Apple's
/// three-cubic corner; their radius is [MorphPopoverTuning.cornerRadius],
/// less on a popover too small to hold it, and a corner next to the arrow
/// ends at least [MorphPopoverTuning.arrowCornerGap] short of the arrow's
/// center.
///
/// Both tiers draw [path]; the liquid tier shades the shape from the
/// distance field of [outline], so the arrow is the body's own glass, edge
/// light and refraction included, as UIKit's one SDF element is. The field
/// is NEAR, invisible: sampled every [fieldStep], it rounds the tip 0.2 pt
/// short of [path], and deeper than 32 pt above the arrow it holds the
/// nearest straight edge or fillet start, at most 1.2 pt off where the
/// glass reads only its sign.
@internal
class MorphPopoverShape {
  /// The shape of a popover whose content box is [content] and whose
  /// arrow, on the edge [direction] names, is centered at [arrowCenter]
  /// along that edge, in the same coordinates.
  MorphPopoverShape({
    required this.content,
    required this.direction,
    required this.arrowCenter,
  });

  /// The content box, without the arrow.
  final Rect content;

  /// The edge the arrow sits on.
  final MorphPopoverArrowDirection direction;

  /// The arrow's center along its edge.
  final double arrowCenter;

  /// The distance between the nodes of the shape's distance field, in
  /// logical pixels.
  ///
  /// The renderer interpolates the field bilinearly between nodes, which
  /// rounds the liquid tier's arrow tip 0.2 pt short of [path] at this
  /// step (0.07 pt at 1, for four times the nodes): NEAR, invisible. The
  /// field of a 240 x 264 popover then takes 0.4 ms to sample on a Mac.
  static const double fieldStep = 2;

  // The field reaches this far past the shape: two nodes and the glass's
  // contour band.
  static const double _fieldMargin = 4;

  /// The box of the content and the arrow.
  Rect get bounds => content.expandToInclude(arrowBox);

  late final _Trace _trace = _Trace.of(this);

  /// The edge of the shape.
  Path get path => _trace.path;

  /// The rounded box nearest the content's own shape: the content box with
  /// the radius of its corners away from the arrow.
  RRect get body =>
      RRect.fromRectAndRadius(content, Radius.circular(_trace.radius));

  /// The box the arrow occupies, for a glass surface that marks the
  /// arrow's part of the body.
  Rect get arrowBox => _trace.arrowBox;

  /// The shape as one glass body: with its distance field for a renderer
  /// that shades it ([shaded]), its edge alone otherwise.
  ///
  /// The last shaded shapes keep their outline, so a popover shown again
  /// where it was neither samples nor uploads its field again.
  MorphGlassOutline outline({required bool shaded}) {
    if (!shaded) return _plain ??= MorphGlassOutline(path);
    final kept = _shaded;
    if (kept != null) return kept;
    for (final shape in _recent) {
      if (shape == this) return _shaded = shape._shaded!;
    }
    final outline = _shaded = morphGlassOutlineOfField(path, _trace.field());
    _recent.insert(0, this);
    if (_recent.length > 2) _recent.removeLast();
    return outline;
  }

  static final List<MorphPopoverShape> _recent = [];

  MorphGlassOutline? _shaded;
  MorphGlassOutline? _plain;

  @override
  bool operator ==(Object other) =>
      other is MorphPopoverShape &&
      other.content == content &&
      other.direction == direction &&
      other.arrowCenter == arrowCenter;

  @override
  int get hashCode => Object.hash(content, direction, arrowCenter);
}

// Apple's continuous corner, in multiples of its radius: how far along each
// edge it reaches, and the controls and end of each of its three cubics as
// (along the edge it leaves, along the edge it joins).
const double _cornerExtent = 1.528665;
const List<double> _cornerCubics = [
  1.088494, 0, 0.868406, 0, 0.631494, 0.074912, //
  0.372824, 0.169059, 0.169059, 0.372824, 0.074912, 0.631494, //
  0, 0.868406, 0, 1.088494, 0, _cornerExtent,
];

// The segments each cubic is flattened into for the distance field, at
// most 0.03 pt from the curve: a corner's middle cubic turns, its ends
// barely do.
const List<int> _cornerSteps = [4, 12, 4];
const int _arrowSteps = 8;

// How deep into the content the arrow is measured exactly. Deeper, the
// field takes the nearest straight edge or fillet start, 1.2 pt farther
// than the arrow at most, where the glass reads nothing of the field but
// its sign: its bevel is 20 deep, its glint and bevel shadow less.
const double _arrowDepth = 32;

/// The shape traced once, in a frame where the arrow hangs from the bottom
/// edge of a `w` x `h` box at `c`: the exact path mapped onto the shape's
/// own edge, and the edge flattened for its distance field.
class _Trace {
  _Trace._(this._direction, this._content, this._w, this._h, this._c);

  factory _Trace.of(MorphPopoverShape shape) {
    final content = shape.content;
    final vertical =
        shape.direction == MorphPopoverArrowDirection.down ||
        shape.direction == MorphPopoverArrowDirection.up;
    final trace = _Trace._(
      shape.direction,
      content,
      vertical ? content.width : content.height,
      vertical ? content.height : content.width,
      vertical
          ? shape.arrowCenter - content.left
          : shape.arrowCenter - content.top,
    );
    trace._draw();
    return trace;
  }

  final MorphPopoverArrowDirection _direction;
  final Rect _content;
  final double _w;
  final double _h;
  final double _c;

  final Path path = Path();

  // The flattened edge in the drawing frame, start x, start y, end x, end
  // y per segment: the whole loop, the arrow's run and each corner's run.
  final List<double> _loop = [];
  final List<double> _arrowRun = [];
  final List<List<double>> _cornerRuns = [];

  // The extent of the top corners and of the bottom corners left and
  // right of the arrow.
  late double _full;
  late double _low;
  late double _high;

  late double radius;

  late Rect arrowBox;

  double _x = 0;
  double _y = 0;

  Offset _map(double x, double y) {
    final l = _content.left;
    final t = _content.top;
    return switch (_direction) {
      MorphPopoverArrowDirection.down => Offset(l + x, t + y),
      MorphPopoverArrowDirection.up => Offset(l + x, t + _h - y),
      MorphPopoverArrowDirection.left => Offset(l + _h - y, t + x),
      MorphPopoverArrowDirection.right => Offset(l + y, t + x),
    };
  }

  void _draw() {
    const base = MorphPopoverTuning.arrowBase / 2;
    const reach = base + MorphPopoverTuning.arrowFilletReach;
    const length = MorphPopoverTuning.arrowLength;
    const gap = MorphPopoverTuning.arrowCornerGap;
    final w = _w;
    final h = _h;
    final c = _c;
    // A popover too small for the radius takes the corner that fits half
    // the shorter side of its box with the arrow.
    radius = math.min(
      MorphPopoverTuning.cornerRadius,
      math.min(w, h + length) / 2 / _cornerExtent,
    );
    _full = radius * _cornerExtent;
    _low = math.min(_full, c - gap);
    _high = math.min(_full, w - c - gap);
    final start = _map(c - reach, h);
    path.moveTo(start.dx, start.dy);
    _x = c - reach;
    _y = h;
    // Each fillet bends over two thirds of the run from its start to the
    // side's end and half the rise, its controls a third along the edge.
    _cubic(c - base, h, c - base, h, c - 7.5, h + 6, _arrowRun, _arrowSteps);
    _line(c - 2, h + length - 1, _arrowRun);
    _cubic(
      c,
      h + length,
      c,
      h + length,
      c + 2,
      h + length - 1,
      _arrowRun,
      _arrowSteps,
    );
    _line(c + 7.5, h + 6, _arrowRun);
    _cubic(c + base, h, c + base, h, c + reach, h, _arrowRun, _arrowSteps);
    _line(w - _high, h, null);
    _corner(w, h, -1, 0, 0, -1, _high);
    _line(w, _full, null);
    _corner(w, 0, 0, 1, -1, 0, _full);
    _line(_full, 0, null);
    _corner(0, 0, 1, 0, 0, 1, _full);
    _line(0, h - _low, null);
    _corner(0, h, 0, -1, 1, 0, _low);
    _line(c - reach, h, null);
    path.close();
    arrowBox = Rect.fromPoints(_map(c - reach, h), _map(c + reach, h + length));
  }

  // A continuous corner whose tip is (kx, ky): it leaves the edge along
  // (ux, uy) from the tip and joins the edge along (vx, vy), reaching
  // [extent] along each.
  void _corner(
    double kx,
    double ky,
    double ux,
    double uy,
    double vx,
    double vy,
    double extent,
  ) {
    final r = extent / _cornerExtent;
    final run = <double>[];
    _cornerRuns.add(run);
    double x(int i) =>
        kx + (ux * _cornerCubics[i] + vx * _cornerCubics[i + 1]) * r;
    double y(int i) =>
        ky + (uy * _cornerCubics[i] + vy * _cornerCubics[i + 1]) * r;
    for (var k = 0; k < 3; k++) {
      final i = k * 6;
      _cubic(
        x(i),
        y(i),
        x(i + 2),
        y(i + 2),
        x(i + 4),
        y(i + 4),
        run,
        _cornerSteps[k],
      );
    }
  }

  void _line(double x, double y, List<double>? run) {
    final to = _map(x, y);
    path.lineTo(to.dx, to.dy);
    _segment(x, y, run);
  }

  void _cubic(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
    List<double> run,
    int steps,
  ) {
    final p1 = _map(x1, y1);
    final p2 = _map(x2, y2);
    final p3 = _map(x3, y3);
    path.cubicTo(p1.dx, p1.dy, p2.dx, p2.dy, p3.dx, p3.dy);
    final x0 = _x;
    final y0 = _y;
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final s = 1 - t;
      final a = s * s * s;
      final b = 3 * s * s * t;
      final c = 3 * s * t * t;
      final d = t * t * t;
      _segment(
        a * x0 + b * x1 + c * x2 + d * x3,
        a * y0 + b * y1 + c * y2 + d * y3,
        run,
      );
    }
  }

  void _segment(double x, double y, List<double>? run) {
    if (x == _x && y == _y) return;
    final segment = [_x, _y, x, y];
    _loop.addAll(segment);
    run?.addAll(segment);
    _x = x;
    _y = y;
  }

  /// The signed distance field of the edge, sampled every
  /// [MorphPopoverShape.fieldStep] over the shape and a margin.
  ///
  /// Each node holds the distance to the edge, negative inside; its
  /// gradient by central differences, turned as the renderer turns a
  /// rounded box's normals near its corners ([morphOpticalCornerScale])
  /// wherever the arrow is not the nearest part; and the half thickness of
  /// the content.
  ///
  /// The straight parts of the edge are measured directly, a corner only
  /// within its square (from the segment nearest the previous node on
  /// along the curve), and the arrow segment by segment near it.
  GlassField field() {
    const step = MorphPopoverShape.fieldStep;
    const margin = MorphPopoverShape._fieldMargin;
    const reach =
        MorphPopoverTuning.arrowBase / 2 + MorphPopoverTuning.arrowFilletReach;
    final w = _w;
    final h = _h;
    final c = _c;
    final full = _full;
    final low = _low;
    final high = _high;
    final x0 = -(margin / step).ceil() * step;
    final y0 = x0;
    final cols = ((w + margin - x0) / step).ceil() + 1;
    final rows =
        ((h + MorphPopoverTuning.arrowLength + margin - y0) / step).ceil() + 1;
    final loop = Float64List.fromList(_loop);
    final arrow = Float64List.fromList(_arrowRun);
    final corners = [for (final run in _cornerRuns) Float64List.fromList(run)];
    // Each corner's square, which no other part of the edge reaches into
    // past a straight edge, as left, top, right, bottom.
    final squares = [
      Float64List.fromList([w - high, h - high, w, h]),
      Float64List.fromList([w - full, 0, w, full]),
      Float64List.fromList([0, 0, full, full]),
      Float64List.fromList([0, h - low, low, h]),
    ];
    final nearest = List<int>.filled(4, 0);
    final distance = Float64List(cols * rows);
    final fromArrow = Uint8List(cols * rows);
    final crossings = <double>[];
    final segments = loop.length ~/ 4;
    final bottomLeft = (math.min(low, c - reach), math.max(low, c - reach));
    final bottomRight = (
      math.min(c + reach, w - high),
      math.max(c + reach, w - high),
    );
    for (var j = 0; j < rows; j++) {
      final y = y0 + j * step;
      crossings.clear();
      for (var s = 0; s < segments; s++) {
        final ay = loop[s * 4 + 1];
        final by = loop[s * 4 + 3];
        if ((ay > y) == (by > y)) continue;
        final ax = loop[s * 4];
        crossings.add(ax + (y - ay) * (loop[s * 4 + 2] - ax) / (by - ay));
      }
      crossings.sort();
      var next = 0;
      var inside = false;
      for (var i = 0; i < cols; i++) {
        final x = x0 + i * step;
        while (next < crossings.length && crossings[next] < x) {
          inside = !inside;
          next++;
        }
        var best = _across(x, full, w - full, y);
        best = math.min(best, _across(y, full, h - high, x - w));
        best = math.min(best, _across(y, full, h - low, x));
        best = math.min(best, _across(x, bottomLeft.$1, bottomLeft.$2, y - h));
        best = math.min(
          best,
          _across(x, bottomRight.$1, bottomRight.$2, y - h),
        );
        for (var k = 0; k < 4; k++) {
          final square = squares[k];
          if (x < square[0] - margin ||
              x > square[2] + margin ||
              y < square[1] - margin ||
              y > square[3] + margin) {
            continue;
          }
          final run = corners[k];
          var at = nearest[k];
          var d = _distance2(run, at, x, y);
          final last = run.length ~/ 4 - 1;
          while (at > 0) {
            final e = _distance2(run, at - 1, x, y);
            if (e >= d) break;
            d = e;
            at--;
          }
          while (at < last) {
            final e = _distance2(run, at + 1, x, y);
            if (e >= d) break;
            d = e;
            at++;
          }
          nearest[k] = at;
          best = math.min(best, d);
        }
        var fromTheArrow = false;
        if ((x - c).abs() <= reach + margin && y >= h - _arrowDepth) {
          for (var s = 0; s < arrow.length ~/ 4; s++) {
            final d = _distance2(arrow, s, x, y);
            if (d < best) {
              best = d;
              fromTheArrow = true;
            }
          }
        }
        final d = math.sqrt(best);
        final at = j * cols + i;
        distance[at] = inside ? -d : d;
        if (fromTheArrow) fromArrow[at] = 1;
      }
    }
    return _sample(distance, fromArrow, cols, rows, x0, y0);
  }

  // The squared distance from a point to a segment along one axis: the
  // point is [along] on that axis, the segment spans [from] to [to], and
  // [off] is the point's distance from the segment's line.
  static double _across(double along, double from, double to, double off) {
    final d = along < from
        ? from - along
        : along > to
        ? along - to
        : 0.0;
    return d * d + off * off;
  }

  // Writes the field of the drawing frame's grid, nodes at (x0, y0) plus
  // multiples of the step, onto the shape's own axes.
  GlassField _sample(
    Float64List distance,
    Uint8List fromArrow,
    int cols,
    int rows,
    double x0,
    double y0,
  ) {
    const step = MorphPopoverShape.fieldStep;
    final content = _content;
    final halfMinor = content.shortestSide / 2;
    final center = content.center;
    // The rounded box whose optical corner each quadrant of the content
    // turns its normals by: left top, right top, left bottom, right
    // bottom.
    final radii = List<double>.filled(4, radius);
    for (final (x, y, extent) in [(_w, _h, _high), (0.0, _h, _low)]) {
      final corner = _map(x, y);
      radii[(corner.dx < center.dx ? 0 : 1) + (corner.dy < center.dy ? 0 : 2)] =
          extent / _cornerExtent;
    }
    final boxes = <double, MorphOutlineBoxes>{};
    final quadrants = [
      for (final r in radii)
        boxes[r] ??= MorphOutlineBoxes([
          RRect.fromRectAndRadius(content, Radius.circular(r)),
        ]),
    ];
    final vertical =
        _direction == MorphPopoverArrowDirection.down ||
        _direction == MorphPopoverArrowDirection.up;
    final outCols = vertical ? cols : rows;
    final outRows = vertical ? rows : cols;
    final near = _map(x0, y0);
    final far = _map(x0 + (cols - 1) * step, y0 + (rows - 1) * step);
    final left = math.min(near.dx, far.dx);
    final top = math.min(near.dy, far.dy);
    // Where node (i, j) of the drawing frame lands, as column and row
    // offsets per step of i and of j, and how its gradient turns.
    final (
      int ci,
      int cj,
      int c0,
      int ri,
      int rj,
      int r0,
    ) = switch (_direction) {
      MorphPopoverArrowDirection.down => (1, 0, 0, 0, 1, 0),
      MorphPopoverArrowDirection.up => (1, 0, 0, 0, -1, rows - 1),
      MorphPopoverArrowDirection.left => (0, -1, rows - 1, 1, 0, 0),
      MorphPopoverArrowDirection.right => (0, 1, 0, 1, 0, 0),
    };
    final (double xx, double xy, double yx, double yy) = switch (_direction) {
      MorphPopoverArrowDirection.down => (1, 0, 0, 1),
      MorphPopoverArrowDirection.up => (1, 0, 0, -1),
      MorphPopoverArrowDirection.left => (0, -1, 1, 0),
      MorphPopoverArrowDirection.right => (0, 1, 1, 0),
    };
    final turn = Float64List(2);
    final samples = Float32List(cols * rows * 4);
    for (var j = 0; j < rows; j++) {
      final up = j > 0 ? j - 1 : 0;
      final down = j < rows - 1 ? j + 1 : rows - 1;
      for (var i = 0; i < cols; i++) {
        final back = i > 0 ? i - 1 : 0;
        final ahead = i < cols - 1 ? i + 1 : cols - 1;
        final at = j * cols + i;
        final gx =
            (distance[j * cols + ahead] - distance[j * cols + back]) /
            ((ahead - back) * step);
        final gy =
            (distance[down * cols + i] - distance[up * cols + i]) /
            ((down - up) * step);
        var rx = xx * gx + xy * gy;
        var ry = yx * gx + yy * gy;
        final oi = c0 + ci * i + cj * j;
        final oj = r0 + ri * i + rj * j;
        if (fromArrow[at] == 0) {
          final x = left + oi * step;
          final y = top + oj * step;
          final boxes =
              quadrants[(x < center.dx ? 0 : 1) + (y < center.dy ? 0 : 2)];
          if (boxes.inOpticalCorner(0, x, y)) {
            boxes.opticalTurn(0, x, y, turn, 0);
            final cos = turn[0];
            final sin = turn[1];
            final tx = rx * cos - ry * sin;
            ry = rx * sin + ry * cos;
            rx = tx;
          }
        }
        final out = (oj * outCols + oi) * 4;
        samples[out] = distance[at];
        samples[out + 1] = rx;
        samples[out + 2] = ry;
        samples[out + 3] = halfMinor;
      }
    }
    return GlassField(
      samples: samples,
      cols: outCols,
      rows: outRows,
      origin: Offset(left, top),
      step: step,
      outline: path,
    );
  }
}

@pragma('vm:prefer-inline')
double _distance2(Float64List segments, int s, double x, double y) {
  final ax = segments[s * 4];
  final ay = segments[s * 4 + 1];
  final dx = segments[s * 4 + 2] - ax;
  final dy = segments[s * 4 + 3] - ay;
  final px = x - ax;
  final py = y - ay;
  final length = dx * dx + dy * dy;
  var t = length == 0 ? 0.0 : (px * dx + py * dy) / length;
  if (t < 0) {
    t = 0;
  } else if (t > 1) {
    t = 1;
  }
  final ex = px - t * dx;
  final ey = py - t * dy;
  return ex * ex + ey * ey;
}
