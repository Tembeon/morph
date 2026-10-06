import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/internal/backdrop_capture_debug.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_container.dart';
import 'package:morph/src/widgets/glass_liquid.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

/// Shows, over [child], how many glass layers the last frame drew, who
/// draws them, and which neighbouring resting glass could share one
/// [MorphGlassContainer].
///
/// Every separate glass layer is a backdrop filter of its own: the engine
/// reads the backdrop under it, filters it and composites it, whatever the
/// layer's size. On a Pixel 6a that is about 0.3 - 0.75 ms of raster time
/// per layer and frame; an iPhone pays far less, but every layer still
/// costs GPU time and energy. Apple's advice for Liquid Glass is the same
/// as this package's: group neighbouring glass in one container
/// (`GlassEffectContainer`, `UIGlassContainerEffect`), and morph's
/// [MorphGlassContainer] shades the resting glass in it in one layer.
///
/// The overlay counts the backdrop filters of the frame and the distinct
/// backdrops they read, names each filter by the Morph widgets above the
/// render object that paints it, and hints where a container would join
/// several layers: resting glass that would join a container (body glass
/// such as glass buttons and search capsules, not pressed, not a bar or a
/// menu, with one material) and that no clip, fade, filter, scrolling
/// viewport or backdrop group separates. It also names what keeps resting
/// glass out of a container it sits in. A hint is a place to look, not a
/// proof: only the app knows whether something it paints between two
/// controls must show through their glass - a container draws its glass
/// under everything inside it.
///
/// The inspector works in debug and profile builds. In a release build it
/// builds [child] alone and its code is removed. The overlay ignores
/// touches and rebuilds only when the counts change.
class MorphGlassInspector extends StatefulWidget {
  /// Shows the glass census of the app over [child] while [enabled].
  const MorphGlassInspector({
    required this.child,
    this.enabled = true,
    this.alignment = AlignmentDirectional.bottomStart,
    super.key,
  });

  /// The app.
  final Widget child;

  /// Whether the overlay shows.
  final bool enabled;

  /// Where the overlay sits over [child].
  final AlignmentGeometry alignment;

  /// The glass of the last frame; empty in a release build.
  static MorphGlassCensus census() =>
      kReleaseMode ? MorphGlassCensus.empty : _takeCensus();

  @override
  State<MorphGlassInspector> createState() => _MorphGlassInspectorState();
}

/// The glass layers of one frame, as [MorphGlassInspector] counts them.
@immutable
class MorphGlassCensus {
  /// Creates a census.
  const MorphGlassCensus({
    required this.filters,
    required this.captures,
    required this.owners,
    required this.hints,
  });

  /// A census of no glass.
  static const empty = MorphGlassCensus(
    filters: 0,
    captures: 0,
    owners: {},
    hints: [],
  );

  /// The backdrop filters the frame draws: one per separate glass layer,
  /// plus other backdrop blurs such as a scroll edge effect.
  final int filters;

  /// The distinct backdrops the filters read: a filter in no backdrop group
  /// reads its own, filters sharing a group share one.
  final int captures;

  /// The filters per owner: the Morph widgets above the render object that
  /// paints each filter, innermost last, with the glass role in brackets.
  final Map<String, int> owners;

  /// Where neighbouring resting glass could share one container.
  final List<MorphGlassHint> hints;
}

/// A place where resting glass draws more layers than it would need in a
/// [MorphGlassContainer].
@immutable
class MorphGlassHint {
  /// Creates a hint.
  const MorphGlassHint({
    required this.layers,
    required this.where,
    this.keptOutBy,
  });

  /// The separate glass layers concerned.
  final int layers;

  /// The widget whose glass is concerned: the nearest common ancestor of
  /// the layers, or the container the glass sits in.
  final String where;

  /// The widget between a container and glass inside it that keeps the
  /// glass in a layer of its own (a clip, a fade, a scrolling viewport),
  /// or null for glass in no container.
  final String? keptOutBy;

  /// The backdrop filters a container would save.
  int get saves => keptOutBy == null ? layers - 1 : layers;

  /// The hint in words.
  String get message => keptOutBy == null
      ? '$layers resting glass layers in $where could share one '
            'MorphGlassContainer: $saves filters fewer'
      : '$layers resting glass in $where kept out of its container by '
            '$keptOutBy';

  @override
  String toString() => message;
}

class _MorphGlassInspectorState extends State<MorphGlassInspector> {
  String _text = '';
  Object? _signature;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    if (!kReleaseMode && widget.enabled) _Frames.watch(this);
  }

  @override
  void didUpdateWidget(MorphGlassInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (kReleaseMode || widget.enabled == oldWidget.enabled) return;
    if (widget.enabled) {
      _Frames.watch(this);
    } else {
      _Frames.unwatch(this);
      _signature = null;
      _text = '';
    }
  }

  @override
  void dispose() {
    if (!kReleaseMode) _Frames.unwatch(this);
    super.dispose();
  }

  void _onFrame(Object signature) {
    if (!widget.enabled || signature == _signature || _pending) return;
    _pending = true;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      _pending = false;
      if (!mounted) return;
      _signature = signature;
      final text = _describe(_takeCensus());
      if (text != _text) setState(() => _text = text);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode || !widget.enabled) return widget.child;
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final inset = MediaQuery.maybePaddingOf(context) ?? EdgeInsets.zero;
    return Stack(
      textDirection: direction,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: Padding(
              padding: inset + const EdgeInsets.all(8),
              child: Align(
                alignment: widget.alignment.resolve(direction),
                child: _text.isEmpty
                    ? const SizedBox.shrink()
                    : DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xCC000000),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            _text,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              inherit: false,
                              fontSize: 11,
                              height: 1.3,
                              color: Color(0xFFFFFFFF),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _describe(MorphGlassCensus census) {
  final lines = <String>[
    'glass: ${census.filters} filters, ${census.captures} captures',
  ];
  final owners = census.owners.entries.toList();
  owners.sort((a, b) => b.value.compareTo(a.value));
  for (final MapEntry(:key, :value) in owners.take(8)) {
    lines.add('  $value  $key');
  }
  if (owners.length > 8) lines.add('  ... ${owners.length - 8} more');
  for (final hint in census.hints.take(4)) {
    lines.add('hint: ${hint.message}');
  }
  if (census.hints.any((MorphGlassHint h) => h.keptOutBy == null)) {
    lines.add('  each filter: ~0.3 - 0.75 ms raster a frame on a Pixel 6a');
  }
  return lines.join('\n');
}

/// The one frame hook every inspector shares: a persistent frame callback
/// cannot be removed, so it is added once and serves the inspectors alive.
abstract final class _Frames {
  static final Set<_MorphGlassInspectorState> _states = {};
  static bool _hooked = false;
  static Expando<RenderObject>? _owners;

  static void watch(_MorphGlassInspectorState state) {
    _states.add(state);
    if (GlassLayerOwners.owners == null) {
      _owners = Expando<RenderObject>();
      GlassLayerOwners.owners = _owners;
    }
    if (_hooked) return;
    _hooked = true;
    SchedulerBinding.instance.addPersistentFrameCallback((Duration _) {
      if (_states.isEmpty) return;
      final signature = _layerSignature();
      for (final state in _states.toList()) {
        state._onFrame(signature);
      }
    });
  }

  static void unwatch(_MorphGlassInspectorState state) {
    _states.remove(state);
    if (_states.isEmpty && identical(GlassLayerOwners.owners, _owners)) {
      GlassLayerOwners.owners = null;
      _owners = null;
    }
  }
}

Iterable<Layer> _roots() sync* {
  for (final view in RendererBinding.instance.renderViews) {
    // The census reads the composited layer tree in profile builds too,
    // where only the protected getter exposes it.
    // ignore: invalid_use_of_protected_member
    final root = view.layer;
    if (root != null) yield root;
  }
}

// A layer the engine skips (an unseeded opacity seed) has no engine layer.
// ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
bool _inScene(Layer layer) => layer.engineLayer != null;

Object _layerSignature() {
  final filters = <Object>[];
  void walk(Layer layer) {
    if (layer is BackdropFilterLayer && _inScene(layer)) {
      filters.add(layer);
      filters.add(layer.backdropKey ?? layer);
    }
    if (layer is ContainerLayer) {
      for (var c = layer.firstChild; c != null; c = c.nextSibling) {
        walk(c);
      }
    }
  }

  _roots().forEach(walk);
  return Object.hashAll(filters);
}

const Set<String> _plumbing = {
  'MorphGlassHost',
  'MorphGlassContentCopy',
  'MorphGlassStageFade',
  'MorphGlassContainerScope',
  'MorphGlassContainerBarrier',
  'MorphFlightScope',
  'MorphSurfaceSpecScope',
  'MorphWidgetsTheme',
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
  'MorphGlassInspector',
};

bool _meaningful(String name) =>
    (name.startsWith('Morph') &&
        !name.startsWith('MorphLive') &&
        !_plumbing.contains(name)) ||
    (name.endsWith('Page') && !name.contains('Route'));

MorphGlassCensus _takeCensus() {
  final root = WidgetsBinding.instance.rootElement;
  final labels = <RenderObject, String>{};
  final layerOwners = <Layer, RenderObject>{};
  final named = <Element, String>{};
  final hosts = <Element>[];
  void visit(Element element, List<String> chain, String role) {
    final widget = element.widget;
    final name = widget.runtimeType.toString();
    final inner = _meaningful(name) && (chain.isEmpty || chain.last != name)
        ? [...chain, name]
        : chain;
    final key = widget.key;
    final here = key is ValueKey ? '${key.value}' : role;
    if (inner.isNotEmpty) named[element] = inner.last;
    if (element is RenderObjectElement) {
      final object = element.renderObject;
      final tail = inner.length > 2 ? inner.sublist(inner.length - 2) : inner;
      labels[object] =
          '${tail.isEmpty ? object.runtimeType : tail.join(' > ')}'
          ' [$here]';
      // The owner of a composited layer is its render object.
      // ignore: invalid_use_of_protected_member
      final own = object.layer;
      if (own != null) layerOwners[own] = object;
    }
    if (debugMorphGlassHostOf(element) != null) hosts.add(element);
    element.visitChildren((Element child) => visit(child, inner, here));
  }

  if (root != null) visit(root, const [], '-');

  var filters = 0;
  var unkeyed = 0;
  final keys = <BackdropKey>{};
  final owners = <String, int>{};
  void walk(Layer layer, RenderObject? owner) {
    final own = layerOwners[layer] ?? owner;
    if (layer is BackdropFilterLayer && _inScene(layer)) {
      filters++;
      final key = layer.backdropKey;
      if (key == null) {
        unkeyed++;
      } else {
        keys.add(key);
      }
      final by = GlassLayerOwners.owners?[layer] ?? own;
      final label = by == null ? 'unknown' : labels[by] ?? '${by.runtimeType}';
      owners[label] = (owners[label] ?? 0) + 1;
    }
    if (layer is ContainerLayer) {
      for (var c = layer.firstChild; c != null; c = c.nextSibling) {
        walk(c, own);
      }
    }
  }

  for (final layer in _roots()) {
    walk(layer, null);
  }
  return MorphGlassCensus(
    filters: filters,
    captures: unkeyed + keys.length,
    owners: owners,
    hints: _hints(hosts, named),
  );
}

bool _resting(MorphGlassRenderer renderer, MorphGlassFrame frame) {
  final parts = frame.parts;
  if (!frame.still ||
      parts.separate.isEmpty ||
      parts.fused.isNotEmpty ||
      parts.floating.isNotEmpty) {
    return false;
  }
  for (final surface in parts.separate) {
    if (surface.lift != 0 ||
        surface.kind == MorphGlassKind.bar ||
        surface.kind == MorphGlassKind.menu ||
        morphLiquidSettings(renderer, surface) !=
            morphLiquidSettings(renderer, parts.separate.first)) {
      return false;
    }
  }
  return true;
}

String _nameOf(Element element, Map<Element, String> named) {
  final own = element.widget.runtimeType.toString();
  final context = named[element];
  return context == null || context == own ? own : '$own in $context';
}

List<MorphGlassHint> _hints(List<Element> hosts, Map<Element, String> named) {
  final planes = <(Element?, Object), List<Element>>{};
  final kept = <(Element, Element), int>{};
  for (final host in hosts) {
    final state = debugMorphGlassHostOf(host);
    if (state == null || state.joined || state.mode != MorphGlassMode.layer) {
      continue;
    }
    final painter = state.painter;
    if (painter.runtimeType != MorphGlassRenderer) continue;
    final renderer = painter as MorphGlassRenderer;
    if (renderer.effectiveTier == MorphGlassTier.flat ||
        !_resting(renderer, state.frame)) {
      continue;
    }
    final scope = host
        .getElementForInheritedWidgetOfExactType<MorphGlassContainerScope>();
    if (scope != null && (scope.widget as MorphGlassContainerScope).open) {
      final blocker = morphGlassContainerBlocker(host, until: scope);
      if (blocker != null) {
        kept[(scope, blocker)] = (kept[(scope, blocker)] ?? 0) + 1;
      }
      continue;
    }
    final settings = morphLiquidSettings(
      renderer,
      state.frame.parts.separate.first,
    );
    (planes[(morphGlassContainerBlocker(host), settings)] ??= []).add(host);
  }
  final hints = <MorphGlassHint>[];
  for (final MapEntry(key: (plane, _), value: group) in planes.entries) {
    if (group.length < 2) continue;
    final common = _commonAncestor(group);
    if (identical(common, plane)) continue;
    hints.add(
      MorphGlassHint(layers: group.length, where: _nameOf(common, named)),
    );
  }
  for (final MapEntry(key: (scope, blocker), value: count) in kept.entries) {
    hints.add(
      MorphGlassHint(
        layers: count,
        where: _containerName(scope, named),
        keptOutBy: blocker.widget.runtimeType.toString(),
      ),
    );
  }
  hints.sort((a, b) => b.saves.compareTo(a.saves));
  return hints;
}

String _containerName(Element scope, Map<Element, String> named) {
  Element? container;
  Element? above;
  scope.visitAncestorElements((Element element) {
    if (container != null) {
      above = element;
      return false;
    }
    final widget = element.widget;
    if (widget is MorphGlassContainer || widget is MorphGlassStage) {
      container = element;
    }
    return true;
  });
  final name = container?.widget.runtimeType.toString() ?? 'a container';
  final context = above == null ? null : named[above];
  return context == null ? name : '$name in $context';
}

Element _commonAncestor(List<Element> elements) {
  List<Element> chain(Element element) {
    final out = <Element>[element];
    element.visitAncestorElements((Element a) {
      out.add(a);
      return true;
    });
    return out;
  }

  final others = [
    for (final element in elements.skip(1)) chain(element).toSet(),
  ];
  for (final candidate in chain(elements.first).skip(1)) {
    if (others.every((Set<Element> s) => s.contains(candidate))) {
      return candidate;
    }
  }
  return elements.first;
}
