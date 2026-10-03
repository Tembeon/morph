import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/push_zoom_motion.dart';
import 'package:morph/src/widgets/sheet_motion.dart';

/// What a page zoomed out of a source needs from its route.
@internal
abstract interface class MorphPushZoomHost {
  /// The tag the page zooms out of and back into.
  MorphTagState get zoomFrom;

  /// The measured zoom.
  MorphPushZoomTuning get zoomTuning;

  /// Whether the page is the navigator's top route.
  bool get zoomIsCurrent;

  /// Asks the navigator to pop the page.
  void zoomPop();

  /// Called once the zoom back into the source has come to rest.
  void zoomClosed();

  /// Hands the host the page's state, or null when it goes away.
  void attachZoomView(MorphPushZoomPageState? view);
}

/// A pushed page drawn as UIKit's zoom transition draws it: grown out of
/// its source, dragged by a finger, zoomed back into the source.
@internal
class MorphPushZoomPage extends StatefulWidget {
  /// Creates the page around [child].
  const MorphPushZoomPage({required this.host, required this.child, super.key});

  /// The route that shows the page.
  final MorphPushZoomHost host;

  /// The page's content.
  final Widget child;

  @override
  State<MorphPushZoomPage> createState() => MorphPushZoomPageState();
}

/// The state of a [MorphPushZoomPage].
@internal
class MorphPushZoomPageState extends State<MorphPushZoomPage>
    with
        SingleTickerProviderStateMixin<MorphPushZoomPage>,
        MorphClock<MorphPushZoomPage> {
  MorphPushZoomMotion? _motion;
  Rect? _sourceRect;
  bool _sourceHidden = false;
  bool _leaving = false;
  bool _finished = false;
  late final _ZoomPanRecognizer _pan = _ZoomPanRecognizer(this);

  MorphPushZoomHost get _host => widget.host;

  /// The motion the page is drawn from, once the page is laid out.
  MorphPushZoomMotion? get motion => _motion;

  @override
  void initState() {
    super.initState();
    _host.attachZoomView(this);
    _pan.onStart = _dragStart;
    _pan.onUpdate = _dragUpdate;
    _pan.onEnd = _dragEnd;
    _pan.onCancel = _dragCancel;
  }

  @override
  void didUpdateWidget(MorphPushZoomPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      oldWidget.host.attachZoomView(null);
      widget.host.attachZoomView(this);
    }
  }

  @override
  void dispose() {
    _host.attachZoomView(null);
    _pan.dispose();
    _revealSource();
    super.dispose();
  }

  void _revealSource() {
    if (!_sourceHidden) return;
    _sourceHidden = false;
    final source = _host.zoomFrom;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (source.mounted) source.reveal();
    });
  }

  Rect? _captureSource() {
    final own = context.findRenderObject();
    final box = own is RenderBox && own.hasSize
        ? own
        : Overlay.maybeOf(context)?.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return _sourceRect;
    final rect = _host.zoomFrom.tryCaptureRect(box);
    if (rect != null) _sourceRect = rect;
    return _sourceRect;
  }

  @override
  void advanceMotion(double t) {
    final motion = _motion;
    if (motion == null) return;
    motion.advance(t);
    if (!motion.isDragging) {
      final source = _captureSource();
      if (source != null && source != motion.source && !motion.isOpening) {
        motion.retargetEnds(t, source: source);
      }
    }
    if (_leaving && !_finished && motion.isClosed) {
      _finished = true;
      _revealSource();
      _host.zoomClosed();
    }
  }

  @override
  bool get motionSettled => _motion?.isSettled ?? true;

  /// Zooms the page back into its source: the route was popped.
  void leave() {
    final motion = _motion;
    _leaving = true;
    if (motion == null) {
      _finished = true;
      _host.zoomClosed();
      return;
    }
    final source = _captureSource() ?? motion.source;
    motion.close(clock, source);
    wake();
  }

  void _layout(Size size) {
    final page = Offset.zero & size;
    final motion = _motion;
    if (motion != null) {
      if (motion.page != page) {
        motion.retargetEnds(clock, page: page);
        wake();
      }
      return;
    }
    final created = MorphPushZoomMotion(tuning: _host.zoomTuning);
    final source = _host.zoomFrom;
    final rect = source.mounted ? _captureSource() : null;
    if (rect == null) {
      created.showInPlace(clock, page, page);
    } else {
      created.open(clock, rect, page);
      _sourceHidden = true;
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (_sourceHidden && source.mounted) source.hideForFlight();
      });
    }
    _motion = created;
    wake();
  }

  void _pointerDown(PointerDownEvent event) {
    stamp(event);
    final motion = _motion;
    if (motion == null || _leaving || !_host.zoomIsCurrent) return;
    _pan.addPointer(event);
  }

  void _dragStart(DragStartDetails details) {
    final motion = _motion;
    if (motion == null || _leaving) return;
    motion.dragStart(clock, details.localPosition);
    wake();
  }

  void _dragUpdate(DragUpdateDetails details) {
    final motion = _motion;
    if (motion == null || !motion.isDragging) return;
    motion.dragUpdate(clock, details.localPosition);
    wake();
  }

  void _dragEnd(DragEndDetails details) {
    final motion = _motion;
    if (motion == null || !motion.isDragging) return;
    final velocity = details.velocity.pixelsPerSecond;
    if (motion.dragEnd(clock, velocity)) _host.zoomPop();
    wake();
  }

  void _dragCancel() {
    final motion = _motion;
    if (motion == null || !motion.isDragging) return;
    motion.dragEnd(clock, Offset.zero);
    wake();
  }

  /// Whether a pointer down at [position] may start an interactive
  /// dismissal: only where no scroll view under the finger has content
  /// above.
  bool _allows(Offset position) {
    final box = context.findRenderObject();
    if (box is! RenderBox) return false;
    final result = BoxHitTestResult();
    box.hitTest(result, position: position);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderViewportBase &&
          target.axis == Axis.vertical &&
          target.offset.hasPixels &&
          target.offset.pixels > 0.5) {
        return false;
      }
    }
    return true;
  }

  bool get _rtl => Directionality.maybeOf(context) == TextDirection.rtl;

  @override
  Widget build(BuildContext context) {
    final displayRadius =
        MediaQuery.maybeDisplayCornerRadiiOf(context)?.bottomLeft.x ??
        MorphSheetTuning.fallbackDisplayRadius;
    final tuning = _host.zoomTuning;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final size = constraints.biggest;
        _layout(size);
        return Listener(
          onPointerDown: _pointerDown,
          behavior: HitTestBehavior.translucent,
          child: ListenableBuilder(
            listenable: frames,
            child: SizedBox.fromSize(size: size, child: widget.child),
            builder: (BuildContext context, Widget? child) {
              final motion = _motion!;
              final t = motion.time;
              final open = motion.isOpen;
              final rect = open ? Offset.zero & size : motion.rect(t);
              final radius = open
                  ? 0.0
                  : math.max(
                      0.0,
                      motion.radius(
                        t,
                        _sourceRadius(_host.zoomFrom, motion.source.size),
                        displayRadius,
                      ),
                    );
              final scale = open ? 1.0 : motion.contentScale(t);
              final fade = open ? 1.0 : motion.fade(t);
              final dim = motion.dimming(t);
              final shape = RRect.fromRectAndRadius(
                Offset.zero & rect.size,
                Radius.circular(radius),
              );
              final source = _host.zoomFrom;
              final showSource = !open && fade < 1 && source.mounted;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Color.fromRGBO(
                          0,
                          0,
                          0,
                          open ? 0 : tuning.dimmingOpacity * dim,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: rect,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(radius),
                        ),
                        shadows: [
                          if (!open && dim > 0)
                            BoxShadow(
                              color: Color.fromRGBO(
                                0,
                                0,
                                0,
                                tuning.shadowOpacity * dim,
                              ),
                              offset: Offset(0, tuning.shadowOffset),
                              blurRadius: _blurRadius(tuning.shadowSigma),
                            ),
                        ],
                      ),
                      child: ClipRRect(
                        clipper: _ShapeClipper(shape),
                        clipBehavior: open ? Clip.none : Clip.antiAlias,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: (rect.width - size.width) / 2,
                              top: 0,
                              width: size.width,
                              height: size.height,
                              child: Transform.scale(
                                scale: scale,
                                alignment: Alignment.topCenter,
                                child: IgnorePointer(
                                  ignoring: !open,
                                  child: Opacity(opacity: fade, child: child),
                                ),
                              ),
                            ),
                            if (showSource)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Opacity(
                                    opacity: 1 - fade,
                                    child: ExcludeFocus(
                                      child: ExcludeSemantics(
                                        child: FittedBox(
                                          fit: BoxFit.fill,
                                          alignment: Alignment.topLeft,
                                          child: SizedBox.fromSize(
                                            size: motion.source.size,
                                            child: MorphSurfaceSpecScope(
                                              spec: source.surfaceSpec,
                                              child: source.replica,
                                            ),
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
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

double _blurRadius(double sigma) => (sigma - 0.5) / 0.57735;

/// The corner radius of [tag]'s shape at [size]: a stadium or a circle is
/// rounded by half the shorter side, a rounded rectangle by its top
/// leading radius.
double _sourceRadius(MorphTagState tag, Size size) {
  final half = size.shortestSide / 2;
  return switch (tag.shape) {
    StadiumBorder() || CircleBorder() => half,
    RoundedRectangleBorder(:final borderRadius) ||
    ContinuousRectangleBorder(:final borderRadius) ||
    RoundedSuperellipseBorder(
      :final borderRadius,
    ) => math.min(half, borderRadius.resolve(TextDirection.ltr).topLeft.x),
    _ => 0,
  };
}

class _ShapeClipper extends CustomClipper<RRect> {
  _ShapeClipper(this.shape);

  final RRect shape;

  @override
  RRect getClip(Size size) => shape;

  @override
  bool shouldReclip(_ShapeClipper oldClipper) => oldClipper.shape != shape;
}

/// A pan that wins the arena after [MorphPushZoomTuning.dragSlop] points
/// when it heads where the page follows, and gives up otherwise.
class _ZoomPanRecognizer extends PanGestureRecognizer {
  _ZoomPanRecognizer(this.page) : super(debugOwner: page) {
    dragStartBehavior = DragStartBehavior.down;
  }

  final MorphPushZoomPageState page;
  final Map<int, Offset> _downs = {};

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (!super.isPointerAllowed(event)) return false;
    final box = page.context.findRenderObject();
    if (box is! RenderBox) return false;
    return page._allows(box.globalToLocal(event.position));
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    gestureSettings = DeviceGestureSettings(
      touchSlop: page._host.zoomTuning.dragSlop / 2,
    );
    _downs[event.pointer] = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    final down = _downs[event.pointer];
    if (event is PointerMoveEvent && down != null) {
      final delta = event.position - down;
      if (delta.distance > page._host.zoomTuning.dragSlop) {
        _downs.remove(event.pointer);
        final motion = page.motion;
        if (motion == null || !motion.allowsDrag(delta, rtl: page._rtl)) {
          resolvePointer(event.pointer, GestureDisposition.rejected);
          stopTrackingPointer(event.pointer);
          return;
        }
      }
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _downs.remove(event.pointer);
    }
    super.handleEvent(event);
  }
}
