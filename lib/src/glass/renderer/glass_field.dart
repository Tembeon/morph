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

  /// Four values per node, row-major; never written after the field is
  /// created (renderers keep an upload while the same list comes back).
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

/// A fused body of a few rounded boxes, merged by the glass container's law
/// with [spacing], whose sampled field is fused only when it is read.
///
/// A liquid layer that evaluates the merge law in its final shader shades
/// the body from [boxes] and [spacing] and never reads the samples; any
/// other reader gets the field [fuse] returns, fused once on first read.
/// A moved body shares that one fusion: every [shift] refers to the field
/// first created, moved once by the total offset.
@internal
@immutable
class GlassBoxField implements GlassField {
  /// Creates a body of [boxes] merged with [spacing], whose field [fuse]
  /// computes on demand.
  GlassBoxField({
    required this.boxes,
    required this.spacing,
    required GlassField Function() fuse,
  }) : assert(
         boxes.every(_uniform),
         'Merged glass boxes require uniform circular corner radii.',
       ),
       _root = _LazyField(fuse),
       _offset = Offset.zero;

  static bool _uniform(RRect box) =>
      box.tlRadiusX == box.tlRadiusY &&
      box.tlRadius == box.trRadius &&
      box.tlRadius == box.blRadius &&
      box.tlRadius == box.brRadius;

  GlassBoxField._moved(this.boxes, this.spacing, this._root, this._offset);

  /// The most boxes a liquid layer merges in its final shader.
  static const int maxBoxes = 4;

  /// The rounded boxes, uniform circular corners, in the layer's logical
  /// coordinates.
  final List<RRect> boxes;

  /// The glass container spacing they merge with, in logical pixels.
  final double spacing;

  // The field of the body this one was moved from, and how far.
  final _LazyField _root;
  final Offset _offset;
  final _MovedField _moved = _MovedField();

  /// The fusion every move of the first body shares, for tests.
  @visibleForTesting
  Object get debugRoot => _root;

  /// The sampled field of the body, fused on first read.
  GlassField get fused => _moved.value ??= _offset == Offset.zero
      ? _root.value
      : _root.value.shift(_offset);

  @override
  Float32List get samples => fused.samples;

  @override
  int get cols => fused.cols;

  @override
  int get rows => fused.rows;

  @override
  Offset get origin => fused.origin;

  @override
  double get step => fused.step;

  @override
  Path? get outline => fused.outline;

  @override
  Rect get bounds => fused.bounds;

  @override
  GlassBoxField shift(Offset offset) => GlassBoxField._moved(
    [for (final box in boxes) box.shift(offset)],
    spacing,
    _root,
    _offset + offset,
  );
}

/// The field a [GlassBoxField] fuses once, on first read.
final class _LazyField {
  _LazyField(this._fuse);

  final GlassField Function() _fuse;
  GlassField? _value;

  GlassField get value => _value ??= _fuse();
}

/// The moved field one [GlassBoxField] keeps once it is read.
final class _MovedField {
  GlassField? value;
}
