import 'dart:typed_data';
import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
    this.analytic,
  });

  /// Enables the beta-only GPU optical grid experiment on native platforms.
  static const bool gpuFusion =
      !kIsWeb && bool.fromEnvironment('MORPH_GPU_FUSION_FIELD');

  /// Describes a small rounded-box fusion without sampling its optical grid.
  ///
  /// The owner still traces [outline] with its CPU merge law. The renderer
  /// evaluates that same law at the coarse nodes; [samples] is empty here.
  factory GlassField.fromBoxes({
    required List<RRect> shapes,
    required double spacing,
    required int cols,
    required int rows,
    required Offset origin,
    required double step,
    required Path outline,
  }) => GlassField(
    samples: _emptySamples,
    cols: cols,
    rows: rows,
    origin: origin,
    step: step,
    outline: outline,
    analytic: GlassAnalyticField(shapes, origin, spacing),
  );

  static final Float32List _emptySamples = Float32List(0);

  /// Four values per node, row-major; never written after the field is
  /// created (renderers keep an upload while the same list comes back).
  final Float32List samples;

  /// An optional owner-provided merge descriptor in grid-relative coordinates.
  ///
  /// When present, [samples] is empty and both native geometry paths must
  /// render the descriptor before sampling it. Web owners never create it.
  final GlassAnalyticField? analytic;

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
    analytic: analytic,
  );
}

/// The owner merge inputs for a GPU optical grid, independent of translation.
@internal
@immutable
class GlassAnalyticField {
  /// Stores at most four uniform circular rounded boxes relative to [origin].
  GlassAnalyticField(List<RRect> shapes, Offset origin, this.spacing)
    : boxes = Float32List(shapes.length * 8) {
    assert(shapes.isNotEmpty && shapes.length <= 4);
    for (var i = 0; i < shapes.length; i++) {
      final shape = shapes[i];
      final at = i * 8;
      boxes[at] = shape.center.dx - origin.dx;
      boxes[at + 1] = shape.center.dy - origin.dy;
      boxes[at + 2] = shape.width / 2;
      boxes[at + 3] = shape.height / 2;
      boxes[at + 4] = shape.tlRadiusX.clamp(0, shape.shortestSide / 2);
    }
  }

  /// Two vec4 values per rounded box: center, half extent, then radius.
  final Float32List boxes;

  /// The owner's spacing in logical pixels, including its angular merge law.
  final double spacing;
}
