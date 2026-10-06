import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Marks where the shapes in [child] would have their own glass layer.
///
/// A glass layer rasterizes its matte on a grid of device pixels anchored at
/// its own origin, and the final pass samples that matte nearest. A shape
/// shaded by a layer further up (a glass container) is rasterized on that
/// layer's grid instead, so off the pixel grid its rim lands up to half a
/// device pixel elsewhere than in a layer of its own. The layer that shades
/// the shapes below this marker shifts them by that difference, so they read
/// the same pixels as in a layer at the marker.
@internal
class GlassRasterAnchor extends SingleChildRenderObjectWidget {
  /// Anchors the raster grid of the shapes in [child].
  const GlassRasterAnchor({required super.child, super.key});

  @override
  RenderGlassRasterAnchor createRenderObject(BuildContext context) =>
      RenderGlassRasterAnchor();
}

/// The render object of a [GlassRasterAnchor].
@internal
class RenderGlassRasterAnchor extends RenderProxyBox {}

/// How far from a texel edge, in device pixels, a pixel center may fall
/// before a sampler's rounding can read either texel.
///
/// GPUs round texture coordinates to a few sub-texel bits and the final
/// pass maps fragment coordinates through 32-bit floats, so a nearest
/// sampled matte whose texel edges fall within this distance of the pixel
/// centers reads one texel or the other row by row, differently on
/// different GPUs. A layer whose grid falls that close moves its grid onto
/// the pixel centers instead and shifts its shapes, so its pixels follow
/// [glassRasterPhase] exactly.
@internal
const double glassRasterTieBand = 1 / 64;

/// The raster grid a glass layer encodes its matte on, for a pass that maps
/// the layer by a translation.
@internal
@immutable
class GlassRasterGrid {
  /// Describes a grid at [origin] device pixels, moved by [bias] device
  /// pixels from the layer's own origin.
  const GlassRasterGrid._(this.origin, this.bias, this.sample);

  /// The grid of a layer whose origin falls at [origin] device pixels of
  /// its pass; with [movable] false the grid stays on the layer's own
  /// pixel grid (a matte drawn from a field placed in layer coordinates).
  factory GlassRasterGrid(Offset origin, {bool movable = true}) {
    double bias(double origin) {
      final phase = glassRasterPhase(origin);
      return movable && phase.abs() > 0.5 - glassRasterTieBand ? -phase : 0;
    }

    final moved = Offset(bias(origin.dx), bias(origin.dy));
    return GlassRasterGrid._(
      origin,
      moved,
      Offset(
        glassRasterPhase(origin.dx + moved.dx),
        glassRasterPhase(origin.dy + moved.dy),
      ),
    );
  }

  /// The layer's origin in device pixels of its pass.
  final Offset origin;

  /// How far the matte's texel grid sits from the layer's own pixel grid,
  /// in device pixels: zero unless the layer's own grid falls within
  /// [glassRasterTieBand] of the pixel centers.
  final Offset bias;

  /// Where a pixel samples the grid, relative to its center, in device
  /// pixels.
  final Offset sample;

  /// Whether the grid sits off the layer's own pixel grid.
  bool get biased => bias != Offset.zero;

  /// The device pixels by which the layer moves a shape so that the shape
  /// reads the pixels a layer of its own at [own] device pixels would read.
  Offset shiftFor(Offset own) => Offset(
    sample.dx - glassRasterPhase(own.dx),
    sample.dy - glassRasterPhase(own.dy),
  );
}

/// The raster grid of a layer that [layerToPass] maps into its pass at
/// [devicePixelRatio]; null when that is more than a translation.
@internal
GlassRasterGrid? glassRasterGrid(
  Matrix4 layerToPass,
  double devicePixelRatio, {
  bool movable = true,
}) {
  final pass = MatrixUtils.getAsTranslation(layerToPass);
  if (pass == null) return null;
  return GlassRasterGrid(pass * devicePixelRatio, movable: movable);
}

/// The offset in [layer]'s logical coordinates by which [layer], encoding
/// its matte on [grid], moves a shape of [geometry] so that the shape
/// samples the same device pixels as in a layer of its own at the nearest
/// [RenderGlassRasterAnchor] between them, or at [layer] itself without an
/// anchor or when the anchor's transform is more than a translation.
@internal
Offset glassRasterPhaseShift(
  RenderObject layer,
  RenderObject geometry,
  GlassRasterGrid grid,
  double devicePixelRatio,
) {
  RenderObject? anchor;
  var node = geometry.parent;
  while (node != null && !identical(node, layer)) {
    if (node is RenderGlassRasterAnchor) {
      anchor = node;
      break;
    }
    node = node.parent;
  }
  var own = grid.origin;
  if (anchor != null && node != null) {
    final local = MatrixUtils.getAsTranslation(anchor.getTransformTo(layer));
    if (local != null) own += local * devicePixelRatio;
  }
  return grid.shiftFor(own) / devicePixelRatio;
}

/// Where a layer whose origin sits at [origin] device pixels samples its
/// nearest-filtered matte for a pixel, relative to the pixel's center: in
/// `[-0.5, 0.5)` device pixels.
///
/// The origin is rounded to the 32-bit float the final pass receives, and a
/// pixel center exactly on a texel edge reads the texel before it, as the
/// GPUs measured do (Apple Metal, SwiftShader).
@internal
double glassRasterPhase(double origin) {
  final f = 0.5 - _float32(origin);
  return f.ceilToDouble() - f - 0.5;
}

final Float32List _float32Slot = Float32List(1);

double _float32(double value) {
  _float32Slot[0] = value;
  return _float32Slot[0];
}
