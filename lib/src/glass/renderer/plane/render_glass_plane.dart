import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:morph/src/glass/renderer/geometry/glass_rest.dart';
import 'package:morph/src/glass/renderer/internal/render_liquid_glass_geometry.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_render_object.dart';

/// How a plane draws one member's glass.
@internal
enum GlassStrategy {
  /// In the member's own layer, through a backdrop filter of its own.
  split,

  /// In the plane's one pass, together with the plane's other merged
  /// members.
  merged,

  /// In the member's own layer, painted over a solid or a cached backdrop
  /// instead of through a backdrop filter.
  painted,
}

/// Why a member's glass is drawn in a layer of its own, in the order a
/// plane checks them.
@internal
enum GlassSplit {
  /// No owned plane is above the member.
  unowned,

  /// Its plane merges nothing now: a stage its owner closed.
  closed,

  /// It reads a backdrop of its own: chrome, or a lifted lens.
  read,

  /// It shows a touch glow, which a pass applies to all of its glass.
  glow,

  /// It shades one fused body, or its shapes blend.
  fused,

  /// It holds no shapes, or shapes of different materials.
  empty,

  /// It frosts, and its plane lets content paint between the plane and
  /// the glass: the frost would read that content around its rim.
  frost,

  /// Something between it and its plane changes how its glass looks: a
  /// fade, a clip, a filter, a scrolling viewport, other glass, a
  /// [GlassPlaneScope.planeBreak].
  blocked,

  /// It or its plane is drawn under more than a translation, where the
  /// raster grids of a pass and of a layer of its own no longer meet.
  scaled,

  /// Its settings differ from its plane's.
  settings,

  /// Its material differs, beyond its tint, from the glass merged before
  /// it.
  look,

  /// Its shapes would exceed what one pass holds.
  capacity,

  /// Its glass moved within the last frames.
  moving,
}

/// What a plane does with one member's glass, and why.
@internal
@immutable
final class GlassMemberCensus {
  /// Describes a member drawn by [strategy], kept apart by [split] when it
  /// is not merged, by [blocker] for [GlassSplit.blocked].
  const GlassMemberCensus(this.strategy, {this.split, this.blocker});

  /// How the member's glass is drawn.
  final GlassStrategy strategy;

  /// Why it is not merged, or null when it is.
  final GlassSplit? split;

  /// The render object between the member and its plane that keeps it out,
  /// for [GlassSplit.blocked].
  final RenderObject? blocker;

  @override
  String toString() => switch (split) {
    null => strategy.name,
    final split => '${strategy.name} (${split.name})',
  };
}

/// The settings and the material, tint aside, that all of a member's
/// shapes share, and how many shapes there are.
@internal
typedef GlassLook = ({
  LiquidGlassSettings settings,
  LiquidGlassAppearance appearance,
  int shapes,
});

/// What a glass layer tells its plane about itself, read again on every
/// notification of its sources.
@internal
typedef GlassMemberInputs = ({
  LiquidGlassSettings settings,
  bool fused,
  bool glows,
});

/// The nearest render object strictly between [member] and [plane] (the
/// root when [plane] is null) that changes how glass under it looks, so
/// that a pass at [plane] would not draw [member]'s glass as its own layer
/// does; null when there is none.
///
/// A fade blocks unless it is exactly opaque, a [GlassPlaneScope.planeBreak]
/// while active; a clip, an offstage, a shader mask, a backdrop filter, a
/// follower, a viewport and other glass always do. Anything else that
/// composites a layer of its own (an image or color filter) blocks too.
@internal
RenderObject? glassPlaneBlocker(RenderObject member, RenderObject? plane) {
  for (var node = member.parent; node != null; node = node.parent) {
    if (identical(node, plane)) return null;
    if (_blocks(node)) return node;
  }
  return null;
}

bool _blocks(RenderObject node) => switch (node) {
  RenderGlassPlaneBreak(:final active) => active,
  RenderOpacity(:final opacity) => opacity != 1,
  RenderSliverOpacity(:final opacity) => opacity != 1,
  RenderAnimatedOpacityMixin() ||
  RenderOffstage() ||
  RenderSliverOffstage() ||
  RenderClipRect() ||
  RenderClipRRect() ||
  RenderClipRSuperellipse() ||
  RenderClipOval() ||
  RenderClipPath() ||
  RenderShaderMask() ||
  RenderBackdropFilter() ||
  RenderFollowerLayer() ||
  RenderAbstractViewport() ||
  RenderGlassMember() => true,
  RenderRepaintBoundary() || RenderGlassPlane() => false,
  // A render object that always composites a layer of its own applies an
  // effect to what it holds; the public effects above are the common ones,
  // this catches the private ones (ImageFiltered, ColorFiltered).
  // ignore: invalid_use_of_protected_member
  _ => node.alwaysNeedsCompositing,
};

/// The render object of a glass layer, through which the layer reports to
/// its plane: the layer's repaint boundary, which clips the layer to its
/// reach, registers with the nearest [RenderGlassPlane] above it and
/// follows whether its glass rests.
@internal
class RenderGlassMember extends RenderProxyBox {
  /// Creates the member of a layer that reads [read], whose shapes
  /// register with [link].
  RenderGlassMember({
    required this._read,
    required this._link,
    required GlassMemberInputs Function() inputsOf,
    this._reach,
    this._painted = false,
    this.backdropKey,
  }) : _inputsOf = inputsOf,
       _inputs = inputsOf();

  /// Whether members outside any plane follow their rest too, for a census
  /// of the whole app (a glass inspector); members of a plane always do.
  static bool followsRestEverywhere = false;

  GlassRead _read;

  /// Where the layer reads its backdrop.
  GlassRead get read => _read;
  set read(GlassRead value) {
    if (_read == value) return;
    _read = value;
    _plane?.memberChanged(this);
  }

  GeometryRenderLink _link;

  /// The link the layer's shapes register with.
  GeometryRenderLink get link => _link;
  set link(GeometryRenderLink value) {
    if (identical(_link, value)) return;
    _link = value;
    _lastTransform = null;
    _plane?.memberChanged(this);
  }

  GlassMemberInputs Function() _inputsOf;
  GlassMemberInputs _inputs;

  /// Reads the layer's inputs through [inputsOf] from now on.
  void readInputs(GlassMemberInputs Function() inputsOf) {
    _inputsOf = inputsOf;
    _refresh();
  }

  /// The layer's settings.
  LiquidGlassSettings get settings => _inputs.settings;

  /// Whether the layer shades one fused body.
  bool get fused => _inputs.fused;

  /// Whether the layer shows a touch glow.
  bool get glows => _inputs.glows;

  double? _reach;

  /// How far around its box the layer may paint, or null for anywhere.
  ///
  /// Bounds the backdrop pass the renderer blurs to the control instead of
  /// the whole screen.
  double? get reach => _reach;
  set reach(double? value) {
    if (_reach == value) return;
    _reach = value;
    markNeedsPaint();
  }

  bool _painted;

  /// Whether the layer paints its glass over a solid or a cached backdrop
  /// instead of through a backdrop filter.
  bool get painted => _painted;
  set painted(bool value) {
    if (_painted == value) return;
    _painted = value;
    _plane?.memberChanged(this);
  }

  /// The plane read the layer's glass shares, or null for a read of its
  /// own.
  BackdropKey? backdropKey;

  Listenable? _live;
  Listenable? _glows;

  /// Reads the inputs again on every notification of [live] and [glows].
  void listen(Listenable? live, Listenable? glows) {
    if (identical(live, _live) && identical(glows, _glows)) return;
    if (attached) {
      _live?.removeListener(_refresh);
      _glows?.removeListener(_refresh);
      live?.addListener(_refresh);
      glows?.addListener(_refresh);
    }
    _live = live;
    _glows = glows;
  }

  void _refresh() {
    final inputs = _inputsOf();
    if (inputs == _inputs) return;
    _inputs = inputs;
    _plane?.memberChanged(this);
  }

  RenderGlassPlane? _plane;

  /// The plane the member belongs to, or null outside any.
  RenderGlassPlane? get plane => _plane;

  /// What the member's plane does with its glass.
  GlassMemberCensus get census =>
      _plane?.censusOf(this) ??
      GlassMemberCensus(
        _painted ? GlassStrategy.painted : GlassStrategy.split,
        split: GlassSplit.unowned,
      );

  /// The look the member's glass would share with other glass in one pass:
  /// null for a layer that reads a backdrop of its own, glows or fuses, and
  /// for one without shapes or with shapes of different materials.
  GlassLook? get look {
    if (_read != GlassRead.plane || glows || fused) return null;
    LiquidGlassAppearance? appearance;
    var shapes = 0;
    for (final shape in _link.shapes) {
      if (shape is! LiquidGlassShapeRenderObject) return null;
      final own = (shape as LiquidGlassShapeRenderObject).appearance.copyWith(
        tint: const Color(0x00000000),
      );
      if (appearance != null && own != appearance) return null;
      appearance = own;
      shapes++;
    }
    if (appearance == null) return null;
    return (settings: settings, appearance: appearance, shapes: shapes);
  }

  int _quiet = GlassRestWatch.restFrames;
  Matrix4? _lastTransform;
  int _lastRevision = 0;

  /// Whether the member's glass stayed where it is, relative to its plane,
  /// and unchanged for [GlassRestWatch.restFrames] composited frames; a
  /// member counts as resting from the moment it appears.
  bool get resting => _quiet >= GlassRestWatch.restFrames;

  void _composited() {
    if (!attached) return;
    final plane = _plane;
    if (plane == null && !followsRestEverywhere) return;
    final transform = getTransformTo(plane);
    final revision = _link.revision;
    final last = _lastTransform;
    final moved =
        last != null &&
        (revision != _lastRevision ||
            !MatrixUtils.matrixEquals(transform, last));
    _lastTransform = transform;
    _lastRevision = revision;
    final was = resting;
    _quiet = moved ? 0 : math.min(_quiet + 1, GlassRestWatch.restFrames);
    if (was != resting) plane?.memberChanged(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _live?.addListener(_refresh);
    _glows?.addListener(_refresh);
    _inputs = _inputsOf();
    _lastTransform = null;
    _quiet = GlassRestWatch.restFrames;
    for (var node = parent; node != null; node = node.parent) {
      if (node is RenderGlassPlane) {
        _plane = node;
        node._join(this);
        break;
      }
    }
  }

  @override
  void detach() {
    _plane?._leave(this);
    _plane = null;
    _live?.removeListener(_refresh);
    _glows?.removeListener(_refresh);
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  OffsetLayer updateCompositedLayer({required OffsetLayer? oldLayer}) {
    final layer = oldLayer is _MemberLayer ? oldLayer : _MemberLayer();
    layer.member = this;
    return layer;
  }

  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    final reach = _reach;
    if (reach == null) {
      _clip.layer = null;
      super.paint(context, offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      (Offset.zero & size).inflate(reach),
      super.paint,
      oldLayer: _clip.layer,
    );
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}

/// A member's layer: hands the member the compositing of every frame it
/// is drawn in, after the frame's paint.
class _MemberLayer extends OffsetLayer {
  RenderGlassMember? member;

  @override
  void updateSubtreeNeedsAddToScene() {
    member?._composited();
    super.updateSubtreeNeedsAddToScene();
  }
}

/// The render object of a plane whose owner declares what is painted
/// between it and its glass ([GlassPlaneScope.owned]): it knows the glass
/// layers below it and decides, from their facts, which of them its pass
/// draws ([GlassMemberCensus]).
@internal
class RenderGlassPlane extends RenderProxyBox {
  /// Creates a plane whose pass has [settings].
  RenderGlassPlane({
    required this._settings,
    required this._open,
    required this._paintOrder,
  });

  /// The most shapes one pass holds.
  static const int capacity = FlutterGpuGeometryRenderer.maxShapes;

  LiquidGlassSettings _settings;

  /// The settings of the plane's pass, which a member must have.
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    _invalidate();
  }

  bool _open;

  /// Whether the plane merges glass now.
  bool get open => _open;
  set open(bool value) {
    if (_open == value) return;
    _open = value;
    _invalidate();
  }

  GlassPaintOrder _paintOrder;

  /// What the plane's owner guarantees about painting between the plane
  /// and its members' glass.
  GlassPaintOrder get paintOrder => _paintOrder;
  set paintOrder(GlassPaintOrder value) {
    if (_paintOrder == value) return;
    _paintOrder = value;
    _invalidate();
  }

  final List<RenderGlassMember> _members = [];
  final Map<RenderGlassMember, GlassMemberCensus> _census = {};
  bool _stale = true;

  /// The glass layers below the plane, in paint order.
  List<RenderGlassMember> get members {
    if (_stale) _resolve();
    return List.unmodifiable(_members);
  }

  void _join(RenderGlassMember member) {
    _members.add(member);
    _invalidate();
  }

  void _leave(RenderGlassMember member) {
    _members.remove(member);
    _census.remove(member);
    _invalidate();
  }

  /// A fact of [member] changed: its inputs, its shapes, its rest.
  void memberChanged(RenderGlassMember member) => _invalidate();

  void _invalidate() => _stale = true;

  /// What the plane does with [member]'s glass.
  GlassMemberCensus censusOf(RenderGlassMember member) {
    if (_stale) _resolve();
    return _census[member] ??
        const GlassMemberCensus(GlassStrategy.split, split: GlassSplit.closed);
  }

  void _resolve() {
    _stale = false;
    _census.clear();
    if (!attached) return;
    sortGlassPaintOrder(this, _members, (RenderGlassMember m) => m);
    final scaled = MatrixUtils.getAsTranslation(getTransformTo(null)) == null;
    LiquidGlassAppearance? reference;
    var shapes = 0;
    for (final member in _members) {
      final (split, blocker, look) = _splitOf(
        member,
        scaled: scaled,
        reference: reference,
        shapes: shapes,
      );
      if (split == null) {
        reference ??= look!.appearance;
        shapes += look!.shapes;
        _census[member] = const GlassMemberCensus(GlassStrategy.merged);
        continue;
      }
      _census[member] = GlassMemberCensus(
        member.painted ? GlassStrategy.painted : GlassStrategy.split,
        split: split,
        blocker: blocker,
      );
    }
  }

  (GlassSplit?, RenderObject?, GlassLook?) _splitOf(
    RenderGlassMember member, {
    required bool scaled,
    required LiquidGlassAppearance? reference,
    required int shapes,
  }) {
    if (!_open) return (GlassSplit.closed, null, null);
    if (member.read != GlassRead.plane) return (GlassSplit.read, null, null);
    if (member.glows) return (GlassSplit.glow, null, null);
    if (member.fused) return (GlassSplit.fused, null, null);
    final look = member.look;
    if (look == null) return (GlassSplit.empty, null, null);
    if (_paintOrder == GlassPaintOrder.outsideGlass &&
        look.settings.effectiveFrost > 0) {
      return (GlassSplit.frost, null, null);
    }
    final blocker = glassPlaneBlocker(member, this);
    if (blocker != null) return (GlassSplit.blocked, blocker, null);
    if (scaled ||
        MatrixUtils.getAsTranslation(member.getTransformTo(this)) == null) {
      return (GlassSplit.scaled, null, null);
    }
    if (look.settings != _settings) return (GlassSplit.settings, null, null);
    if (reference != null && look.appearance != reference) {
      return (GlassSplit.look, null, null);
    }
    if (shapes + look.shapes > capacity) {
      return (GlassSplit.capacity, null, null);
    }
    if (!member.resting) return (GlassSplit.moving, null, null);
    return (null, null, look);
  }
}

/// The render object of [GlassPlaneScope.planeBreak].
@internal
class RenderGlassPlaneBreak extends RenderProxyBox {
  /// Creates a break, keeping glass out of a plane's pass while [active].
  RenderGlassPlaneBreak({required this._active});

  bool _active;

  /// Whether the glass below is kept out of the planes above now.
  bool get active => _active;
  set active(bool value) {
    if (_active == value) return;
    _active = value;
    for (var node = parent; node != null; node = node.parent) {
      if (node is RenderGlassPlane) {
        node._invalidate();
        return;
      }
    }
  }
}
