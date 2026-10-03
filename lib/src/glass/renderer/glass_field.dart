import 'dart:typed_data';
import 'dart:ui';

import 'package:meta/meta.dart';

/// The signed distance field of a glass body whose outline its owner has
/// already fused, sampled on a square grid.
///
/// A layer given a field shades the body the field describes instead of
/// fusing its shapes itself: the geometry pass reads the distance, the
/// normal and the local half thickness from the field, so any outline the
/// owner can describe by a distance field is shaded as liquid glass.
///
/// Every node holds four values in [samples]: the signed distance
/// (negative inside), its gradient along x and y, and the half minor
/// extent of the shape the node belongs to, all in logical pixels of the
/// layer. Node (i, j) sits at [origin] + (i, j) * [step]. The grid must
/// cover the body with a margin of at least two nodes and hold at least
/// two nodes along each axis.
@internal
@immutable
class GlassField {
  /// Creates a field from its samples.
  const GlassField({
    required this.samples,
    required this.cols,
    required this.rows,
    required this.origin,
    required this.step,
    this.outline,
  });

  /// Four values per node, row-major.
  final Float32List samples;

  /// The nodes along x.
  final int cols;

  /// The nodes along y.
  final int rows;

  /// The position of node (0, 0) in the layer's logical coordinates.
  final Offset origin;

  /// The distance between neighboring nodes, in logical pixels.
  final double step;

  /// The zero contour of the field as a path in the layer's logical
  /// coordinates, when its owner traced it: fake glass, which draws no
  /// field, clips its backdrop and surfaces to it.
  final Path? outline;

  /// The box the grid spans.
  Rect get bounds =>
      Rect.fromLTWH(origin.dx, origin.dy, (cols - 1) * step, (rows - 1) * step);

  /// The same field moved by [offset].
  GlassField shift(Offset offset) => GlassField(
    samples: samples,
    cols: cols,
    rows: rows,
    origin: origin + offset,
    step: step,
    outline: outline?.shift(offset),
  );
}
