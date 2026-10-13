import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/push_zoom_motion.dart';
import 'package:morph/src/widgets/sheet_motion.dart';
import 'package:morph/src/widgets/zoom_source.dart';

/// What a page zoomed out of a source needs from its route.
@internal
abstract interface class MorphPushZoomHost {
  /// The source geometry and lifetime.
  MorphZoomSource get zoomFrom;

  /// The measured zoom.
  MorphPushZoomTuning get zoomTuning;

  /// Whether the page is the navigator's top route.
  bool get zoomIsCurrent;

  /// Whether a finger may drag the page toward a pop: false while the
  /// route would veto it ([PopScope] that cannot pop) or handles the pop
  /// internally.
  bool get zoomCanPop;

  /// Asks the navigator to pop the page; completes once it has decided,
  /// whether or not the page left.
  Future<void> zoomPop();

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
  late final MorphZoomSource _source = _host.zoomFrom;
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
    _sync.follow(frames);
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
    _sync.dispose();
    _host.attachZoomView(null);
    _pan.dispose();
    _source.reveal();
    super.dispose();
  }

  @override
  void advanceMotion(double t) {
    final motion = _motion;
    if (motion == null) return;
    motion.advance(t);
    if (!motion.isDragging && !motion.isOpening) {
      final source = _source.capture(context);
      if (source != null && source != motion.source) {
        motion.retargetEnds(t, source: source);
      }
    }
    if (_leaving && !_finished && motion.isClosed) {
      _finished = true;
      _source.reveal();
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
    final source = _source.capture(context) ?? motion.source;
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
    final rect = _source.capture(context);
    if (rect == null) {
      created.showInPlace(clock, page, page);
    } else {
      created.open(clock, rect, page);
      _source.hide();
    }
    _motion = created;
    wake();
  }

  void _pointerDown(PointerDownEvent event) {
    final motion = _motion;
    if (motion == null ||
        _leaving ||
        !_host.zoomIsCurrent ||
        !_host.zoomCanPop) {
      return;
    }
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
    if (motion.dragEnd(clock, velocity)) {
      unawaited(_host.zoomPop().then((_) => _stayed()));
    }
    wake();
  }

  /// Returns the page from the frame the finger left it in when the
  /// navigator vetoed the pop the drag asked for; otherwise the page would
  /// hold that frame and the clock would never settle.
  void _stayed() {
    final motion = _motion;
    if (!mounted || _leaving || motion == null || !motion.isDragging) return;
    // A drag restarted with zero travel ends on the return path, from where
    // the springs were snapped by the last move.
    motion.dragStart(clock, Offset.zero);
    motion.dragEnd(clock, Offset.zero);
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

  // The page builds only when it opens or leaves the open state.
  late final MorphFrameSync<bool?> _sync = MorphFrameSync<bool?>(
    structure: () => _motion?.isOpen,
    rebuild: (bool? _) => setState(() {}),
  );

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
        final motion = _motion!;
        final open = _sync.read()!;
        double t() => motion.time;
        Rect rect() => motion.isOpen ? Offset.zero & size : motion.rect(t());
        double radius() => motion.isOpen
            ? 0.0
            : math.max(
                0.0,
                motion.radius(
                  t(),
                  _source.radius(motion.source.size),
                  displayRadius,
                ),
              );
        return Listener(
          onPointerDown: _pointerDown,
          behavior: HitTestBehavior.translucent,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: MorphLiveColoredBox(
                    live: frames,
                    colorOf: () => Color.fromRGBO(
                      0,
                      0,
                      0,
                      motion.isOpen
                          ? 0
                          : tuning.dimmingOpacity * motion.dimming(t()),
                    ),
                  ),
                ),
              ),
              MorphLivePositionedTemplate(
                live: frames,
                template: () =>
                    Positioned.fromRect(rect: rect(), child: morphLiveSlot),
                child: MorphLiveOpacity(
                  live: frames,
                  opacityOf: () => _source.opacity(
                    motion.source == motion.page
                        ? motion.fade(t())
                        : motion.reach(t()),
                    closing: !motion.isOpening,
                  ),
                  child: MorphLiveTemplate(
                    live: frames,
                    template: () {
                      final dim = motion.dimming(t());
                      return DecoratedBox(
                        decoration: ShapeDecoration(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(radius()),
                          ),
                          shadows: [
                            if (!motion.isOpen && dim > 0)
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
                      );
                    },
                    child: MorphLiveTemplate(
                      live: frames,
                      template: () => ClipRRect(
                        clipper: MorphZoomShapeClipper(
                          RRect.fromRectAndRadius(
                            Offset.zero & rect().size,
                            Radius.circular(radius()),
                          ),
                        ),
                        clipBehavior: open ? Clip.none : Clip.antiAlias,
                      ),
                      child: _ZoomCrossfade(
                        frames: frames,
                        source: _source,
                        motion: motion,
                        open: open,
                        size: size,
                        rect: rect,
                        child: SizedBox.fromSize(
                          size: size,
                          child: widget.child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The page's content crossfaded with its source's look: the content and
/// the look's fade follow the motion on live render objects, and the
/// crossfade builds again only when the look appears, leaves or changes
/// size, or the source tag takes a new widget while the look shows.
class _ZoomCrossfade extends StatefulWidget {
  const _ZoomCrossfade({
    required this.frames,
    required this.source,
    required this.motion,
    required this.open,
    required this.size,
    required this.rect,
    required this.child,
  });

  final Listenable frames;
  final MorphZoomSource source;
  final MorphPushZoomMotion motion;
  final bool open;
  final Size size;
  final Rect Function() rect;
  final Widget child;

  @override
  State<_ZoomCrossfade> createState() => _ZoomCrossfadeState();
}

class _ZoomCrossfadeState extends State<_ZoomCrossfade> {
  late final MorphFrameSync<Object?> _sync = MorphFrameSync<Object?>(
    structure: _inputsNow,
    rebuild: (Object? _) => setState(() {}),
  );

  late Listenable _ticks = _ticksOf(widget);

  // A tag rebuild notifies during build, so the sync hears it in a
  // microtask and the replica takes the new widget on the next frame.
  static Listenable _ticksOf(_ZoomCrossfade widget) {
    final revisions = widget.source.revisions;
    return revisions == null
        ? widget.frames
        : Listenable.merge(<Listenable>[widget.frames, revisions]);
  }

  @override
  void initState() {
    super.initState();
    _sync.follow(_ticks);
  }

  @override
  void didUpdateWidget(_ZoomCrossfade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frames, widget.frames) ||
        !identical(oldWidget.source, widget.source)) {
      _ticks = _ticksOf(widget);
      _sync.follow(_ticks);
    }
  }

  @override
  void dispose() {
    _sync.dispose();
    super.dispose();
  }

  // The fade spring is critically damped and only nears 1, so an open page
  // counts as fully faded in: the source's replica leaves and the content
  // paints without an opacity layer.
  double get _fade =>
      widget.motion.isOpen ? 1.0 : widget.motion.fade(widget.motion.time);

  bool get _closing => !widget.motion.isOpening;

  Object? _inputsNow() {
    final size = widget.motion.source.size;
    return (size, widget.source.look(_fade, size));
  }

  @override
  Widget build(BuildContext context) {
    _sync.read();
    final frames = widget.frames;
    final motion = widget.motion;
    final size = widget.size;
    return widget.source.crossfade(
      live: frames,
      fadeOf: () => _fade,
      size: motion.source.size,
      content: MorphLivePositionedTemplate(
        live: frames,
        template: () => Positioned(
          left: (widget.rect().width - size.width) / 2,
          top: 0,
          width: size.width,
          height: size.height,
          child: morphLiveSlot,
        ),
        child: MorphLiveTransform.matrix(
          live: frames,
          alignment: Alignment.topCenter,
          matrixOf: () {
            final scale = motion.isOpen
                ? 1.0
                : motion.contentScale(motion.time);
            return Matrix4.diagonal3Values(scale, scale, 1);
          },
          child: IgnorePointer(
            ignoring: !widget.open,
            child: MorphLiveOpacity(
              live: frames,
              opacityOf: () => widget.source.isLost && _closing ? 1 : _fade,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

double _blurRadius(double sigma) => (sigma - 0.5) / 0.57735;

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
