import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Whether glass under a [GlassBackdropCacheScope] reads the scope's cached
/// backdrop instead of a backdrop filter (prototype, `MORPH_BACKDROP_CACHE`).
bool debugMorphBackdropCache = const bool.fromEnvironment(
  'MORPH_BACKDROP_CACHE',
);

/// How many copies every [GlassBackdropCache] took, for a bench report.
int debugMorphBackdropCacheCaptures = 0;

/// A copy of what lies under a glass surface, reused while nothing the
/// surface samples has changed since it was taken.
///
/// [source] names the repaint boundary that holds everything under the
/// surface (the page below a sheet). The copy is taken after a frame, from
/// that frame's layers, and serves a later frame only while the source's
/// layers that reach the surface are the same ones: the copy is then
/// exactly what the backdrop would hold. A frame whose source changed reads
/// its backdrop as before; a copy is taken after the source has stayed the
/// same for a frame, so continuous motion under the surface costs no
/// copies. The glass never shows an older frame. [overlay] is a uniform
/// color painted between the source and the glass (a dimming), which the
/// glass shader composites itself.
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
  List<Object?>? _previous;
  bool _capturing = false;

  /// How many copies the cache has taken.
  @visibleForTesting
  int debugCaptures = 0;

  /// Whether the source can be copied: built, composited and at the
  /// screen origin. Glass reads its backdrop as before while it cannot.
  bool get ready => _boundary() != null;

  RenderBox? _boundary() {
    final boundary = source();
    if (boundary == null || !boundary.attached || boundary is! RenderBox) {
      return null;
    }
    // ignore: invalid_use_of_protected_member
    if (boundary.layer is! OffsetLayer) return null;
    return _isOrigin(boundary.getTransformTo(null)) ? boundary : null;
  }

  /// The frosted copy of the source if it is still exact for this frame,
  /// aligned to the screen at [devicePixelRatio]; else null, and the glass
  /// reads its backdrop this frame.
  ///
  /// Call it while the frame composites: the source's layers are final.
  /// Only what the source draws inside [region] (screen logical pixels:
  /// everything the glass may sample, frost and refraction included) can
  /// invalidate the copy; the copy itself is the whole source.
  ui.Image? imageFor({
    required double sigma,
    required double devicePixelRatio,
    required Rect region,
  }) {
    final boundary = _boundary();
    if (boundary == null) return null;
    // ignore: invalid_use_of_protected_member
    final layer = boundary.layer! as OffsetLayer;
    final signature = <Object?>[];
    _sign(layer, region, signature);
    if (_image != null && sigma == _sigma && _same(signature, _signature)) {
      _previous = signature;
      return _image;
    }
    final previous = _previous;
    _previous = signature;
    if (previous != null && _same(signature, previous) && !_capturing) {
      _capturing = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _capturing = false;
        _capture(signature, sigma, devicePixelRatio);
      });
    }
    return null;
  }

  // Copies the source as the frame that just composited left it; nothing
  // paints between compositing and the post-frame callbacks.
  void _capture(
    List<Object?> signature,
    double sigma,
    double devicePixelRatio,
  ) {
    // Released since the request: the surface is gone.
    if (_previous == null) return;
    final boundary = _boundary();
    if (boundary == null) return;
    // ignore: invalid_use_of_protected_member
    final layer = boundary.layer! as OffsetLayer;
    final raw = layer.toImageSync(
      Offset.zero & boundary.size,
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
  }

  /// Releases the copy.
  void dispose() {
    _image?.dispose();
    _image = null;
    _signature = const [];
    _previous = null;
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

/// The repaint boundary that holds [route]'s page, or null when [route] is
/// not a modal route or is not built.
///
/// A presentation over a page names the page's route (the route below a
/// sheet or an alert, the route of the control a menu opens from); the
/// boundary is the source of its [GlassBackdropCache].
@internal
RenderObject? glassRouteBoundary(Route<Object?>? route) {
  if (route is! ModalRoute<Object?>) return null;
  RenderObject? node = route.subtreeContext?.findRenderObject();
  while (node != null && !node.isRepaintBoundary) {
    node = node.parent;
  }
  return node;
}

/// The route of [overlay]'s navigator that [context] lies in: the page an
/// overlay presentation opened from [context] floats over, with everything
/// that navigator's page draws (nested navigators and their bars), or null.
@internal
ModalRoute<Object?>? glassRouteUnder(
  BuildContext context,
  OverlayState overlay,
) {
  var at = context;
  while (true) {
    final route = ModalRoute.of(at);
    final navigator = route?.navigator;
    if (route == null || navigator == null) return null;
    if (identical(navigator.overlay, overlay)) return route;
    at = navigator.context;
  }
}

/// A presentation route whose glass reads a [GlassBackdropCache] of the
/// page below it.
///
/// The cache's source is the route below while that route is opaque: a
/// translucent route below (another presentation, still closing) shows a
/// page of its own under it, which its boundary does not hold, and the
/// glass then reads its backdrop as before.
@internal
mixin GlassBackdropCacheRoute<T> on ModalRoute<T> {
  Route<Object?>? _below;

  /// The cache of the page below; hand it to the route's glass with a
  /// [GlassBackdropCacheScope].
  late final GlassBackdropCache backdropCache = GlassBackdropCache(
    source: () {
      final below = _below;
      if (below is! ModalRoute<Object?> || !below.opaque) return null;
      return glassRouteBoundary(below);
    },
  );

  @override
  void didChangePrevious(Route<Object?>? previousRoute) {
    super.didChangePrevious(previousRoute);
    _below = previousRoute;
  }

  @override
  void dispose() {
    backdropCache.dispose();
    super.dispose();
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
