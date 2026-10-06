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

/// The offset in [layer]'s logical coordinates by which [layer] moves a
/// shape of [geometry] so that the shape samples the same device pixels as
/// in a layer of its own at the nearest [RenderGlassRasterAnchor] between
/// them; zero without an anchor, when [layerToPass] or the anchor's
/// transform is more than a translation.
///
/// [layerToPass] maps [layer]'s coordinates to the render pass the matte is
/// sampled in, at [devicePixelRatio].
@internal
Offset glassRasterPhaseShift(
  RenderObject layer,
  RenderObject geometry,
  Matrix4 layerToPass,
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
  if (anchor == null || node == null) return Offset.zero;
  final pass = MatrixUtils.getAsTranslation(layerToPass);
  final local = MatrixUtils.getAsTranslation(anchor.getTransformTo(layer));
  if (pass == null || local == null) return Offset.zero;
  double shift(double layerOrigin, double anchorOffset) {
    final own = (layerOrigin + anchorOffset) * devicePixelRatio;
    final shared = layerOrigin * devicePixelRatio;
    return (glassRasterPhase(shared) - glassRasterPhase(own)) /
        devicePixelRatio;
  }

  return Offset(shift(pass.dx, local.dx), shift(pass.dy, local.dy));
}

/// Where a layer whose origin sits at [origin] device pixels samples its
/// nearest-filtered matte for a pixel, relative to the pixel's center: in
/// `(-0.5, 0.5]` device pixels.
@internal
double glassRasterPhase(double origin) {
  final f = 0.5 - origin;
  return 0.5 - (f - f.floorToDouble());
}
