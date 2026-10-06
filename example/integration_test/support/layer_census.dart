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
///
/// With `owners` every backdrop filter is also named by its owner: the
/// Morph widgets above the render object that paints it (the innermost
/// last), the nearest value key between them (the glass host's role:
/// body, separate, a lens's glass), and the painter's type. Captures
/// count the distinct backdrop readbacks: a filter without a key is its
/// own, filters sharing a key share one.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
// The census reads the renderer's owner registry, a package internal.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/internal/backdrop_capture_debug.dart';

/// Counts layers per frame while a scene is open.
class LayerCensus {
  /// Creates a census that counts while [begin] has opened a scene, naming
  /// each backdrop filter's owner when [owners] is set.
  LayerCensus({bool owners = false}) : _named = owners {
    // ignore: invalid_use_of_internal_member
    if (owners) GlassLayerOwners.owners = Expando<RenderObject>();
    SchedulerBinding.instance.addPersistentFrameCallback(_onFrame);
  }

  final bool _named;
  String? _scene;
  final Map<String, List<Map<String, int>>> _frames = {};
  final Map<String, Map<String, int>> _owners = {};
  final Map<String, Map<String, int>> _firstOwners = {};
  final Map<RenderObject, String> _labels = {};

  /// Starts counting the frames of [scene].
  void begin(String scene) => _scene = scene;

  /// Stops counting.
  void end() => _scene = null;

  void _onFrame(Duration _) {
    final scene = _scene;
    if (scene == null) return;
    final counts = <String, int>{};
    final named = _named ? <String, int>{} : null;
    _placing = _named && (_frames[scene]?.isEmpty ?? true);
    final keys = <BackdropKey>{};
    for (final view in RendererBinding.instance.renderViews) {
      // The root layer is the census's whole input; profile builds expose
      // it only through the protected getter.
      // ignore: invalid_use_of_protected_member
      final root = view.layer;
      if (root != null) _walk(root, counts, named, keys);
    }
    counts['captures'] = (counts['captures'] ?? 0) + keys.length;
    final frames = _frames[scene] ??= [];
    frames.add(counts);
    if (named == null) return;
    final total = _owners[scene] ??= {};
    for (final MapEntry(:key, :value) in named.entries) {
      final at = key.indexOf(' @');
      final label = at < 0 ? key : key.substring(0, at);
      total[label] = (total[label] ?? 0) + value;
    }
    if (frames.length == 1) _firstOwners[scene] = named;
  }

  bool _placing = false;

  String _ownerOf(Layer layer) {
    final label = _labelOf(layer);
    if (!_placing) return label;
    // ignore: invalid_use_of_internal_member
    final owner = GlassLayerOwners.owners?[layer] ?? _layerOwners[layer];
    if (owner is! RenderBox || !owner.attached || !owner.hasSize) return label;
    final rect = MatrixUtils.transformRect(
      owner.getTransformTo(null),
      Offset.zero & owner.size,
    );
    return '$label @${rect.left.round()},${rect.top.round()} '
        '${rect.width.round()}x${rect.height.round()}';
  }

  String _labelOf(Layer layer) {
    final owner =
        // ignore: invalid_use_of_internal_member
        GlassLayerOwners.owners?[layer] ??
        // A render object whose own layer is the filter (BackdropFilter,
        // fake glass) is found by the walk below.
        _layerOwners[layer];
    if (owner == null) {
      _relabel();
      return _labels[_layerOwners[layer]] ?? 'unknown ${layer.runtimeType}';
    }
    final label = _labels[owner];
    if (label != null) return label;
    _relabel();
    return _labels[owner] ?? 'detached ${owner.runtimeType}';
  }

  final Map<Layer, RenderObject> _layerOwners = {};

  static bool _meaningful(String name) =>
      (name.startsWith('Morph') &&
          !name.startsWith('MorphLive') &&
          !_plumbing.contains(name)) ||
      (name.endsWith('Page') && !name.contains('Route'));

  static const Set<String> _plumbing = {
    'MorphGlassHost',
    'MorphGlassContentCopy',
    'MorphGlassStageFade',
    'MorphFlightScope',
    'MorphSurfaceSpecScope',
    'MorphWidgetsTheme',
    'MorphGlassContainerScope',
    'MorphGlassContainerBarrier',
    'MorphFocusRing',
    'MorphTouchListener',
    'MorphControlCapsule',
    'MorphGlassLayer',
    'MorphChromeBackdrop',
    'MorphChromeBackdropScope',
    'MorphBarItems',
    'MorphGlass',
    'MorphAdaptiveGlass',
    'MorphScope',
    'MorphControlFocus',
  };

  void _relabel() {
    _labels.clear();
    _layerOwners.clear();
    void visit(Element element, List<String> chain, String role) {
      final widget = element.widget;
      final name = widget.runtimeType.toString();
      final inner = _meaningful(name) && (chain.isEmpty || chain.last != name)
          ? [...chain, name]
          : chain;
      final key = widget.key;
      final here = key is ValueKey ? '${key.value}' : role;
      if (element is RenderObjectElement) {
        final object = element.renderObject;
        final tail = inner.length > 3 ? inner.sublist(inner.length - 3) : inner;
        _labels[object] = '${tail.join(' > ')} [$here] ${object.runtimeType}';
        // ignore: invalid_use_of_protected_member
        final own = object.layer;
        if (own is BackdropFilterLayer) _layerOwners[own] = object;
      }
      element.visitChildren((Element child) => visit(child, inner, here));
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root, const [], '-');
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
    'captures',
  ];

  static void _add(Map<String, int> counts, String kind) =>
      counts[kind] = (counts[kind] ?? 0) + 1;

  // Engine layers count only while they are in the scene: the opacity seed
  // drops its native pass when unseeded.
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  static bool _inScene(Layer layer) => layer.engineLayer != null;

  void _walk(
    Layer layer,
    Map<String, int> counts,
    Map<String, int>? named,
    Set<BackdropKey> keys,
  ) {
    _add(counts, 'layers');
    if (layer is BackdropFilterLayer && _inScene(layer)) {
      final key = layer.backdropKey;
      if (key == null) {
        _add(counts, 'captures');
      } else {
        keys.add(key);
      }
      if (named != null) _add(named, _ownerOf(layer));
    }
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
        _walk(child, counts, named, keys);
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
        if (_owners[scene] case final owners?)
          'owners': {
            for (final MapEntry(:key, :value) in _byCount(owners))
              key: value / frames.length,
          },
        'owners_first': ?_firstOwners[scene],
      },
  };

  static List<MapEntry<String, int>> _byCount(Map<String, int> counts) {
    final entries = counts.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }
}
