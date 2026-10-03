import 'package:flutter/widgets.dart';

import 'package:morph/src/flight.dart';
import 'package:morph/src/frame.dart';
import 'package:morph/src/scope.dart';

/// Shared elements inside a flight: a piece of content (an album cover,
/// an avatar, an icon) that TRAVELS from its place in the source to its
/// place in the target instead of riding the fade-through crossfade.
///
/// Mark the element on both sides with the same id:
///
/// ```dart
/// // in the button:
/// MorphSharedElement(id: 'cover', child: AlbumArt(size: 48))
/// // in the dialog content:
/// MorphSharedElement(id: 'cover', child: AlbumArt(size: 240))
/// ```
///
/// Unlike route-level hero frameworks there is no teleportation and no
/// second animation: both contents already live inside the one shuttle,
/// so the flying frame is a pure function of the same spring value
/// (geometry linear in value - interruptions stay continuous by
/// construction), and the element is clipped by the morphing container
/// shape like everything else.
///
/// Rules and graceful degradation:
///  - an id present on only one side simply renders in place;
///  - with `snapshotGhost` the source side has no live markers, so
///    pairs do not form and the flight falls back to fade-through;
///  - the child must not carry a GlobalKey (it is replicated into the
///    flying layer).
class MorphSharedElement extends StatefulWidget {
  /// Marks [child] as one side of the shared pair [id].
  const MorphSharedElement({
    super.key,
    required this.id,
    this.fade = .through,
    required this.child,
  });

  /// Pair identity; the same id on both sides of a flight forms a pair.
  final Object id;

  /// How the two sides blend while flying; either side declaring
  /// [MorphSharedFade.none] applies it to the whole pair.
  final MorphSharedFade fade;

  /// The content that flies between its endpoint rects.
  final Widget child;

  @override
  State<MorphSharedElement> createState() => MorphSharedElementState();
}

/// How a shared pair blends during the flight.
enum MorphSharedFade {
  /// The container's fade-through curves: the source side dissolves
  /// early, the target side arrives late. Right when the two sides
  /// genuinely differ - the unreadable midstate is never shown.
  through,

  /// No fade at all: the TARGET side renders alone at full opacity for
  /// the whole flight. Declare this when the content is the SAME on
  /// both sides (a cover, a title) - fade-through would dim it
  /// mid-flight into a visible blink, and identical content has no
  /// midstate to hide.
  none,
}

/// Registration and measurement side of a [MorphSharedElement].
class MorphSharedElementState extends State<MorphSharedElement> {
  SharedSideScope? _side;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final SharedSideScope? side = SharedSideScope.maybeOf(context);
    if (!identical(side, _side)) {
      _side?.unregister(widget.id, this);
      _side = side;
      side?.register(widget.id, this);
    }
  }

  @override
  void didUpdateWidget(MorphSharedElement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _side?.unregister(oldWidget.id, this);
      _side?.register(widget.id, this);
    }
  }

  @override
  void dispose() {
    _side?.unregister(widget.id, this);
    super.dispose();
  }

  /// The element rect relative to its side's anchor box (the box laid
  /// out at the endpoint size); null until laid out.
  Rect? rectInAnchor(RenderBox anchor) {
    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    return MatrixUtils.transformRect(
      renderObject.getTransformTo(anchor),
      Offset.zero & renderObject.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.child.key is! GlobalKey,
      'MorphSharedElement(id: ${widget.id}): the child is replicated '
      'into the flying layer and cannot carry a GlobalKey.',
    );
    final SharedSideScope? side = _side;
    if (side == null) {
      // In the wild (the live widget tree): render normally. During a
      // flight the whole tag is hidden anyway.
      return widget.child;
    }
    // Inside the shuttle: the original hides while the flying layer
    // owns the element, and hands back at the ends (opacity keeps the
    // layout slot). The hide predicate is canFly - the SAME condition
    // under which the flying layer can render - not the pair registration: it
    // forms during the shuttle's first build, but the flying layer
    // cannot measure until that frame's layout has run, so a marker
    // hiding on registration alone leaves the element visible NOWHERE
    // for one frame - a blink on every launch.
    return ListenableBuilder(
      listenable: side.flight.controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final bool flying =
            side.flight.sharedElements.canFly(widget.id) &&
            (side.flight.controller.isAnimating ||
                side.flight.controller.isScrubbing);
        return Opacity(opacity: flying ? 0 : 1, child: child);
      },
    );
  }
}

/// The per-flight registry of marked elements on both sides. Owned by
/// [MorphFlight]; sides register through [SharedSideScope].
class SharedElementRegistry {
  final Map<Object, MorphSharedElementState> _source =
      <Object, MorphSharedElementState>{};
  final Map<Object, MorphSharedElementState> _target =
      <Object, MorphSharedElementState>{};

  final Set<Object> _measured = <Object>{};

  /// Whether [id] rendered as a flying layer in the last shuttle
  /// build - the marker-hide predicate. Recorded by
  /// [buildSharedFlightLayers] as it measures (the markers sit deeper
  /// in the same build pass, so they read the same frame's verdict);
  /// deliberately NOT computed from the marker elements - the markers
  /// must never touch render objects themselves, because during the
  /// route-mode reparent their subtree is briefly inactive. Hiding on
  /// registration alone left the element visible NOWHERE on the
  /// shuttle's first frame (the pair registers during that build, but
  /// nothing is measurable until its layout has run) - a blink on
  /// every launch.
  bool canFly(Object id) => _measured.contains(id);

  /// Ids registered on both sides, in target-registration order.
  Iterable<Object> get pairedIds =>
      _source.keys.where(_target.containsKey).toList();

  /// The source-side marker of [id], if registered.
  MorphSharedElementState? sourceOf(Object id) => _source[id];

  /// The target-side marker of [id], if registered.
  MorphSharedElementState? targetOf(Object id) => _target[id];
}

/// Which side of the shuttle a marker lives on. Installed by the
/// shuttle around the source replica and the target content;
/// library-internal.
class SharedSideScope extends InheritedWidget {
  /// Publishes which flight side the subtree's markers register on.
  const SharedSideScope({
    super.key,
    required this.flight,
    required this.isTarget,
    required this.anchorKey,
    required super.child,
  });

  /// The flight whose registry the markers join.
  final MorphFlight flight;

  /// true for the target content, false for the source replica.
  final bool isTarget;

  /// The box laid out at this side's endpoint size - the coordinate
  /// space element rects are measured in.
  final GlobalKey anchorKey;

  /// The enclosing side scope, or null outside flight content.
  static SharedSideScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SharedSideScope>();

  /// Adds a marker to this side's registry.
  ///
  /// A second live marker with the same id on one side is reported as
  /// a [FlutterError] (without throwing) and stays in place: the marker
  /// registered first is the one that flies.
  void register(Object id, MorphSharedElementState state) {
    final Map<Object, MorphSharedElementState> map = isTarget
        ? flight.sharedElements._target
        : flight.sharedElements._source;
    final MorphSharedElementState? holder = map[id];
    if (holder == null || !holder.mounted) {
      map[id] = state;
      return;
    }
    if (holder == state) {
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary(
            'Duplicate MorphSharedElement(id: $id) on the '
            '${isTarget ? 'target' : 'source'} side of one flight.',
          ),
          ErrorDescription(
            'Only the marker registered first flies; this one renders in '
            'place.',
          ),
          ErrorHint('Give every shared element on one side its own id.'),
        ]),
        library: 'morph',
        context: ErrorDescription('while registering a shared element'),
      ),
    );
  }

  /// Removes a marker if [state] still owns the slot.
  void unregister(Object id, MorphSharedElementState state) {
    final Map<Object, MorphSharedElementState> map = isTarget
        ? flight.sharedElements._target
        : flight.sharedElements._source;
    if (map[id] == state) {
      map.remove(id);
    }
  }

  @override
  bool updateShouldNotify(SharedSideScope oldWidget) =>
      flight != oldWidget.flight || isTarget != oldWidget.isTarget;
}

/// The flying layers for one shuttle frame: one crossfading box per
/// paired id, its rect a lerp of the endpoint rects in overlay
/// coordinates by the RAW spring value (matching the container
/// geometry), positioned in the container's local space so the morphing
/// shape clips it like native content.
List<Widget> buildSharedFlightLayers({
  required MorphFlight flight,
  required MorphFrame frame,
  required GlobalKey sourceAnchorKey,
  required GlobalKey targetAnchorKey,
  required Rect sourceRect,
  required Rect targetRect,
  required MorphSurfaceSpec targetSpec,
}) {
  // The measured set mirrors THIS build exactly: an id is in it iff a
  // flying layer for it is in the returned list - the markers hide by
  // that set ([SharedElementRegistry.canFly]), so the element is
  // always visible in exactly one place.
  flight.sharedElements._measured.clear();
  if (!(flight.controller.isAnimating || flight.controller.isScrubbing)) {
    return const <Widget>[];
  }
  final RenderObject? sourceAnchor = sourceAnchorKey.currentContext
      ?.findRenderObject();
  final RenderObject? targetAnchor = targetAnchorKey.currentContext
      ?.findRenderObject();
  if (sourceAnchor is! RenderBox ||
      targetAnchor is! RenderBox ||
      !sourceAnchor.hasSize ||
      !targetAnchor.hasSize) {
    return const <Widget>[];
  }
  final List<Widget> layers = <Widget>[];
  for (final Object id in flight.sharedElements.pairedIds) {
    final MorphSharedElementState? source = flight.sharedElements.sourceOf(id);
    final MorphSharedElementState? target = flight.sharedElements.targetOf(id);
    if (source == null || target == null) {
      continue;
    }
    final Rect? sourceLocal = source.rectInAnchor(sourceAnchor);
    final Rect? targetLocal = target.rectInAnchor(targetAnchor);
    if (sourceLocal == null || targetLocal == null) {
      continue;
    }
    flight.sharedElements._measured.add(id);
    final Rect sourceOverlay = sourceLocal.shift(sourceRect.topLeft);
    final Rect targetOverlay = targetLocal.shift(targetRect.topLeft);
    final Rect flying = Rect.lerp(
      sourceOverlay,
      targetOverlay,
      flight.controller.value,
    )!.shift(-frame.rect.topLeft);
    // Either side declaring no-fade applies it to the pair: the
    // declaration means "this content is the same on both sides", and
    // one side knowing that is enough.
    final bool solo =
        source.widget.fade == MorphSharedFade.none ||
        target.widget.fade == MorphSharedFade.none;
    layers.add(
      Positioned.fromRect(
        key: ValueKey<Object>(id),
        rect: flying,
        child: IgnorePointer(
          child: Stack(
            fit: .expand,
            children: <Widget>[
              // Fade-through swaps DIFFERING sides without ever showing
              // the unreadable midstate; identical sides opt out via
              // MorphSharedFade.none instead - both faders dip together
              // mid-flight, so a fade-through of the same content reads
              // as a blink.
              if (!solo && frame.sourceOpacity > 0)
                Opacity(
                  opacity: frame.sourceOpacity,
                  child: FittedBox(
                    fit: .fill,
                    child: SizedBox.fromSize(
                      size: sourceLocal.size,
                      child: MorphSurfaceSpecScope(
                        spec: flight.tag.surfaceSpec,
                        child: source.widget.child,
                      ),
                    ),
                  ),
                ),
              // The target side is the one that lands (the Hero
              // precedent); solo mode renders it alone at full opacity.
              Opacity(
                opacity: solo ? 1 : frame.targetOpacity,
                child: FittedBox(
                  fit: .fill,
                  child: SizedBox.fromSize(
                    size: targetLocal.size,
                    child: MorphSurfaceSpecScope(
                      spec: targetSpec,
                      child: target.widget.child,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  return layers;
}
