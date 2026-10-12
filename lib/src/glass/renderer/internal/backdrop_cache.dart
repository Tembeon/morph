import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Whether glass under a [GlassBackdropCacheScope] reads the scope's cached
/// backdrop instead of a backdrop filter (prototype, `MORPH_BACKDROP_CACHE`).
bool debugMorphBackdropCache = const bool.fromEnvironment(
  'MORPH_BACKDROP_CACHE',
);

/// How many copies every [GlassBackdropCache] took, for a bench report.
int debugMorphBackdropCacheCaptures = 0;

/// A copy of what lies under a glass surface, taken in the frame it is
/// drawn, and reused while nothing under the surface changes.
///
/// [source] names the repaint boundary that holds everything under the
/// surface (the page below a sheet). While its layers stay the same, the
/// frosted copy is still exact and the glass paints over it with no
/// backdrop read; when they change, the copy is taken again before the
/// frame composites, so the glass never shows an older frame. [overlay] is
/// a uniform color painted between the source and the glass (a dimming),
/// which the glass shader composites itself.
@internal
class GlassBackdropCache {
  /// Creates a cache over [source].
  GlassBackdropCache({required this.source});

  /// The repaint boundary under the surface, or null when there is none.
  final RenderObject? Function() source;

  /// The uniform color between [source] and the glass, straight alpha.
  ui.Color overlay = const ui.Color(0x00000000);

  ui.Image? _image;
  List<Object?> _signature = const [];
  double _sigma = -1;

  /// How many copies the cache has taken.
  @visibleForTesting
  int debugCaptures = 0;

  /// The frosted copy of the source for this frame, aligned to the screen
  /// at [devicePixelRatio], or null when the source cannot be copied (it
  /// is missing, not a composited boundary, or not at the screen origin).
  ///
  /// Call it while the frame composites: the source's layers are final.
  ui.Image? imageFor({
    required double sigma,
    required double devicePixelRatio,
  }) {
    final boundary = source();
    if (boundary == null || !boundary.attached || boundary is! RenderBox) {
      return null;
    }
    // ignore: invalid_use_of_protected_member
    final layer = boundary.layer;
    if (layer is! OffsetLayer) return null;
    final screen = boundary.getTransformTo(null);
    if (!_isOrigin(screen)) return null;
    final signature = <Object?>[];
    _sign(layer, signature);
    if (_image != null && sigma == _sigma && _same(signature, _signature)) {
      return _image;
    }
    final size = boundary.size;
    final raw = layer.toImageSync(
      Offset.zero & size,
      pixelRatio: devicePixelRatio,
    );
    var image = raw;
    if (sigma > 0) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint();
      paint.imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma * devicePixelRatio,
        sigmaY: sigma * devicePixelRatio,
        tileMode: TileMode.mirror,
      );
      canvas.drawImage(raw, Offset.zero, paint);
      final picture = recorder.endRecording();
      image = picture.toImageSync(raw.width, raw.height);
      picture.dispose();
      raw.dispose();
    }
    _image?.dispose();
    _image = image;
    _signature = signature;
    _sigma = sigma;
    debugCaptures++;
    debugMorphBackdropCacheCaptures++;
    return image;
  }

  /// Releases the copy.
  void dispose() {
    _image?.dispose();
    _image = null;
    _signature = const [];
  }

  static bool _isOrigin(Matrix4 m) {
    const epsilon = 1e-6;
    final s = m.storage;
    return (s[0] - 1).abs() < epsilon &&
        (s[5] - 1).abs() < epsilon &&
        s[1].abs() < epsilon &&
        s[4].abs() < epsilon &&
        s[12].abs() < epsilon &&
        s[13].abs() < epsilon;
  }

  static bool _same(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (identical(x, y)) continue;
      if (x is ui.Picture || x is ui.Path || x is ui.ImageFilter) return false;
      if (x != y) return false;
    }
    return true;
  }

  // Everything a layer contributes to the scene, so two equal signatures
  // render the same pixels. A layer whose content the framework cannot see
  // (a texture, a platform view, a follower) never compares equal.
  static void _sign(Layer layer, List<Object?> out) {
    out.add(layer.runtimeType);
    switch (layer) {
      case PictureLayer():
        out.add(layer.picture);
      case TextureLayer() || PlatformViewLayer() || FollowerLayer():
        out.add(Object());
      case TransformLayer():
        out.add(layer.transform?.clone());
        out.add(layer.offset);
      case OpacityLayer():
        out.add(layer.alpha);
        out.add(layer.offset);
      case ImageFilterLayer():
        out.add(layer.imageFilter);
        out.add(layer.offset);
      case OffsetLayer():
        out.add(layer.offset);
      case ClipRectLayer():
        out.add(layer.clipRect);
        out.add(layer.clipBehavior);
      case ClipRRectLayer():
        out.add(layer.clipRRect);
        out.add(layer.clipBehavior);
      case ClipRSuperellipseLayer():
        out.add(layer.clipRSuperellipse);
        out.add(layer.clipBehavior);
      case ClipPathLayer():
        out.add(layer.clipPath);
        out.add(layer.clipBehavior);
      case ColorFilterLayer():
        out.add(layer.colorFilter);
      case BackdropFilterLayer():
        out.add(layer.filter);
        out.add(layer.blendMode);
        out.add(layer.backdropKey);
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        out.add(layer.engineLayer == null);
      case ShaderMaskLayer():
        out.add(layer.shader);
        out.add(layer.maskRect);
        out.add(layer.blendMode);
      case AnnotatedRegionLayer() || LeaderLayer():
        break;
      case ContainerLayer() when layer.runtimeType == ContainerLayer:
        break;
      default:
        out.add(Object());
    }
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        _sign(child, out);
      }
      out.add(#end);
    }
  }
}

/// Hands [cache] to the glass in [child].
@internal
class GlassBackdropCacheScope extends InheritedWidget {
  /// Scopes [cache] (null clears an outer one).
  const GlassBackdropCacheScope({
    required this.cache,
    required super.child,
    super.key,
  });

  /// The cache, or null.
  final GlassBackdropCache? cache;

  /// The cache of the nearest scope above [context], or null.
  static GlassBackdropCache? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GlassBackdropCacheScope>()
      ?.cache;

  @override
  bool updateShouldNotify(GlassBackdropCacheScope oldWidget) =>
      !identical(oldWidget.cache, cache);
}
