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
  ///
  /// Only what the source draws inside [region] (screen logical pixels:
  /// everything the glass may sample, frost and refraction included) can
  /// invalidate the copy; the copy itself is the whole source.
  ui.Image? imageFor({
    required double sigma,
    required double devicePixelRatio,
    required Rect region,
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
    _sign(layer, region, signature);
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

  // What the source contributes inside [region] (screen logical px): every
  // leaf whose bounds reach the region, with the transform, clip, opacity
  // and filters it is drawn under. Two equal signatures draw the same
  // pixels there. A leaf the framework cannot see into (a texture, a
  // platform view, a follower, an unknown layer) never compares equal.
  static void _sign(Layer root, Rect region, List<Object?> out) {
    void walk(Layer layer, Matrix4 transform, Rect? clip, List<Object?> state) {
      bool reaches(Rect local) {
        var bounds = MatrixUtils.transformRect(transform, local);
        if (clip != null) bounds = bounds.intersect(clip);
        return bounds.overlaps(region);
      }

      void leaf(Object? content) {
        out.add(content);
        out.add(transform.clone());
        out.add(clip);
        out.addAll(state);
        out.add(#leaf);
      }

      Rect? clipped(Rect local) {
        final bounds = MatrixUtils.transformRect(transform, local);
        return clip == null ? bounds : clip.intersect(bounds);
      }

      var next = transform;
      var nextClip = clip;
      var nextState = state;
      switch (layer) {
        case PictureLayer():
          if (reaches(layer.canvasBounds)) leaf(layer.picture);
          return;
        case TextureLayer():
          if (reaches(layer.rect)) leaf(Object());
          return;
        case PlatformViewLayer():
          if (reaches(layer.rect)) leaf(Object());
          return;
        case TransformLayer():
          next = transform.clone();
          next.multiply(
            Matrix4.translationValues(layer.offset.dx, layer.offset.dy, 0),
          );
          if (layer.transform case final matrix?) next.multiply(matrix);
        case OpacityLayer():
          next = transform.clone();
          next.multiply(
            Matrix4.translationValues(layer.offset.dx, layer.offset.dy, 0),
          );
          nextState = [...state, layer.alpha];
        case ImageFilterLayer():
          // A filter can move pixels anywhere: its whole subtree counts.
          next = transform.clone();
          next.multiply(
            Matrix4.translationValues(layer.offset.dx, layer.offset.dy, 0),
          );
          nextState = [...state, layer.imageFilter];
          nextClip = null;
        case OffsetLayer():
          next = transform.clone();
          next.multiply(
            Matrix4.translationValues(layer.offset.dx, layer.offset.dy, 0),
          );
        case ClipRectLayer():
          if (layer.clipBehavior != Clip.none) {
            nextClip = clipped(layer.clipRect!);
            nextState = [...state, layer.clipRect, layer.clipBehavior];
          }
        case ClipRRectLayer():
          if (layer.clipBehavior != Clip.none) {
            nextClip = clipped(layer.clipRRect!.outerRect);
            nextState = [...state, layer.clipRRect, layer.clipBehavior];
          }
        case ClipRSuperellipseLayer():
          if (layer.clipBehavior != Clip.none) {
            nextClip = clipped(layer.clipRSuperellipse!.outerRect);
            nextState = [...state, layer.clipRSuperellipse, layer.clipBehavior];
          }
        case ClipPathLayer():
          if (layer.clipBehavior != Clip.none) {
            nextClip = clipped(layer.clipPath!.getBounds());
            nextState = [...state, layer.clipPath, layer.clipBehavior];
          }
        case ColorFilterLayer():
          nextState = [...state, layer.colorFilter];
        case BackdropFilterLayer():
          // It reads and writes everything inside its clip.
          final bounds = clip ?? Rect.largest;
          if (bounds.overlaps(region)) {
            out.add(layer.blendMode);
            // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
            out.add(layer.engineLayer == null);
            leaf(layer.filter);
          }
          nextState = [...state, layer.filter];
        case ShaderMaskLayer():
          nextState = [...state, layer.shader, layer.maskRect, layer.blendMode];
        case AnnotatedRegionLayer() || LeaderLayer():
          break;
        case ContainerLayer() when layer.runtimeType == ContainerLayer:
          break;
        default:
          leaf(Object());
          return;
      }
      if (layer is ContainerLayer) {
        for (
          var child = layer.firstChild;
          child != null;
          child = child.nextSibling
        ) {
          walk(child, next, nextClip, nextState);
        }
      }
    }

    walk(root, Matrix4.identity(), null, const []);
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
