import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:morph/src/glass/renderer/geometry/glass_rest.dart';
import 'package:morph/src/glass/renderer/internal/raster_phase.dart';
import 'package:morph/src/glass/renderer/internal/render_liquid_glass_geometry.dart';
import 'package:morph/src/glass/renderer/liquid_glass.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_render_object.dart';
import 'package:morph/src/motion/spring_state.dart';

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

  /// It reads a backdrop other than its plane's: its own (chrome, a lifted
  /// lens), or the read of another plane in between (a bar's).
  read,

  /// Its control draws fills, platters or fused bodies in order with this
  /// glass, which a pass at the plane would draw under them.
  control,

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
/// notification of its sources: its settings, whether it shades a fused
/// body or shows a glow, and whether its control lets a pass at the plane
/// draw it ([GlassSplit.control]).
@internal
typedef GlassMemberInputs = ({
  LiquidGlassSettings settings,
  bool fused,
  bool glows,
  bool joins,
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

/// Whether [transform] draws a box of [size] where a translation would, to
/// within the rest of a settled motion ([MorphRest.length]): a control's
/// spring settles once its remaining swing is invisible and may stay
/// there, so a resting control can be drawn at a scale that close to 1.
/// The pass draws such glass on its own grid, without the shift onto the
/// grid of the glass's own layer (NEAR, at most half a device pixel on
/// the rim).
bool _translates(Matrix4 transform, Size size) {
  if (MatrixUtils.getAsTranslation(transform) != null) return true;
  final m = transform.storage;
  if (m[2] != 0 ||
      m[3] != 0 ||
      m[6] != 0 ||
      m[7] != 0 ||
      m[8] != 0 ||
      m[9] != 0 ||
      m[10] != 1 ||
      m[11] != 0 ||
      m[15] != 1) {
    return false;
  }
  final extent = math.max(size.width, size.height);
  return ((m[0] - 1).abs() + m[4].abs()) * extent <= MorphRest.length &&
      (m[1].abs() + (m[5] - 1).abs()) * extent <= MorphRest.length;
}

/// The render object of a glass layer, through which the layer reports to
/// its plane: the layer's repaint boundary, which clips the layer to its
/// reach, registers with the nearest [RenderGlassPlane] above it and
/// follows whether its glass rests.
///
/// It is also where a layer of the member's own would rasterize: a pass
/// that draws the member's shapes shifts them onto that grid.
@internal
class RenderGlassMember extends RenderGlassRasterAnchor {
  /// Creates the member of a layer that reads [read], whose shapes
  /// register with [link].
  RenderGlassMember({
    required this._read,
    required this._link,
    required GlassMemberInputs Function() inputsOf,
    this._reach,
    this._painted = false,
    this._backdropKey,
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
    _link.lendTo(null);
    _link = value;
    _signature = null;
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

  /// Whether the layer's control lets a pass at its plane draw this glass.
  bool get joins => _inputs.joins;

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

  BackdropKey? _backdropKey;

  /// The plane read the layer's glass shares, or null for a read of its
  /// own.
  BackdropKey? get backdropKey => _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (_backdropKey == value) return;
    _backdropKey = value;
    _plane?.memberChanged(this);
  }

  Color? _planeSolid;

  /// The opaque color the member's plane is painted over, while the plane
  /// reaches the member: glass the plane does not merge (pressed, glowing,
  /// unlike the others) lies on that color as much as its merged
  /// neighbours, and the layer shades it over the color too. Read from the
  /// plane's backdrop instead, the layer would become the plane read's
  /// first reader whenever it paints before the plane's pass, and move that
  /// read above whatever paints between them.
  Color? get planeSolid => _planeSolid;
  set planeSolid(Color? value) {
    if (_planeSolid == value) return;
    _planeSolid = value;
    onPlaneSolid?.call();
  }

  /// Called when [planeSolid] changes: the layer's own glass draws anew.
  VoidCallback? onPlaneSolid;

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
    for (final shape in _link.ownShapes) {
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
  List<Object?>? _signature;
  int _seen = -1;
  // Whether the member is drawn under more than a translation relative to
  // its plane, or null before it first composited.
  bool? _scaled;

  /// Whether the member's glass stayed where it is, relative to its plane,
  /// and unchanged for [GlassRestWatch.restFrames] composited frames; a
  /// member counts as resting from the moment it appears.
  bool get resting => _quiet >= GlassRestWatch.restFrames;

  /// Where the member sits relative to its plane, and where and how its
  /// shapes sit in it: what a pass at the plane would encode again when it
  /// changes.
  List<Object?> _signatureNow(Matrix4 toPlane) => [
    toPlane,
    for (final shape in _link.ownShapes)
      if (shape.attached && shape.hasSize) ...[
        shape.getTransformTo(this),
        shape.size,
        if (shape is RenderLiquidGlass) ...[shape.shape, shape.appearance],
      ],
  ];

  static bool _same(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final (x, y) = (a[i], b[i]);
      final same = x is Matrix4 && y is Matrix4
          ? MatrixUtils.matrixEquals(x, y)
          : x == y;
      if (!same) return false;
    }
    return true;
  }

  void _composited() {
    if (!attached) return;
    final plane = _plane;
    if (plane == null && !followsRestEverywhere) return;
    _seen = plane?._epoch ?? -1;
    final toPlane = getTransformTo(plane);
    final scaled = !_translates(toPlane, size);
    final signature = _signatureNow(toPlane);
    final last = _signature;
    final moved = last != null && !_same(signature, last);
    _signature = signature;
    final was = (resting, _scaled);
    if (moved) {
      _quiet = 0;
    } else if (_quiet < GlassRestWatch.restFrames) {
      _quiet++;
    }
    _scaled = scaled;
    if (was != (resting, _scaled)) {
      plane?.memberChanged(this, afterPaint: true);
    }
    if (!resting && !_restCheck) {
      _restCheck = true;
      SchedulerBinding.instance.addPostFrameCallback(_checkRest);
    }
  }

  bool _restCheck = false;

  // Glass that moved in a frame after which no frame comes rests from then
  // on: nothing will draw it anywhere else.
  void _checkRest(Duration _) {
    _restCheck = false;
    if (!attached || resting || SchedulerBinding.instance.hasScheduledFrame) {
      return;
    }
    _quiet = GlassRestWatch.restFrames;
    _plane?.memberChanged(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _live?.addListener(_refresh);
    _glows?.addListener(_refresh);
    _inputs = _inputsOf();
    _signature = null;
    _scaled = null;
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
    planeSolid = null;
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
/// layers below it, decides from their facts which of them its pass draws
/// ([GlassMemberCensus]), and lends the shapes of those to its pass.
///
/// It decides in layout, from the facts its members reported since; a
/// member's own change (a glow, a break, a tag hiding it) reaches it in the
/// same frame. What only the composited frame shows - a member that moved,
/// faded, was not drawn, or a plane drawn scaled - it checks after paint,
/// and a merged member leaves its pass in the next frame.
@internal
class RenderGlassPlane extends RenderProxyBox {
  /// Creates a plane whose pass has [settings] and paints the shapes of
  /// [pass].
  RenderGlassPlane({
    required this._settings,
    required this._open,
    required this._paintOrder,
    required this._pass,
    this._solid,
    this._readKey,
  });

  /// The most shapes one pass holds.
  static const int capacity = FlutterGpuGeometryRenderer.maxShapes;

  LiquidGlassSettings _settings;

  /// The settings of the plane's pass, which a member must have.
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    _requestResolve();
  }

  bool _open;

  /// Whether the plane merges glass now.
  bool get open => _open;
  set open(bool value) {
    if (_open == value) return;
    _open = value;
    _requestResolve();
  }

  GlassPaintOrder _paintOrder;

  /// What the plane's owner guarantees about painting between the plane
  /// and its members' glass.
  GlassPaintOrder get paintOrder => _paintOrder;
  set paintOrder(GlassPaintOrder value) {
    if (_paintOrder == value) return;
    _paintOrder = value;
    _requestResolve();
  }

  BackdropKey? _readKey;

  /// The read the plane's pass shares: a member must read it too.
  BackdropKey? get readKey => _readKey;
  set readKey(BackdropKey? value) {
    if (_readKey == value) return;
    _readKey = value;
    _requestResolve();
  }

  Color? _solid;

  /// The opaque color the plane is painted directly over, or null: its pass
  /// shades over it, and so does every member it reaches but does not
  /// merge ([RenderGlassMember.planeSolid]).
  Color? get solid => _solid;
  set solid(Color? value) {
    if (_solid == value) return;
    _solid = value;
    _requestResolve();
  }

  GeometryRenderLink _pass;

  /// The link of the plane's pass, to which merged members lend their
  /// shapes.
  GeometryRenderLink get pass => _pass;
  set pass(GeometryRenderLink value) {
    if (identical(_pass, value)) return;
    for (final member in _members) {
      member.link.lendTo(null);
    }
    _pass = value;
    _requestResolve();
  }

  final List<RenderGlassMember> _members = [];
  final Map<RenderGlassMember, GlassMemberCensus> _census = {};
  final Set<RenderGlassMember> _merged = {};
  bool _stale = true;
  // Whether the plane was drawn under more than a translation when it last
  // composited, or null before it first did: the transforms of its
  // ancestors are only known after layout, where the plane decides, and a
  // plane merges nothing until it knows (a member merged under a scale
  // draws its own layer differently for frames after it leaves).
  bool? _scaled;
  int _epoch = 0;

  /// The glass layers below the plane, in paint order.
  List<RenderGlassMember> get members => List.unmodifiable(_members);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scaled = null;
  }

  void _join(RenderGlassMember member) {
    _members.add(member);
    _requestResolve();
  }

  void _leave(RenderGlassMember member) {
    _members.remove(member);
    _census.remove(member);
    if (_merged.remove(member)) member.link.lendTo(null);
    _requestResolve();
  }

  /// A fact of [member] changed: its inputs, its shapes, its rest;
  /// [afterPaint] for one found after the frame's paint.
  void memberChanged(RenderGlassMember member, {bool afterPaint = false}) =>
      _requestResolve(afterPaint: afterPaint);

  bool _resolveScheduled = false;

  void _requestResolve({bool afterPaint = false}) {
    _stale = true;
    if (!attached) return;
    // Layout may only dirty what lies below the node laying out (a layout
    // builder mounting a member): a plane laying out now resolves at the
    // end of its own layout, one that is not in the next frame. After
    // paint the frame still flushes semantics, which must find the tree
    // laid out.
    if (afterPaint || owner!.debugDoingLayout) {
      if (_resolveScheduled) return;
      _resolveScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((Duration _) {
        _resolveScheduled = false;
        if (_stale && attached) markNeedsLayout();
      });
      return;
    }
    markNeedsLayout();
  }

  /// What the plane does with [member]'s glass.
  GlassMemberCensus censusOf(RenderGlassMember member) =>
      _census[member] ??
      const GlassMemberCensus(GlassStrategy.split, split: GlassSplit.closed);

  @override
  void performLayout() {
    super.performLayout();
    if (_stale) _resolve();
  }

  void _resolve() {
    _stale = false;
    _census.clear();
    _merged.clear();
    sortGlassPaintOrder(this, _members, (RenderGlassMember m) => m);
    final solid = (_solid?.a ?? 0) == 1 ? _solid : null;
    LiquidGlassAppearance? reference;
    var shapes = 0;
    for (final member in _members) {
      final (split, blocker, look) = _splitOf(
        member,
        reference: reference,
        shapes: shapes,
      );
      member.planeSolid = solid != null && _reaches(member, split)
          ? solid
          : null;
      if (split == null) {
        reference ??= look!.appearance;
        shapes += look!.shapes;
        _merged.add(member);
        _census[member] = const GlassMemberCensus(GlassStrategy.merged);
      } else {
        _census[member] = GlassMemberCensus(
          member.painted || member.planeSolid != null
              ? GlassStrategy.painted
              : GlassStrategy.split,
          split: split,
          blocker: blocker,
        );
      }
    }
    for (final member in _members) {
      member.link.lendTo(_merged.contains(member) ? _pass : null);
    }
  }

  // Whether the plane reaches [member], split for [split]: nothing between
  // them changes its glass, and the glass reads nothing but what lies under
  // it at the plane (no frost over content the plane lets paint between).
  bool _reaches(RenderGlassMember member, GlassSplit? split) =>
      member.read == GlassRead.plane &&
      member.backdropKey == _readKey &&
      !(_paintOrder == GlassPaintOrder.outsideGlass &&
          member.settings.effectiveFrost > 0) &&
      switch (split) {
        GlassSplit.closed ||
        GlassSplit.read ||
        GlassSplit.frost ||
        GlassSplit.blocked ||
        GlassSplit.scaled => false,
        GlassSplit.control ||
        GlassSplit.glow ||
        GlassSplit.fused ||
        GlassSplit.empty => glassPlaneBlocker(member, this) == null,
        _ => true,
      };

  (GlassSplit?, RenderObject?, GlassLook?) _splitOf(
    RenderGlassMember member, {
    required LiquidGlassAppearance? reference,
    required int shapes,
  }) {
    if (!_open) return (GlassSplit.closed, null, null);
    if (member.read != GlassRead.plane || member.backdropKey != _readKey) {
      return (GlassSplit.read, null, null);
    }
    if (!member.joins) return (GlassSplit.control, null, null);
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
    if ((_scaled ?? true) || (member._scaled ?? true)) {
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

  void _beginFrame() => _epoch++;

  // A merged member that was not drawn this frame (hidden above it), that
  // something now fades, clips or scales, or a plane now drawn scaled,
  // leaves the pass in the next frame.
  void _endFrame() {
    if (!attached) return;
    final scaled = !_translates(getTransformTo(null), size);
    var changed = scaled != _scaled;
    _scaled = scaled;
    if (_stale) return;
    for (final member in _merged) {
      if (changed) break;
      changed =
          member._seen != _epoch ||
          (member._scaled ?? true) ||
          glassPlaneBlocker(member, this) != null;
    }
    if (changed) _requestResolve(afterPaint: true);
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  OffsetLayer updateCompositedLayer({required OffsetLayer? oldLayer}) {
    final layer = oldLayer is _PlaneLayer ? oldLayer : _PlaneLayer();
    layer.plane = this;
    return layer;
  }
}

/// A plane's layer: hands the plane the compositing of every frame it is
/// drawn in, around its members'.
class _PlaneLayer extends OffsetLayer {
  RenderGlassPlane? plane;

  @override
  void updateSubtreeNeedsAddToScene() {
    plane?._beginFrame();
    super.updateSubtreeNeedsAddToScene();
    plane?._endFrame();
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
        node._requestResolve();
        return;
      }
    }
  }
}
