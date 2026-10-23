import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/flight.dart';
import 'package:morph/src/flight_springs.dart';
import 'package:morph/src/show.dart';
import 'package:morph/src/target.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/haptics.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/menu_content.dart';
import 'package:morph/src/widgets/menu_entries.dart';
import 'package:morph/src/widgets/menu_layout.dart';
import 'package:morph/src/widgets/menu_motion.dart';

/// Owns the gesture, motion, content and flight of a button or bar menu.
///
/// The source supplies its geometry and motion clock. After source disposal,
/// the flight's frames continue the close on the same motion timeline.
@internal
class MorphMenuController implements MorphMenuHost {
  /// Creates a host whose source is [tagId] in [scopeContext].
  MorphMenuController({
    required this.tagId,
    required this.scopeContext,
    required this.clock,
    required this.stamp,
    required this.wake,
    required this.style,
    this.surface,
    required this.glyph,
    this.glyphKey,
    required this.semanticLabel,
    this.onOpen,
    this.onClose,
    this.onTap,
    this.launch,
  }) {
    menuContent = MorphMenuContent(onChanged: _contentChanged);
  }

  /// The identity of the source surface.
  final Object tagId;

  /// The mounted context below the source scope.
  final BuildContext? Function() scopeContext;

  /// The source motion clock, in seconds.
  final double Function() clock;

  /// Stamps pointer events on the source motion clock.
  final double Function(PointerEvent event) stamp;

  /// Wakes the source motion clock.
  final VoidCallback wake;

  /// Resolves the current menu appearance.
  final MorphMenuAppearance Function() style;

  /// Resolves the fill and flat rim of the source's own surface, or null
  /// for a source drawn on the menu's glass.
  final ({Color color, Color? rim})? Function()? surface;

  /// Builds the source content carried by the menu.
  final Widget Function() glyph;

  /// Reads a value that changes whenever [glyph] would build differently
  /// for the same [style]; null when it never does.
  final Object? Function()? glyphKey;

  /// Resolves the caller's localized menu label.
  final String? Function() semanticLabel;

  /// Receives each newly launched flight.
  final ValueChanged<MorphFlight>? onOpen;

  /// Launches the flight that carries the menu instead of the vessel
  /// flight from [tagId], or retargets it: a source that carries more than
  /// the menu in one flight (a context menu's preview) builds a
  /// [MorphMenuLayer] for this controller into it.
  final MorphFlight Function()? launch;

  /// Called when the menu starts closing, however it closes: a row chosen,
  /// a touch outside it, Esc or [close].
  final VoidCallback? onClose;

  /// Called for a tap on the source that does not open the menu
  /// ([MorphMenuTapped]).
  final VoidCallback? onTap;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  final ValueNotifier<int> _glows = ValueNotifier<int>(0);
  OverlayState? _overlay;

  MorphMenuMotion? _motion;
  MorphFlight? _flight;
  int? _pointer;
  int? _early;
  bool _routing = false;
  bool _delivering = false;
  bool _disposed = false;
  bool _repaintDisposed = false;
  MorphMenuAppearance? _lastStyle;
  ({Color color, Color? rim})? _lastSurface;
  MorphGlassPainter? _lastGlass;
  Widget? _lastGlyph;
  Object? _lastGlyphKey;
  double _detachedTime = 0;
  Duration _detachedFrame = Duration.zero;

  @override
  late final MorphMenuContent menuContent;

  /// Whether the source's element is in the tree. Set false while it is
  /// deactivated: a deactivated element still reads as mounted, but looking
  /// up its ancestors asserts, so the menu serves what it read last.
  bool sourceActive = true;

  bool get _sourceGone => _disposed || !sourceActive;

  @override
  MorphMenuAppearance get menuStyle => _sourceGone
      ? _lastStyle ?? MorphMenuAppearance.light
      : _lastStyle = style();

  @override
  ({Color color, Color? rim})? get menuSourceSurface =>
      _sourceGone ? _lastSurface : _lastSurface = surface?.call();

  @override
  MorphGlassPainter? get menuGlass {
    final context = _sourceGone ? null : scopeContext();
    if (context != null && context.mounted) {
      _lastGlass = morphGlassAbove(context);
    }
    return _lastGlass;
  }

  @override
  Widget get menuGlyph => _sourceGone
      ? _lastGlyph ?? const SizedBox.shrink()
      : _lastGlyph = glyph();

  @override
  Object? get menuGlyphKey =>
      _sourceGone ? _lastGlyphKey : _lastGlyphKey = glyphKey?.call();

  @override
  Listenable get menuRepaint => _repaint;

  @override
  Listenable get menuGlows => _glows;

  @override
  final GlobalKey menuRowsKey = GlobalKey(debugLabel: 'menu rows');

  /// How many root elements are built ahead of the opening; zero when
  /// nothing is.
  ///
  /// While a touch may open the menu and no flight carries it, each
  /// advance of the motion adds [prebuildStep] elements, up to all of the
  /// root's, so the rows the first frame of the menu would build are built
  /// over the frames of the press and the tap's opening delay instead, out
  /// of sight.
  int get prebuildCount => _prebuildCount;
  int _prebuildCount = 0;

  /// The elements built ahead of the opening per advance of the motion.
  static const int prebuildStep = 6;

  /// Whether menus build their rows ahead of the opening; tests turn it
  /// off to compare the frames drawn both ways.
  @visibleForTesting
  static bool debugPrebuild = true;

  OverlayEntry? _prebuildEntry;
  final ValueNotifier<(int, MorphMenuLayout?)> _prebuilt =
      ValueNotifier<(int, MorphMenuLayout?)>((0, null));

  void _syncPrebuild() {
    final entry = _prebuildEntry;
    if (_prebuildCount == 0) {
      if (entry == null) return;
      _prebuildEntry = null;
      entry.remove();
      entry.dispose();
      return;
    }
    final overlay = _overlay;
    if (entry != null || overlay == null || !overlay.mounted) return;
    menuRowsBlur.value = 0;
    final created = OverlayEntry(
      builder: (BuildContext context) => ListenableBuilder(
        listenable: _prebuilt,
        builder: (BuildContext context, Widget? _) =>
            _prebuildCount == 0 || _motion == null
            ? const SizedBox.shrink()
            : morphMenuPrebuiltRows(this, _prebuildCount, context: context),
      ),
    );
    _prebuildEntry = created;
    overlay.insert(created);
  }

  /// What rows built ahead of the opening hide: nothing.
  final ValueNotifier<int?> prebuildHidden = ValueNotifier<int?>(null);

  @override
  final ValueNotifier<double> menuRowsBlur = ValueNotifier<double>(0);

  @override
  MorphMenuMotion? get menuMotion => _motion;

  @override
  double get menuClock => _disposed ? _detachedTime : clock();

  /// The flight carrying this menu, or null after its landing.
  MorphFlight? get flight => _flight;

  /// Whether a menu pointer is already held by this host.
  bool get hasPointer => _pointer != null;

  /// Whether the source draws the remainder of the close after the latch.
  bool get isLanding =>
      (_motion?.isPresented ?? false) && !(_flight?.isAirborne ?? false);

  /// Prepares the measured motion in [overlay]'s coordinates; a source
  /// whose corners are not a capsule passes their [sourceRadius].
  MorphMenuMotion prepare({
    required Rect button,
    required Size bounds,
    required EdgeInsets padding,
    required MorphMenuTuning tuning,
    required OverlayState overlay,
    double? sourceHeight,
    double? sourceRadius,
    bool? dismissOnSelect,
    MorphMenuAttachment? attachment,
  }) {
    _overlay = overlay;
    _lastStyle = style();
    _lastGlyph = glyph();
    final current = _motion;
    if (current != null && identical(current.tuning, tuning)) {
      current.relayout(
        button: button,
        bounds: bounds,
        padding: padding,
        sourceRadius: sourceRadius,
        attachment: attachment,
      );
      current.dismissOnSelect = dismissOnSelect;
      current.lightsGlow = morphGlassLightsGlow(menuGlass);
      return current;
    }
    final motion = MorphMenuMotion(
      button: button,
      layout: menuContent.root,
      bounds: bounds,
      padding: padding,
      sourceHeight: sourceHeight,
      sourceRadius: sourceRadius,
      tuning: tuning,
      attachment: attachment,
      progress: MorphMenuFlightProgress(
        tuning,
        onOpen: _launch,
        onClose: _closeFlight,
      ),
    );
    morphConnectMenu(motion, menuContent, dismissOnSelect: dismissOnSelect);
    motion.lightsGlow = morphGlassLightsGlow(menuGlass);
    motion.advance(menuClock);
    _motion = motion;
    return motion;
  }

  void _trackedHighlight() {
    final context = _sourceGone ? null : scopeContext();
    if (context != null && context.mounted) {
      morphPlayHaptic(context, MorphHaptic.selection);
    }
  }

  /// Applies declarative entries and resizes an already presented menu; a
  /// closed one takes them when it opens next.
  void updateEntries(
    List<MorphMenuEntry> entries, {
    MorphMenuOrder order = MorphMenuOrder.automatic,
    bool? dismissOnSelect,
  }) {
    final changed =
        !identical(entries, menuContent.entries) || order != menuContent.order;
    menuContent.entries = entries;
    menuContent.order = order;
    _motion?.dismissOnSelect = dismissOnSelect;
    if (changed) _contentChanged(animate: true);
  }

  /// Starts a new content session for a menu reopened while it closes, so
  /// its uncached deferred groups load again as at any other opening.
  void beginReopenSession() {
    menuContent.beginSession();
    _contentChanged(animate: true);
  }

  void _contentChanged({required bool animate}) {
    if (_disposed) return;
    final motion = _motion;
    // A closed menu lays its root out again in prepare, before it opens.
    if (motion == null || !(motion.isPresented || motion.isArming)) return;
    final animated = animate && motion.isPresented;
    menuCommand((motion, t) => motion.updateLayout(t, animate: animated));
    menuWake();
  }

  void _launch() {
    final context = scopeContext();
    final motion = _motion;
    if (_disposed || context == null || !context.mounted || motion == null) {
      motion?.close(menuClock);
      return;
    }
    final tuning = motion.tuning;
    final launch = this.launch;
    final flight = launch != null
        ? launch()
        : showMorph(
            context,
            from: tagId,
            target: MorphTargetSpec.vessel(
              rectFor: (Size size, EdgeInsets padding) => motion.menuRect,
            ),
            builder: (BuildContext context, MorphFlight flight) =>
                MorphMenuLayer(host: this, flight: flight),
            motion: FlightSprings(
              name: 'menu',
              openSpring: tuning.openSpring,
              closeSpring: tuning.closeSpring,
            ),
            maxScrimOpacity: 0,
            onDismissRequested: close,
            semanticLabel: semanticLabel(),
            overlay: _overlay,
          );
    if (identical(flight, _flight)) return;
    _flight = flight;
    flight.closed.whenComplete(() {
      flight.frameTicks.removeListener(_advanceDetached);
      if (identical(_flight, flight)) _flight = null;
      if (_disposed && _flight == null) _disposeRepaint();
    });
    onOpen?.call(flight);
  }

  void _closeFlight() {
    if (!_disposed) onClose?.call();
    final flight = _flight;
    if (flight == null || flight.isFinished) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (!flight.isFinished && !(_motion?.isOpen ?? false)) flight.close();
      });
    } else {
      flight.close();
    }
  }

  /// Closes the motion and its flight, including any pending opening,
  /// from where the motion stands: never before its last sample.
  @override
  void close() {
    if (_disposed) return;
    final motion = _motion;
    if (motion != null) {
      menuCommand(
        (motion, t) => motion.close(t),
        at: math.max(menuClock, motion.time),
      );
    }
    menuWake();
  }

  @override
  void menuWake() {
    if (!_disposed) wake();
  }

  @override
  void menuCommand(
    void Function(MorphMenuMotion motion, double t) command, {
    double? at,
  }) {
    final motion = _motion;
    if (motion == null) return;
    final t = at ?? menuClock;
    _reach(motion, t);
    command(motion, t);
    _deliver(motion);
  }

  /// Advances [motion] to [t], delivering its events and answering each
  /// close it requests on the way at the time it requested it.
  void _reach(MorphMenuMotion motion, double t) {
    while (!motion.advanceToRequest(t)) {
      _deliver(motion);
    }
    _deliver(motion);
  }

  // Events a callback raises while others are delivered follow them, in
  // order, instead of interrupting them.
  void _deliver(MorphMenuMotion motion) {
    if (_delivering) return;
    _delivering = true;
    try {
      for (
        var events = motion.drainEvents();
        events.isNotEmpty;
        events = motion.drainEvents()
      ) {
        for (final event in events) {
          try {
            _receive(motion, event);
          } catch (error, stack) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stack,
                library: 'morph',
                context: ErrorDescription('while delivering a menu event'),
              ),
            );
          }
        }
      }
    } finally {
      _delivering = false;
    }
  }

  void _receive(MorphMenuMotion motion, MorphMenuEvent event) {
    switch (event) {
      case MorphMenuHighlightChanged(:final from, :final to, :final tracked):
        if (_disposed) return;
        menuContent.highlight(from, to);
        if (tracked) _trackedHighlight();
      case MorphMenuActivated(:final target):
        if (!_disposed) menuContent.activate(target);
      case MorphMenuTapped():
        if (!_disposed) onTap?.call();
      case MorphMenuCloseRequested():
        // An overlay menu has no pop policy of its own to consult, so it
        // closes at the measured time; a request a reentrant command
        // passed by closes from where the motion stands now.
        if (!motion.admitClose(event) && motion.isOpen) {
          motion.close(math.max(menuClock, motion.time));
        }
    }
  }

  /// The motion time before which the menu draws nothing new, or null when
  /// it changes on the next frame; the source clock dozes until then.
  ///
  /// Rows still being built ahead of the opening keep it awake.
  double? get wakeTime {
    final motion = _motion;
    if (motion == null || _prebuildCount > 0) return null;
    return motion.wakeTime;
  }

  /// Advances the measured motion to the frame at [t] and notifies its
  /// layer.
  ///
  /// [framePeriod] is the source clock's frame grid
  /// (`MorphClock.framePeriod`), from which the motion fuses its coming
  /// frames' silhouettes ahead; null fuses nothing ahead.
  void advance(double t, {double? framePeriod}) {
    final motion = _motion;
    if (motion == null || _repaintDisposed) return;
    motion.frameTime = t;
    motion.framePeriod = framePeriod;
    // A pointer event may have advanced the motion past the frame already.
    _reach(motion, math.max(t, motion.time));
    if (_early == null && !motion.isOpenPending) _unroute();
    final layout = motion.layout;
    _prebuildCount = debugPrebuild && _flight == null && motion.isArming
        ? math.min(_prebuildCount + prebuildStep, layout.elements.length)
        : 0;
    _prebuilt.value = (_prebuildCount, _prebuildCount == 0 ? null : layout);
    _syncPrebuild();
    final revision = motion.revision;
    final still = motion.isStill;
    final same =
        identical(motion, _drawnMotion) &&
        revision == _drawnRevision &&
        _drawnStill &&
        still;
    _drawnMotion = motion;
    _drawnRevision = revision;
    _drawnStill = still;
    final glowing = motion.isGlowing;
    if (!same) {
      _repaint.value++;
    } else if (glowing || _drawnGlowing) {
      _glows.value++;
    }
    _drawnGlowing = glowing;
  }

  // A frame whose motion stood still since the previous one, with no input
  // or pending reaction in between, shows the same picture but for the
  // touch glow: it paints nothing (a finger resting on the open menu
  // between two steps of its flex pulse, MorphMenuTuning.flexPulseRate),
  // and a glow that moves reaches only the glass that draws it. The frame
  // after the glow came to rest still hands it its last value.
  MorphMenuMotion? _drawnMotion;
  int _drawnRevision = -1;
  bool _drawnStill = false;
  bool _drawnGlowing = false;

  Offset _local(Offset global) {
    final box = _overlay?.context.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : global;
  }

  /// Opens the prepared menu under the finger [pointer], which has held
  /// the source and rests at the global [position]: its moves and its
  /// release, fed to [menuPointerMove] and [menuPointerUp], slide the
  /// highlight through the menu and choose a row
  /// ([MorphMenuMotion.holdOpen]).
  void holdOpen(int pointer, Offset position) {
    final motion = _motion;
    if (_disposed || motion == null) return;
    if (_pointer != null) {
      menuCommand((motion, t) => motion.open(t));
    } else {
      _pointer = pointer;
      final local = _local(position);
      menuCommand((motion, t) => motion.holdOpen(t, local));
    }
    menuWake();
  }

  /// Opens the prepared menu without a finger on it.
  void open() {
    if (_disposed || _motion == null) return;
    menuCommand((motion, t) => motion.open(t));
    menuWake();
  }

  @override
  void menuPointerDown(PointerDownEvent event) {
    final motion = _motion;
    if (_disposed ||
        motion == null ||
        _pointer != null ||
        event.buttons != kPrimaryButton) {
      return;
    }
    _pointer = event.pointer;
    final local = _local(event.position);
    menuCommand((motion, t) => motion.pointerDown(t, local), at: stamp(event));
  }

  @override
  void menuPointerMove(PointerMoveEvent event) {
    if (_disposed || event.pointer != _pointer) return;
    final local = _local(event.position);
    menuCommand((motion, t) => motion.pointerMove(t, local), at: stamp(event));
  }

  @override
  void menuPointerUp(PointerUpEvent event) {
    if (_disposed || event.pointer != _pointer) return;
    _pointer = null;
    final motion = _motion;
    if (motion == null) return;
    final local = _local(event.position);
    menuCommand((motion, t) => motion.pointerUp(t, local), at: stamp(event));
    if (motion.isOpenPending) _route();
  }

  @override
  void menuPointerCancel(PointerCancelEvent event) {
    if (_disposed || event.pointer != _pointer) return;
    _pointer = null;
    menuCommand((motion, t) => motion.pointerCancel(t), at: stamp(event));
  }

  void _route() {
    if (_routing) return;
    _routing = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_earlyEvent);
  }

  void _unroute() {
    if (!_routing) return;
    _routing = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_earlyEvent);
  }

  void _earlyEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      if (!(_motion?.isOpenPending ?? false) ||
          hasPointer ||
          event.buttons != kPrimaryButton) {
        return;
      }
      _early = event.pointer;
      menuPointerDown(event);
    } else if (event.pointer == _early) {
      if (event is PointerMoveEvent) menuPointerMove(event);
      if (event is PointerUpEvent) {
        _early = null;
        menuPointerUp(event);
      }
      if (event is PointerCancelEvent) {
        _early = null;
        menuPointerCancel(event);
      }
    }
  }

  /// Releases source resources and continues a live close after the frame.
  void dispose() {
    if (_disposed) return;
    _detachedTime = clock();
    _disposed = true;
    _prebuildCount = 0;
    _syncPrebuild();
    _unroute();
    menuContent.dispose();
    final flight = _flight;
    if (flight == null || flight.isFinished) {
      _motion?.close(_detachedTime);
      _disposeRepaint();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (flight.isFinished) return;
      _detachedFrame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
      _motion?.close(_detachedTime);
      flight.frameTicks.addListener(_advanceDetached);
    });
  }

  void _advanceDetached() {
    final frame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    _detachedTime +=
        (frame - _detachedFrame).inMicroseconds / 1e6 / timeDilation;
    _detachedFrame = frame;
    advance(_detachedTime);
  }

  void _disposeRepaint() {
    if (_repaintDisposed) return;
    _repaintDisposed = true;
    _repaint.dispose();
    _glows.dispose();
    _prebuilt.dispose();
    prebuildHidden.dispose();
    menuRowsBlur.dispose();
  }
}
