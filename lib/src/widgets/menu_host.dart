import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/flight.dart';
import 'package:morph/src/motion.dart';
import 'package:morph/src/show.dart';
import 'package:morph/src/target.dart';
import 'package:morph/src/widgets/glass.dart';
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
    required this.glyph,
    required this.semanticLabel,
    this.onOpen,
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
  final MorphMenuStyle Function() style;

  /// Builds the source content carried by the menu.
  final Widget Function() glyph;

  /// Resolves the caller's localized menu label.
  final String? Function() semanticLabel;

  /// Receives each newly launched flight.
  final ValueChanged<MorphFlight>? onOpen;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  OverlayState? _overlay;

  MorphMenuMotion? _motion;
  MorphFlight? _flight;
  int? _pointer;
  int? _early;
  bool _routing = false;
  bool _disposed = false;
  bool _repaintDisposed = false;
  MorphMenuStyle? _lastStyle;
  MorphGlassPainter? _lastGlass;
  Widget? _lastGlyph;
  double _detachedTime = 0;
  Duration _detachedFrame = Duration.zero;

  @override
  late final MorphMenuContent menuContent;

  @override
  MorphMenuStyle get menuStyle =>
      _disposed ? _lastStyle ?? MorphMenuStyle.light : _lastStyle = style();

  @override
  MorphGlassPainter? get menuGlass {
    final context = _disposed ? null : scopeContext();
    if (context != null && context.mounted) {
      _lastGlass = morphGlassAbove(context);
    }
    return _lastGlass;
  }

  @override
  Widget get menuGlyph =>
      _disposed ? _lastGlyph ?? const SizedBox.shrink() : _lastGlyph = glyph();

  @override
  Listenable get menuRepaint => _repaint;

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
            : morphMenuPrebuiltRows(this, _prebuildCount),
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

  final MorphFrameGrid _grid = MorphFrameGrid();

  /// The flight carrying this menu, or null after its landing.
  MorphFlight? get flight => _flight;

  /// Whether a menu pointer is already held by this host.
  bool get hasPointer => _pointer != null;

  /// Whether the source draws the remainder of the close after the latch.
  bool get isLanding =>
      (_motion?.isPresented ?? false) && !(_flight?.isAirborne ?? false);

  /// Prepares the measured motion in [overlay]'s coordinates.
  MorphMenuMotion prepare({
    required Rect button,
    required Size bounds,
    required EdgeInsets padding,
    required MorphMenuTuning tuning,
    required OverlayState overlay,
    double? sourceHeight,
    bool? dismissOnSelect,
  }) {
    _overlay = overlay;
    _lastStyle = style();
    _lastGlyph = glyph();
    final current = _motion;
    if (current != null && identical(current.tuning, tuning)) {
      current.relayout(button: button, bounds: bounds, padding: padding);
      current.dismissOnSelect = dismissOnSelect;
      return current;
    }
    final motion = MorphMenuMotion(
      button: button,
      layout: menuContent.root,
      bounds: bounds,
      padding: padding,
      sourceHeight: sourceHeight,
      tuning: tuning,
      progress: MorphMenuFlightProgress(
        tuning,
        onOpen: _launch,
        onClose: _closeFlight,
      ),
    );
    morphConnectMenu(motion, menuContent, dismissOnSelect: dismissOnSelect);
    motion.advance(menuClock);
    _motion = motion;
    return motion;
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

  void _contentChanged({required bool animate}) {
    if (_disposed) return;
    final motion = _motion;
    // A closed menu lays its root out again in prepare, before it opens.
    if (motion == null || !(motion.isPresented || motion.isArming)) return;
    motion.updateLayout(menuClock, animate: animate && motion.isPresented);
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
    final flight = showMorph(
      context,
      from: tagId,
      target: MorphTargetSpec.vessel(
        rectFor: (Size size, EdgeInsets padding) => motion.menuRect,
      ),
      builder: (BuildContext context, MorphFlight flight) =>
          MorphMenuLayer(host: this, flight: flight),
      motion: MorphMotion.springs(
        name: 'menu',
        open: tuning.openSpring,
        close: tuning.closeSpring,
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

  /// Closes the motion and its flight, including any pending opening.
  void close() {
    if (_disposed) return;
    _motion?.close(menuClock);
    menuWake();
  }

  @override
  void menuWake() {
    if (!_disposed) wake();
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

  /// Advances the measured motion and notifies its layer.
  ///
  /// The frame's time is put on the display's frame grid first
  /// ([MorphFrameGrid]), so the silhouettes the motion fuses ahead for its
  /// coming frames are the ones those frames ask for.
  void advance(double t) {
    final motion = _motion;
    if (motion == null || _repaintDisposed) return;
    // A pointer event may have advanced the motion past the node already.
    motion.advance(math.max(_grid.snap(t), motion.time));
    if (_early == null && !motion.isOpenPending) _unroute();
    final layout = motion.layout;
    _prebuildCount = debugPrebuild && _flight == null && motion.isArming
        ? math.min(_prebuildCount + prebuildStep, layout.elements.length)
        : 0;
    _prebuilt.value = (_prebuildCount, _prebuildCount == 0 ? null : layout);
    _syncPrebuild();
    _repaint.value++;
  }

  Offset _local(Offset global) {
    final box = _overlay?.context.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : global;
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
    motion.pointerDown(stamp(event), _local(event.position));
  }

  @override
  void menuPointerMove(PointerMoveEvent event) {
    if (_disposed || event.pointer != _pointer) return;
    _motion?.pointerMove(stamp(event), _local(event.position));
  }

  @override
  void menuPointerUp(PointerUpEvent event) {
    if (_disposed || event.pointer != _pointer) return;
    _pointer = null;
    final motion = _motion;
    if (motion == null) return;
    motion.pointerUp(stamp(event), _local(event.position));
    if (motion.isOpenPending) _route();
  }

  @override
  void menuPointerCancel(PointerCancelEvent event) {
    if (_disposed || event.pointer != _pointer) return;
    _pointer = null;
    _motion?.pointerCancel(stamp(event));
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
    _motion?.onActivate = null;
    _motion?.onHighlight = null;
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
    _prebuilt.dispose();
    prebuildHidden.dispose();
    menuRowsBlur.dispose();
  }
}

/// Puts frame times on the display's frame grid.
///
/// A frame's time is the vsync timestamp, which jitters by tens of
/// microseconds around the display's period. A menu fuses its coming
/// frames' silhouettes ahead from predicted times and serves one only
/// when the frame's shapes are within `MorphMenuFusion.prefetchTolerance`
/// (0.02 pt) of the prediction, which at the morph's peak speed is about
/// 10 us: the jitter alone made a third of the frames fuse their own. On
/// the grid the coming frames' times are exact and the prediction is the
/// frame.
///
/// A grid starts at a frame and is spaced by the median step of the last
/// steady frames, fixed for the grid's life (it carries over to the next
/// grid until new steps replace it). [snap] moves a time to the nearest
/// later node within [reach]; otherwise (a pause, a changed rate, a drift)
/// the time stays as it is and starts a new grid.
///
/// Fidelity: NEAR. The motion is sampled up to [reach] (1 ms) from the
/// vsync timestamp, typically tens of microseconds; the frame is shown at
/// the same vsync either way.
@internal
class MorphFrameGrid {
  /// How far, in seconds, a time may move onto the grid.
  static const double reach = 0.001;

  final Float64List _steps = Float64List(8);
  int _count = 0;
  double? _raw;
  double? _anchor;
  double? _period;
  double _last = 0;

  /// [t] on the frame grid, or [t] itself when no node is within [reach].
  double snap(double t) {
    final raw = _raw;
    _raw = t;
    if (raw != null) {
      final step = t - raw;
      if (step > 0.004 && step < 0.05) {
        _steps[_count % _steps.length] = step;
        _count++;
      } else if (step != 0) {
        _count = 0;
      }
    }
    final anchor = _anchor;
    final period = _period;
    if (anchor == null || period == null) return _restart(t);
    final k = ((t - anchor) / period).round();
    final node = anchor + k * period;
    if (k < 1 || (node - t).abs() >= reach || node < _last) return _restart(t);
    return _last = (node - t).abs() < 1e-9 ? t : node;
  }

  double _restart(double t) {
    final n = math.min(_count, _steps.length);
    if (n >= 3) {
      final sorted = Float64List.fromList(
        Float64List.sublistView(_steps, 0, n),
      );
      sorted.sort();
      _period = sorted[n ~/ 2];
    }
    _anchor = t;
    return _last = t;
  }
}
