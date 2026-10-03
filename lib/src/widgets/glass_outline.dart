import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
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
  MorphGlassOutline shift(Offset offset) =>
      MorphGlassOutline._(path.shift(offset), _field?.shift(offset));
}

/// The sampled distance field of [outline], or null for an outline built
/// from a path alone.
@internal
GlassField? morphGlassOutlineField(MorphGlassOutline outline) => outline._field;

/// The outline whose distance field is [distance] on a grid of [cols] x
/// [rows] nodes, node (i, j) at ([left] + i [step], [top] + j [step]),
/// negative inside, with [halfMinor] the half thickness of the shape each
/// node belongs to.
///
/// The edge is the field's zero contour, traced by the skin's marching
/// squares on every node; the field a renderer shades from keeps every
/// [fieldStride]th node along each axis (a fine trace grid needs no fine
/// shading grid: the shader interpolates a smooth field), with the
/// gradient from central differences, so its normals are the field's own.
@internal
MorphGlassOutline morphGlassOutlineFromGrid(
  Float64List distance,
  Float64List halfMinor,
  int cols,
  int rows, {
  required double left,
  required double top,
  required double step,
  int smoothPasses = 2,
  int fieldStride = 1,
}) {
  assert(cols >= 2 && rows >= 2, 'A field needs two nodes along each axis.');
  final stride =
      (cols - 1) ~/ fieldStride >= 1 && (rows - 1) ~/ fieldStride >= 1
      ? fieldStride
      : 1;
  final fieldCols = (cols - 1) ~/ stride + 1;
  final fieldRows = (rows - 1) ~/ stride + 1;
  final samples = Float32List(fieldCols * fieldRows * 4);
  for (var fj = 0; fj < fieldRows; fj++) {
    final j = fj * stride;
    final up = math.max(j - 1, 0);
    final down = math.min(j + 1, rows - 1);
    for (var fi = 0; fi < fieldCols; fi++) {
      final i = fi * stride;
      final back = math.max(i - 1, 0);
      final ahead = math.min(i + 1, cols - 1);
      final at = j * cols + i;
      final out = (fj * fieldCols + fi) * 4;
      samples[out] = distance[at];
      samples[out + 1] =
          (distance[j * cols + ahead] - distance[j * cols + back]) /
          ((ahead - back) * step);
      samples[out + 2] =
          (distance[down * cols + i] - distance[up * cols + i]) /
          ((down - up) * step);
      samples[out + 3] = halfMinor[at];
    }
  }
  final path = Path();
  path.fillType = PathFillType.evenOdd;
  for (final loop in liquidGridContours(
    distance,
    cols,
    rows,
    left: left,
    top: top,
    step: step,
    smoothPasses: smoothPasses,
  )) {
    path.moveTo(loop.first.dx, loop.first.dy);
    for (var i = 1; i < loop.length; i++) {
      path.lineTo(loop[i].dx, loop[i].dy);
    }
    path.close();
  }
  return MorphGlassOutline._(
    path,
    GlassField(
      samples: samples,
      cols: fieldCols,
      rows: fieldRows,
      origin: Offset(left, top),
      step: step * stride,
    ),
  );
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

/// The last outlines [morphGlassContainerOutline] fused, newest last.
final List<(List<RRect>, double, MorphGlassOutline)> _recentOutlines = [];

/// The outline a glass container with [spacing] fuses [shapes] into, by
/// the skin's merge law ([LiquidField] with blend [spacing], 1:1 the
/// container spacing of UIKit's `UIGlassContainerEffect`).
///
/// The last few outlines are remembered, so a layer that rebuilds without
/// its shapes moving does not fuse them again.
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

MorphGlassOutline _fuseContainer(List<RRect> shapes, double spacing) {
  final field = LiquidField([
    for (final shape in shapes)
      MorphMass.box(shape.outerRect, radius: _radius(shape)),
  ], k: spacing);
  final area = field.bounds(pad: 2 * _fusionStep);
  final cols = (area.width / _fusionStep).ceil() + 1;
  final rows = (area.height / _fusionStep).ceil() + 1;
  final distance = Float64List(cols * rows);
  final halfMinor = Float64List(cols * rows);
  for (var j = 0; j < rows; j++) {
    final y = area.top + j * _fusionStep;
    for (var i = 0; i < cols; i++) {
      final x = area.left + i * _fusionStep;
      final p = Offset(x, y);
      distance[j * cols + i] = field.eval(p);
      var nearest = double.infinity;
      var half = 0.0;
      for (final shape in shapes) {
        final d = liquidBoxDistance(p, shape.outerRect, _radius(shape));
        if (d < nearest) {
          nearest = d;
          half = shape.outerRect.shortestSide / 2;
        }
      }
      halfMinor[j * cols + i] = half;
    }
  }
  return morphGlassOutlineFromGrid(
    distance,
    halfMinor,
    cols,
    rows,
    left: area.left,
    top: area.top,
    step: _fusionStep,
    fieldStride: 2,
  );
}

double _radius(RRect shape) =>
    math.min(shape.tlRadiusX, shape.outerRect.shortestSide / 2);
