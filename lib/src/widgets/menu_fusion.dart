import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:morph/src/liquid_field.dart';

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
/// the sign, all the trace needs, is the unblurred one. The last outline
/// is reused while its inputs do not change.
@internal
class MorphMenuFusion {
  /// The radius below which the silhouette is the plain union.
  static const double minimumRadius = 1;

  RRect? _menu;
  RRect? _source;
  double _radius = 0;
  Path? _outline;

  /// The fused outline of [menu] and [source] blurred by [radius], or
  /// null when [radius] is under [minimumRadius] and the silhouette is
  /// their plain union.
  Path? outline(RRect menu, RRect source, double radius) {
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

/// The zero contour of the union of [menu] and [source] whose signed
/// distance field is blurred by a Gaussian of standard deviation
/// [radius], as one even-odd path.
@internal
Path morphMenuSilhouette(RRect menu, RRect source, double radius) {
  final double step = (radius / 3).clamp(2.0, 6.0);
  final Rect trace = menu.outerRect
      .expandToInclude(source.outerRect)
      .inflate(2 * step);
  final int cols = (trace.width / step).ceil() + 1;
  final int rows = (trace.height / step).ceil() + 1;
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
  final int width = cols + 2 * reach;
  final int height = rows + 2 * reach;
  final double left = trace.left - reach * step;
  final double top = trace.top - reach * step;
  final _Box g = _Box(menu);
  final _Box s = _Box(source);
  final Float64List field = Float64List(width * height);
  for (var j = 0; j < height; j++) {
    final double y = top + j * step;
    final int row = j * width;
    for (var i = 0; i < width; i++) {
      final double x = left + i * step;
      field[row + i] = math.min(g.distance(x, y), s.distance(x, y));
    }
  }
  final double band = 1.26 * radius + 1.5 * step;
  final Float64List across = Float64List(cols * height);
  across.fillRange(0, across.length, double.nan);
  final Float64List blurred = Float64List(cols * rows);
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      final double raw = field[(j + reach) * width + i + reach];
      if (raw.abs() > band) {
        blurred[j * cols + i] = raw;
        continue;
      }
      var v = 0.0;
      for (var k = 0; k < kernel.length; k++) {
        final int at = (j + k) * cols + i;
        var h = across[at];
        if (h.isNaN) {
          h = 0;
          final int from = (j + k) * width + i;
          for (var m = 0; m < kernel.length; m++) {
            h += kernel[m] * field[from + m];
          }
          across[at] = h;
        }
        v += kernel[k] * h;
      }
      blurred[j * cols + i] = v;
    }
  }
  final Path path = Path();
  path.fillType = PathFillType.evenOdd;
  for (final List<Offset> loop in liquidGridContours(
    blurred,
    cols,
    rows,
    left: trace.left,
    top: trace.top,
    step: step,
  )) {
    path.moveTo(loop.first.dx, loop.first.dy);
    for (var i = 1; i < loop.length; i++) {
      path.lineTo(loop[i].dx, loop[i].dy);
    }
    path.close();
  }
  return path;
}

class _Box {
  _Box(RRect shape)
    : cx = shape.center.dx,
      cy = shape.center.dy,
      r = math.min(shape.tlRadiusX, math.min(shape.width, shape.height) / 2),
      hx = shape.width / 2,
      hy = shape.height / 2;

  final double cx;
  final double cy;
  final double r;
  final double hx;
  final double hy;

  double distance(double x, double y) {
    final double qx = (x - cx).abs() - (hx - r);
    final double qy = (y - cy).abs() - (hy - r);
    final double ox = math.max(qx, 0);
    final double oy = math.max(qy, 0);
    return math.sqrt(ox * ox + oy * oy) + math.min(math.max(qx, qy), 0) - r;
  }
}
