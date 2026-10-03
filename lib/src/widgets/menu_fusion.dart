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
  final double shift = 1.26 * radius;
  final double band = shift + 1.5 * step;
  final double depth = math.max(band, MorphMenuFusion.shadedDepth);
  final double halfMenu = menu.outerRect.shortestSide / 2;
  final double halfSource = source.outerRect.shortestSide / 2;
  final double blend = math.max(radius, step);
  final int fieldCols = (cols - 1) ~/ stride + 1;
  final int fieldRows = (rows - 1) ~/ stride + 1;
  final Float64List trace = _Scratch.trace(cols * rows);
  final int nodes = fieldCols * fieldRows;
  final Float64List distance = _Scratch.field(0, nodes);
  final Float64List halfMinor = _Scratch.field(1, nodes);
  final Float64List clearance = _Scratch.field(2, nodes);
  final Float64List turn = _Scratch.field(3, 2 * nodes);
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
      f.remember(i, j, raw);
      final bool exact = raw <= band && raw >= -depth;
      final double value = exact ? f.smoothed(i, j, dg, ds) : raw;
      distance[at] = value;
      clearance[at] = exact ? value.abs() : raw.abs() - shift;
      trace[j * cols + i] = value;
      final double share = 0.5 + (ds - dg) / (2 * blend);
      final double towardMenu = share < 0
          ? 0
          : share > 1
          ? 1
          : share;
      halfMinor[at] = halfSource + (halfMenu - halfSource) * towardMenu;
      final bool menuCorner = menuTurns && boxes.inOpticalCorner(0, x, y);
      final bool sourceCorner = sourceTurns && boxes.inOpticalCorner(1, x, y);
      if (menuCorner) {
        boxes.opticalTurn(0, x, y, turn, at * 2);
      } else {
        turn[at * 2] = 1;
        turn[at * 2 + 1] = 0;
      }
      if (sourceCorner) {
        boxes.opticalTurn(1, x, y, sourceTurn, 0);
      } else {
        sourceTurn[0] = 1;
        sourceTurn[1] = 0;
      }
      if ((menuCorner || sourceCorner) && towardMenu < 1) {
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
  final double reachOfEdge = step * math.sqrt2 + b * step * math.sqrt1_2;
  final int span = b ~/ stride;
  for (var bj = 0; bj < blockRows; bj++) {
    for (var bi = 0; bi < blockCols; bi++) {
      final int corner = bj * span * fieldCols + bi * span;
      final double nearest = math.min(
        math.min(clearance[corner], clearance[corner + span]),
        math.min(
          clearance[corner + span * fieldCols],
          clearance[corner + span * fieldCols + span],
        ),
      );
      if (nearest <= reachOfEdge) {
        near[bj * blockCols + bi] = 1;
        for (var j = bj * b; j <= bj * b + b; j++) {
          for (var i = bi * b; i <= bi * b + b; i++) {
            if (stride == 1 || ((i | j) & 1) == 0) continue;
            final double dg = f.menuDistance(i, j);
            final double ds = f.sourceDistance(i, j);
            final double raw = math.min(dg, ds);
            f.remember(i, j, raw);
            trace[j * cols + i] = raw.abs() > band
                ? raw
                : f.smoothed(i, j, dg, ds);
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
      _dense = step >= 4,
      deviation = _deviationOf(kernel, step),
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
    if (_dense) {
      for (var j = 0; j < height; j++) {
        final double menuY = _menuY[j];
        final double sourceY = _sourceY[j];
        final int row = j * width;
        for (var i = 0; i < width; i++) {
          final double dg = morphBoxDistance(_menuX[i], menuY, _menuRadius);
          final double ds = morphBoxDistance(
            _sourceX[i],
            sourceY,
            _sourceRadius,
          );
          _rawValues[row + i] = dg < ds ? dg : ds;
        }
      }
    }
  }

  static double _deviationOf(Float64List kernel, double step) {
    final int reach = kernel.length ~/ 2;
    var variance = 0.0;
    for (var k = 0; k < kernel.length; k++) {
      final double x = (k - reach) * step;
      variance += kernel[k] * x * x;
    }
    return math.sqrt(variance);
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

  /// Whether the whole grid is sampled up front: at a coarse step the band
  /// the blur reaches covers most of it, and a plain array beats a memo.
  final bool _dense;

  /// The standard deviation of the truncated kernel along each axis.
  final double deviation;

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

  Float64List _rawValues = _Scratch.raw;
  Int32List _rawStamps = _Scratch.rawStamp;
  Float64List _acrossValues = _Scratch.across;
  Int32List _acrossStamps = _Scratch.acrossStamp;
  int _generation = 0;

  /// Remembers [raw], the unblurred union at trace node (i, j), for the
  /// blur windows that will read it.
  void remember(int i, int j, double raw) {
    if (_dense) return;
    final int at = (j + reach) * width + i + reach;
    _rawStamps[at] = _generation;
    _rawValues[at] = raw;
  }

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
        if (_dense) {
          for (var m = 0; m < taps; m++) {
            h += kernel[m] * rawValues[base + m];
          }
          acrossStamps[at] = generation;
          acrossValues[at] = h;
          v += kernel[k] * h;
          continue;
        }
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

  /// The blurred union at trace node (i, j), where the menu's distance is
  /// [dg] and the button's [ds].
  ///
  /// Where one shape is nearer over the whole blur window, the window may
  /// see one straight side of it, where the field is linear and the
  /// symmetric kernel leaves it unchanged, or one round corner, where the
  /// field is the distance from the corner's center less its radius and
  /// its blur is the mean of a Rice distribution (taken with the kernel's
  /// own variance). Elsewhere the kernel is applied.
  double smoothed(int i, int j, double dg, double ds) {
    final double raw = dg < ds ? dg : ds;
    if ((dg - ds).abs() < 2 * math.sqrt2 * window) return blurred(i, j);
    final bool menu = dg < ds;
    final double qx = menu ? _menuX[i + reach] : _sourceX[i + reach];
    final double qy = menu ? _menuY[j + reach] : _sourceY[j + reach];
    final Offset inner = menu ? _menuInner : _sourceInner;
    final double r = window;
    if ((qx + r <= 0 && qy - qx >= 2 * r && qy + inner.dy >= r) ||
        (qy + r <= 0 && qx - qy >= 2 * r && qx + inner.dx >= r)) {
      return raw;
    }
    if ((inner.dx <= 0 || qx >= r) && (inner.dy <= 0 || qy >= r)) {
      return morphRiceMean(math.sqrt(qx * qx + qy * qy), deviation) -
          (menu ? _menuRadius : _sourceRadius);
    }
    return blurred(i, j);
  }
}

/// The mean distance from the origin of a point drawn from a 2D isotropic
/// Gaussian of standard deviation [sigma] per axis centered [nu] away: the
/// mean of a Rice distribution, `sigma sqrt(pi / 2) L_1/2(-nu^2 / 2
/// sigma^2)`, with the Bessel functions from Abramowitz and Stegun 9.8
/// (relative error under 2e-7).
@internal
double morphRiceMean(double nu, double sigma) {
  final double t = nu * nu / (4 * sigma * sigma);
  double i0e;
  double i1e;
  if (t < 3.75) {
    final double u = (t / 3.75) * (t / 3.75);
    final double i0 =
        1 +
        u *
            (3.5156229 +
                u *
                    (3.0899424 +
                        u *
                            (1.2067492 +
                                u *
                                    (0.2659732 +
                                        u * (0.0360768 + u * 0.0045813)))));
    final double i1 =
        t *
        (0.5 +
            u *
                (0.87890594 +
                    u *
                        (0.51498869 +
                            u *
                                (0.15084934 +
                                    u *
                                        (0.02658733 +
                                            u *
                                                (0.00301532 +
                                                    u * 0.00032411))))));
    final double decay = math.exp(-t);
    i0e = i0 * decay;
    i1e = i1 * decay;
  } else {
    final double v = 3.75 / t;
    final double root = math.sqrt(t);
    i0e =
        (0.39894228 +
            v *
                (0.01328592 +
                    v *
                        (0.00225319 +
                            v *
                                (-0.00157565 +
                                    v *
                                        (0.00916281 +
                                            v *
                                                (-0.02057706 +
                                                    v *
                                                        (0.02635537 +
                                                            v *
                                                                (-0.01647633 +
                                                                    v * 0.00392377)))))))) /
        root;
    i1e =
        (0.39894228 +
            v *
                (-0.03988024 +
                    v *
                        (-0.00362018 +
                            v *
                                (0.00163801 +
                                    v *
                                        (-0.01031555 +
                                            v *
                                                (0.02282967 +
                                                    v *
                                                        (-0.02895312 +
                                                            v *
                                                                (0.01787654 +
                                                                    v * -0.00420059)))))))) /
        root;
  }
  return sigma * math.sqrt(math.pi / 2) * ((1 + 2 * t) * i0e + 2 * t * i1e);
}

/// The buffers [_BlurredUnion] remembers its nodes in, kept across calls
/// and invalidated by a generation count instead of being cleared.
abstract final class _Scratch {
  static Float64List raw = Float64List(0);
  static Int32List rawStamp = Int32List(0);
  static Float64List across = Float64List(0);
  static Int32List acrossStamp = Int32List(0);
  static int generation = 0;
  static Float64List _trace = Float64List(0);
  static final List<Float64List> _fields = [
    for (var i = 0; i < 4; i++) Float64List(0),
  ];

  /// Field grid buffer [index] with room for at least [values] values,
  /// overwritten by every call.
  static Float64List field(int index, int values) {
    if (_fields[index].length < values) {
      _fields[index] = Float64List(values + values ~/ 2);
    }
    return _fields[index];
  }

  /// A trace grid of at least [nodes] nodes; only the nodes a caller
  /// writes are meaningful.
  static Float64List trace(int nodes) {
    if (_trace.length < nodes) _trace = Float64List(nodes + nodes ~/ 2);
    return _trace;
  }

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
