import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_liquid.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// Shades the resting glass of the controls below it in one glass layer:
/// one geometry pass and one backdrop filter for all of them instead of
/// one each.
///
/// UIKit's `UIGlassContainerEffect` for glass that does not fuse: sibling
/// glass buttons on one plane - a row of buttons, a cluster over a map -
/// read the backdrop once and are shaded together. Each control still
/// lays out, hits, moves and paints its content as before.
///
/// The container's glass is painted where the container paints, under
/// everything inside it, and it is drawn whatever lies between the
/// container and a control: a control under an opacity, a clip, a filter
/// or a scrolling viewport inside the container (a list of buttons, a
/// fading or hidden button, a morph source) keeps its own layer. So everything in [child] is content above the
/// glass: a card, a row background or an image placed inside the container
/// would cover the glass of the buttons over it. Put what the glass must
/// show through outside the container, under it.
///
/// Only glass that would look the same either way joins: resting body
/// glass (glass buttons, search capsules) of the installed
/// [MorphGlassRenderer] on the liquid or fake tier, with the material the
/// container's own resting button has and the tint of the glass already
/// in the container, up to the most shapes one geometry pass encodes. A pressed button, whose rim lights up, a lens, a bar, a
/// menu and every other surface keep their own layer, as without the
/// container. On the flat tier, under another painter or with no painter
/// installed the container does nothing.
class MorphGlassContainer extends StatefulWidget {
  /// Shades the resting glass of the controls in [child] together.
  const MorphGlassContainer({required this.child, super.key});

  /// The controls whose resting glass the container shades.
  final Widget child;

  @override
  State<MorphGlassContainer> createState() => _MorphGlassContainerState();
}

class _MorphGlassContainerState extends State<MorphGlassContainer> {
  final MorphGlassContainerLink _link = MorphGlassContainerLink();

  @override
  Widget build(BuildContext context) =>
      _containerLayer(context, _link, open: true, child: widget.child);
}

/// A glass container a package widget owns: [open] while nothing it does
/// to its members - a fade, a scale, a blur - changes how their glass
/// would look in layers of their own.
///
/// The stage's own fades go through [MorphGlassStageFade], which a member
/// sees through; whenever such a fade is not opaque, or anything else the
/// stage draws between its members moves, the stage closes and every
/// member draws its own layer, in the same frame.
@internal
class MorphGlassStage extends StatefulWidget {
  /// Shades the resting glass in [child] together while [open].
  const MorphGlassStage({required this.open, required this.child, super.key});

  /// Whether the members are shaded together now.
  final bool open;

  /// The members.
  final Widget child;

  @override
  State<MorphGlassStage> createState() => _MorphGlassStageState();
}

class _MorphGlassStageState extends State<MorphGlassStage> {
  final MorphGlassContainerLink _link = MorphGlassContainerLink();

  @override
  Widget build(BuildContext context) =>
      _containerLayer(context, _link, open: widget.open, child: widget.child);
}

/// An [Opacity] of a [MorphGlassStage] that its members see through: the
/// stage closes whenever [opacity] is below 1.
@internal
class MorphGlassStageFade extends Opacity {
  /// Fades [child] by [opacity].
  const MorphGlassStageFade({required super.opacity, super.child, super.key});

  @override
  RenderOpacity createRenderObject(BuildContext context) =>
      _RenderStageFade(opacity: opacity);
}

class _RenderStageFade extends RenderOpacity {
  _RenderStageFade({super.opacity});
}

Widget _containerLayer(
  BuildContext context,
  MorphGlassContainerLink link, {
  required bool open,
  required Widget child,
}) {
  final painter = MorphGlass.maybeOf(context);
  if (painter is! MorphGlassRenderer ||
      painter.runtimeType != MorphGlassRenderer) {
    return child;
  }
  return ValueListenableBuilder<bool>(
    valueListenable: morphLiquidGlassCapability,
    builder: (BuildContext context, bool _, Widget? child) {
      final tier = painter.effectiveTier;
      if (tier == MorphGlassTier.flat) return child!;
      final settings = morphLiquidSettings(
        painter,
        MorphGlassSurface(
          kind: MorphGlassKind.button,
          shape: RRect.zero,
          color: const Color(0x00000000),
          brightness: morphBrightnessOf(context),
        ),
      );
      link.configure(painter, settings);
      return LiquidGlassLayer(
        settings: settings,
        fake: tier == MorphGlassTier.fake,
        useBackdropGroup: true,
        child: MorphGlassContainerScope(
          link: link,
          renderer: painter,
          settings: settings,
          open: open,
          child: child!,
        ),
      );
    },
    child: child,
  );
}

/// Whether the glass of [host] would look the same shaded by the nearest
/// glass container: nothing between them fades, clips, filters or hides
/// what is painted, since the container's layer shades every shape it
/// holds whatever lies between, and no backdrop group between them gives
/// the host a backdrop copy other than the container's (a bar floating in
/// its own group stays out).
@internal
bool morphGlassContainerReaches(Element host) {
  final scope = host
      .getElementForInheritedWidgetOfExactType<MorphGlassContainerScope>();
  if (scope == null) return false;
  final group = scope.getElementForInheritedWidgetOfExactType<BackdropGroup>();
  final shared = (group?.widget as BackdropGroup?)?.backdropKey;
  var clear = true;
  host.visitAncestorElements((Element element) {
    if (identical(element, scope)) return false;
    final widget = element.widget;
    if (widget is BackdropGroup && widget.backdropKey != shared) {
      clear = false;
      return false;
    }
    final render = element is RenderObjectElement ? element.renderObject : null;
    if (render is _RenderStageFade) return true;
    if (render is RenderOpacity ||
        render is RenderAnimatedOpacityMixin ||
        render is RenderSliverOpacity ||
        render is RenderOffstage ||
        render is RenderClipRect ||
        render is RenderClipRRect ||
        render is RenderClipRSuperellipse ||
        render is RenderClipOval ||
        render is RenderClipPath ||
        render is RenderShaderMask ||
        render is RenderBackdropFilter ||
        render is RenderViewportBase ||
        render is RenderFollowerLayer ||
        element.widget is ImageFiltered ||
        element.widget is ColorFiltered ||
        element.widget is Visibility) {
      clear = false;
      return false;
    }
    return true;
  });
  return clear;
}

/// The glass container above a control, read by its glass hosts.
@internal
class MorphGlassContainerScope extends InheritedWidget {
  /// Publishes [link] for the hosts in [child].
  const MorphGlassContainerScope({
    required this.link,
    required this.renderer,
    required this.settings,
    required super.child,
    this.open = true,
    super.key,
  });

  /// Whether the container takes members now; a closed one is no
  /// container to them.
  final bool open;

  /// The container's admission record.
  final MorphGlassContainerLink link;

  /// The renderer the container shades with.
  final MorphGlassRenderer renderer;

  /// The settings of the container's layer.
  final LiquidGlassSettings settings;

  /// The nearest container above [context], or null.
  static MorphGlassContainerLink? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MorphGlassContainerScope>();
    return scope != null && scope.open ? scope.link : null;
  }

  @override
  bool updateShouldNotify(MorphGlassContainerScope oldWidget) =>
      oldWidget.open != open ||
      oldWidget.link != link ||
      oldWidget.renderer != renderer ||
      oldWidget.settings != settings;
}

/// Which glass hosts a container shades, and how many shapes each holds.
@internal
class MorphGlassContainerLink {
  MorphGlassRenderer? _renderer;
  LiquidGlassSettings? _settings;
  LiquidGlassAppearance? _appearance;
  final Map<Object, int> _members = {};
  int _shapes = 0;

  /// The most shapes the container's layer shades.
  static const int capacity = FlutterGpuGeometryRenderer.maxShapes;

  /// The shapes the container shades now.
  int get shapes => _shapes;

  /// Sets the renderer and the layer settings members must match.
  void configure(MorphGlassRenderer renderer, LiquidGlassSettings settings) {
    _renderer = renderer;
    _settings = settings;
  }

  /// Whether [host], drawing [frame] with [renderer], is shaded by the
  /// container; records or releases its shapes accordingly.
  bool admit(Object host, MorphGlassRenderer renderer, MorphGlassFrame frame) {
    final count = _joinable(renderer, frame);
    final held = _members[host];
    if (count == 0 || _shapes - (held ?? 0) + count > capacity) {
      release(host);
      return false;
    }
    _members[host] = count;
    _shapes += count - (held ?? 0);
    return true;
  }

  /// Whether [host] is shaded by the container.
  bool holds(Object host) => _members.containsKey(host);

  /// Gives back the shapes of [host].
  void release(Object host) {
    final held = _members.remove(host);
    if (held != null) _shapes -= held;
    if (_members.isEmpty) _appearance = null;
  }

  int _joinable(MorphGlassRenderer renderer, MorphGlassFrame frame) {
    final settings = _settings;
    if (settings == null ||
        renderer != _renderer ||
        renderer.effectiveTier == MorphGlassTier.flat) {
      return 0;
    }
    final parts = frame.parts;
    if (!frame.still ||
        parts.separate.isEmpty ||
        parts.fused.isNotEmpty ||
        parts.floating.isNotEmpty) {
      return 0;
    }
    var appearance = _appearance;
    for (final surface in parts.separate) {
      final own = morphLiquidAppearance(renderer, surface);
      appearance ??= own;
      if (surface.lift != 0 ||
          surface.kind == MorphGlassKind.bar ||
          surface.kind == MorphGlassKind.menu ||
          own != appearance ||
          morphLiquidSettings(renderer, surface) != settings) {
        return 0;
      }
    }
    _appearance = appearance;
    return parts.separate.length;
  }
}
