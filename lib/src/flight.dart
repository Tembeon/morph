import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';
import 'package:meta/meta.dart';

import 'package:morph/src/controller.dart';
import 'package:morph/src/frame.dart';
import 'package:morph/src/gesture.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/shared.dart';
import 'package:morph/src/motion.dart';
import 'package:morph/src/target.dart';

/// Builds the target content of a flight; called once per flight and
/// reused between spring ticks.
typedef MorphContentBuilder =
    Widget Function(BuildContext context, MorphFlight flight);

/// One flight: the tag -> shuttle -> target trio. Lives from launch to
/// close finalization. A repeated showMorph on the same tag does not
/// create a new flight - it retargets this one, which makes interruption
/// free for the caller.
class MorphFlight {
  MorphFlight._({
    required this.scope,
    required this.tag,
    required this.target,
    required this.builder,
    required this.barrierDismissible,
    required this.maxScrimOpacity,
    required this._overlay,
    required MorphMotion motion,
    required bool disableAnimations,
  }) {
    controller =
        MorphController(vsync: scope, motion: motion, onHandoff: _onHandoff)
          ..disableAnimations = disableAnimations
          ..addListener(_onTick);
  }

  /// The scope this flight is registered in.
  final MorphScopeState scope;

  /// The source tag the flight departs from and lands into.
  final MorphTagState tag;

  /// The destination description; its rect is re-read every frame.
  final MorphTargetSpec target;

  /// Builds the target content.
  final MorphContentBuilder builder;

  /// Whether scrim taps and Esc dismiss the flight.
  final bool barrierDismissible;

  /// Scrim opacity in the fully open state.
  final double maxScrimOpacity;
  final OverlayState _overlay;

  /// The declarative close route: when set, a scrim tap or Esc does not
  /// close the flight itself but asks the state owner - who flips state,
  /// and close() arrives from above. State down, events up.
  VoidCallback? onDismissRequested;

  /// Accessibility name of the opened overlay: it scopes and names the
  /// semantic route, so screen readers announce the opening. null keeps
  /// the overlay unnamed (still scoped).
  String? semanticLabel;

  /// The single spring every visual property derives from.
  late final MorphController controller;
  OverlayEntry? _entry;

  /// The source rect in overlay coordinates; engine-written every
  /// frame, read-only for apps.
  Rect sourceRect = .zero;

  /// The current target rect, refreshed by the shuttle every frame.
  Rect lastTargetRect = .zero;

  bool _finished = false;
  bool _controllerDisposed = false;
  Object? _result;
  final Completer<Object?> _closedCompleter = Completer<Object?>();

  /// Marked shared elements on both sides of this flight (see
  /// [MorphSharedElement]).
  @internal
  final SharedElementRegistry sharedElements = SharedElementRegistry();

  /// A pixel ghost of the button (captured from the tag's live
  /// RepaintBoundary at launch): an exact copy including a ripple, with
  /// no double build and no GlobalKey restrictions. Until it is ready
  /// the shuttle draws the widget replica.
  ui.Image? _sourceSnapshot;

  /// The captured pixel ghost, when [MorphTag.snapshotGhost] is set.
  ui.Image? get sourceSnapshot => _sourceSnapshot;

  /// The source tag's id.
  Object get tagId => tag.id;

  /// Completes when the flight finalizes (landed or aborted), with the
  /// result of the [close] that landed it - the overlay counterpart of
  /// awaiting showDialog. A dismissal (scrim tap, Esc, back) closes
  /// with null; in route mode the value passed to Navigator.pop rides
  /// here too.
  Future<Object?> get closed => _closedCompleter.future;

  /// Whether the flight has finalized.
  bool get isFinished => _finished;

  /// Whether the flight targets the open state.
  bool get isOpenOrOpening => !_finished && controller.target >= 1;

  /// The content lives in the shuttle: from takeoff to the handoff
  /// latch. For that whole span the source widget is hidden, and its
  /// mass (for the liquid skin) should follow the shuttle instead of
  /// sitting at home.
  bool get isAirborne => !_finished && !controller.hasHandedOff;

  /// Landing: the latch has fired, the content is back in the widget,
  /// and the spring is playing out the residual undershoot (the bump)
  /// on the live button.
  bool get isLanding => !_finished && controller.hasHandedOff;

  /// The impact axis for the landing bump: from the target toward home.
  Offset get impactAxis => sourceRect.center - lastTargetRect.center;

  // Route mode: the SECOND latch. A MorphPageRoute pushes immediately
  // and this flight plays as its visual transition; once the open
  // spring settles, ownership of the target content transfers from the
  // shuttle to the route page, and transfers back the moment a close
  // starts. Both sides listen to [routeOwnsContent] and rebuild in the
  // same frame, so the [routeContentKey]-ed subtree reparents with its
  // live state instead of rebuilding - the one sanctioned GlobalKey
  // move in the system (the tag-side ban on GlobalKeys is about double
  // mounting a replica, which route mode never does).
  @internal
  /// Route mode: true while the route page (not the shuttle) owns the
  /// target content. Both owners listen and rebuild in the same frame,
  /// so the [routeContentKey] subtree reparents with live state.
  final ValueNotifier<bool> routeOwnsContent = ValueNotifier<bool>(false);
  GlobalKey? _routeContentKey;

  /// Non-null only in route mode: the shared identity of the target
  /// content subtree, mounted by exactly one side at a time.
  @internal
  GlobalKey? get routeContentKey => _routeContentKey;

  /// Switches this flight into route mode (see [routeOwnsContent]).
  /// Called by the route before the flight opens; irreversible for the
  /// flight's lifetime.
  @internal
  void enableRouteMode() {
    _routeContentKey ??= GlobalKey(debugLabel: 'morph route content');
  }

  // Pop layering: an OVERLAY flight opened above a ModalRoute registers
  // a LocalHistoryEntry on it, so Esc (DismissIntent -> maybePop), the
  // Android back and a plain Navigator.pop all close the TOPMOST
  // surface first - the flight - and only the next pop touches the
  // route. Route-mode flights skip this: their own route IS the
  // history. Without the entry, Esc under a morph route popped the
  // route while the flight kept hanging above it, orphaned.
  LocalHistoryEntry? _historyEntry;
  ModalRoute<Object?>? _historyRoute;
  bool _removingHistory = false;

  void _addHistoryEntry(BuildContext context) {
    if (_routeContentKey != null || _historyEntry != null) {
      return;
    }
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route == null) {
      return;
    }
    _historyRoute = route;
    _pushHistoryEntry(route);
  }

  void _pushHistoryEntry(ModalRoute<Object?> route) {
    _historyEntry = LocalHistoryEntry(
      onRemove: () {
        _historyEntry = null;
        if (!_removingHistory) {
          // Popped from the history side (Esc, back, Navigator.pop):
          // dismiss the flight, honoring the declarative close route.
          requestDismiss();
        }
      },
    );
    route.addLocalHistoryEntry(_historyEntry!);
  }

  /// Re-registers the entry after an interrupted close: close() removes
  /// it immediately, so a close -> open retarget must put it back or
  /// the next system pop reaches the page UNDER the visible overlay.
  void _restoreHistoryEntry() {
    final ModalRoute<Object?>? route = _historyRoute;
    if (_routeContentKey != null ||
        _historyEntry != null ||
        route == null ||
        !route.isActive) {
      return;
    }
    _pushHistoryEntry(route);
  }

  void _removeHistoryEntry() {
    final LocalHistoryEntry? entry = _historyEntry;
    if (entry != null) {
      _historyEntry = null;
      _removingHistory = true;
      // The owning route survives a pushReplacement/removeRoute only as
      // a corpse: its modal barrier is already disposed and
      // removeLocalHistoryEntry would trip markNeedsBuild on it. The
      // entry dies with its route - dropping the reference is enough.
      if (_historyRoute?.isActive ?? false) {
        entry.remove();
      }
      _removingHistory = false;
    }
  }

  /// The displacement channel (see [_DragChannel]): finger-owned
  /// container offset, orthogonal to the morph value.
  late final _DragChannel _drag = _DragChannel(this);

  /// One subscription point for everything that renders a flight frame:
  /// the value spring and the displacement channel merged. The shuttle
  /// and the skin listen HERE, so a new co-driver of the frame never
  /// needs a second subscription seam.
  late final Listenable frameTicks = .merge(<Listenable>[controller, _drag]);

  /// The raw finger displacement of the container, in overlay px.
  Offset get dragOffset => _drag.offset;

  /// true between [beginDrag] and [endDrag].
  bool get isDragging => _drag.isActive;

  /// Distance-based preview of the release heuristic: true when letting
  /// go RIGHT NOW would commit the close (a fast fling can still commit
  /// from closer). Watch it during dragBy for haptics or custom cues -
  /// the built-in visual cue ([morphDragArm]) rides the same threshold.
  bool get isDragArmed => _drag.offset.distance > morphDragCommitDistance;

  /// The displacement to apply to the container this frame: the raw
  /// offset plus the armed "lean toward home" cue, all faded by
  /// progress so it vanishes exactly at the handoff latch - the swap
  /// back to the home widget happens at zero offset.
  Offset get appliedDragOffset {
    final Offset offset = _drag.offset;
    if (offset == .zero) {
      return Offset.zero;
    }
    Offset total = offset;
    final double arm = morphDragArm(offset.distance);
    if (arm > 0) {
      // Armed, the card starts drifting toward its source: the
      // destination of a release becomes legible before the release.
      final Offset toHome =
          sourceRect.center - (lastTargetRect.center + offset);
      final double distance = toHome.distance;
      if (distance >= 1) {
        total += toHome / distance * (12 * arm);
      }
    }
    return total * controller.progress;
  }

  /// Starts finger ownership of the container displacement. The morph
  /// value is untouched: grabbing a still-opening overlay lets it keep
  /// materializing while it follows the hand.
  void beginDrag() {
    if (_finished) {
      return;
    }
    _drag.begin();
  }

  /// Feeds a pointer delta 1:1: the whole container - surface, shadow,
  /// content, shared elements - moves as one rigid body.
  void dragBy(Offset delta) {
    if (_finished) {
      return;
    }
    _drag.moveBy(delta);
  }

  /// Releases the finger. The displacement always springs back to zero
  /// with the carried velocity; whether the close flight plays too is
  /// decided by momentum projection ([morphProjectValue] per axis)
  /// against [morphDragCommitDistance] / [morphDragCommitVelocity] -
  /// or forced either way with [commit].
  void endDrag(Offset velocityPerSecond, {bool? commit}) {
    if (_finished || !_drag.isActive) {
      return;
    }
    final Offset offset = _drag.offset;
    final Offset projected = Offset(
      morphProjectValue(offset.dx, velocityPerSecond.dx),
      morphProjectValue(offset.dy, velocityPerSecond.dy),
    );
    final bool shouldClose =
        commit ??
        (projected.distance > morphDragCommitDistance ||
            velocityPerSecond.distance > morphDragCommitVelocity);
    _drag.release(velocityPerSecond);
    if (shouldClose && isOpenOrOpening) {
      close();
    }
  }

  /// Launches (or retargets) the flight for [from]. Prefer the
  /// showMorph* entry points: they also resolve [MorphTheme] defaults,
  /// this method does not.
  static MorphFlight launch(
    BuildContext context, {
    required Object from,
    required MorphTargetSpec target,
    required MorphContentBuilder builder,
    MorphMotion? motion,
    bool barrierDismissible = true,
    double maxScrimOpacity = 0.45,
    VoidCallback? onDismissRequested,
    String? semanticLabel,
    bool routeMode = false,
    // The shuttle's home. Defaults to the root overlay above [context];
    // a route passes its navigator's own overlay explicitly, because
    // the navigator's context sits ABOVE that overlay.
    OverlayState? overlay,
  }) {
    final MorphScopeState scope = MorphScope.of(context);
    // liveFlightOf, not flightOf: retargeting a stray flight whose tag
    // was disposed would drive show/hide on a defunct State.
    final MorphFlight? existing = scope.liveFlightOf(from);
    if (existing != null) {
      assert(
        !routeMode || existing.routeContentKey != null,
        'showMorphRoute(from: $from): an overlay flight is already live '
        'for this tag. A route cannot adopt an overlay flight mid-air - '
        'the content ownership chains differ. Close the overlay first, '
        'or retarget it with showMorph.',
      );
      if (motion != null) {
        existing.controller.motion = motion;
      }
      if (onDismissRequested != null) {
        existing.onDismissRequested = onDismissRequested;
      }
      if (semanticLabel != null) {
        existing.semanticLabel = semanticLabel;
      }
      if (routeMode) {
        existing.enableRouteMode();
      }
      // RETARGET CONTRACT: the existing flight keeps its target,
      // builder, barrier and scrim - the content lives in the shuttle
      // and cannot be swapped mid-air. Only motion, dismissal routing
      // and the semantic label are updated.
      existing
        ..open()
        .._addHistoryEntry(context);
      return existing;
    }
    final MorphFlight flight =
        MorphFlight._(
            scope: scope,
            tag: scope.tagOf(from),
            target: target,
            builder: builder,
            barrierDismissible: barrierDismissible,
            maxScrimOpacity: maxScrimOpacity,
            // The NEAREST overlay: the flight belongs to the world its
            // scope lives in. A nested navigator (a tab, an embedded
            // device mockup) keeps its flights inside itself; in a
            // single-navigator app this is the root overlay anyway.
            overlay: overlay ?? Overlay.of(context),
            motion: motion ?? .normal,
            disableAnimations:
                MediaQuery.maybeDisableAnimationsOf(context) ?? false,
          )
          ..onDismissRequested = onDismissRequested
          ..semanticLabel = semanticLabel;
    if (routeMode) {
      flight.enableRouteMode();
    }
    scope.adoptFlight(flight);
    flight
      ..open()
      .._addHistoryEntry(context);
    return flight;
  }

  /// Retargets the spring toward open, inserting the shuttle if needed.
  void open({double? velocity}) {
    if (_finished) {
      return;
    }
    if (_entry == null) {
      _insertEntry();
    }
    _restoreHistoryEntry();
    controller.open(velocity: velocity);
  }

  /// Retargets the spring toward closed; from rest the close velocity
  /// hint scales with the flight's pixel travel so a far close lands
  /// heavier.
  ///
  /// [result] is what [closed] completes with at finalization - "what
  /// did the user pick". Every close overwrites it (a dismissal after
  /// a value-carrying close honestly reports null).
  void close({double? velocity, Object? result}) {
    if (_finished || (controller.target == 0 && !controller.isScrubbing)) {
      return;
    }
    _result = result;
    _removeHistoryEntry();
    refreshSourceRect();
    double? v = velocity;
    // Value space normalizes distance, so the flight's pixel scale
    // re-enters the physics here: a far close gets a bigger velocity
    // injection - it lands heavier and bounces more visibly. Only from
    // rest: a live interruption has its own velocity. A scrub whose
    // value stands still (a committed predictive back) counts as rest -
    // its zero velocity would starve the landing bump.
    if (v == null &&
        !controller.isAnimating &&
        (!controller.isScrubbing || controller.velocity == 0)) {
      final double travel =
          (lastTargetRect.center - sourceRect.center).distance;
      v =
          controller.effectiveMotion.closeVelocityHint *
          morphCloseHintScale(travel);
    }
    controller.close(velocity: v);
  }

  /// Live source tracking: the tag's rect is re-read on every flight
  /// frame (window resized, layout shifted - we fly to the current
  /// point, with at most one frame of lag).
  @internal
  void refreshSourceRect() {
    final RenderBox? overlayBox = _overlayBox;
    if (overlayBox == null || !tag.mounted) {
      return;
    }
    final Rect? fresh = tag.tryCaptureRect(overlayBox);
    if (fresh != null) {
      sourceRect = fresh;
    }
  }

  /// [close] when open or opening, [open] otherwise.
  void toggle() {
    if (controller.target >= 1) {
      close();
    } else {
      open();
    }
  }

  /// Rebuilds the shuttle's content subtree from the current builder
  /// closure. Overlay content does not follow its owner's build on its
  /// own (an OverlayEntry is an island): a state owner whose open
  /// content derives from that state calls this after setState -
  /// [MorphAnchor] does it on every rebuild.
  void markNeedsBuild() => _entry?.markNeedsBuild();

  /// Routes a dismissal through [onDismissRequested] when set,
  /// otherwise calls [close] - the single funnel for scrim taps, Esc
  /// and back.
  void requestDismiss() {
    final VoidCallback? request = onDismissRequested;
    if (request != null) {
      request();
    } else {
      close();
    }
  }

  RenderBox? get _overlayBox {
    final RenderObject? box = _overlay.context.findRenderObject();
    return box is RenderBox ? box : null;
  }

  /// The box of the overlay the shuttle renders in - the coordinate
  /// space [sourceRect] and [lastTargetRect] live in. Consumers in a
  /// DIFFERENT space (the skin's mirror blob) translate through it; a
  /// nested overlay does not sit at the window origin.
  @internal
  RenderBox? get overlayBox => _overlayBox;

  void _insertEntry() {
    refreshSourceRect();
    if (tag.widget.snapshotGhost) {
      // A flight usually launches from the button's own tap, mid-ripple:
      // the boundary is dirty at that moment and toImage asserts on it -
      // and once the tag hides (opacity 0) its subtree never paints
      // again, so a dirty boundary would stay dirty forever. The capture
      // therefore waits for this frame's paint, and the tag hides only
      // AFTER the shot. The shuttle already covers the source exactly
      // (drawing the live replica meanwhile), so the extra visible
      // frames are occluded.
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        _captureSourceSnapshot().whenComplete(() {
          if (!_finished &&
              _entry != null &&
              tag.mounted &&
              !controller.hasHandedOff) {
            tag.hideForFlight();
          }
        });
      });
    } else {
      tag.hideForFlight();
    }
    _entry = OverlayEntry(
      builder: (BuildContext context) => _MorphShuttle(flight: this),
    );
    _overlay.insert(_entry!);
  }

  Future<void> _captureSourceSnapshot() async {
    if (!tag.mounted || !tag.widget.snapshotGhost) {
      return;
    }
    final double dpr = MediaQuery.maybeDevicePixelRatioOf(tag.context) ?? 1;
    final ui.Image? image = await tag.captureSnapshot(dpr);
    if (image == null) {
      return;
    }
    if (_finished || _entry == null) {
      image.dispose();
      return;
    }
    _sourceSnapshot?.dispose();
    _sourceSnapshot = image;
    _entry?.markNeedsBuild();
  }

  void _disposeSnapshot() {
    _sourceSnapshot?.dispose();
    _sourceSnapshot = null;
  }

  void _removeEntry() {
    final OverlayEntry? entry = _entry;
    _entry = null;
    if (entry != null) {
      entry
        ..remove()
        ..dispose();
    }
  }

  void _onHandoff() {
    if (tag.mounted) {
      tag.revealWithBump(controller, impactAxis: impactAxis);
    }
    _removeEntry();
  }

  void _onTick() {
    // A scrub parks the ticker with the target still at 0: that is an
    // interruption of the close, not its end.
    if (!_finished &&
        controller.target == 0 &&
        !controller.isAnimating &&
        !controller.isScrubbing) {
      _finalize();
    }
  }

  void _disposeDrag() => _drag.reset();

  /// Any teardown that skips the handoff latch must return the source
  /// widget itself: the only other un-hide lives on the latch, and a
  /// hidden tag with no flight would stay invisible forever.
  void _revealTagIfAirborne() {
    if (!controller.hasHandedOff && tag.mounted) {
      tag.reveal();
    }
  }

  void _finalize() {
    _finished = true;
    controller.removeListener(_onTick);
    _revealTagIfAirborne();
    _removeHistoryEntry();
    _historyRoute = null;
    _removeEntry();
    _disposeSnapshot();
    _disposeDrag();
    tag.clearBump();
    scope.retireFlight(this);
    _closedCompleter.complete(_result);
  }

  /// Tears the flight down without animation.
  void abort() {
    if (!_finished) {
      _finished = true;
      controller.removeListener(_onTick);
      _revealTagIfAirborne();
      _removeHistoryEntry();
      _historyRoute = null;
      _removeEntry();
      _disposeSnapshot();
      _disposeDrag();
      controller.stop();
      scope.retireFlight(this);
      if (!_closedCompleter.isCompleted) {
        _closedCompleter.complete(_result);
      }
    }
    // Disposing the controller is deferred to the scope's retire
    // mechanism: external listeners (a HUD, derived animations) may
    // still be subscribed, and a synchronous dispose would break their
    // removeListener.
  }

  /// Disposes the controller and channels; called by the scope's
  /// deferred retirement.
  @internal
  void disposeController() {
    if (!_controllerDisposed) {
      _controllerDisposed = true;
      controller.dispose();
      _drag.dispose();
      routeOwnsContent.dispose();
    }
  }
}

/// The modal barrier of a flight: the dimming layer, its dismiss tap
/// and the screen-reader dismiss affordance. Opacity is computed by the
/// frame (scrim curve x displacement recede x arm cue).
class _ShuttleScrim extends StatelessWidget {
  const _ShuttleScrim({required this.flight, required this.opacity});

  final MorphFlight flight;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: flight.barrierDismissible
          ? MaterialLocalizations.of(context).modalBarrierDismissLabel
          : null,
      container: flight.barrierDismissible,
      onDismiss: flight.barrierDismissible ? flight.requestDismiss : null,
      child: GestureDetector(
        behavior: .opaque,
        onTap: flight.barrierDismissible ? flight.requestDismiss : null,
        child: ColoredBox(color: Colors.black.withValues(alpha: opacity)),
      ),
    );
  }
}

/// The source ghost inside the shuttle: the button as it looked at
/// takeoff (a pixel snapshot when opted in, the live replica
/// otherwise). Stays MOUNTED for the whole flight, not only while
/// visible - shared-element markers inside it must keep reporting
/// endpoint rects.
class _SourceGhost extends StatelessWidget {
  const _SourceGhost({
    required this.flight,
    required this.opacity,
    required this.scale,
    required this.anchorKey,
  });

  final MorphFlight flight;
  final double opacity;

  /// The container's growth since launch (width ratio). The replica
  /// RIDES the geometry: a button-sized copy floating at natural size
  /// inside a grown container reads as a second surface layered on the
  /// card, at any opacity. Scaled, the replica and the container are
  /// one body; at the home end the scale is exactly 1, so the latch
  /// swap is pixel-identical.
  final double scale;
  final GlobalKey anchorKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Transform.scale(
        scale: scale,
        child: OverflowBox(
          minWidth: flight.sourceRect.width,
          maxWidth: flight.sourceRect.width,
          minHeight: flight.sourceRect.height,
          maxHeight: flight.sourceRect.height,
          child: KeyedSubtree(
            key: anchorKey,
            child: IgnorePointer(
              child: Opacity(
                opacity: opacity,
                child: flight.sourceSnapshot != null
                    ? RawImage(
                        image: flight.sourceSnapshot,
                        width: flight.sourceRect.width,
                        height: flight.sourceRect.height,
                        fit: .fill,
                      )
                    : MorphSurfaceSpecScope(
                        // One mass - one shadow: the container casts THE
                        // shadow, so the spec the replica renders from
                        // carries no elevation - a spec-driven button
                        // must not cast a second shadow inside the
                        // shuttle.
                        spec: flight.tag.surfaceSpec.copyWith(elevation: 0),
                        child: SharedSideScope(
                          flight: flight,
                          isTarget: false,
                          anchorKey: anchorKey,
                          child: flight.tag.replica,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The gesture displacement channel: a SECOND degree of freedom,
/// orthogonal to the morph value. While the finger is down it owns a
/// whole-container offset 1:1 (direct manipulation: the value does not
/// move, so no morph midstates can show); releasing always springs the
/// offset home on its own simulations, and past the commit threshold
/// the ordinary close flight plays simultaneously - the superposition
/// reads as "the card flies home out of the hand". The offset cannot
/// be a function of the spring value (at value 1 it must equal both
/// the release offset and zero at settle), so it is honest extra state
/// with its own always-to-zero spring; each DOF stays a pure function
/// of its own spring and interruption continuity survives.
///
/// A ChangeNotifier: its ticks join [MorphFlight.frameTicks], the one
/// stream every frame consumer subscribes to.
class _DragChannel extends ChangeNotifier {
  _DragChannel(this._flight);

  final MorphFlight _flight;

  Offset _offset = .zero;
  bool _active = false;
  Ticker? _ticker;
  Simulation? _simX;
  Simulation? _simY;

  Offset get offset => _offset;
  bool get isActive => _active;

  void begin() {
    _simX = null;
    _simY = null;
    _ticker?.stop();
    _active = true;
  }

  void moveBy(Offset delta) {
    if (!_active) {
      return;
    }
    _offset += delta;
    notifyListeners();
  }

  /// Springs the offset home with the carried velocity on per-axis
  /// simulations of the flight's closeMotion.
  void release(Offset velocityPerSecond) {
    _active = false;
    if (_offset == .zero && velocityPerSecond == .zero) {
      return;
    }
    final Motion motion = _flight.controller.effectiveMotion.closeMotion;
    _simX = motion.createSimulation(
      start: _offset.dx,
      end: 0,
      velocity: velocityPerSecond.dx,
    );
    _simY = motion.createSimulation(
      start: _offset.dy,
      end: 0,
      velocity: velocityPerSecond.dy,
    );
    // The ticker restarts, so its clock restarts too - the simulations
    // above are created at the same moment and stay consistent.
    _ticker ??= _flight.scope.createTicker(_tick);
    _ticker!
      ..stop()
      ..start();
  }

  void _tick(Duration elapsed) {
    final Simulation? simX = _simX;
    final Simulation? simY = _simY;
    if (simX == null || simY == null) {
      _ticker?.stop();
      return;
    }
    final double t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _offset = Offset(simX.x(t), simY.x(t));
    if (simX.isDone(t) && simY.isDone(t)) {
      _offset = .zero;
      _simX = null;
      _simY = null;
      _ticker!.stop();
    }
    notifyListeners();
  }

  /// Emergency teardown at finalize/abort: the channel survives for a
  /// possible reuse only through [MorphFlight.launch] retargets, never
  /// across a finished flight.
  void reset() {
    _active = false;
    _simX = null;
    _simY = null;
    _ticker?.dispose();
    _ticker = null;
    _offset = .zero;
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

/// Resolves the target's surface model against the ambient color
/// scheme: a null target color adopts surfaceContainerHigh, so every
/// renderer of the target - the shuttle, the route page, the flying
/// shared layers - agrees on one value.
@internal
MorphSurfaceSpec resolveMorphTargetSurface(
  MorphFlight flight,
  ColorScheme scheme,
) {
  return flight.target.surface.color == null
      ? flight.target.surface.copyWith(color: scheme.surfaceContainerHigh)
      : flight.target.surface;
}

/// The target-content subtree with its wrapper chain (flight scope,
/// surface spec, shared-element side, builder) - and, in route mode,
/// the shared [MorphFlight.routeContentKey] identity. The shuttle and
/// the route page both mount exactly this: the route-mode reparent
/// preserves live state only while the chains match, so the chain
/// lives in one place and cannot drift.
@internal
Widget buildMorphTargetContent({
  required MorphFlight flight,
  required MorphSurfaceSpec spec,
  required GlobalKey anchorKey,
}) {
  // The target's surface model is published the same way the tag
  // publishes its own, so custom dialog content renders its accents
  // from MorphTag.specOf instead of repeating the model.
  final Widget content = MorphFlightScope(
    flight: flight,
    child: MorphSurfaceSpecScope(
      spec: spec,
      child: SharedSideScope(
        flight: flight,
        isTarget: true,
        anchorKey: anchorKey,
        child: Builder(
          builder: (BuildContext context) => flight.builder(context, flight),
        ),
      ),
    ),
  );
  final GlobalKey? routeKey = flight.routeContentKey;
  if (routeKey == null) {
    return content;
  }
  return KeyedSubtree(key: routeKey, child: content);
}

/// Gives overlay content access to its flight (e.g. MorphReveal finds
/// it here) without threading the flight through builder parameters.
class MorphFlightScope extends InheritedWidget {
  /// Publishes [flight] to the content subtree.
  const MorphFlightScope({
    super.key,
    required this.flight,
    required super.child,
  });

  /// The flight this content belongs to.
  final MorphFlight flight;

  /// The enclosing flight; asserts outside flight content.
  static MorphFlight of(BuildContext context) {
    final MorphFlightScope? scope = context
        .getInheritedWidgetOfExactType<MorphFlightScope>();
    assert(
      scope != null,
      'No MorphFlightScope found: MorphReveal and other flight consumers '
      'only work inside the content of a morph overlay.',
    );
    return scope!.flight;
  }

  @override
  bool updateShouldNotify(MorphFlightScope oldWidget) =>
      flight != oldWidget.flight;
}

class _MorphShuttle extends StatefulWidget {
  const _MorphShuttle({required this.flight});

  final MorphFlight flight;

  @override
  State<_MorphShuttle> createState() => _MorphShuttleState();
}

class _MorphShuttleState extends State<_MorphShuttle> {
  MorphFlight get flight => widget.flight;

  FocusNode? _previousFocus;
  final GlobalKey _sourceAnchorKey = GlobalKey();
  final GlobalKey _targetAnchorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _previousFocus = FocusManager.instance.primaryFocus;
  }

  @override
  void dispose() {
    // Return focus to where the shuttle's autofocus took it from: after
    // Esc/close, keyboard navigation continues from the same place
    // instead of dying into the void.
    final FocusNode? previous = _previousFocus;
    if (previous != null) {
      scheduleMicrotask(() {
        // The FocusNode may have been disposed between capture and this
        // microtask - getters on a disposed node trip asserts in debug.
        try {
          if (previous.context != null && previous.canRequestFocus) {
            previous.requestFocus();
          }
        } on Object {
          // Deliberate swallow: focus restore is best-effort.
        }
      });
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    flight.controller.disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == .escape &&
        flight.barrierDismissible) {
      flight.requestDismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final MorphSurfaceSpec targetSpec = resolveMorphTargetSurface(
      flight,
      scheme,
    );
    // Content is built ONCE and reused between ticks: the spring only
    // moves the wrappers (Opacity, Transform, rect), not the user's
    // build at 120 Hz.
    final Widget content = buildMorphTargetContent(
      flight: flight,
      spec: targetSpec,
      anchorKey: _targetAnchorKey,
    );
    // A FocusScope traps Tab traversal inside the overlay while it is
    // up; Esc handling rides the same node.
    return FocusScope(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: FocusTraversalGroup(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size overlaySize = constraints.biggest;
            final EdgeInsets padding = MediaQuery.paddingOf(context);
            return ListenableBuilder(
              listenable: .merge(<Listenable>[
                flight.frameTicks,
                flight.routeOwnsContent,
              ]),
              child: content,
              builder: (BuildContext context, Widget? content) {
                if (flight.routeOwnsContent.value) {
                  // The route page owns the content (and draws the
                  // settled scrim and surface itself): the shuttle
                  // steps aside entirely, unmounting the keyed subtree
                  // so the route can adopt it this same frame.
                  return const SizedBox.shrink();
                }
                flight.refreshSourceRect();
                final Rect targetRect = flight.target.rectFor(
                  overlaySize,
                  padding,
                );
                flight.lastTargetRect = targetRect;
                final Color targetColor =
                    flight.target.surfaceColor ?? scheme.surfaceContainerHigh;
                final MorphFrame frame = computeMorphFrame(
                  value: flight.controller.value,
                  sourceRect: flight.sourceRect,
                  targetRect: targetRect,
                  sourceShape: flight.tag.shape,
                  targetShape: flight.target.shape,
                  sourceColor: flight.tag.surfaceColor ?? targetColor,
                  targetColor: targetColor,
                  maxScrimOpacity: flight.maxScrimOpacity,
                  sourceElevation: flight.tag.elevation,
                  targetElevation: flight.target.elevation,
                );
                // Content comes alive on approach without waiting for the
                // spring to fully settle: waiting for settle would serve
                // dead clicks on a visually ready overlay.
                final bool interactive =
                    flight.controller.target >= 1 &&
                    flight.controller.value >= 0.85;
                // The displacement channel moves the whole container as
                // one rigid body; the scrim dims and the card recedes
                // slightly with distance, and past the commit threshold
                // the arm cue deepens both - all pure functions of the
                // displacement.
                final Offset drag = flight.appliedDragOffset;
                final double recede = morphDragRecede(drag.distance);
                final double arm = morphDragArm(flight.dragOffset.distance);
                return Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: _ShuttleScrim(
                        flight: flight,
                        opacity:
                            frame.scrimOpacity *
                            (1 - 0.5 * recede) *
                            (1 - 0.35 * arm),
                      ),
                    ),
                    Positioned.fromRect(
                      rect: frame.rect.shift(drag),
                      child: IgnorePointer(
                        ignoring: !interactive,
                        child: Transform.scale(
                          scale: 1 - 0.08 * recede - 0.05 * arm,
                          child: Semantics(
                            // The overlay is a semantic route: focus and
                            // reading scope in, and a label announces the
                            // opening.
                            scopesRoute: true,
                            namesRoute: flight.semanticLabel != null,
                            label: flight.semanticLabel,
                            explicitChildNodes: true,
                            child: Material(
                              color: frame.surfaceColor,
                              shape: frame.shape,
                              // Material animates shape/color/elevation
                              // changes on its own 200 ms clock
                              // (kThemeChangeDuration); with per-tick
                              // shape updates that tween lags the frame.
                              // The spring is the only clock here.
                              animationDuration: .zero,
                              clipBehavior: .antiAlias,
                              elevation: frame.elevation,
                              shadowColor: Colors.black.withValues(alpha: 0.6),
                              child: Stack(
                                fit: .expand,
                                children: <Widget>[
                                  // No conditional mounting: the target
                                  // content lives in the shuttle for the whole
                                  // flight, otherwise a close -> open
                                  // interruption would lose its state.
                                  Align(
                                    alignment: flight.target.contentAlignment,
                                    child: OverflowBox(
                                      minWidth: targetRect.width,
                                      maxWidth: targetRect.width,
                                      minHeight: targetRect.height,
                                      maxHeight: targetRect.height,
                                      alignment: flight.target.contentAlignment,
                                      child: KeyedSubtree(
                                        key: _targetAnchorKey,
                                        child: Opacity(
                                          opacity: frame.targetOpacity,
                                          child: Transform.scale(
                                            scale: frame.targetScale,
                                            child: content,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  _SourceGhost(
                                    flight: flight,
                                    opacity: frame.sourceOpacity,
                                    scale: flight.sourceRect.width <= 0
                                        ? 1
                                        : frame.rect.width /
                                              flight.sourceRect.width,
                                    anchorKey: _sourceAnchorKey,
                                  ),
                                  ...buildSharedFlightLayers(
                                    flight: flight,
                                    frame: frame,
                                    sourceAnchorKey: _sourceAnchorKey,
                                    targetAnchorKey: _targetAnchorKey,
                                    sourceRect: flight.sourceRect,
                                    targetRect: targetRect,
                                    targetSpec: targetSpec,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
