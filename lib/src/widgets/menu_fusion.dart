import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:morph/src/widgets/glass_outline.dart';

/// The silhouette of a menu morph: its two shapes fused the way UIKit's
/// morph container fuses them.
///
/// The container is one SDF layer whose elements, the menu shape and the
/// button shape, are united by a plain minimum (its smoothness is 0) and
/// whose distance field is blurred by a Gaussian of standard deviation
/// `MorphMenuMotion.fusionRadius`. The blur pulls the facing edges into
/// points and joins the shapes by a neck while they are within a few
/// radii of each other; it also rounds and narrows each shape a little,
/// by about `radius^2 / (2 r)` on an edge of curvature radius `r`. Below
/// [minimumRadius] the blur moves no edge by more than a few hundredths
/// of a point and the silhouette is the plain union of the two shapes.
///
/// The fused outline is traced on a grid whose step grows with the
/// radius (a blurred field varies no faster than its blur), and the blur
/// is evaluated only near the edge: a blur of standard deviation `s`
/// moves a distance field by at most `1.26 s`, so farther from the edge
/// the sign, all the trace needs, is the unblurred one; inside the body
/// the blur reaches [shadedDepth] deeper, as far as a renderer shades
/// it. The last outline is reused while its inputs do not change.
@internal
class MorphMenuFusion {
  /// The radius below which the silhouette is the plain union.
  static const double minimumRadius = 1;

  /// How deep inside the body the field stays blurred at least, in
  /// logical pixels (the trace itself needs only the band near the edge).
  ///
  /// A renderer bends light by the field's distance and normal within its
  /// bevel (20 points deep on the iOS 27 presets); farther in, the face is
  /// flat and only the sign matters. Blurring that deep keeps the field
  /// continuous wherever a renderer reads more than its sign.
  static const double shadedDepth = 24;

  RRect? _menu;
  RRect? _source;
  double _radius = 0;
  MorphGlassOutline? _outline;

  /// The fused outline of [menu] and [source] blurred by [radius], or
  /// null when [radius] is under [minimumRadius] and the silhouette is
  /// their plain union.
  MorphGlassOutline? outline(RRect menu, RRect source, double radius) {
    if (radius < minimumRadius) return null;
    if (menu == _menu && source == _source && radius == _radius) {
      return _outline;
    }
    _menu = menu;
    _source = source;
    _radius = radius;
    return _outline = morphMenuSilhouette(menu, source, radius);
  }
}

/// The union of [menu] and [source] whose signed distance field is
/// blurred by a Gaussian of standard deviation [radius]: its zero contour
/// as one even-odd path, with the blurred field itself for a renderer that
/// shades the body.
///
/// The half thickness each node of the field belongs to, and the turn of
/// its normal toward the optical corners of the shapes, blend from the
/// button's to the menu's over the blur radius, by which of the two shapes
/// is nearer.
///
/// The field grid (every second trace node below a 4 pt step) is sampled
/// everywhere; the trace grid only in blocks whose corners leave the edge
/// within reach. A node whose blur window sees one straight side of one
/// shape takes its unblurred distance: the kernel is symmetric, so it
/// leaves a linear field unchanged.
@internal
MorphGlassOutline morphMenuSilhouette(RRect menu, RRect source, double radius) {
  final double step = (radius / 3).clamp(2.0, 6.0);
  final int stride = step < 4 ? 2 : 1;
  const int b = 2;
  final Rect area = menu.outerRect
      .expandToInclude(source.outerRect)
      .inflate(2 * step);
  final int cols = ((area.width / step).ceil() ~/ b) * b + b + 1;
  final int rows = ((area.height / step).ceil() ~/ b) * b + b + 1;
  final int reach = (3 * radius / step).ceil();
  final Float64List kernel = Float64List(2 * reach + 1);
  var sum = 0.0;
  for (var k = -reach; k <= reach; k++) {
    final double x = k * step / radius;
    final double w = math.exp(-0.5 * x * x);
    kernel[k + reach] = w;
    sum += w;
  }
  for (var k = 0; k < kernel.length; k++) {
    kernel[k] /= sum;
  }
  final f = _BlurredUnion(menu, source, area, step, cols, rows, kernel);
  final boxes = MorphOutlineBoxes([menu, source]);
  final double band = 1.26 * radius + 1.5 * step;
  final double depth = math.max(band, MorphMenuFusion.shadedDepth);
  final double halfMenu = menu.outerRect.shortestSide / 2;
  final double halfSource = source.outerRect.shortestSide / 2;
  final double blend = math.max(radius, step);
  final int fieldCols = (cols - 1) ~/ stride + 1;
  final int fieldRows = (rows - 1) ~/ stride + 1;
  final Float64List trace = Float64List(cols * rows);
  final Float64List distance = Float64List(fieldCols * fieldRows);
  final Float64List halfMinor = Float64List(fieldCols * fieldRows);
  final Float64List turn = Float64List(fieldCols * fieldRows * 2);
  final Float64List unblurred = Float64List(fieldCols * fieldRows);
  final Float64List sourceTurn = Float64List(2);
  sourceTurn[0] = 1;
  final bool menuTurns = boxes.turns(0);
  final bool sourceTurns = boxes.turns(1);
  for (var fj = 0; fj < fieldRows; fj++) {
    final int j = fj * stride;
    final double y = area.top + j * step;
    for (var fi = 0; fi < fieldCols; fi++) {
      final int i = fi * stride;
      final double x = area.left + i * step;
      final int at = fj * fieldCols + fi;
      final double dg = f.menuDistance(i, j);
      final double ds = f.sourceDistance(i, j);
      final double raw = math.min(dg, ds);
      final double value = raw > band || raw < -depth
          ? raw
          : f.linear(i, j, dg, ds)
          ? raw
          : f.blurred(i, j);
      distance[at] = value;
      unblurred[at] = raw;
      trace[j * cols + i] = value;
      final double towardMenu = (0.5 + (ds - dg) / (2 * blend)).clamp(0.0, 1.0);
      halfMinor[at] = halfSource + (halfMenu - halfSource) * towardMenu;
      if (menuTurns) {
        boxes.opticalTurn(0, x, y, turn, at * 2);
      } else {
        turn[at * 2] = 1;
      }
      if (sourceTurns) {
        boxes.opticalTurn(1, x, y, sourceTurn, 0);
      }
      if ((menuTurns || sourceTurns) && towardMenu < 1) {
        turn[at * 2] =
            sourceTurn[0] + (turn[at * 2] - sourceTurn[0]) * towardMenu;
        turn[at * 2 + 1] =
            sourceTurn[1] + (turn[at * 2 + 1] - sourceTurn[1]) * towardMenu;
        morphNormalizeTurn(turn, at * 2);
      }
    }
  }
  final int blockCols = (cols - 1) ~/ b;
  final int blockRows = (rows - 1) ~/ b;
  final Uint8List near = Uint8List(blockCols * blockRows);
  final double slop = b * step * math.sqrt1_2;
  final int span = b ~/ stride;
  for (var bj = 0; bj < blockRows; bj++) {
    for (var bi = 0; bi < blockCols; bi++) {
      final int corner = bj * span * fieldCols + bi * span;
      final double c0 = unblurred[corner];
      final double c1 = unblurred[corner + span];
      final double c2 = unblurred[corner + span * fieldCols];
      final double c3 = unblurred[corner + span * fieldCols + span];
      final double lo = math.min(math.min(c0, c1), math.min(c2, c3));
      final double hi = math.max(math.max(c0, c1), math.max(c2, c3));
      if (lo - slop > band) {
        morphFillOutlineBlock(trace, cols, stride, b, bi, bj, 1);
      } else if (hi + slop < -band) {
        morphFillOutlineBlock(trace, cols, stride, b, bi, bj, -1);
      } else {
        near[bj * blockCols + bi] = 1;
        for (var j = bj * b; j <= bj * b + b; j++) {
          for (var i = bi * b; i <= bi * b + b; i++) {
            if (i % stride == 0 && j % stride == 0) continue;
            final double dg = f.menuDistance(i, j);
            final double ds = f.sourceDistance(i, j);
            final double raw = math.min(dg, ds);
            trace[j * cols + i] = raw.abs() > band || f.linear(i, j, dg, ds)
                ? raw
                : f.blurred(i, j);
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

/// The union of two rounded boxes on a grid and its Gaussian blur, both
/// evaluated on demand: the trace and field grid of [morphMenuSilhouette]
/// padded by the kernel's reach, node (i, j) of the trace grid at padded
/// node (i + reach, j + reach).
///
/// The unblurred distance and the horizontal pass of the separable blur
/// are remembered per node in buffers kept across calls (an outline is
/// fused on the UI thread, one at a time), so each is computed once.
class _BlurredUnion {
  _BlurredUnion(
    RRect menu,
    RRect source,
    Rect area,
    double step,
    this.cols,
    int rows,
    this.kernel,
  ) : reach = kernel.length ~/ 2,
      width = cols + kernel.length - 1,
      height = rows + kernel.length - 1,
      window = (kernel.length ~/ 2) * step,
      _menuX = Float64List(cols + kernel.length - 1),
      _menuY = Float64List(rows + kernel.length - 1),
      _sourceX = Float64List(cols + kernel.length - 1),
      _sourceY = Float64List(rows + kernel.length - 1),
      _menuRadius = _cornerOf(menu),
      _sourceRadius = _cornerOf(source),
      _menuInner = Offset(
        menu.width / 2 - _cornerOf(menu),
        menu.height / 2 - _cornerOf(menu),
      ),
      _sourceInner = Offset(
        source.width / 2 - _cornerOf(source),
        source.height / 2 - _cornerOf(source),
      ) {
    final double left = area.left - reach * step;
    final double top = area.top - reach * step;
    for (var i = 0; i < width; i++) {
      final double x = left + i * step;
      _menuX[i] = (x - menu.center.dx).abs() - _menuInner.dx;
      _sourceX[i] = (x - source.center.dx).abs() - _sourceInner.dx;
    }
    for (var j = 0; j < height; j++) {
      final double y = top + j * step;
      _menuY[j] = (y - menu.center.dy).abs() - _menuInner.dy;
      _sourceY[j] = (y - source.center.dy).abs() - _sourceInner.dy;
    }
    _Scratch.begin(width * height, cols * height);
    _rawValues = _Scratch.raw;
    _rawStamps = _Scratch.rawStamp;
    _acrossValues = _Scratch.across;
    _acrossStamps = _Scratch.acrossStamp;
    _generation = _Scratch.generation;
  }

  static double _cornerOf(RRect shape) =>
      math.min(shape.tlRadiusX, math.min(shape.width, shape.height) / 2);

  final int cols;
  final Float64List kernel;
  final int reach;
  final int width;
  final int height;

  /// The distance from a node to the farthest node of its blur window
  /// along each axis.
  final double window;

  final Float64List _menuX;
  final Float64List _menuY;
  final Float64List _sourceX;
  final Float64List _sourceY;
  final double _menuRadius;
  final double _sourceRadius;
  final Offset _menuInner;
  final Offset _sourceInner;

  /// The menu's distance at trace node (i, j).
  double menuDistance(int i, int j) =>
      morphBoxDistance(_menuX[i + reach], _menuY[j + reach], _menuRadius);

  /// The button's distance at trace node (i, j).
  double sourceDistance(int i, int j) =>
      morphBoxDistance(_sourceX[i + reach], _sourceY[j + reach], _sourceRadius);

  late final Float64List _rawValues;
  late final Int32List _rawStamps;
  late final Float64List _acrossValues;
  late final Int32List _acrossStamps;
  late final int _generation;

  /// The blurred union at trace node (i, j).
  double blurred(int i, int j) {
    final Float64List kernel = this.kernel;
    final int taps = kernel.length;
    final int generation = _generation;
    final Float64List acrossValues = _acrossValues;
    final Int32List acrossStamps = _acrossStamps;
    final Float64List rawValues = _rawValues;
    final Int32List rawStamps = _rawStamps;
    final Float64List menuX = _menuX;
    final Float64List sourceX = _sourceX;
    final double menuRadius = _menuRadius;
    final double sourceRadius = _sourceRadius;
    var v = 0.0;
    for (var k = 0; k < taps; k++) {
      final int row = j + k;
      final int at = row * cols + i;
      double h;
      if (acrossStamps[at] == generation) {
        h = acrossValues[at];
      } else {
        h = 0;
        final double menuY = _menuY[row];
        final double sourceY = _sourceY[row];
        final int base = row * width + i;
        for (var m = 0; m < taps; m++) {
          final int node = base + m;
          double raw;
          if (rawStamps[node] == generation) {
            raw = rawValues[node];
          } else {
            raw = math.min(
              morphBoxDistance(menuX[i + m], menuY, menuRadius),
              morphBoxDistance(sourceX[i + m], sourceY, sourceRadius),
            );
            rawStamps[node] = generation;
            rawValues[node] = raw;
          }
          h += kernel[m] * raw;
        }
        acrossStamps[at] = generation;
        acrossValues[at] = h;
      }
      v += kernel[k] * h;
    }
    return v;
  }

  /// Whether the union is linear over the blur window of trace node (i, j),
  /// where the menu's distance is [dg] and the button's [ds]: one shape is
  /// nearer over the whole window and the window sees one straight side
  /// of it.
  bool linear(int i, int j, double dg, double ds) {
    if ((dg - ds).abs() < 2 * math.sqrt2 * window) return false;
    return dg < ds
        ? _straight(_menuX[i + reach], _menuY[j + reach], _menuInner)
        : _straight(_sourceX[i + reach], _sourceY[j + reach], _sourceInner);
  }

  bool _straight(double qx, double qy, Offset inner) {
    final double r = window;
    return (qx + r <= 0 && qy - qx >= 2 * r && qy + inner.dy >= r) ||
        (qy + r <= 0 && qx - qy >= 2 * r && qx + inner.dx >= r);
  }
}

/// The buffers [_BlurredUnion] remembers its nodes in, kept across calls
/// and invalidated by a generation count instead of being cleared.
abstract final class _Scratch {
  static Float64List raw = Float64List(0);
  static Int32List rawStamp = Int32List(0);
  static Float64List across = Float64List(0);
  static Int32List acrossStamp = Int32List(0);
  static int generation = 0;

  static void begin(int rawNodes, int acrossNodes) {
    if (raw.length < rawNodes) {
      raw = Float64List(rawNodes + rawNodes ~/ 2);
      rawStamp = Int32List(raw.length);
      rawStamp.fillRange(0, rawStamp.length, generation);
    }
    if (across.length < acrossNodes) {
      across = Float64List(acrossNodes + acrossNodes ~/ 2);
      acrossStamp = Int32List(across.length);
      acrossStamp.fillRange(0, acrossStamp.length, generation);
    }
    generation++;
    if (generation == 0x3FFFFFFF) {
      generation = 1;
      rawStamp.fillRange(0, rawStamp.length, 0);
      acrossStamp.fillRange(0, acrossStamp.length, 0);
    }
  }
}
