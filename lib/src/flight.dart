import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';
import 'package:meta/meta.dart';

import 'package:morph/src/controller.dart';
import 'package:morph/src/frame.dart';
import 'package:morph/src/gesture.dart';
import 'package:morph/src/measure.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/scrim.dart';
import 'package:morph/src/shared.dart';
import 'package:morph/src/motion.dart';
import 'package:morph/src/presentation.dart';
import 'package:morph/src/target.dart';
import 'package:morph/src/theme.dart';
import 'package:morph/src/themes.dart';

/// Builds the target content of a flight; called once per flight and
/// reused between spring ticks.
typedef MorphContentBuilder =
    Widget Function(BuildContext context, MorphFlight flight);

/// The discrete moments of a flight, delivered on [MorphFlight.events]:
/// the seam for haptics and app-side choreography that must mark a
/// moment instead of guessing it from the spring value.
enum MorphFlightEvent {
  /// The flight took off toward open: a fresh launch, or a close
  /// interrupted by a re-open.
  launched,

  /// The open spring came to rest: the surface stands fully open.
  settled,

  /// A close began - a dismissal, [MorphFlight.close], a route pop.
  closing,

  /// The handoff latch fired: the shuttle handed the surface back to
  /// the source widget. The catch moment of a landing.
  latched,

  /// The flight finalized after landing: the close spring has come to
  /// rest and the overlay is gone.
  landed,

  /// The flight was torn down without animation ([MorphFlight.abort]).
  aborted,
}

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
    required this.modal,
    required this.barrierDismissible,
    required this.maxScrimOpacity,
    required this.scrimColor,
    required this.scrimMotion,
    required this.shadowColor,
    required this._overlay,
    required MorphMotion motion,
    required bool disableAnimations,
  }) {
    controller = MorphController(
      vsync: scope,
      motion: motion,
      onHandoff: _onHandoff,
    );
    controller.disableAnimations = disableAnimations;
    controller.addListener(_onTick);
    final MorphScrimMotion? scrim = scrimMotion;
    if (scrim != null) {
      final MorphScrimChannel channel = MorphScrimChannel(
        scrim: scrim,
        vsync: scope,
        reducedMotion: () => controller.disableAnimations,
      );
      channel.addListener(_onScrimTick);
      controller.addListener(_followTargetWithScrim);
      _scrim = channel;
    }
    sourceThemes = MorphThemeCarrier(tag.context, to: _overlay.context);
    morphDependOnThemes(tag.context, to: _overlay.context);
  }

  /// The scope this flight is registered in.
  final MorphScopeState scope;

  /// The source tag the flight departs from and lands into.
  final MorphTagState tag;

  /// The destination description; its rect is re-read every frame.
  final MorphTargetSpec target;

  /// Builds the target content.
  final MorphContentBuilder builder;

  /// Whether the flight is a MODAL overlay. A modal flight (the
  /// default) mounts the scrim: a pointer-blocking, semantics-blocking
  /// dimming layer - dialogs, sheets, menus.
  ///
  /// A non-modal flight ([modal] false) mounts NO scrim at all: the
  /// page underneath stays fully interactive while the surface hovers
  /// over it - a tool flying over live content (an expanding search
  /// field filtering the list below). No dimming, no tap-outside
  /// dismissal ([barrierDismissible] has nothing to attach to); Esc
  /// and the local history entry still close the flight.
  final bool modal;

  /// Whether scrim taps and Esc dismiss the flight.
  final bool barrierDismissible;

  /// Scrim opacity in the fully open state.
  final double maxScrimOpacity;

  /// Scrim hue; its own opacity composes with the animated scrim
  /// opacity.
  final Color scrimColor;

  /// The scrim's own springs, or null for a scrim that follows the
  /// flight value. See [MorphScrimMotion].
  final MorphScrimMotion? scrimMotion;

  MorphScrimChannel? _scrim;

  /// The scrim opacity this frame, before a drag's thinning: the scrim
  /// channel's value times [maxScrimOpacity] when the flight has a
  /// [scrimMotion], otherwise the value's own fade
  /// (`morphScrimOpacity`).
  double get scrimOpacity =>
      _scrim?.opacity(maxScrimOpacity) ??
      morphScrimOpacity(maxScrimOpacity, controller.progress);

  /// The scrim channel's value (0 clear, 1 full), or null without a
  /// [scrimMotion].
  double? get scrimValue => _scrim?.value;

  /// Whether the shuttle stands past the handoff latch only to finish
  /// a scrim that rides its own springs.
  bool get _scrimOnly =>
      controller.hasHandedOff && _scrim != null && !_scrim!.isAtRest;

  void _followTargetWithScrim() {
    if (!_finished) {
      _scrim?.retarget(controller.target);
    }
  }

  void _onScrimTick() {
    if (_finished) {
      return;
    }
    if (controller.hasHandedOff && _scrim!.isAtRest && _entry != null) {
      _removeEntry();
    }
    _onTick();
  }

  /// Shadow color of the flying surface, opacity included.
  final Color shadowColor;
  final OverlayState _overlay;

  /// The inherited themes of the source tag ([InheritedTheme], such as
  /// the theme, the default text style or the glass painter): the
  /// shuttle and the settled route page draw everything under them, the
  /// way a popup route draws under the themes of the context that showed
  /// it. They follow the source while it is in the tree, one frame late,
  /// and stay as last seen once it is gone.
  @internal
  late final MorphThemeCarrier sourceThemes;

  bool _themesRefreshPending = false;

  /// Re-reads the source's themes after the current frame; called by the
  /// tag when one of its dependencies changed.
  @internal
  void sourceDependenciesChanged() {
    if (_finished || !tag.isTreeActive || !_overlay.mounted) return;
    morphDependOnThemes(tag.context, to: _overlay.context);
    if (_themesRefreshPending) return;
    _themesRefreshPending = true;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      _themesRefreshPending = false;
      if (_finished || _controllerDisposed || !tag.isTreeActive) return;
      sourceThemes.refresh(tag.context);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// The declarative close route: when set, a scrim tap or Esc does not
  /// close the flight itself but asks the state owner - who flips state,
  /// and close() arrives from above. State down, events up.
  VoidCallback? onDismissRequested;

  /// Accessibility name of the opened overlay: it scopes and names the
  /// semantic route, so screen readers announce the opening. null keeps
  /// the overlay unnamed (still scoped).
  String? semanticLabel;

  /// The value spring, for observation, motion changes and custom scrubbing.
  ///
  /// Use [open], [close], [toggle] and [abort] for lifecycle changes;
  /// driving the controller's lifecycle directly bypasses flight history,
  /// source visibility and finalization.
  late final MorphController controller;
  OverlayEntry? _entry;

  /// The source rect in overlay coordinates; engine-written every
  /// frame, read-only for apps.
  Rect get sourceRect => _sourceRect;
  Rect _sourceRect = .zero;

  /// The current target rect, refreshed by the shuttle or settled route.
  /// Read-only for apps.
  Rect get lastTargetRect => _lastTargetRect;
  Rect _lastTargetRect = .zero;

  /// Records the target geometry resolved by the shuttle or settled route.
  @internal
  void updateTargetRect(Rect rect) {
    _lastTargetRect = rect;
  }

  bool _finished = false;
  bool _controllerDisposed = false;
  Object? _result;
  final Completer<Object?> _closedCompleter = Completer<Object?>();

  final StreamController<MorphFlightEvent> _events =
      StreamController<MorphFlightEvent>.broadcast();
  final List<MorphFlightEvent> _pendingEvents = <MorphFlightEvent>[];
  bool _eventFlushScheduled = false;
  bool _eventsDone = false;
  bool _settledAnnounced = false;

  bool _sourceLost = false;
  double? _dissolveStart;

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

  /// The flight's discrete moments, in order: launched, settled,
  /// closing, latched, landed - or aborted. The seam for haptics and
  /// app-side choreography. Delivery is asynchronous, a microtask after
  /// the moment, so a listener attached in the same synchronous run as
  /// showMorph (before any await) hears the launch too; the order is
  /// always preserved. The stream closes after the final moment.
  Stream<MorphFlightEvent> get events => _events.stream;

  /// Whether the source tag has left the tree while this flight was up.
  /// The flight survives it: the source rect freezes where it last
  /// stood, open content stays usable, and the close plays as a
  /// dissolve ([dissolveOpacity]) instead of a landing on a phantom.
  bool get isSourceLost => _sourceLost;

  /// The container's opacity this frame. 1 while the source lives, and
  /// while opening even without it - open content stays usable. Once
  /// the source is gone, a close fades the container out over the
  /// first half of its remaining travel: a pure function of the spring
  /// value from the moment the dissolve begins (continuous at 1), so
  /// the surface evaporates on its way home instead of landing on a
  /// row that no longer exists.
  double get dissolveOpacity {
    final double? start = _dissolveStart;
    if (start == null || controller.target != 0) {
      return 1;
    }
    final double t = controller.progress / start;
    return clampDouble((t - 0.5) * 2, 0, 1);
  }

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
  /// and the close spring is playing out its residual undershoot before
  /// the flight finalizes.
  bool get isLanding => !_finished && controller.hasHandedOff;

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
          WidgetsBinding.instance.addPostFrameCallback((Duration _) {
            if (isOpenOrOpening) {
              _restoreHistoryEntry();
            }
          });
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

  /// The measured content size of a measured target and its spring
  /// (see [_ContentSizeChannel]).
  late final _ContentSizeChannel _contentSize = _ContentSizeChannel(this);

  /// Geometry changes from the value spring, displacement, content size
  /// and the target's repaint signal; excludes independent scrim ticks.
  ///
  /// Skins use this stream to follow the flying surface without repainting
  /// when only its scrim changes.
  late final Listenable geometryTicks = .merge(<Listenable>[
    controller,
    _drag,
    _contentSize,
    ?target.repaint,
  ]);

  /// All visual changes, including [geometryTicks] and independent scrim
  /// ticks. The shuttle and settled route page use this stream.
  late final Listenable frameTicks = .merge(<Listenable>[
    geometryTicks,
    ?_scrim,
  ]);

  /// The content size the target is placed for this frame, for a
  /// target measured by its content ([MorphTargetSpec.measured]): the
  /// measured size, spring-smoothed on the flight's open motion when
  /// it changes while the flight is up. Null for a fixed target, and
  /// until the first measurement lands - the shuttle stays invisible
  /// and the source visible for that frame.
  Size? get contentSize => _contentSize.value;

  /// The latest measured content size of a measured target, before
  /// smoothing; null for a fixed target or before the first
  /// measurement.
  Size? get measuredContentSize => _contentSize.measured;

  /// Feeds a measurement from a renderer of the target content.
  @internal
  void reportContentSize(Size size) {
    if (_finished) {
      return;
    }
    _contentSize.report(size);
  }

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

  /// Rejects adoption of an overlay flight by a Navigator route.
  @internal
  static void checkRouteLaunch(MorphFlight? existing) {
    if (existing != null && existing.routeContentKey == null) {
      throw FlutterError(
        'showMorphRoute(from: ${existing.tag.id}): an overlay flight is '
        'already live for this tag. A route cannot adopt an overlay flight '
        'mid-air - the content ownership chains differ. Close the overlay '
        'first, or retarget it with showMorph.',
      );
    }
  }

  /// Launches (or retargets) the flight for [from]. Prefer the
  /// showMorph* entry points: they also resolve [MorphTheme] defaults,
  /// this method does not.
  @internal
  static MorphFlight launch(
    BuildContext context, {
    required Object from,
    required MorphTargetSpec target,
    required MorphContentBuilder builder,
    MorphMotion? motion,
    bool modal = true,
    bool barrierDismissible = true,
    double maxScrimOpacity = MorphTheme.defaultMaxScrimOpacity,
    Color scrimColor = MorphTheme.defaultScrimColor,
    MorphScrimMotion? scrimMotion,
    Color shadowColor = MorphTheme.defaultShadowColor,
    VoidCallback? onDismissRequested,
    String? semanticLabel,
    bool routeMode = false,
    // The shuttle's home. Defaults to morphPresentationOverlayOf; a
    // route passes its navigator's own overlay explicitly (the
    // navigator's context sits ABOVE that overlay), and an app passes
    // one to fly above chrome layered over a nested navigator.
    OverlayState? overlay,
  }) {
    final MorphScopeState scope = MorphScope.of(context);
    // liveFlightOf, not flightOf: retargeting a stray flight whose tag
    // was disposed would drive show/hide on a defunct State.
    final MorphFlight? existing = scope.liveFlightOf(from);
    if (existing != null) {
      if (routeMode) {
        checkRouteLaunch(existing);
      }
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
      existing.open();
      existing._addHistoryEntry(context);
      return existing;
    }
    final MorphFlight flight = MorphFlight._(
      scope: scope,
      tag: scope.tagOf(from),
      target: target,
      builder: builder,
      modal: modal,
      barrierDismissible: barrierDismissible,
      maxScrimOpacity: maxScrimOpacity,
      scrimColor: scrimColor,
      scrimMotion: scrimMotion,
      shadowColor: shadowColor,
      // The nearest overlay outside any presentation boundary: a
      // nested navigator (a tab, an embedded device mockup) keeps its
      // flights inside itself, a navigation stack's pages fly above
      // the stack's bars.
      overlay:
          overlay ?? morphPresentationOverlayOf(context) ?? Overlay.of(context),
      motion: motion ?? .liquid,
      disableAnimations: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
    );
    flight.onDismissRequested = onDismissRequested;
    flight.semanticLabel = semanticLabel;
    if (routeMode) {
      flight.enableRouteMode();
    }
    scope.adoptFlight(flight);
    flight.open();
    flight._addHistoryEntry(context);
    return flight;
  }

  /// Retargets the spring toward open, inserting the shuttle if needed.
  void open({double? velocity}) {
    if (_finished) {
      return;
    }
    final bool fresh = _entry == null;
    // A shuttle kept past the latch for its scrim alone: the tag is
    // visible again and must hide once more, like a fresh launch.
    final bool relaunch = !fresh && controller.hasHandedOff;
    if (fresh) {
      _insertEntry();
    }
    _restoreHistoryEntry();
    // A re-open cancels a pending dissolve: the surface is wanted
    // again, whatever became of its source.
    _dissolveStart = null;
    // The launch is announced BEFORE the controller moves: an instant
    // profile settles synchronously inside open(), and settled must
    // never precede launched on the stream.
    if (fresh || controller.target < 1) {
      _settledAnnounced = false;
      _emit(MorphFlightEvent.launched);
    }
    controller.open(velocity: velocity);
    if (fresh || relaunch) {
      _hideTagWhenStaged();
    }
  }

  /// Retargets the spring toward closed with its current velocity.
  /// An explicit [velocity] overrides that velocity; a close from rest
  /// starts still.
  ///
  /// [result] is what [closed] completes with at finalization - "what
  /// did the user pick". An accepted close replaces the result;
  /// repeated calls while already closing leave it unchanged.
  void close({double? velocity, Object? result}) {
    if (_finished || (controller.target == 0 && !controller.isScrubbing)) {
      return;
    }
    _result = result;
    _removeHistoryEntry();
    refreshSourceRect();
    controller.close(velocity: velocity);
    if (_sourceLost) {
      _beginDissolve();
    }
    _emit(MorphFlightEvent.closing);
  }

  /// Live source tracking: the tag's rect is re-read on every flight
  /// frame (window resized, layout shifted - we fly to the current
  /// point, with at most one frame of lag). A source that has left the
  /// tree freezes the rect where it last stood ([isSourceLost]).
  @internal
  void refreshSourceRect() {
    if (!tag.mounted) {
      _loseSource();
      return;
    }
    final RenderBox? overlayBox = _overlayBox;
    if (overlayBox == null) {
      return;
    }
    final Rect? fresh = tag.tryCaptureRect(overlayBox);
    if (fresh != null) {
      _sourceRect = fresh;
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
    if (!_overlay.mounted) {
      abort();
      throw _overlayError;
    }
    final RenderObject? box = _overlay.context.findRenderObject();
    return box is RenderBox ? box : null;
  }

  FlutterError get _overlayError => FlutterError(
    'MorphFlight(from: ${tag.id}): its Overlay has been unmounted. '
    'Keep the chosen overlay mounted for the flight lifetime, or close '
    'the flight before removing the overlay. The flight has been aborted '
    'and its source revealed.',
  );

  void _abortForLostOverlay() {
    if (_finished) {
      return;
    }
    abort();
    FlutterError.reportError(
      FlutterErrorDetails(exception: _overlayError, library: 'morph'),
    );
  }

  /// The box of the overlay the shuttle renders in - the coordinate
  /// space [sourceRect] and [lastTargetRect] live in. Consumers in a
  /// DIFFERENT space (the skin's mirror blob) translate through it; a
  /// nested overlay does not sit at the window origin.
  @internal
  RenderBox? get overlayBox => _overlayBox;

  void _insertEntry() {
    refreshSourceRect();
    _entry = OverlayEntry(
      builder: (BuildContext context) => _MorphShuttle(flight: this),
    );
    _overlay.insert(_entry!);
    if (tag.widget.snapshotGhost) {
      // A flight usually launches from the button's own tap, mid-ripple:
      // the boundary is dirty at that moment and toImage asserts on it -
      // and once the tag hides (opacity 0) its subtree never paints
      // again, so a dirty boundary would stay dirty forever. The capture
      // therefore waits for this frame's paint, and the tag hides only
      // AFTER the shot. The shuttle already covers the source exactly
      // (drawing the live replica meanwhile), so the extra visible
      // frames are occluded.
      _awaitingSnapshot = true;
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        _captureSourceSnapshot().whenComplete(() {
          _awaitingSnapshot = false;
          _hideTagWhenStaged();
        });
      });
    }
  }

  bool _awaitingSnapshot = false;

  /// Hides the source once the shuttle can stand in for it: after the
  /// snapshot shot when one is pending, and, for a measured target,
  /// after the first measurement - until then the shuttle is invisible
  /// (nothing to size it by), and a hidden source under an invisible
  /// shuttle would be a blank frame. Called from every path that can
  /// satisfy a condition; a no-op until all are met.
  void _hideTagWhenStaged() {
    if (_finished ||
        _entry == null ||
        !tag.mounted ||
        controller.hasHandedOff ||
        _awaitingSnapshot ||
        (target.isMeasured && !_contentSize.isSeeded)) {
      return;
    }
    tag.hideForFlight();
  }

  /// Whether the shuttle is laid out but not yet shown: a measured
  /// target before its first measurement.
  bool get _staged => target.isMeasured && !_contentSize.isSeeded;

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
      entry.remove();
      entry.dispose();
    }
  }

  void _onHandoff() {
    if (tag.mounted) {
      tag.reveal();
    }
    // A scrim on its own springs may still be dimming the page: the
    // shuttle stays, drawing only the scrim (its frame builder sees the
    // latch on this very tick), until it rests.
    final MorphScrimChannel? scrim = _scrim;
    if (scrim == null || scrim.isAtRest) {
      _removeEntry();
    }
    _emit(MorphFlightEvent.latched);
  }

  void _onTick() {
    if (_finished) {
      return;
    }
    if (!_overlay.mounted) {
      _abortForLostOverlay();
      return;
    }
    // A scrub parks the ticker with the target still at 0: that is an
    // interruption of the close, not its end.
    if (controller.target == 0 &&
        !controller.isAnimating &&
        !controller.isScrubbing &&
        (_scrim?.isAtRest ?? true)) {
      _finalize();
      return;
    }
    if (controller.target >= 1 &&
        !controller.isAnimating &&
        !controller.isScrubbing &&
        !_settledAnnounced) {
      _settledAnnounced = true;
      _emit(MorphFlightEvent.settled);
    }
  }

  // The event queue: moments are recorded synchronously, in order, and
  // handed to the stream in a microtask - so the launch announced
  // inside showMorph reaches the listener the caller attaches right
  // after the call returns (a broadcast stream drops what nobody hears
  // yet), and a listener that closes the flight from inside its
  // handler never re-enters a firing controller.
  void _emit(MorphFlightEvent event) {
    if (_eventsDone) {
      return;
    }
    _pendingEvents.add(event);
    if (!_eventFlushScheduled) {
      _eventFlushScheduled = true;
      scheduleMicrotask(_flushEvents);
    }
  }

  void _flushEvents() {
    _eventFlushScheduled = false;
    final List<MorphFlightEvent> batch = List<MorphFlightEvent>.of(
      _pendingEvents,
    );
    _pendingEvents.clear();
    for (final MorphFlightEvent event in batch) {
      _events.add(event);
    }
    if (_eventsDone) {
      _events.close();
    }
  }

  /// Seals the stream after the final moment: whatever is queued still
  /// goes out, then the stream closes.
  void _finishEvents() {
    _eventsDone = true;
    if (!_eventFlushScheduled) {
      _events.close();
    }
  }

  /// The source tag has left the tree. Sticky: a tag that unmounts does
  /// not come back (a new tag under the same id is a different tag,
  /// and this flight keeps flying for the one that launched it).
  void _loseSource() {
    if (_sourceLost) {
      return;
    }
    _sourceLost = true;
    if (controller.target == 0 && _dissolveStart == null) {
      _beginDissolve();
    }
  }

  void _beginDissolve() {
    final double progress = controller.progress;
    _dissolveStart = progress < 0.001 ? 0.001 : progress;
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
    _contentSize.reset();
    _scrim?.reset();
    scope.retireFlight(this);
    _emit(MorphFlightEvent.landed);
    _finishEvents();
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
      _contentSize.reset();
      _scrim?.reset();
      controller.stop();
      scope.retireFlight(this);
      _emit(MorphFlightEvent.aborted);
      _finishEvents();
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
      _contentSize.dispose();
      _scrim?.dispose();
      routeOwnsContent.dispose();
      sourceThemes.dispose();
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
    // BlockSemantics, like ModalBarrier's: the scrim blocks POINTERS
    // to the page underneath, and assistive tech must not keep a
    // side door - without the block a screen reader swipes past the
    // open overlay into the page and activates it.
    return BlockSemantics(
      child: Semantics(
        label: flight.barrierDismissible
            ? Localizations.of<MaterialLocalizations>(
                context,
                MaterialLocalizations,
              )?.modalBarrierDismissLabel
            : null,
        container: flight.barrierDismissible,
        onDismiss: flight.barrierDismissible ? flight.requestDismiss : null,
        child: GestureDetector(
          behavior: .opaque,
          onTap: flight.barrierDismissible ? flight.requestDismiss : null,
          child: ColoredBox(
            color: flight.scrimColor.withValues(
              alpha: flight.scrimColor.a * opacity,
            ),
          ),
        ),
      ),
    );
  }
}

/// The source ghost inside the shuttle: the button as it looked at
/// takeoff (a pixel snapshot when opted in, the live replica
/// otherwise). Stays MOUNTED for the whole flight, not only while
/// visible - shared-element markers inside it must keep reporting
/// endpoint rects.
/// [shape] with any border side taken off - the outline belongs to the
/// flying container, not to a copy riding inside it.
ShapeBorder _unstroked(ShapeBorder shape) {
  if (shape is OutlinedBorder && shape.side != BorderSide.none) {
    return shape.copyWith(side: BorderSide.none);
  }
  return shape;
}

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
            // The ghost is a pixels-only copy: pointer is ignored and
            // focus is excluded SYMMETRICALLY. The live replica shares
            // the source widget config, and it stays mounted inside
            // the overlay's own Tab trap for the whole flight -
            // without the exclusion Tab reaches the invisible copy and
            // Enter fires its onTap (and an explicit source FocusNode,
            // attached to the replica for the duration, would let
            // requestFocus pull focus into the shuttle).
            child: IgnorePointer(
              child: ExcludeFocus(
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
                          // One mass - one outline, one shadow: the
                          // container draws both, so the spec the replica
                          // renders from carries neither. A spec-driven
                          // button would otherwise cast a second shadow
                          // and trace a second contour inside the
                          // shuttle, at its own scale.
                          spec: flight.tag.surfaceSpec.copyWith(
                            elevation: 0,
                            shape: _unstroked(flight.tag.surfaceSpec.shape),
                          ),
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
    _ticker!.stop();
    _ticker!.start();
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

/// The content-size channel of a measured target: the endpoint filter
/// on the target rect's one live input that is not a per-frame read.
/// The first measurement seeds it without motion (a launch flies to
/// the content's real size from its first visible frame); every later
/// change retargets per-axis simulations of the flight's open motion
/// from the current (value, velocity) - the surface answers a size
/// change the way it answered the opening (on the default profile,
/// with UIKit's slight overshoot), and instantly under reduced motion. The value is an INPUT to the frame, not a second clock on
/// any property: the container rect stays a pure function of the
/// flight value and this frame's endpoints.
///
/// A ChangeNotifier: its ticks join [MorphFlight.frameTicks].
class _ContentSizeChannel extends ChangeNotifier {
  _ContentSizeChannel(this._flight);

  final MorphFlight _flight;

  Size? _measured;
  Size? _value;
  double _velocityW = 0;
  double _velocityH = 0;
  Simulation? _simW;
  Simulation? _simH;
  Ticker? _ticker;

  /// The latest measurement, unsmoothed.
  Size? get measured => _measured;

  /// The smoothed size this frame; null until seeded.
  Size? get value => _value;

  /// Whether a first measurement has landed.
  bool get isSeeded => _value != null;

  void report(Size size) {
    if (size == _measured) {
      return;
    }
    _measured = size;
    if (_value == null) {
      _value = size;
      _flight._hideTagWhenStaged();
      notifyListeners();
      return;
    }
    final Motion motion = _flight.controller.effectiveMotion.openMotion;
    _simW = motion.createSimulation(
      start: _value!.width,
      end: size.width,
      velocity: _velocityW,
    );
    _simH = motion.createSimulation(
      start: _value!.height,
      end: size.height,
      velocity: _velocityH,
    );
    if (_simW!.isDone(0) && _simH!.isDone(0)) {
      _settle();
      notifyListeners();
      return;
    }
    // The ticker restarts, so its clock restarts too - the simulations
    // above are created at the same moment and stay consistent.
    _ticker ??= _flight.scope.createTicker(_tick);
    _ticker!.stop();
    _ticker!.start();
  }

  void _tick(Duration elapsed) {
    final Simulation? simW = _simW;
    final Simulation? simH = _simH;
    if (simW == null || simH == null) {
      _ticker?.stop();
      return;
    }
    final double t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    _value = Size(simW.x(t), simH.x(t));
    _velocityW = simW.dx(t);
    _velocityH = simH.dx(t);
    if (simW.isDone(t) && simH.isDone(t)) {
      _settle();
      _ticker!.stop();
    }
    notifyListeners();
  }

  void _settle() {
    _value = _measured;
    _velocityW = 0;
    _velocityH = 0;
    _simW = null;
    _simH = null;
  }

  /// Teardown at finalize/abort.
  void reset() {
    _simW = null;
    _simH = null;
    _ticker?.dispose();
    _ticker = null;
    _measured = null;
    _value = null;
    _velocityW = 0;
    _velocityH = 0;
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

/// Gives overlay content access to its flight (to close it, or to read
/// its spring) without threading the flight through builder parameters.
class MorphFlightScope extends InheritedWidget {
  /// Publishes [flight] to the content subtree.
  const MorphFlightScope({
    super.key,
    required this.flight,
    required super.child,
  });

  /// The flight this content belongs to.
  final MorphFlight flight;

  /// The enclosing flight; throws a [FlutterError] outside flight content.
  static MorphFlight of(BuildContext context) {
    final MorphFlightScope? scope = context
        .getInheritedWidgetOfExactType<MorphFlightScope>();
    if (scope == null) {
      throw FlutterError(
        'No MorphFlightScope found: flight consumers only work inside the '
        'content of a morph overlay.',
      );
    }
    return scope.flight;
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
  final FocusScopeNode _focusScope = FocusScopeNode(
    debugLabel: 'morph overlay',
  );
  final GlobalKey _sourceAnchorKey = GlobalKey();
  final GlobalKey _targetAnchorKey = GlobalKey();
  late final Listenable _frameTicks = Listenable.merge(<Listenable>[
    flight.frameTicks,
    flight.routeOwnsContent,
  ]);

  @override
  void initState() {
    super.initState();
    _previousFocus = FocusManager.instance.primaryFocus;
    // The overlay must TAKE focus, not merely offer autofocus:
    // autofocus yields when something already holds primary focus -
    // and the launcher button usually does, in exactly the keyboard
    // flow (focus, Enter) that needs the trap. Esc and Tab would keep
    // acting on the page under the open modal. setFirstFocus installs
    // the scope as the child scope that owns focus; requestFocus then
    // pulls primary focus off the launcher into it (a focusable inside
    // - a field's autofocus - refines it further on its own).
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || _focusScope.hasFocus) {
        return;
      }
      FocusScope.of(context).setFirstFocus(_focusScope);
      _focusScope.requestFocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!flight._overlay.mounted) {
        flight._abortForLostOverlay();
      }
    });
    _focusScope.dispose();
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

  /// The scrim alone, past the handoff latch: the content is home, the
  /// page takes touches again, and the dimming finishes on its own
  /// springs.
  Widget _lingeringScrim() {
    if (!flight.modal) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox.expand(
          child: ColoredBox(
            color: flight.scrimColor.withValues(
              alpha: flight.scrimColor.a * flight.scrimOpacity,
            ),
          ),
        ),
      ),
    );
  }

  /// A vessel's frame: the scrim, then the content over the whole
  /// overlay at full opacity; both take pointers only while the flight
  /// is open or opening, so a closing vessel lets touches reach the page.
  /// The same wrapper chain on every frame, so the content never
  /// remounts.
  Widget _buildVessel(Widget content) {
    return Stack(
      children: <Widget>[
        if (flight.modal)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: flight.controller.target < 1,
              child: _ShuttleScrim(
                flight: flight,
                opacity: flight.scrimOpacity,
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: flight.controller.target < 1,
            child: Opacity(
              opacity: flight.dissolveOpacity,
              child: Semantics(
                scopesRoute: true,
                namesRoute: flight.semanticLabel != null,
                label: flight.semanticLabel,
                explicitChildNodes: true,
                child: KeyedSubtree(key: _targetAnchorKey, child: content),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: flight.sourceThemes,
      builder: (BuildContext context, Widget? _) =>
          flight.sourceThemes.wrap(Builder(builder: _buildThemed)),
    );
  }

  Widget _buildThemed(BuildContext context) {
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
    // up; Esc handling rides the same node. The Actions map exists
    // because the shuttle lives OUTSIDE any ModalScope: without a
    // reachable DismissIntent action, an EditableText in the content
    // asserts the moment Esc bubbles out of it.
    return Actions(
      actions: <Type, Action<Intent>>{
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (DismissIntent intent) {
            if (flight.barrierDismissible) {
              flight.requestDismiss();
            }
            return null;
          },
        ),
      },
      child: FocusScope(
        node: _focusScope,
        onKeyEvent: _onKeyEvent,
        child: FocusTraversalGroup(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Size overlaySize = constraints.biggest;
              // The safe area unioned with the keyboard: the space the
              // target is placed in. The content below sees only the
              // part of the keyboard the surface still overlaps.
              final EdgeInsets padding = morphTargetPaddingOf(
                context,
                overlaySize,
                overlayBox: flight.overlayBox,
              );
              final EdgeInsets overlayViewInsets = morphOverlayViewInsetsOf(
                context,
                overlaySize,
                overlayBox: flight.overlayBox,
              );
              final MorphTargetSpec target = flight.target;
              return ListenableBuilder(
                listenable: _frameTicks,
                child: content,
                builder: (BuildContext context, Widget? content) {
                  if (flight.routeOwnsContent.value) {
                    // The route page owns the content (and draws the
                    // settled scrim and surface itself): the shuttle
                    // steps aside entirely, unmounting the keyed subtree
                    // so the route can adopt it this same frame.
                    return const SizedBox.shrink();
                  }
                  if (flight._scrimOnly) {
                    return _lingeringScrim();
                  }
                  flight.refreshSourceRect();
                  final Rect targetRect = target.resolveRect(
                    overlaySize,
                    padding,
                    flight.contentSize,
                  );
                  flight.updateTargetRect(targetRect);
                  if (target.isVessel) {
                    return _buildVessel(content!);
                  }
                  // A measured target lays its content out under the
                  // content constraints and measures it; a fixed one
                  // lays it out tight at the rect. Either way the box
                  // aligns inside the growing container.
                  final BoxConstraints contentConstraints =
                      target.constraintsFor?.call(overlaySize, padding) ??
                      BoxConstraints.tight(targetRect.size);
                  // A measured target before its first measurement is
                  // laid out but not shown, and the source stays
                  // visible: a launch never shows a guessed box.
                  final bool staged = flight._staged;
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
                  final Alignment contentAlignment = target.contentAlignment;
                  // The wrapper chain is the same on every frame (a
                  // staged frame differs only in values): a changed
                  // tree shape would remount the content.
                  return IgnorePointer(
                    ignoring: staged,
                    child: ExcludeSemantics(
                      excluding: staged,
                      child: Opacity(
                        opacity: staged ? 0 : 1,
                        child: Stack(
                          children: <Widget>[
                            // A non-modal flight mounts no scrim at all:
                            // the Stack's empty area does not hit-test,
                            // so the page underneath stays live while the
                            // surface hovers.
                            if (flight.modal)
                              Positioned.fill(
                                child: _ShuttleScrim(
                                  flight: flight,
                                  opacity:
                                      flight.scrimOpacity *
                                      morphDragScrimFactor(recede, arm),
                                ),
                              ),
                            Positioned.fromRect(
                              rect: frame.rect.shift(drag),
                              child: IgnorePointer(
                                ignoring: !interactive,
                                // The dissolve of a flight whose source
                                // is gone; 1 on every ordinary frame, and
                                // an Opacity at 1 paints straight through.
                                child: Opacity(
                                  opacity: flight.dissolveOpacity,
                                  child: Transform.scale(
                                    scale: morphDragScale(recede, arm),
                                    child: Semantics(
                                      // The overlay is a semantic route:
                                      // focus and reading scope in, and a
                                      // label announces the opening.
                                      scopesRoute: true,
                                      namesRoute: flight.semanticLabel != null,
                                      label: flight.semanticLabel,
                                      explicitChildNodes: true,
                                      child: Material(
                                        color: frame.surfaceColor,
                                        shape: frame.shape,
                                        // Material animates shape/color/
                                        // elevation changes on its own
                                        // 200 ms clock (kThemeChangeDuration);
                                        // with per-tick shape updates that
                                        // tween lags the frame. The spring is
                                        // the only clock here.
                                        animationDuration: .zero,
                                        clipBehavior: target.clipBehavior,
                                        elevation: frame.elevation,
                                        shadowColor: flight.shadowColor,
                                        child: Stack(
                                          fit: .expand,
                                          // The Material clips to its
                                          // shape; the Stack's rect clip
                                          // only matters when the target
                                          // asked for none - then content
                                          // may overflow the vessel.
                                          clipBehavior:
                                              target.clipBehavior == Clip.none
                                              ? Clip.none
                                              : Clip.hardEdge,
                                          children: <Widget>[
                                            // No conditional mounting: the
                                            // target content lives in the
                                            // shuttle for the whole flight,
                                            // otherwise a close -> open
                                            // interruption would lose its
                                            // state.
                                            Align(
                                              alignment: contentAlignment,
                                              child: MorphContentMeasure(
                                                childConstraints:
                                                    contentConstraints,
                                                alignment: contentAlignment,
                                                onSize: target.isMeasured
                                                    ? flight.reportContentSize
                                                    : null,
                                                child: Opacity(
                                                  opacity: frame.targetOpacity,
                                                  child: Transform.scale(
                                                    scale: frame.targetScale,
                                                    // The anchor sits below
                                                    // the reveal scale: shared
                                                    // elements measure their
                                                    // target rect in layout
                                                    // space, the endpoint
                                                    // they fly to.
                                                    child: KeyedSubtree(
                                                      key: _targetAnchorKey,
                                                      child:
                                                          _MorphContentMediaQuery(
                                                            overlayViewInsets:
                                                                overlayViewInsets,
                                                            targetRect:
                                                                targetRect,
                                                            overlaySize:
                                                                overlaySize,
                                                            child: content!,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            _SourceGhost(
                                              flight: flight,
                                              opacity: frame.sourceOpacity,
                                              scale:
                                                  flight.sourceRect.width <= 0
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
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MorphContentMediaQuery extends StatelessWidget {
  const _MorphContentMediaQuery({
    required this.overlayViewInsets,
    required this.targetRect,
    required this.overlaySize,
    required this.child,
  });

  final EdgeInsets overlayViewInsets;
  final Rect targetRect;
  final Size overlaySize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        viewInsets: morphContentViewInsets(
          overlayViewInsets,
          targetRect,
          overlaySize,
        ),
      ),
      child: child,
    );
  }
}
