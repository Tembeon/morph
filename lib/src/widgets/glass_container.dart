import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_liquid.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/glass_inspector.dart';
import 'package:morph/src/widgets/list.dart';
import 'package:morph/src/widgets/search_field.dart';
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
/// fading or hidden button, a morph source while it flies) keeps its own
/// layer. So everything in [child] is content above the
/// glass: a card, a row background or an image placed inside the container
/// would cover the glass of the buttons over it. Put what the glass must
/// show through outside the container, under it.
///
/// Only glass that looks the same, or within a few channel steps, either
/// way joins: resting body glass (glass buttons, search capsules) of the
/// installed [MorphGlassRenderer] on the liquid or fake tier, with the
/// material the container's own resting button has, up to the most shapes
/// one geometry pass encodes. A member whose glass differs only in tint (a
/// prominent button) joins too and reads its tint from the layer's material
/// map: at most 7 channel steps on about 100 rim pixels on the iPhone 16
/// Pro. A pressed button, whose rim lights up, a lens, a bar, a
/// menu and every other surface keep their own layer, as without the
/// container. On the flat tier, under another painter or with no painter
/// installed the container does nothing.
///
/// Group neighbouring glass, as Apple advises for Liquid Glass: every
/// separate glass layer reads, filters and composites the backdrop under
/// it whatever its size, about 0.3 - 0.75 ms of raster time per layer and
/// frame on a Pixel 6a. Four resting buttons over a scrolling page draw 18
/// percent faster on that phone in a container, eight 22 percent. Wrap
/// the row or cluster itself, inside any scroll view, clip or fade: a
/// container around a scroll view joins nothing in it. A
/// [MorphListSection] already shades its rows' resting glass in one layer,
/// a resting [MorphSearchToolbar] its field and buttons.
/// [MorphGlassInspector] shows the layers of each frame and names
/// neighbouring glass that a container would join.
class MorphGlassContainer extends StatefulWidget {
  /// Shades the resting glass of the controls in [child] together.
  const MorphGlassContainer({
    required this.child,
    this.solidBackdrop,
    super.key,
  });

  /// The controls whose resting glass the container shades.
  final Widget child;

  /// The opaque color the container is painted directly over, or null.
  ///
  /// Declare it when the container sits on a fill of this color with
  /// nothing painted between, and its members are inset from the fill's
  /// edges by more than their refraction reaches - typically a cluster of
  /// buttons on a page's own background. The container then shades its
  /// members over the color itself instead of reading the backdrop: no
  /// backdrop filter at all, the most expensive part of glass on a phone's
  /// GPU. The container trusts the color: glass over anything else shows
  /// this color instead. A member that leaves the container reads its
  /// backdrop in its own layer as before. Ignored unless the color is
  /// fully opaque.
  final Color? solidBackdrop;

  @override
  State<MorphGlassContainer> createState() => _MorphGlassContainerState();
}

class _MorphGlassContainerState extends State<MorphGlassContainer> {
  final MorphGlassContainerLink _link = MorphGlassContainerLink();

  @override
  Widget build(BuildContext context) => _containerLayer(
    context,
    _link,
    open: true,
    solidBackdrop: widget.solidBackdrop,
    child: widget.child,
  );
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
  const MorphGlassStage({
    required this.open,
    required this.child,
    this.sharpOnly = false,
    this.solidBackdrop,
    super.key,
  });

  /// Whether the members are shaded together now.
  final bool open;

  /// The opaque color the stage is painted directly over, or null.
  ///
  /// When every member's glass would read only this color - the stage
  /// sits on a fill of it with nothing painted between, and its members
  /// are inset from the fill's edges by more than their refraction reaches
  /// - the stage shades its members over the color itself instead of
  /// reading the backdrop: no backdrop filter at all. A member that leaves
  /// the stage reads its backdrop in its own layer as before. Ignored
  /// unless the color is fully opaque.
  final Color? solidBackdrop;

  /// Whether the stage closes while its glass would blur: for a stage
  /// that paints content between its members, which resting glass without
  /// a blur never reads (its refraction samples only inside its own
  /// outline) but a frosted one reads around its rim.
  final bool sharpOnly;

  /// The members.
  final Widget child;

  @override
  State<MorphGlassStage> createState() => _MorphGlassStageState();
}

class _MorphGlassStageState extends State<MorphGlassStage> {
  final MorphGlassContainerLink _link = MorphGlassContainerLink();

  @override
  Widget build(BuildContext context) => _containerLayer(
    context,
    _link,
    open: widget.open && debugMorphGlassStagesOpen,
    sharpOnly: widget.sharpOnly,
    solidBackdrop: debugMorphGlassStageSolidBackdrops
        ? widget.solidBackdrop
        : null,
    child: widget.child,
  );
}

/// Whether package stages that know their solid backdrop shade over it;
/// false makes them read their backdrop, the reference the solid backdrop
/// is measured against.
@visibleForTesting
@internal
bool debugMorphGlassStageSolidBackdrops = true;

/// Whether package stages shade their members together; false keeps every
/// member in its own layer, the reference a stage is measured against.
@visibleForTesting
@internal
bool debugMorphGlassStagesOpen = true;

/// Closes every glass container in [child] while [open] is false.
///
/// A glass container rasterizes all its members' mattes on its own grid
/// and moves each member's shapes so that they read the pixels a layer of
/// its own would read. That works while the container is drawn under a
/// translation; under a scale the grids of members at different fractions
/// of a device pixel from the container no longer meet at any one shift,
/// so a package widget that draws its content scaled (a floating sheet)
/// closes the containers in it until it draws it unscaled again, and every
/// member draws its own layer, in the same frame.
@internal
class MorphGlassContainerGate extends StatelessWidget {
  /// Closes the containers in [child] unless [open].
  const MorphGlassContainerGate({
    required this.open,
    required this.child,
    super.key,
  });

  /// Whether the containers in [child] may shade their members together.
  final bool open;

  /// The subtree whose containers the gate closes.
  final Widget child;

  /// Whether every gate above [context] is open.
  static bool openAt(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GateScope>()?.open ?? true;

  @override
  Widget build(BuildContext context) =>
      _GateScope(open: open && openAt(context), child: child);
}

class _GateScope extends InheritedWidget {
  const _GateScope({required this.open, required super.child});

  final bool open;

  @override
  bool updateShouldNotify(_GateScope oldWidget) => oldWidget.open != open;
}

/// Keeps the glass in [child] out of every glass container above it while
/// [clear] is false: for a package widget that sometimes paints between a
/// container and its members, as a list row paints its highlight under
/// its accessories.
@internal
class MorphGlassContainerBarrier extends InheritedWidget {
  /// Lets the glass in [child] reach a container above it only while
  /// [clear].
  const MorphGlassContainerBarrier({
    required this.clear,
    required super.child,
    super.key,
  });

  /// Whether nothing is painted between a container above and the glass in
  /// the child now.
  final bool clear;

  @override
  bool updateShouldNotify(MorphGlassContainerBarrier oldWidget) =>
      clear != oldWidget.clear;
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
  bool sharpOnly = false,
  Color? solidBackdrop,
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
        defaultAppearance: morphLiquidAppearance(
          painter,
          MorphGlassSurface(
            kind: MorphGlassKind.button,
            shape: RRect.zero,
            color: const Color(0x00000000),
            brightness: morphBrightnessOf(context),
          ),
        ),
        fake: tier == MorphGlassTier.fake,
        useBackdropGroup: true,
        solidBackdrop: solidBackdrop,
        child: MorphGlassContainerScope(
          link: link,
          renderer: painter,
          settings: settings,
          open:
              open &&
              MorphGlassContainerGate.openAt(context) &&
              (!sharpOnly || settings.effectiveFrost == 0),
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
/// its own group stays out). A [MorphTag]'s own opacity is seen through
/// while the tag shows its child; the host depends on the tag, so a tag
/// hiding for its flight sends it back into a layer of its own.
@internal
bool morphGlassContainerReaches(Element host) {
  final scope = host
      .getElementForInheritedWidgetOfExactType<MorphGlassContainerScope>();
  if (scope == null) return false;
  final group = scope.getElementForInheritedWidgetOfExactType<BackdropGroup>();
  final shared = (group?.widget as BackdropGroup?)?.backdropKey;
  var clear = true;
  Element? below;
  host.visitAncestorElements((Element element) {
    if (identical(element, scope)) return false;
    final child = below;
    below = element;
    final widget = element.widget;
    if (widget is MorphGlassContainerBarrier || widget is MorphTagVisibility) {
      host.dependOnInheritedElement(element as InheritedElement);
    }
    if (_passes(element, child, (BackdropKey key) => key == shared)) {
      return true;
    }
    clear = false;
    return false;
  });
  return clear;
}

/// The nearest ancestor of [host] below [until] that keeps its glass out of
/// a glass container above it, or null when none does; with [until] null,
/// every [BackdropGroup] keeps it out and the walk ends at the root.
@internal
Element? morphGlassContainerBlocker(Element host, {Element? until}) {
  final group = until?.getElementForInheritedWidgetOfExactType<BackdropGroup>();
  final shared = (group?.widget as BackdropGroup?)?.backdropKey;
  Element? blocker;
  Element? below;
  host.visitAncestorElements((Element element) {
    if (identical(element, until)) return false;
    final child = below;
    below = element;
    if (_passes(
      element,
      child,
      (BackdropKey key) => until != null && key == shared,
    )) {
      return true;
    }
    blocker = element;
    return false;
  });
  return blocker;
}

bool _passes(
  Element element,
  Element? child,
  bool Function(BackdropKey key) shares,
) {
  final widget = element.widget;
  if (widget is BackdropGroup) return shares(widget.backdropKey);
  if (widget is MorphGlassContainerBarrier) return widget.clear;
  if (widget is MorphTagVisibility) return !widget.hidden;
  final render = element is RenderObjectElement ? element.renderObject : null;
  if (render is _RenderStageFade) return true;
  if (render is RenderOpacity &&
      child?.widget is MorphTagVisibility &&
      render.opacity == 1) {
    return true;
  }
  return !(render is RenderOpacity ||
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
      widget is ImageFiltered ||
      widget is ColorFiltered ||
      widget is Visibility);
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
    final parts = frame.partsFor(renderer.effectiveTier);
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
          own.copyWith(tint: appearance.tint) != appearance ||
          morphLiquidSettings(renderer, surface) != settings) {
        return 0;
      }
    }
    _appearance = appearance;
    return parts.separate.length;
  }
}
