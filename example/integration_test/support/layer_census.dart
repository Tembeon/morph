/// The layer census of a timed scene: the engine layers of every frame the
/// scene draws, counted after the frame composited.
///
/// Each counted kind is a layer the engine draws as an offscreen pass
/// (a saveLayer): backdrop filters (one per glass layer, plus an opacity
/// seed while it is seeded), fractional opacity, image and color filters,
/// shader masks and clips with `Clip.antiAliasWithSaveLayer`. Pictures are
/// counted too, and among them the glass shadow pictures - the
/// renderer's shadow slot, a container of one picture right before the
/// clip of the layer's backdrop filter. A saveLayer recorded INSIDE a
/// picture is invisible to the layer tree: the raster trace's
/// Canvas::saveLayer count per frame minus the census's offscreen count
/// is that number (tool/ios_reference/perf/atrace_slices.py --scenes).
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Counts layers per frame while a scene is open.
class LayerCensus {
  /// Creates a census that counts while [begin] has opened a scene.
  LayerCensus() {
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  String? _scene;
  final Map<String, List<Map<String, int>>> _frames = {};

  /// Starts counting the frames of [scene].
  void begin(String scene) => _scene = scene;

  /// Stops counting.
  void end() => _scene = null;

  void _onFrame(Duration _) {
    final scene = _scene;
    if (scene == null) return;
    final counts = <String, int>{};
    for (final view in RendererBinding.instance.renderViews) {
      // The root layer is the census's whole input; profile builds expose
      // it only through the protected getter.
      // ignore: invalid_use_of_protected_member
      final root = view.layer;
      if (root != null) _walk(root, counts);
    }
    (_frames[scene] ??= []).add(counts);
  }

  static const List<String> _kinds = [
    'backdrop',
    'opacity',
    'image_filter',
    'color_filter',
    'shader_mask',
    'clip_save_layer',
    'offscreen',
    'pictures',
    'glass_shadow_pictures',
    'layers',
  ];

  static void _add(Map<String, int> counts, String kind) =>
      counts[kind] = (counts[kind] ?? 0) + 1;

  // Engine layers count only while they are in the scene: the opacity seed
  // drops its native pass when unseeded.
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  static bool _inScene(Layer layer) => layer.engineLayer != null;

  static void _walk(Layer layer, Map<String, int> counts) {
    _add(counts, 'layers');
    final offscreen = switch (layer) {
      BackdropFilterLayer() when _inScene(layer) => 'backdrop',
      OpacityLayer(:final alpha?) when alpha > 0 && alpha < 255 => 'opacity',
      ImageFilterLayer() => 'image_filter',
      ColorFilterLayer() => 'color_filter',
      ShaderMaskLayer() => 'shader_mask',
      ClipRectLayer(clipBehavior: Clip.antiAliasWithSaveLayer) ||
      ClipRRectLayer(clipBehavior: Clip.antiAliasWithSaveLayer) ||
      ClipRSuperellipseLayer(clipBehavior: Clip.antiAliasWithSaveLayer) ||
      ClipPathLayer(
        clipBehavior: Clip.antiAliasWithSaveLayer,
      ) => 'clip_save_layer',
      _ => null,
    };
    if (offscreen != null) {
      _add(counts, offscreen);
      _add(counts, 'offscreen');
    }
    if (layer is PictureLayer) _add(counts, 'pictures');
    if (_isGlassShadowSlot(layer)) _add(counts, 'glass_shadow_pictures');
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        _walk(child, counts);
      }
    }
  }

  static bool _isGlassShadowSlot(Layer layer) {
    if (layer.runtimeType != ContainerLayer) return false;
    final slot = layer as ContainerLayer;
    final picture = slot.firstChild;
    if (picture is! PictureLayer || picture.nextSibling != null) return false;
    final clip = slot.nextSibling;
    return clip is ClipRectLayer && clip.firstChild is BackdropFilterLayer;
  }

  /// Per scene: the frames counted, the mean and the largest count of each
  /// kind per frame, and the first frame's counts (the scene at rest).
  Map<String, Object?> report() => {
    for (final MapEntry(key: scene, value: frames) in _frames.entries)
      scene: {
        'frames': frames.length,
        'mean': {
          for (final kind in _kinds)
            kind:
                frames.fold(
                  0,
                  (int a, Map<String, int> f) => a + (f[kind] ?? 0),
                ) /
                frames.length,
        },
        'max': {
          for (final kind in _kinds)
            kind: frames.fold(
              0,
              (int a, Map<String, int> f) =>
                  (f[kind] ?? 0) > a ? f[kind] ?? 0 : a,
            ),
        },
        'first': {for (final kind in _kinds) kind: frames.first[kind] ?? 0},
      },
  };
}
