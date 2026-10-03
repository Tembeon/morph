import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:morph/src/flight.dart';
import 'package:morph/src/frame.dart';
import 'package:morph/src/liquid_field.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/theme.dart';

/// A per-frame geometry channel for a [MorphPiece]: a translation plus
/// per-axis scales over the piece's base [MorphPiece.rect], written by
/// the app (a drag, a tether, an orbit) and consumed by the skin's
/// render object directly. A write repaints and re-traces the skin with
/// no widget rebuild and no relayout - the same citizenship flight
/// ticks have.
///
/// The delta lives in the group's local pixels and applies about the
/// base rect's center. The skin mirrors it onto the piece's mass and,
/// as a child-local paint transform, onto the content: one rigid body.
/// The content paint-scales rather than reflows (text does not rewrap
/// at a stretched width) - the contract of the channel, invisible at
/// tether scales. A [MorphTag] inside the content measures itself
/// through the same transform, so a flight launches from wherever the
/// piece currently stands; hit testing follows the displaced content,
/// which must stay within the group's own box to remain reachable.
///
/// The app owns the channel: create it in a State, dispose it there,
/// hand it to [MorphPiece.channel]. Transient motion (a drag) commits
/// into the base rect at rest and calls [reset] - the channel carries
/// the live delta, the rect carries the truth.
class MorphPieceChannel extends ChangeNotifier {
  Offset _offset = .zero;
  double _scaleX = 1;
  double _scaleY = 1;

  /// Translation of the piece's base rect, in group-local px.
  Offset get offset => _offset;

  /// Horizontal scale about the base rect's center.
  double get scaleX => _scaleX;

  /// Vertical scale about the base rect's center.
  double get scaleY => _scaleY;

  /// Whether the channel currently displaces nothing.
  bool get isIdentity => _offset == .zero && _scaleX == 1 && _scaleY == 1;

  /// Writes the delta; omitted fields keep their value. Notifies only
  /// when something actually changed, so an idle writer costs nothing.
  ///
  /// A scale of ZERO is legal and deflates the mass to nothing -
  /// births and deaths are mass, not opacity (the selection-blob
  /// pattern). Content of a fully deflated piece paints as nothing and
  /// is skipped by hit testing (the transform degenerates). Liquid
  /// Glass itself births at [birthScale] on [birthSpring].
  void update({Offset? offset, double? scaleX, double? scaleY}) {
    assert(scaleX == null || scaleX >= 0, 'channel scaleX cannot be negative.');
    assert(scaleY == null || scaleY >= 0, 'channel scaleY cannot be negative.');
    final Offset nextOffset = offset ?? _offset;
    final double nextScaleX = scaleX ?? _scaleX;
    final double nextScaleY = scaleY ?? _scaleY;
    if (nextOffset == _offset &&
        nextScaleX == _scaleX &&
        nextScaleY == _scaleY) {
      return;
    }
    _offset = nextOffset;
    _scaleX = nextScaleX;
    _scaleY = nextScaleY;
    notifyListeners();
  }

  /// Returns the channel to identity.
  void reset() => update(offset: .zero, scaleX: 1, scaleY: 1);

  /// The scale a new Liquid Glass shape is born at, about its final
  /// center, before it springs to full size on [birthSpring]; a shape
  /// leaving a merge shrinks back to it, parked inside the survivor.
  /// Measured from SwiftUI's `glassEffectID` on iOS 27.
  static const double birthScale = 0.2;

  /// The spring a Liquid Glass shape grows from [birthScale] to full
  /// size on, and shrinks back on when it leaves - SwiftUI's `.bouncy`
  /// as fitted to the per-frame shape rects recorded on iOS 27: the
  /// size peaks about 3 percent over at 0.38 s and settles by 0.7 s.
  static const MorphSpring birthSpring = MorphSpring(0.492, 0.711);

  /// [base] displaced by the current delta: shifted by [offset], scaled
  /// about its center by [scaleX] and [scaleY].
  Rect apply(Rect base) {
    if (isIdentity) {
      return base;
    }
    return .fromCenter(
      center: base.center + _offset,
      width: base.width * _scaleX,
      height: base.height * _scaleY,
    );
  }
}

/// A piece of a liquid group: explicit geometry (no tree measurement,
/// like the rest of the morph system) plus live content on top of the
/// skin. rect and radius are plain frame data: an animating consumer
/// derives them from its own spring value.
///
/// Morphing out of a piece takes no ceremony: [MorphPiece.morphable]
/// wraps the content in a correctly configured MorphTag (piece id, shape
/// from its radius, skin color and elevation), and the group finds the
/// flight in the MorphScope by id on its own. The consumer just calls showMorph*(from: id) from any
/// context.
class MorphPiece {
  /// Creates a plain piece: mass and content, no morph identity.
  const MorphPiece({
    required this.id,
    required this.rect,
    this.radius = 20,
    this.solid = true,
    this.channel,
    this.tint,
    this.child,
  }) : morphable = false;

  /// A morph-source piece: the group installs a MorphTag around the
  /// content itself and plays the flight neck whenever a flight is
  /// launched with this piece's id.
  // The child is required BY TYPE: the MorphTag that gives the piece
  // its flight identity wraps the child, so a childless piece would
  // register no tag and showMorph*(from: id) could never find the
  // source.
  const MorphPiece.morphable({
    required this.id,
    required this.rect,
    this.radius = 20,
    this.solid = true,
    this.channel,
    this.tint,
    required Widget this.child,
  }) : morphable = true;

  /// Identity within the group; also the flight id for morphable pieces.
  final Object id;

  /// The mass geometry in the group's local coordinates.
  final Rect rect;

  /// Corner radius of the mass; clamped to half the shorter side, so
  /// radius >= min(w, h) / 2 yields a stadium.
  final double radius;

  /// false - the piece contributes no mass to the skin (and its bridges
  /// are skipped), but the content stays mounted in place.
  final bool solid;

  /// Whether the group installs a [MorphTag] around [child].
  final bool morphable;

  /// App-driven per-frame geometry over [rect]: when set, the skin
  /// subscribes and mirrors the channel's delta onto the mass and the
  /// content with no widget rebuild. See [MorphPieceChannel].
  final MorphPieceChannel? channel;

  /// Ink tint of the piece's own body - a hover/selection wash that is
  /// PART of the skin, not an overlay approximating it. Painted over
  /// the skin fill from the piece's RESOLVED geometry, so it stays
  /// glued to the mass through channel displacement and deflation, and
  /// an airborne piece (its mass has flown away)
  /// paints no ink at all. Clipped by the traced silhouette; the neck
  /// to a neighbor stays untinted - ink soaks the body, not the bond.
  /// Content paints above the ink, so glyphs stay crisp. Toggling only
  /// the tint is paint-only: no relayout, no re-trace.
  final Color? tint;

  /// Live content laid out over the piece's [rect].
  final Widget? child;

  bool _geometryEquals(MorphPiece other) {
    return id == other.id &&
        rect == other.rect &&
        radius == other.radius &&
        solid == other.solid &&
        morphable == other.morphable &&
        identical(channel, other.channel);
  }
}

/// An explicit pipe between two pieces by id - for distant pieces where
/// proximity fusion is not enough. width defaults to half the smaller
/// height of the pair.
class MorphLink {
  /// Creates a bridge between the pieces with ids [from] and [to].
  const MorphLink({required this.from, required this.to, this.width});

  /// Id of the piece at one end.
  final Object from;

  /// Id of the piece at the other end.
  final Object to;

  /// Pipe width in px; null derives half the smaller piece height.
  final double? width;
}

/// The contour of a skin's mass: a line of [width] px drawn along the
/// INSIDE of the traced silhouette.
///
/// Fill and stroke are the two halves of one material, declared side by
/// side on [MorphSkin]; the stroke follows the same living path as the
/// fill, so necks, deformations and flight blobs carry their outline
/// for free.
///
/// The stroke is inner by contract: it never extends past the
/// silhouette, so turning it on does not optically grow any existing
/// skin. Note that a line reveals the tracer's polygonization more than
/// a fill does - a skin that reads faceted under its stroke wants a
/// finer [MorphSkin.cell], which is a frame-budget decision.
@immutable
class MorphStroke {
  /// Creates a contour of [width] px in [color].
  const MorphStroke({required this.color, this.width = 1})
    : assert(width > 0, 'stroke width must be positive.');

  /// Line color, opacity included.
  final Color color;

  /// Line width in px, measured inward from the silhouette.
  final double width;

  @override
  bool operator ==(Object other) {
    return other is MorphStroke && other.color == color && other.width == width;
  }

  @override
  int get hashCode => Object.hash(color, width);

  @override
  String toString() => 'MorphStroke(color: $color, width: $width)';
}

/// A group of pieces with one shared "skin": the smooth union of their
/// SDFs traced into a single [Path] behind live content. Nearby pieces
/// fuse with a concave fillet on their own, by the merge iOS 27 Liquid
/// Glass draws: [blend] is a glass container's spacing, 1:1 in logical
/// px - facing surfaces lean toward each other below a gap of blend and
/// touch at blend / 2, while edges running side by side stay straight.
///
/// "One mass - one shadow": elevation is drawn as a single shadow of the
/// unified contour, so pieces cannot visually split into layers.
///
/// The flight neck comes for free: the group finds flights launched in
/// the [MorphScope] under its piece ids (including a declarative
/// MorphAnchor with an explicit tagId) and plays the airborne blob under
/// the shuttle and bridge detachment by itself. Outside a MorphScope the group degrades to pure fusion.
///
/// Implemented as a render object: spring ticks mark paint only - no
/// widget rebuild, no relayout participates in an animation frame.
/// App-driven geometry gets the same citizenship through
/// [MorphPieceChannel]: a channel write repaints and re-traces without
/// touching the widget tree. The channel delta is a paint transform of
/// the content, mirroring the skin's mass deformation. The group is its own repaint boundary, so an
/// animating skin never repaints its ancestors.
class MorphSkin extends StatelessWidget {
  /// Creates a skin over [pieces], optionally bridged by [links].
  const MorphSkin({
    super.key,
    required this.pieces,
    this.links = const <MorphLink>[],
    this.extraMasses = const <MorphMass>[],
    this.style,
    this.blend,
    this.cell,
    this.smoothPasses,
    this.evalBudget = defaultEvalBudget,
    required this.color,
    this.gradient,
    this.stroke,
    this.elevation = 0,
    this.shadowColor,
    this.clipBehavior = .none,
    this.contentFilterQuality,
  }) : assert(
         blend == null || blend >= 0,
         'blend (the smin k) is a distance in px and cannot be negative.',
       ),
       assert(
         cell == null || cell > 0,
         'cell is the sampling grid step in px and must be positive.',
       ),
       assert(
         smoothPasses == null || smoothPasses >= 0,
         'smoothPasses cannot be negative.',
       ),
       assert(
         evalBudget == null || evalBudget > 0,
         'evalBudget is a positive per-cluster evaluation cap; '
         'pass null to disable it.',
       ),
       assert(elevation >= 0, 'elevation cannot be negative.');

  /// The pieces sharing this skin; ids must be unique.
  final List<MorphPiece> pieces;

  /// Explicit bridges between distant pieces.
  final List<MorphLink> links;

  /// Extra contentless mass: raw SDF masses poured into the skin
  /// alongside the pieces.
  final List<MorphMass> extraMasses;

  /// A ready-made knob bundle; explicit [blend]/[cell]/[smoothPasses]
  /// win over it. null falls back to [MorphTheme.skinStyle], then to
  /// [MorphSkinStyle.subtle] - SwiftUI's default spacing.
  final MorphSkinStyle? style;

  /// Blend width in pixels: Liquid Glass's container spacing
  /// (`UIGlassContainerEffect.spacing`, `GlassEffectContainer(spacing:)`)
  /// 1:1. Two facing surfaces start to lean toward each other below a gap
  /// of blend and meet at a gap of blend / 2. A distance, not a fraction:
  /// at a different scene scale it scales along with the scene.
  final double? blend;

  /// Marching-squares grid step in pixels: smaller - crisper and more
  /// expensive.
  final double? cell;

  /// Chaikin smoothing passes over the traced contour.
  final int? smoothPasses;

  /// Cap on field evaluations per cluster per trace (default
  /// [defaultEvalBudget]): extreme scenes coarsen their grid so the
  /// worst frame stays bounded - quality degrades before the frame
  /// rate does. null disables the cap.
  final int? evalBudget;

  /// The default [evalBudget]: the cap on field evaluations (grid
  /// vertices x shapes) per cluster per trace. A deterministic
  /// function of geometry - no time, no hysteresis; the same scene
  /// always traces identically.
  static const int defaultEvalBudget = liquidDefaultEvalBudget;

  /// Fill color of the skin; also the surface color that shuttles of
  /// morphable pieces take off from.
  final Color color;

  /// Optional skin fill gradient, shaded across the group bounds; when
  /// set it wins over [color] for the fill (the [color] still names the
  /// surface for morph shuttles of morphable pieces).
  final Gradient? gradient;

  /// Optional contour of the mass, drawn inside the silhouette after
  /// the fill and the piece tints; null draws none.
  final MorphStroke? stroke;

  /// Shadow of the unified contour: one mass, one shadow.
  final double elevation;

  /// Color of the [elevation] shadow, opacity included; null resolves
  /// [MorphTheme.shadowColor], then 60% black - the same builtin
  /// flights use, so a launch out of a piece keeps its shadow tint
  /// with no theme installed.
  final Color? shadowColor;

  /// The skin bulges past the piece bounds by up to ~k; not clipped by
  /// default.
  final Clip clipBehavior;

  /// Sampling for piece CONTENT under a moving channel, or null to
  /// transform the canvas.
  ///
  /// Null (the default) paints content through
  /// [PaintingContext.pushTransform]: glyphs land at the final
  /// resolution and stay vector-crisp. The cost shows up only while a
  /// piece is in MOTION - the transform differs every frame, so glyph
  /// origins re-snap to a different subpixel bucket each time and
  /// letters visibly shuffle against each other.
  ///
  /// A non-null value paints content into an [ImageFilterLayer]
  /// instead: it is rasterized ONCE in its own unchanging local space
  /// and the channel transform only resamples that raster, so the
  /// shuffling cannot happen. Text is a little softer while deformed -
  /// the trade this knob exists to let the caller make.
  final FilterQuality? contentFilterQuality;

  @override
  Widget build(BuildContext context) {
    final MorphTheme? theme = MorphTheme.maybeOf(context);
    final MorphSkinStyle effectiveStyle =
        style ?? theme?.skinStyle ?? MorphSkinStyle.subtle;
    return _RawMorphSkin(
      pieces: pieces,
      links: links,
      extraMasses: extraMasses,
      k: blend ?? effectiveStyle.blend,
      cell: cell ?? effectiveStyle.cell,
      smoothPasses: smoothPasses ?? effectiveStyle.smoothPasses,
      evalBudget: evalBudget,
      color: color,
      gradient: gradient,
      stroke: stroke,
      elevation: elevation,
      shadowColor:
          shadowColor ?? theme?.shadowColor ?? MorphTheme.defaultShadowColor,
      clipBehavior: clipBehavior,
      contentFilterQuality: contentFilterQuality,
      scope: MorphScope.maybeOf(context),
      children: <Widget>[
        // The key by id is mandatory: without keys, removing a piece
        // from the middle of the list makes Flutter reuse elements by
        // position, and stateful content (e.g. a MorphTag) receives a
        // foreign id.
        for (final MorphPiece piece in pieces)
          if (piece.child != null)
            KeyedSubtree(
              key: ValueKey<Object>(piece.id),
              child: piece.morphable
                  ? MorphTag(
                      id: piece.id,
                      // The stroke is part of the material, so the
                      // flight inherits it: the container launches with
                      // the piece's contour and the side lerps toward
                      // the target's (usually none) instead of popping
                      // off on the first frame.
                      shape: RoundedRectangleBorder(
                        borderRadius: .circular(piece.radius),
                        side: stroke == null
                            ? BorderSide.none
                            : BorderSide(
                                color: stroke!.color,
                                width: stroke!.width,
                              ),
                      ),
                      surfaceColor: color,
                      elevation: elevation,
                      child: piece.child!,
                    )
                  : piece.child!,
            ),
      ],
    );
  }
}

class _RawMorphSkin extends MultiChildRenderObjectWidget {
  const _RawMorphSkin({
    required this.pieces,
    required this.links,
    required this.extraMasses,
    required this.k,
    required this.cell,
    required this.smoothPasses,
    required this.evalBudget,
    required this.color,
    required this.gradient,
    required this.stroke,
    required this.elevation,
    required this.shadowColor,
    required this.clipBehavior,
    required this.contentFilterQuality,
    required this.scope,
    required super.children,
  });

  final List<MorphPiece> pieces;
  final List<MorphLink> links;
  final List<MorphMass> extraMasses;
  final double k;
  final double cell;
  final int smoothPasses;
  final int? evalBudget;
  final Color color;
  final Gradient? gradient;
  final MorphStroke? stroke;
  final double elevation;
  final Color shadowColor;
  final Clip clipBehavior;
  final FilterQuality? contentFilterQuality;
  final MorphScopeState? scope;

  @override
  RenderMorphSkin createRenderObject(BuildContext context) {
    return RenderMorphSkin(
      pieces: pieces,
      links: links,
      extraMasses: extraMasses,
      k: k,
      cell: cell,
      smoothPasses: smoothPasses,
      evalBudget: evalBudget,
      color: color,
      gradient: gradient,
      stroke: stroke,
      elevation: elevation,
      shadowColor: shadowColor,
      clipBehavior: clipBehavior,
      contentFilterQuality: contentFilterQuality,
      scope: scope,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderMorphSkin renderObject) {
    renderObject
      ..pieces = pieces
      ..links = links
      ..extraMasses = extraMasses
      ..k = k
      ..cell = cell
      ..smoothPasses = smoothPasses
      ..evalBudget = evalBudget
      ..color = color
      ..gradient = gradient
      ..stroke = stroke
      ..elevation = elevation
      ..shadowColor = shadowColor
      ..clipBehavior = clipBehavior
      ..contentFilterQuality = contentFilterQuality
      ..scope = scope;
  }
}

class _LiquidChildParentData extends ContainerBoxParentData<RenderBox> {
  MorphPiece? piece;

  /// The child's own filter layer under
  /// [MorphSkin.contentFilterQuality], kept across paints so its raster
  /// survives them; disposed with the child.
  final LayerHandle<ImageFilterLayer> filterLayer =
      LayerHandle<ImageFilterLayer>();

  @override
  void detach() {
    filterLayer.layer = null;
    super.detach();
  }
}

/// A piece after accounting for its flight: where the mass sits and
/// whether it exists.
class _ResolvedPiece {
  const _ResolvedPiece({
    required this.piece,
    required this.rect,
    required this.solid,
    this.flight,
  });

  final MorphPiece piece;
  final Rect rect;
  final bool solid;
  final MorphFlight? flight;
}

/// The render side of [MorphSkin]. Owns the tracer cache, the flight
/// subscriptions (attach/detach lifecycle), skin painting, the channel
/// paint transform of content, and transform-aware hit testing. Spring
/// ticks call [markNeedsPaint] only; layout runs solely when piece
/// geometry changes from the outside.
class RenderMorphSkin extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _LiquidChildParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _LiquidChildParentData> {
  /// Creates the render object; prefer the [MorphSkin] widget.
  RenderMorphSkin({
    required this._pieces,
    required this._links,
    required this._extraMasses,
    required this._k,
    required this._cell,
    required this._smoothPasses,
    required this._evalBudget,
    required this._color,
    required this._gradient,
    required this._stroke,
    required this._elevation,
    required this._shadowColor,
    required this._clipBehavior,
    required this._contentFilterQuality,
    required this._scope,
  });

  final LiquidTracer _tracer = LiquidTracer();
  Float64List? _signature;
  Path _path = Path();

  final Map<MorphFlight, VoidCallback> _flightSubs =
      <MorphFlight, VoidCallback>{};

  /// The launch fellowship of each active flight: ids of the pieces
  /// whose mass formed one body with the flying piece when the skin
  /// subscribed - the connectivity component over solid pieces AND
  /// their MorphLink bridges, the same predicate the tracer clusters
  /// by. The companion blob necks only to these: a flight stays
  /// attached to what it was PART OF, not to whatever it passes.
  /// Entries outlive subscription blips (a tag deactivating for a
  /// frame) and are erased only when the flight closes or the skin
  /// detaches.
  final Map<MorphFlight, Set<Object>> _flightFellowship =
      <MorphFlight, Set<Object>>{};

  /// How many companion blobs the last paint poured into the field -
  /// an instrument for tests, same convention as
  /// [LiquidTracer.lastMissCount].
  int lastFlightBlobCount = 0;

  /// The group-local outer rects of the blobs from the last paint -
  /// the coordinate-translation instrument (a nested overlay must not
  /// displace the neck).
  @visibleForTesting
  List<Rect> lastFlightBlobRects = const <Rect>[];

  /// The per-cluster trace cache - exposed for its instruments
  /// ([LiquidTracer.lastMissCount], [LiquidTracer.lastClusterCount]),
  /// which tests use to pin re-trace isolation.
  @visibleForTesting
  LiquidTracer get tracer => _tracer;

  /// An animating skin must not repaint ancestors: the group owns its
  /// layer.
  @override
  bool get isRepaintBoundary => true;

  List<MorphPiece> _pieces;

  /// The live piece list; geometry changes re-layout and re-trace.
  List<MorphPiece> get pieces => _pieces;
  set pieces(List<MorphPiece> value) {
    if (identical(_pieces, value)) {
      return;
    }
    final bool sameGeometry =
        value.length == _pieces.length &&
        () {
          for (int i = 0; i < value.length; i++) {
            if (!value[i]._geometryEquals(_pieces[i])) {
              return false;
            }
          }
          return true;
        }();
    // Tint is paint-only by contract: a hover wash toggling per frame
    // must not pay for relayout, re-trace or subscription resync.
    final bool sameTint =
        sameGeometry &&
        () {
          for (int i = 0; i < value.length; i++) {
            if (value[i].tint != _pieces[i].tint) {
              return false;
            }
          }
          return true;
        }();
    _pieces = value;
    if (!sameGeometry) {
      _syncFlightSubscriptions();
      _syncChannelSubscriptions();
      markNeedsLayout();
      markNeedsPaint();
    } else if (!sameTint) {
      markNeedsPaint();
    }
  }

  /// Structural comparison instead of hashes: a changed link may never
  /// keep a stale contour.
  List<MorphLink> _links;
  int _linksEpoch = 0;

  /// The live bridges; changes re-trace the skin.
  List<MorphLink> get links => _links;
  set links(List<MorphLink> value) {
    bool changed = value.length != _links.length;
    if (!changed) {
      for (int i = 0; i < value.length; i++) {
        if (value[i].from != _links[i].from ||
            value[i].to != _links[i].to ||
            value[i].width != _links[i].width) {
          changed = true;
          break;
        }
      }
    }
    _links = value;
    if (changed) {
      _linksEpoch++;
      markNeedsPaint();
    }
  }

  List<MorphMass> _extraMasses;

  /// The live extra mass shapes; changes re-trace the skin.
  List<MorphMass> get extraMasses => _extraMasses;
  set extraMasses(List<MorphMass> value) {
    _extraMasses = value;
    markNeedsPaint();
  }

  double _k;

  /// The fusion width in px (the widget's `blend`).
  double get k => _k;
  set k(double value) {
    if (_k != value) {
      _k = value;
      markNeedsPaint();
    }
  }

  double _cell;

  /// The outline grid step in px.
  double get cell => _cell;
  set cell(double value) {
    if (_cell != value) {
      _cell = value;
      markNeedsPaint();
    }
  }

  int _smoothPasses;

  /// Chaikin passes over the traced contour.
  int get smoothPasses => _smoothPasses;
  set smoothPasses(int value) {
    if (_smoothPasses != value) {
      _smoothPasses = value;
      markNeedsPaint();
    }
  }

  int? _evalBudget;

  /// Per-cluster field-evaluation cap; null is unbounded.
  int? get evalBudget => _evalBudget;
  set evalBudget(int? value) {
    if (_evalBudget != value) {
      _evalBudget = value;
      markNeedsPaint();
    }
  }

  Color _color;

  /// The skin fill color.
  Color get color => _color;
  set color(Color value) {
    if (_color != value) {
      _color = value;
      markNeedsPaint();
    }
  }

  Gradient? _gradient;

  /// The skin fill gradient; wins over [color] when set.
  Gradient? get gradient => _gradient;
  set gradient(Gradient? value) {
    if (_gradient != value) {
      _gradient = value;
      markNeedsPaint();
    }
  }

  MorphStroke? _stroke;

  /// The inner contour of the mass; not part of the trace signature,
  /// so changing it repaints without re-tracing.
  MorphStroke? get stroke => _stroke;
  set stroke(MorphStroke? value) {
    if (_stroke != value) {
      _stroke = value;
      markNeedsPaint();
    }
  }

  double _elevation;

  /// The unified-contour shadow.
  double get elevation => _elevation;
  set elevation(double value) {
    if (_elevation != value) {
      _elevation = value;
      markNeedsPaint();
    }
  }

  Color _shadowColor;

  /// The [elevation] shadow color.
  Color get shadowColor => _shadowColor;
  set shadowColor(Color value) {
    if (_shadowColor != value) {
      _shadowColor = value;
      markNeedsPaint();
    }
  }

  FilterQuality? _contentFilterQuality;

  /// Sampling for piece content under a moving channel; see
  /// [MorphSkin.contentFilterQuality].
  FilterQuality? get contentFilterQuality => _contentFilterQuality;
  set contentFilterQuality(FilterQuality? value) {
    if (_contentFilterQuality != value) {
      _contentFilterQuality = value;
      markNeedsPaint();
    }
  }

  Clip _clipBehavior;

  /// Clip of the bulging skin; none by default.
  Clip get clipBehavior => _clipBehavior;
  set clipBehavior(Clip value) {
    if (_clipBehavior != value) {
      _clipBehavior = value;
      markNeedsPaint();
    }
  }

  MorphScopeState? _scope;

  /// The scope used for flight discovery; null degrades to pure fusion.
  MorphScopeState? get scope => _scope;
  set scope(MorphScopeState? value) {
    if (_scope == value) {
      return;
    }
    if (attached) {
      _scope?.lastFlight.removeListener(_onFlightLaunched);
      value?.lastFlight.addListener(_onFlightLaunched);
    }
    _scope = value;
    _syncFlightSubscriptions();
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scope?.lastFlight.addListener(_onFlightLaunched);
    _syncFlightSubscriptions();
    _syncChannelSubscriptions();
  }

  @override
  void detach() {
    _scope?.lastFlight.removeListener(_onFlightLaunched);
    for (final MapEntry<MorphFlight, VoidCallback> sub in _flightSubs.entries) {
      sub.key.frameTicks.removeListener(sub.value);
    }
    _flightSubs.clear();
    _flightFellowship.clear();
    for (final MorphPieceChannel channel in _channelSubs) {
      channel.removeListener(_onChannelTick);
    }
    _channelSubs.clear();
    super.detach();
  }

  void _onFlightLaunched() {
    _syncFlightSubscriptions();
    markNeedsPaint();
  }

  final Set<MorphPieceChannel> _channelSubs = <MorphPieceChannel>{};

  /// A channel tick is paint-only by contract: geometry change is not a
  /// subscription change, so no flight resync and no allocation runs
  /// here. Semantics do recompute - the channel displaces the geometry
  /// applyPaintTransform reports, and assistive tech reads through the
  /// same transform (a no-op while semantics are off).
  void _onChannelTick() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  /// Subscriptions to the piece geometry channels; one shared handler
  /// serves them all. Synced on attach/detach and when the piece list
  /// itself changes - never on a tick.
  void _syncChannelSubscriptions() {
    Set<MorphPieceChannel>? active;
    for (final MorphPiece piece in _pieces) {
      final MorphPieceChannel? channel = piece.channel;
      if (channel == null) {
        continue;
      }
      (active ??= <MorphPieceChannel>{}).add(channel);
      if (attached && _channelSubs.add(channel)) {
        channel.addListener(_onChannelTick);
      }
    }
    if (_channelSubs.isNotEmpty) {
      _channelSubs.removeWhere((MorphPieceChannel channel) {
        if (active?.contains(channel) ?? false) {
          return false;
        }
        channel.removeListener(_onChannelTick);
        return true;
      });
    }
  }

  /// The piece's base rect displaced by its channel - the geometry the
  /// whole pipeline (mass, signature, fellowship, bridges, blobs) sees.
  Rect _effectiveRect(MorphPiece piece) {
    final MorphPieceChannel? channel = piece.channel;
    return channel == null ? piece.rect : channel.apply(piece.rect);
  }

  /// The live flight launched under the piece's id, if the scope has
  /// one.
  MorphFlight? _flightFor(MorphPiece piece) {
    final MorphFlight? flight = _scope?.liveFlightOf(piece.id);
    if (flight == null || flight.isFinished) {
      return null;
    }
    return flight;
  }

  /// Subscriptions to the frame streams of active flights (value spring
  /// plus displacement channel): the skin repaints on every frame tick
  /// with no widget rebuild involved.
  /// Unsubscription happens on flight completion (closed runs before
  /// the controller's deferred dispose) or on detach.
  void _syncFlightSubscriptions() {
    // Runs on every geometry change (the pieces setter fires per frame
    // of an app-driven drag): allocate nothing until a flight exists.
    Set<MorphFlight>? active;
    for (final MorphPiece piece in _pieces) {
      final MorphFlight? flight = _flightFor(piece);
      if (flight == null) {
        continue;
      }
      (active ??= <MorphFlight>{}).add(flight);
      if (_flightSubs.containsKey(flight)) {
        continue;
      }
      _flightFellowship.putIfAbsent(flight, () => _launchFellowship(piece));
      void tick() => markNeedsPaint();
      _flightSubs[flight] = tick;
      flight.frameTicks.addListener(tick);
      flight.closed.then((Object? _) {
        final VoidCallback? sub = _flightSubs.remove(flight);
        if (sub != null) {
          flight.frameTicks.removeListener(sub);
        }
        _flightFellowship.remove(flight);
        if (attached) {
          markNeedsPaint();
        }
      });
    }
    if (_flightSubs.isNotEmpty) {
      for (final MorphFlight flight in _flightSubs.keys.toList()) {
        if (!(active?.contains(flight) ?? false)) {
          flight.frameTicks.removeListener(_flightSubs.remove(flight)!);
        }
      }
    }
  }

  /// The pieces forming one body with [origin] at this moment: the
  /// connectivity component over solid pieces AND their MorphLink
  /// bridges, labeled by [liquidConnectivityLabels] - the exact
  /// predicate the tracer clusters by, so a bridged piece is a fellow
  /// even across a gap wider than k. Captured once per flight, at
  /// subscription, from the EFFECTIVE rects of that moment (base +
  /// channel): a launch out of a body fused by a live drag keeps its
  /// neck.
  Set<Object> _launchFellowship(MorphPiece origin) {
    final List<MorphPiece> solid = <MorphPiece>[
      for (final MorphPiece piece in _pieces)
        if (piece.solid) piece,
    ];
    final Map<Object, int> indexOf = <Object, int>{
      for (int i = 0; i < solid.length; i++) solid[i].id: i,
    };
    final int? originIndex = indexOf[origin.id];
    if (originIndex == null) {
      return const <Object>{};
    }
    final List<Rect> effective = <Rect>[
      for (final MorphPiece piece in solid) _effectiveRect(piece),
    ];
    final List<Rect> rects = <Rect>[
      ...effective,
      for (final MorphLink link in _links)
        if (indexOf[link.from] case final int from?)
          if (indexOf[link.to] case final int to?)
            if ((link.width ??
                        _defaultBridgeWidth(effective[from], effective[to])) /
                    2
                case final double radius when radius > 0)
              MorphMass.bridge(
                effective[from].center,
                effective[to].center,
                radius: radius,
              ).outerRect,
    ];
    final List<int> labels = liquidConnectivityLabels(rects, _k);
    final int home = labels[originIndex];
    return <Object>{
      for (int i = 0; i < solid.length; i++)
        if (i != originIndex && labels[i] == home) solid[i].id,
    };
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LiquidChildParentData) {
      child.parentData = _LiquidChildParentData();
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    assert(
      constraints.hasBoundedWidth && constraints.hasBoundedHeight,
      'MorphSkin needs bounded constraints (wrap it in a SizedBox or '
      'a Positioned.fill).',
    );
    size = constraints.biggest;
    final List<MorphPiece> withChild = <MorphPiece>[
      for (final MorphPiece piece in _pieces)
        if (piece.child != null) piece,
    ];
    RenderBox? child = firstChild;
    int index = 0;
    while (child != null && index < withChild.length) {
      final MorphPiece piece = withChild[index];
      final _LiquidChildParentData pd =
          child.parentData! as _LiquidChildParentData;
      child.layout(BoxConstraints.tight(piece.rect.size));
      pd
        ..offset = piece.rect.topLeft
        ..piece = piece;
      child = pd.nextSibling;
      index++;
    }
  }

  List<_ResolvedPiece> _resolvePieces() {
    return <_ResolvedPiece>[
      for (final MorphPiece piece in _pieces)
        _resolvePiece(piece, _effectiveRect(piece)),
    ];
  }

  _ResolvedPiece _resolvePiece(MorphPiece piece, Rect base) {
    return switch (_flightFor(piece)) {
      null => _ResolvedPiece(piece: piece, rect: base, solid: piece.solid),
      final MorphFlight flight when flight.isAirborne => _ResolvedPiece(
        piece: piece,
        rect: base,
        solid: false,
        flight: flight,
      ),
      final MorphFlight flight => _ResolvedPiece(
        piece: piece,
        rect: base,
        solid: piece.solid,
        flight: flight,
      ),
    };
  }

  /// Companion blobs of flown-away pieces: a mirror of the flight frame
  /// geometry (center by value, size by progress, radius via the
  /// concentric lerp with its cap) translated into the group's local
  /// coordinates. The blob is hidden under the shuttle for most of the
  /// flight - only the neck tail shows. The blob necks ONLY to the
  /// flight's launch fellowship - the pieces its mass was connected to
  /// when it took off; a dialog flying past an unrelated piece must not
  /// goo onto it. Perf gate: when the gap to every fellow piece exceeds
  /// k, the neck provably cannot exist and the blob is not poured in (a
  /// pure function of geometry, not of time).
  List<MorphMass> _flightBlobs(List<_ResolvedPiece> resolved) {
    final List<MorphMass> blobs = <MorphMass>[];
    lastFlightBlobRects = const <Rect>[];
    Offset? origin;
    for (final _ResolvedPiece r in resolved) {
      final MorphFlight? flight = r.flight;
      if (flight == null || !flight.isAirborne) {
        continue;
      }
      origin ??= localToGlobal(.zero);
      // The flight rects live in ITS overlay's coordinates, not global
      // ones: under a nested Overlay (an embedded device frame) the two
      // spaces differ by the overlay's own offset.
      final RenderBox? overlayBox = flight.overlayBox;
      final Offset delta =
          (overlayBox?.localToGlobal(Offset.zero) ?? Offset.zero) - origin;
      final Rect source = flight.sourceRect == .zero
          ? r.rect
          : flight.sourceRect.shift(delta);
      final Rect target = flight.lastTargetRect == .zero
          ? source
          : flight.lastTargetRect.shift(delta);
      // The SAME geometry the shuttle renders (morphFlightGeometry),
      // shifted by the displacement channel - the mirror blob cannot
      // drift from the visible container by construction. An offset
      // delta needs no origin translation.
      final ({Rect rect, double? sourceRadius, double? targetRadius}) g =
          morphFlightGeometry(
            value: flight.controller.value,
            sourceRect: source,
            targetRect: target,
            sourceShape: flight.tag.shape,
            targetShape: flight.target.shape,
          );
      final Rect flying = g.rect.shift(flight.appliedDragOffset);
      final double r0 = g.sourceRadius ?? r.piece.radius;
      final double radius = morphConcentricRadius(
        r0,
        g.targetRadius ?? r0,
        flight.controller.progress,
        flying,
      );
      final Set<Object> fellow = _flightFellowship[flight] ?? const <Object>{};
      final bool nearFellow = resolved.any(
        (_ResolvedPiece other) =>
            other.solid &&
            fellow.contains(other.piece.id) &&
            liquidRectGap(flying, other.rect) <= _k,
      );
      if (nearFellow) {
        blobs.add(.box(flying, radius: radius));
      }
    }
    if (blobs.isNotEmpty) {
      lastFlightBlobRects = <Rect>[
        for (final MorphMass blob in blobs) blob.outerRect,
      ];
    }
    return blobs;
  }

  Float64List _computeSignature(
    List<_ResolvedPiece> resolved,
    List<MorphMass> blobs,
  ) {
    final Float64List sig = Float64List(
      5 +
          resolved.length * 6 +
          (_extraMasses.length + blobs.length) * liquidMassSignatureStride,
    );
    int i = 0;
    sig[i++] = _k;
    sig[i++] = _cell;
    sig[i++] = _smoothPasses.toDouble();
    sig[i++] = (_evalBudget ?? -1).toDouble();
    sig[i++] = _linksEpoch.toDouble();
    for (final _ResolvedPiece r in resolved) {
      sig[i++] = r.rect.left;
      sig[i++] = r.rect.top;
      sig[i++] = r.rect.width;
      sig[i++] = r.rect.height;
      sig[i++] = r.piece.radius;
      sig[i++] = r.solid ? 1 : 0;
    }
    for (final MorphMass mass in _extraMasses) {
      i = liquidMassSignature(mass, sig, i);
    }
    for (final MorphMass mass in blobs) {
      i = liquidMassSignature(mass, sig, i);
    }
    return sig;
  }

  Path _rebuildPath(List<_ResolvedPiece> resolved, List<MorphMass> blobs) {
    final Map<Object, _ResolvedPiece> byId = <Object, _ResolvedPiece>{
      for (final _ResolvedPiece r in resolved)
        if (r.solid) r.piece.id: r,
    };
    final List<MorphMass> shapes = <MorphMass>[
      for (final _ResolvedPiece r in resolved)
        if (r.solid) .box(r.rect, radius: r.piece.radius),
      // Bridges of non-solid (including flown-away) pieces detach on
      // their own: they are absent from byId - a pipe stretched to the
      // flight target would be an artifact. A pipe into a deflated
      // piece (channel scale 0 collapses the height the default width
      // derives from) has no mass and is skipped, not asserted on.
      for (final MorphLink link in _links)
        if (byId[link.from] case final _ResolvedPiece from?)
          if (byId[link.to] case final _ResolvedPiece to?)
            if ((link.width ?? _defaultBridgeWidth(from.rect, to.rect)) / 2
                case final double radius when radius > 0)
              .bridge(from.rect.center, to.rect.center, radius: radius),
      ..._extraMasses,
      ...blobs,
    ];
    return _tracer.trace(
      LiquidField(shapes, k: _k),
      cell: _cell,
      smoothPasses: _smoothPasses,
      evalBudget: _evalBudget,
    );
  }

  static double _defaultBridgeWidth(Rect a, Rect b) {
    final double h = a.height < b.height ? a.height : b.height;
    return h * 0.5;
  }

  /// The channel delta as a child-local paint transform: the content
  /// deforms exactly with the skin's mass instead of being relaid out.
  Matrix4? _contentTransform(MorphPiece piece) {
    final MorphPieceChannel? channel = piece.channel;
    if (channel == null) {
      return null;
    }
    final double scaleX = channel.scaleX;
    final double scaleY = channel.scaleY;
    final double dx = channel.offset.dx;
    final double dy = channel.offset.dy;
    if (scaleX == 1 && scaleY == 1 && dx == 0 && dy == 0) {
      return null;
    }
    final double cx = piece.rect.width / 2;
    final double cy = piece.rect.height / 2;
    return Matrix4.diagonal3Values(scaleX, scaleY, 1)
      ..setTranslationRaw(cx * (1 - scaleX) + dx, cy * (1 - scaleY) + dy, 0);
  }

  void _paintSkinAndChildren(PaintingContext context, Offset offset) {
    final List<_ResolvedPiece> resolved = _resolvePieces();
    final List<MorphMass> blobs = _flightBlobs(resolved);
    lastFlightBlobCount = blobs.length;
    final Float64List signature = _computeSignature(resolved, blobs);
    if (!_signaturesMatch(signature)) {
      _signature = signature;
      _path = _rebuildPath(resolved, blobs);
    }

    final Canvas canvas = context.canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    if (_elevation > 0) {
      // A translucent skin must be declared as a transparent occluder,
      // otherwise the shadow is clipped as if the surface were opaque.
      canvas.drawShadow(_path, _shadowColor, _elevation, _color.a < 1);
    }
    final Paint fill = Paint();
    final Gradient? gradient = _gradient;
    if (gradient != null) {
      fill.shader = gradient.createShader(Offset.zero & size);
    } else {
      fill.color = _color;
    }
    canvas.drawPath(_path, fill);
    _paintTints(canvas, resolved);
    // The stroke goes LAST: a tint clips itself by the same path, and
    // painting it over the contour would eat the edge - a tinted piece
    // would lose its outline exactly while pressed. The clip is what
    // makes the line inner, so the mass geometry does not change.
    final MorphStroke? stroke = _stroke;
    if (stroke != null) {
      canvas.save();
      canvas.clipPath(_path);
      // The airborne companion is the shuttle's own surface mirrored
      // into the mass; the shuttle draws that surface's contour
      // itself, so stroking the blob here would lay a second line over
      // the first. Clip its box out and let the home body keep its
      // outline.
      for (final Rect blob in lastFlightBlobRects) {
        canvas.clipRect(blob, clipOp: ui.ClipOp.difference);
      }
      canvas.drawPath(_path, _strokePaint(stroke));
      canvas.restore();
    }
    canvas.restore();

    RenderBox? child = firstChild;
    while (child != null) {
      final _LiquidChildParentData pd =
          child.parentData! as _LiquidChildParentData;
      final Matrix4? transform = pd.piece == null
          ? null
          : _contentTransform(pd.piece!);
      if (transform == null) {
        context.paintChild(child, pd.offset + offset);
      } else {
        final RenderBox current = child;
        final FilterQuality? quality = _contentFilterQuality;
        if (quality == null) {
          context.pushTransform(
            needsCompositing,
            pd.offset + offset,
            transform,
            (PaintingContext ctx, Offset o) {
              ctx.paintChild(current, o);
            },
          );
        } else {
          // The filter must act about the child's own origin, so the
          // paint offset is taken out before the channel transform and
          // put back after: the raster then lives in a local space that
          // does not move, which is the whole point - glyphs snap once
          // instead of once per frame.
          final Offset o = pd.offset + offset;
          final Matrix4 local = Matrix4.translationValues(o.dx, o.dy, 0);
          local.multiply(transform);
          local.translateByDouble(-o.dx, -o.dy, 0, 1);
          // The layer is RETAINED per child: a fresh one each paint
          // gives the engine a new layer identity every frame, and the
          // raster keyed on it can never be reused - which is exactly
          // the saving this knob is here to buy.
          final ImageFilterLayer layer =
              pd.filterLayer.layer ?? ImageFilterLayer();
          layer.imageFilter = ui.ImageFilter.matrix(
            local.storage,
            filterQuality: quality,
          );
          pd.filterLayer.layer = layer;
          context.pushLayer(layer, (PaintingContext ctx, Offset inner) {
            ctx.paintChild(current, inner);
          }, o);
        }
      }
      child = pd.nextSibling;
    }
  }

  /// The contour's paint, rebuilt only when the stroke itself changes.
  Paint _strokePaint(MorphStroke stroke) {
    final Paint paint = _cachedStrokePaint ?? Paint();
    _cachedStrokePaint = paint;
    paint.style = PaintingStyle.stroke;
    // Drawn at double width with the outside clipped away: a centered
    // line would put half of itself past the silhouette and optically
    // grow every skin that turns it on.
    paint.strokeWidth = stroke.width * 2;
    paint.color = stroke.color;
    return paint;
  }

  Paint? _cachedStrokePaint;

  /// Per-piece ink: the tinted piece's own rounded body, filled over
  /// the skin and clipped by the traced silhouette. The body rect is
  /// the RESOLVED one - channel displacement and deflation are already
  /// in - so the ink stays glued to the mass through
  /// every deformation; an airborne piece is not solid here and paints
  /// no ink. The rect is inflated by half a grid cell so the quantized
  /// contour cannot peek out along the rim (the clip guarantees the ink
  /// never exceeds the mass); necks stay untinted - ink soaks the body,
  /// not the bond.
  void _paintTints(Canvas canvas, List<_ResolvedPiece> resolved) {
    for (final _ResolvedPiece r in resolved) {
      final Color? tint = r.piece.tint;
      if (tint == null || !r.solid) {
        continue;
      }
      final Rect rect = r.rect;
      if (rect.width <= 0 || rect.height <= 0) {
        continue;
      }
      final double pad = _cell / 2;
      final double half = rect.shortestSide / 2;
      final double radius =
          (r.piece.radius > half ? half : r.piece.radius) + pad;
      canvas
        ..save()
        ..clipPath(_path)
        ..drawRRect(
          RRect.fromRectAndRadius(rect.inflate(pad), Radius.circular(radius)),
          Paint()..color = tint,
        )
        ..restore();
    }
  }

  bool _signaturesMatch(Float64List signature) {
    final Float64List? previous = _signature;
    if (previous == null || previous.length != signature.length) {
      return false;
    }
    for (int i = 0; i < signature.length; i++) {
      if (previous[i] != signature[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_clipBehavior == .none) {
      _paintSkinAndChildren(context, offset);
      return;
    }
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      _paintSkinAndChildren,
      clipBehavior: _clipBehavior,
    );
  }

  /// The clip paint applies is described to semantics too, so
  /// assistive tech does not reach content the eye cannot see.
  @override
  Rect? describeApproximatePaintClip(covariant RenderObject child) =>
      _clipBehavior == .none ? null : Offset.zero & size;

  /// localToGlobal must see the exact transform paint applies: a
  /// [MorphTag] inside a channel-displaced piece measures its launch
  /// rect through here, and a popover anchored to a displaced control
  /// aims through here too.
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final _LiquidChildParentData pd =
        child.parentData! as _LiquidChildParentData;
    transform.translateByDouble(pd.offset.dx, pd.offset.dy, 0, 1);
    final MorphPiece? piece = pd.piece;
    if (piece == null) {
      return;
    }
    final Matrix4? content = _contentTransform(piece);
    if (content != null) {
      transform.multiply(content);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    while (child != null) {
      final _LiquidChildParentData pd =
          child.parentData! as _LiquidChildParentData;
      final Matrix4? transform = pd.piece == null
          ? null
          : _contentTransform(pd.piece!);
      final RenderBox current = child;
      final bool isHit;
      if (transform == null) {
        isHit = result.addWithPaintOffset(
          offset: pd.offset,
          position: position,
          hitTest: (BoxHitTestResult result, Offset transformed) {
            return current.hitTest(result, position: transformed);
          },
        );
      } else {
        isHit = result.addWithPaintTransform(
          transform: Matrix4.translationValues(pd.offset.dx, pd.offset.dy, 0)
            ..multiply(transform),
          position: position,
          hitTest: (BoxHitTestResult result, Offset transformed) {
            return current.hitTest(result, position: transformed);
          },
        );
      }
      if (isHit) {
        return true;
      }
      child = pd.previousSibling;
    }
    return false;
  }
}
