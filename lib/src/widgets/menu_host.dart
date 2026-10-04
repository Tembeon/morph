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
      _lastGlass = context.getInheritedWidgetOfExactType<MorphGlass>()?.painter;
    }
    return _lastGlass;
  }

  @override
  Widget get menuGlyph =>
      _disposed ? _lastGlyph ?? const SizedBox.shrink() : _lastGlyph = glyph();

  @override
  Listenable get menuRepaint => _repaint;

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

  /// Applies declarative entries and resizes an already presented menu.
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
    if (motion == null) return;
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

  /// Advances the measured motion and notifies its layer.
  void advance(double t) {
    final motion = _motion;
    if (motion == null || _repaintDisposed) return;
    motion.advance(t);
    if (_early == null && !motion.isOpenPending) _unroute();
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
  }
}
