import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import 'package:morph/src/controller.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/scrim.dart';
import 'package:morph/src/motion.dart';
import 'package:morph/src/presentation.dart';
import 'package:morph/src/target.dart';
import 'package:morph/src/theme.dart';
import 'package:morph/src/themes.dart';

// Without a scrim motion the scrim fades in over the first 70 percent of
// the flight's progress.
const Interval _scrimFade = Interval(0, 0.7);

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
    tag.context.dependOnInheritedWidgetOfExactType<DefaultTextStyle>();
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
      maxScrimOpacity *
          _scrimFade.transform(clampDouble(controller.progress, 0, 1));

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
    tag.context.dependOnInheritedWidgetOfExactType<DefaultTextStyle>();
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

  /// The source tag's id.
  Object get tagId => tag.id;

  /// Completes when the flight finalizes (landed or aborted), with the
  /// result of the [close] that landed it - the overlay counterpart of
  /// awaiting showDialog. A dismissal (scrim tap, Esc, back) closes
  /// with null.
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
    if (_historyEntry != null) {
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
    if (_historyEntry != null || route == null || !route.isActive) {
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

  /// Geometry changes from the value spring, displacement, content size
  /// and the target's repaint signal; excludes independent scrim ticks.
  ///
  /// Skins use this stream to follow the flying surface without repainting
  /// when only its scrim changes.
  late final Listenable geometryTicks = .merge(<Listenable>[
    controller,
    ?target.repaint,
  ]);

  /// All visual changes, including [geometryTicks] and independent scrim
  /// ticks. The shuttle and settled route page use this stream.
  late final Listenable frameTicks = .merge(<Listenable>[
    geometryTicks,
    ?_scrim,
  ]);

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
      if (motion != null) {
        existing.controller.motion = motion;
      }
      if (onDismissRequested != null) {
        existing.onDismissRequested = onDismissRequested;
      }
      if (semanticLabel != null) {
        existing.semanticLabel = semanticLabel;
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
  /// content derives from that state calls this after setState.
  void markNeedsBuild() => _entry?.markNeedsBuild();

  /// Bumped to rebuild only the target content (the builder closure),
  /// not the shuttle or the settled route page around it.
  @internal
  Listenable get contentRevision => _contentRevision;
  final ValueNotifier<int> _contentRevision = ValueNotifier<int>(0);

  /// Rebuilds the target content from the current builder closure,
  /// wherever it is mounted, without rebuilding the frame chain, the
  /// layout or the placement around it.
  @internal
  void markContentNeedsBuild() {
    if (_controllerDisposed) {
      return;
    }
    _contentRevision.value++;
  }

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

  /// [overlayBox] for a reader in the paint phase, where neither the
  /// abort's setState nor a throw may run: null while the overlay is
  /// being removed (deactivated this frame, its box already detached)
  /// and once it has been unmounted; an unmounted overlay aborts the
  /// flight after the frame instead.
  @internal
  RenderBox? get overlayBoxOrNull {
    if (!_overlay.mounted) {
      if (!_finished && !_lostOverlayAbortScheduled) {
        _lostOverlayAbortScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((Duration _) {
          _lostOverlayAbortScheduled = false;
          _abortForLostOverlay();
        });
      }
      return null;
    }
    // Element.renderObject, not findRenderObject: the latter asserts on
    // an element deactivated earlier in this frame, which is exactly
    // the state a skin outside the removed overlay paints against.
    final RenderObject? box = (_overlay.context as Element).renderObject;
    return box is RenderBox && box.attached ? box : null;
  }

  bool _lostOverlayAbortScheduled = false;

  void _insertEntry() {
    refreshSourceRect();
    _entry = OverlayEntry(
      builder: (BuildContext context) => _MorphShuttle(flight: this),
    );
    _overlay.insert(_entry!);
  }

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
        controller.hasHandedOff) {
      return;
    }
    tag.hideForFlight();
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
      _scrim?.dispose();
      _contentRevision.dispose();
      sourceThemes.dispose();
    }
  }
}

/// The modal barrier of a flight: the dimming layer, its dismiss tap
/// and the screen-reader dismiss affordance. Opacity is computed by the
/// frame (scrim curve x displacement recede x arm cue) and read again on
/// every notification of [live].
class _ShuttleScrim extends StatelessWidget {
  const _ShuttleScrim({
    required this.flight,
    required this.live,
    required this.opacityOf,
  });

  final MorphFlight flight;
  final Listenable? live;
  final double Function() opacityOf;

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
          child: MorphLiveColoredBox(
            live: live,
            colorOf: () => flight.scrimColor.withValues(
              alpha: flight.scrimColor.a * opacityOf(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Resolves the target's surface model against the ambient color
/// scheme: a null target color adopts surfaceContainerHigh, so every
/// renderer of the target agrees on one value.
@internal
MorphSurfaceSpec resolveMorphTargetSurface(
  MorphFlight flight,
  ColorScheme scheme,
) {
  return flight.target.surface.color == null
      ? flight.target.surface.copyWith(color: scheme.surfaceContainerHigh)
      : flight.target.surface;
}

/// The target-content subtree with its wrapper chain: flight scope,
/// surface spec and builder.
@internal
Widget buildMorphTargetContent({
  required MorphFlight flight,
  required MorphSurfaceSpec spec,
}) {
  return MorphFlightScope(
    flight: flight,
    child: MorphSurfaceSpecScope(
      spec: spec,
      child: ListenableBuilder(
        listenable: flight.contentRevision,
        builder: (BuildContext context, Widget? _) =>
            flight.builder(context, flight),
      ),
    ),
  );
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
  final GlobalKey _targetAnchorKey = GlobalKey();
  late final Listenable _frameTicks = flight.frameTicks;

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
              // The scrim's opacity rides its own springs: the frame ticks
              // repaint the scrim's box, so the vessel's chain does not
              // build on every frame of the dim,
              // and in a repaint boundary of its own the dim repaints
              // alone, not the overlay it lies in.
              child: RepaintBoundary(
                child: _ShuttleScrim(
                  flight: flight,
                  live: _frameTicks,
                  opacityOf: () => flight.scrimOpacity,
                ),
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
              return _VesselFrame(
                flight: flight,
                ticks: _frameTicks,
                overlaySize: overlaySize,
                padding: padding,
                lingeringScrim: _lingeringScrim,
                buildVessel: _buildVessel,
                content: content,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A vessel's frame chain, rebuilt only when something it shows
/// changes: content ownership, the lingering scrim, the pointer gate,
/// the dissolve or the scrim opacity. Every other tick (the progress
/// spring, a vessel's own geometry signal) only advances the flight's
/// source and target rects - the vessel content draws the motion
/// itself.
class _VesselFrame extends StatefulWidget {
  const _VesselFrame({
    required this.flight,
    required this.ticks,
    required this.overlaySize,
    required this.padding,
    required this.lingeringScrim,
    required this.buildVessel,
    required this.content,
  });

  final MorphFlight flight;
  final Listenable ticks;
  final Size overlaySize;
  final EdgeInsets padding;
  final Widget Function() lingeringScrim;
  final Widget Function(Widget content) buildVessel;
  final Widget content;

  @override
  State<_VesselFrame> createState() => _VesselFrameState();
}

class _VesselFrameState extends State<_VesselFrame> {
  Object? _built;

  @override
  void initState() {
    super.initState();
    widget.ticks.addListener(_onTick);
  }

  @override
  void didUpdateWidget(_VesselFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.ticks, oldWidget.ticks)) {
      oldWidget.ticks.removeListener(_onTick);
      widget.ticks.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    widget.ticks.removeListener(_onTick);
    super.dispose();
  }

  /// Advances the rect bookkeeping and returns what the built chain
  /// depends on.
  Object? _advance() {
    final MorphFlight flight = widget.flight;
    if (flight._scrimOnly) {
      return (flight.scrimOpacity,);
    }
    flight.refreshSourceRect();
    flight.updateTargetRect(
      flight.target.resolveRect(widget.overlaySize, widget.padding),
    );
    return (
      flight.controller.target < 1,
      flight.dissolveOpacity,
      flight.modal,
      flight.semanticLabel,
    );
  }

  void _onTick() {
    if (_advance() != _built) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final Object? built = _advance();
    _built = built;
    return switch (built) {
      null => const SizedBox.shrink(),
      (double _,) => widget.lingeringScrim(),
      _ => widget.buildVessel(widget.content),
    };
  }
}
