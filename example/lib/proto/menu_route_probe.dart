import 'dart:async';
import 'dart:developer' show Timeline;

import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/motion.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/menu_motion.dart'
    show morphMenuSetCloseAdmission;
import 'package:morph_example/proto/menu_transfer_probe.dart';
import 'package:morph_example/proto/motion_clock_probe.dart';

/// A command or frame observed by the independent replay model.
enum ProbeMenuSampleKind {
  /// A frame sample.
  frame,

  /// A raw pointer command.
  pointer,

  /// Input that does not belong to the session's current interaction.
  ignoredPointer,

  /// A model interaction revoked independently of binding pointer delivery.
  cancelInput,

  /// An explicit programmatic open.
  open,

  /// An explicit programmatic close.
  close,
}

/// An input's canonical time and resulting frame, including delayed input.
typedef ProbeMenuSample = ({
  ProbeMenuSampleKind kind,
  double time,
  PointerEvent? event,
  ProbeMenuFrame frame,
});

/// A reduced source/menu pair for Navigator ownership experiments.
class ProbeMenuSource extends StatefulWidget {
  /// Uses fixed geometry so the experiment isolates route and clock lifetime.
  const ProbeMenuSource({
    required this.menuBuilder,
    this.button = const Rect.fromLTWH(24, 80, 44, 44),
    this.bounds = const Size(402, 874),
    this.now,
    this.pointerInput = false,
    this.pointerOffset,
    this.createMotion,
    this.onSample,
    this.neighbors = const [],
    super.key,
  });

  /// Builds stable menu content in the root route.
  final WidgetBuilder menuBuilder;

  /// The source's rectangle in root navigator coordinates.
  final Rect button;

  /// The fixed available presentation size.
  final Size bounds;

  /// Engine-clock time at input delivery; tests supply their fake clock.
  final Duration Function()? now;

  /// Runs measured pointer behavior instead of opening on a recognized tap.
  final bool pointerInput;

  /// Converts recorded pointer timestamps onto the engine clock.
  final Duration? Function()? pointerOffset;

  /// Creates a fixed-geometry model matching a recording's configuration.
  final MorphMenuMotion Function()? createMotion;

  /// Observes commands and every model sample for replay comparison.
  final ValueChanged<ProbeMenuSample>? onSample;

  /// Fixed neighboring capsules in the reduced bar scene.
  final List<RRect> neighbors;

  @override
  State<ProbeMenuSource> createState() => ProbeMenuSourceState();
}

/// Source controls and observations for the P2 host harness.
class ProbeMenuSourceState extends State<ProbeMenuSource>
    with SingleTickerProviderStateMixin {
  late final _MenuSession _session;

  /// The complete model's most recent sampled frame.
  ProbeMenuFrame get frame => _session.transfer.frame;

  /// Whether the source currently owns the model.
  bool get ownsMotion => identical(_session.transfer.owner, _session.source);

  /// Whether every model channel is at rest.
  bool get motionSettled => _session.transfer.isSettled;

  /// How many frames the source clock has sampled.
  int get motionFrames => _session.sourceFrames;

  /// The route currently holding the model, if any.
  ProbeMenuRoute? get activeRoute => _session.activeRoute;

  @override
  void initState() {
    super.initState();
    _session = _MenuSession(this, widget);
    _session.present = open;
    _session.sourceEligible = _sourceCanAcquire;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session.updateSourceView(View.of(context).viewId);
  }

  bool _sourceCanAcquire() {
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    var eligible = true;
    context.visitAncestorElements((element) {
      if (element is StatefulElement &&
          element.state is NavigatorState &&
          ModalRoute.of(element)?.isCurrent == false) {
        eligible = false;
        return false;
      }
      return true;
    });
    return eligible;
  }

  /// Opens on the root navigator, or reverses the current closing owner.
  ProbeMenuRoute open() {
    final current = _session.activeRoute;
    if (current != null && !current.closing) return current;
    final route = ProbeMenuRoute._(_session, widget.menuBuilder);
    unawaited(Navigator.of(context, rootNavigator: true).push<void>(route));
    return route;
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: .expand,
    children: [
      IgnorePointer(
        child: CustomPaint(painter: _MenuPainter(_session, _session.source)),
      ),
      Positioned.fromRect(
        rect: widget.button,
        child: widget.pointerInput
            ? Listener(
                behavior: .opaque,
                onPointerDown: (event) {
                  _session.handlePointer(event, sourceHit: true);
                  // Push before Navigator's ancestor Listener records this down.
                  if (_session.activeRoute == null &&
                      _session._pointer?.matches(event) == true) {
                    open();
                  }
                },
              )
            : GestureDetector(behavior: .opaque, onTap: open),
      ),
    ],
  );

  @override
  void dispose() {
    _session.detachSource();
    super.dispose();
  }
}

class _MenuSession {
  _MenuSession(TickerProvider vsync, ProbeMenuSource widget)
    : button = widget.button,
      bounds = widget.bounds,
      pointerInput = widget.pointerInput,
      now = widget.now ?? _engineNow,
      pointerOffset = widget.pointerOffset ?? _unknownOffset,
      createMotion = widget.createMotion,
      neighbors = List.unmodifiable(widget.neighbors),
      onSample = widget.onSample {
    transfer = _newMotion();
    sourceClock = ProbeMotionClock(
      vsync: vsync,
      now: now,
      pointerOffset: pointerOffset,
      onFrame: (time) {
        if (!advance(source, time)) {
          return (settled: true, wakeTime: null);
        }
        sourceFrames++;
        emit(.frame);
        syncInputPhase();
        frames.value++;
        return (
          settled: !identical(transfer.owner, source) || transfer.isSettled,
          wakeTime: null,
        );
      },
    );
    if (pointerInput) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(handlePointer);
    }
  }

  final Rect button;
  final Size bounds;
  final Duration Function() now;
  final bool pointerInput;
  final Duration? Function() pointerOffset;
  final MorphMenuMotion Function()? createMotion;
  final ValueChanged<ProbeMenuSample>? onSample;
  final List<RRect> neighbors;
  VoidCallback? present;
  bool Function()? sourceEligible;
  _PointerSequence? _pointer;
  int? _viewId;
  int _modelDepth = 0;
  ProbeMenuTransfer? _cancelAfterCommand;
  final source = ProbeMenuLease(.source);
  final frames = ValueNotifier<int>(0);
  final _routes = <ProbeMenuRoute>{};
  late ProbeMenuTransfer transfer;
  ProbeMotionClock? sourceClock;
  ProbeMenuRoute? activeRoute;
  int sourceFrames = 0;
  MorphMenuMotion? _admittedMotion;
  final _closeRequests =
      <({ProbeMenuRoute route, bool admitted, double time})>[];

  T command<T>(T Function() operation) {
    _modelDepth++;
    try {
      return operation();
    } finally {
      _modelDepth--;
      if (_modelDepth == 0) _drainPointerCancel();
    }
  }

  bool advance(ProbeMenuLease lease, double time) {
    final target = transfer;
    final advanced = command(() => target.advance(lease, time));
    return advanced &&
        identical(target, transfer) &&
        identical(target.owner, lease);
  }

  void updateSourceView(int viewId) {
    if (_viewId != null && _viewId != viewId) _revokePointer();
    _viewId = viewId;
  }

  bool get _menuCanAcquire {
    final route = activeRoute;
    return route != null &&
        !route.closing &&
        !route.disposed &&
        route.isCurrent;
  }

  bool get _sourceCanContinue {
    final route = activeRoute;
    return (route == null || (route.closing && route._revealed.value)) &&
        (sourceEligible?.call() ?? false);
  }

  void revokePointerFor(ProbeMenuRoute route) {
    if (identical(activeRoute, route)) _revokePointer();
  }

  void _revokePointer() {
    if (_pointer == null) return;
    _pointer = null;
    _cancelAfterCommand = transfer;
    if (_modelDepth == 0) _drainPointerCancel();
  }

  void _drainPointerCancel() {
    final target = _cancelAfterCommand;
    _cancelAfterCommand = null;
    if (target == null || !identical(target, transfer)) return;
    command(() => target.cancelPointer(target.owner));
    if (!identical(target, transfer)) return;
    emit(.cancelInput);
    if (!identical(target, transfer)) return;
    final route = activeRoute;
    if (route != null && !route.disposed) {
      route._clock.resumeAt(now());
    } else {
      sourceClock?.resumeAt(now());
    }
  }

  ProbeMenuTransfer _newMotion() {
    final previous = _admittedMotion;
    if (previous != null) morphMenuSetCloseAdmission(previous, null);
    final motion =
        createMotion?.call() ??
        MorphMenuMotion(
          button: button,
          bounds: bounds,
          itemCount: 3,
          sourceHeight: 64,
          sourceRadius: 22,
        );
    if (pointerInput) {
      _admittedMotion = motion;
      morphMenuSetCloseAdmission(motion, (time) {
        final route = activeRoute;
        if (route == null || route.closing || !route.isCurrent) return false;
        if (route._deferDismissal(time)) return false;
        route.closeRequestedAt = time;
        final admitted = route.popDisposition == RoutePopDisposition.pop;
        _closeRequests.add((route: route, admitted: admitted, time: time));
        return admitted && !route.willHandlePopInternally;
      });
    }
    return ProbeMenuTransfer(
      motion: motion,
      source: source,
      sourceTime: sourceClock?.time ?? 0,
    );
  }

  void acquire(ProbeMenuRoute route) {
    final previous = activeRoute;
    final previousClock = previous?._clock ?? sourceClock!;
    final lease = transfer.owner;
    if (!pointerInput) {
      command(() => transfer.open(lease, previousClock.time));
      emit(.open);
    }
    command(
      () => transfer.transfer(
        lease,
        fromTime: previousClock.time,
        to: route._lease,
        toTime: 0,
      ),
    );
    previousClock.pause();
    _routes.add(route);
    activeRoute = route;
    previous?._relinquish();
    route._clock.resumeAt(now());
    frames.value++;
  }

  bool land(ProbeMenuRoute route, double localTime) {
    final clock = sourceClock;
    if (clock == null) return false;
    final before = transfer.frame;
    final anchor = clock.resumeAt(
      SchedulerBinding.instance.currentSystemFrameTimeStamp,
    );
    command(
      () => transfer.transfer(
        route._lease,
        fromTime: localTime,
        to: source,
        toTime: anchor,
      ),
    );
    route.handBack = (before: before, after: transfer.frame);
    activeRoute = null;
    frames.value++;
    return true;
  }

  void detachSource() {
    present = null;
    sourceEligible = null;
    sourceClock!.dispose();
    sourceClock = null;
    _disposeIfUnused();
  }

  void routeDisposed(ProbeMenuRoute route) {
    _routes.remove(route);
    if (identical(activeRoute, route)) {
      activeRoute = null;
      _pointer = null;
      if (sourceClock != null) {
        // Forced removal skips visual closing, as Navigator.removeRoute does.
        transfer = _newMotion();
        frames.value++;
      }
    }
    _disposeIfUnused();
  }

  void _disposeIfUnused() {
    if (sourceClock == null && _routes.isEmpty) {
      final motion = _admittedMotion;
      if (motion != null) {
        morphMenuSetCloseAdmission(motion, null);
        _admittedMotion = null;
      }
      if (pointerInput) {
        GestureBinding.instance.pointerRouter.removeGlobalRoute(handlePointer);
      }
      frames.dispose();
    }
  }

  void emit(ProbeMenuSampleKind kind, {PointerEvent? event, double? time}) {
    onSample?.call((
      kind: kind,
      time: time ?? transfer.frame.time,
      event: event,
      frame: transfer.frame,
    ));
  }

  void syncInputPhase() {
    if (!pointerInput) return;
    final requests = List.of(_closeRequests);
    _closeRequests.clear();
    for (final request in requests) {
      final route = request.route;
      if (!identical(activeRoute, route) || route.closing || !route.isCurrent) {
        continue;
      }
      if (request.admitted) {
        route._admittedCloseTime = transfer.isClosing ? request.time : null;
        route.navigator!.pop();
      } else {
        route.onPopInvokedWithResult(false, null);
      }
    }
    activeRoute?._drainDismissal();
    final route = activeRoute;
    if (transfer.isOpen) {
      if (route == null || route.closing) {
        present?.call();
      } else {
        route._reveal();
      }
    } else if (route != null &&
        !route._revealed.value &&
        !transfer.isArming &&
        !transfer.isPresented &&
        !route.closing) {
      route.navigator!.pop();
    }
    activeRoute?._updatePendingBarrier();
  }

  void handlePointer(PointerEvent event, {bool sourceHit = false}) {
    final route = activeRoute;
    if (route != null && route.closing && !route._revealed.value) {
      if (_pointer?.matches(event) == true &&
          (event is PointerUpEvent || event is PointerCancelEvent)) {
        _pointer = null;
      }
      emit(.ignoredPointer, event: event);
      return;
    }
    if (event is PointerDownEvent) {
      if (_pointer != null || event.buttons != kPrimaryButton) return;
      if (event.viewId != _viewId ||
          (!_menuCanAcquire && !(sourceHit && _sourceCanContinue))) {
        emit(.ignoredPointer, event: event);
        return;
      }
      _pointer = _PointerSequence(event.pointer, event.viewId);
    } else if (_pointer?.matches(event) != true) {
      if (event is PointerMoveEvent ||
          event is PointerUpEvent ||
          event is PointerCancelEvent) {
        emit(.ignoredPointer, event: event);
      }
      return;
    }
    final sequence = _pointer!;
    if (!_menuCanAcquire && !_sourceCanContinue) {
      _revokePointer();
      emit(.ignoredPointer, event: event);
      return;
    }
    final clock = activeRoute?._clock ?? sourceClock;
    if (clock == null) return;
    final local = clock.stamp(event);
    final target = transfer;
    final lease = target.owner;
    final time = command(() {
      target.advance(lease, local);
      if (!identical(target, transfer) ||
          !identical(target.owner, lease) ||
          !identical(_pointer, sequence) ||
          (!_menuCanAcquire && !_sourceCanContinue)) {
        return null;
      }
      final time = target.pointer(lease, local, event);
      if (!identical(target, transfer) ||
          !identical(target.owner, lease) ||
          !identical(_pointer, sequence) ||
          (!_menuCanAcquire && !_sourceCanContinue)) {
        return null;
      }
      if (time != null) emit(.pointer, event: event, time: time);
      return time;
    });
    if ((event is PointerUpEvent || event is PointerCancelEvent) &&
        identical(_pointer, sequence)) {
      _pointer = null;
    }
    if (time == null) {
      emit(.ignoredPointer, event: event);
      return;
    }
    if (!identical(target, transfer)) return;
    syncInputPhase();
    frames.value++;
  }
}

class _PointerSequence {
  _PointerSequence(this.pointer, this.viewId);

  final int pointer;
  final int viewId;

  bool matches(PointerEvent event) =>
      event.pointer == pointer && event.viewId == viewId;
}

class _DismissAttempt {
  _DismissAttempt(
    this.requestedAt, {
    required this.fromModel,
    this.consultPolicy = true,
  });

  final double requestedAt;
  final bool consultPolicy;
  bool fromModel;
  Completer<RoutePopDisposition>? permission;
  Completer<bool>? firstMount;
  bool approved = false;
  bool claimed = false;
}

/// A real PopupRoute driven by the same menu model the source later resumes.
class ProbeMenuRoute extends PopupRoute<void> {
  ProbeMenuRoute._(this._session, this._builder)
    : _revealed = ValueNotifier(!_session.pointerInput);

  final _MenuSession _session;
  final WidgetBuilder _builder;
  final _lease = ProbeMenuLease(.route);
  final _projection = _MenuAnimation();
  final _pushSignal = Ticker((_) {});
  final ValueNotifier<bool> _revealed;
  bool _pendingBarrier = false;
  double? _admittedCloseTime;
  Route<Object?>? _nextRoute;
  _DismissAttempt? _dismissal;
  _MountedMenuPolicyState? _policyMount;
  late final ProbeMotionClock _clock;

  /// Whether logical pop has started closing this presentation.
  bool closing = false;

  /// Whether Navigator has disposed this route.
  bool disposed = false;

  /// How many model samples this route has written.
  int motionFrames = 0;

  /// How many times the route content page was built.
  int pageBuilds = 0;

  /// The frame on each side of the ownership change, before any next tick.
  ({ProbeMenuFrame before, ProbeMenuFrame after})? handBack;

  /// The shared model's latest frame, including the source's landing tail.
  ProbeMenuFrame get frame => _session.transfer.frame;

  /// The canonical model time at logical closing.
  double? closedAt;

  /// The canonical time of the latest request to consult presentation policy.
  double? closeRequestedAt;

  /// Whether this close was committed after waiting for SDK permission.
  bool deferredClose = false;

  bool get _policyReady => _policyMount?._ready ?? false;

  bool _isLive(_DismissAttempt request) =>
      identical(_dismissal, request) &&
      !disposed &&
      !closing &&
      navigator?.mounted == true &&
      isCurrent &&
      identical(_session.activeRoute, this) &&
      identical(_session.transfer.owner, _lease);

  bool _deferDismissal(double time) {
    final current = _dismissal;
    if (current != null) {
      current.fromModel = true;
      return true;
    }
    if (_policyReady && !hasScopedWillPopCallback) return false;
    closeRequestedAt = time;
    _dismissal = _DismissAttempt(time, fromModel: true);
    return true;
  }

  void _drainDismissal() {
    final request = _dismissal;
    if (request != null && request.permission == null && _isLive(request)) {
      unawaited(willPop());
    }
  }

  @override
  Future<RoutePopDisposition> willPop() async {
    final request = _dismissal ??= _DismissAttempt(
      frame.time,
      fromModel: false,
      consultPolicy: _revealed.value || _session.transfer.isOpen,
    );
    closeRequestedAt = request.requestedAt;
    if (!_isLive(request)) {
      _invalidateDismissal();
      return RoutePopDisposition.doNotPop;
    }
    final current = request.permission;
    final permission = current ?? Completer<RoutePopDisposition>();
    if (current == null) {
      request.permission = permission;
      unawaited(_resolvePermission(request, permission));
    }
    final answer = await permission.future;
    if (answer != RoutePopDisposition.pop) return answer;
    if (!_isLive(request) || request.claimed) {
      return RoutePopDisposition.doNotPop;
    }
    request.claimed = true;
    return RoutePopDisposition.pop;
  }

  Future<void> _resolvePermission(
    _DismissAttempt request,
    Completer<RoutePopDisposition> permission,
  ) async {
    var result = RoutePopDisposition.doNotPop;
    try {
      if (request.consultPolicy && !_policyReady) {
        final mounted = request.firstMount ??= Completer<bool>();
        if (!await mounted.future || !_isLive(request)) return;
      }
      final answer = request.consultPolicy
          ? await super.willPop()
          : RoutePopDisposition.pop;
      if (_isLive(request)) {
        if (answer == RoutePopDisposition.doNotPop) {
          _invalidateDismissal();
        } else {
          result = popDisposition;
          if (result == RoutePopDisposition.pop) {
            request.approved = true;
            if (request.fromModel) _clock.resumeAt(_session.now());
          } else {
            _invalidateDismissal();
            if (result == RoutePopDisposition.doNotPop) {
              onPopInvokedWithResult(false, null);
            }
          }
        }
      }
    } on Object catch (error, stack) {
      if (_isLive(request)) _invalidateDismissal();
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'morph P2 prototype',
          context: ErrorDescription('while awaiting menu dismissal permission'),
        ),
      );
    }
    if (!permission.isCompleted) permission.complete(result);
  }

  void _consumeApprovedDismissal() {
    final request = _dismissal;
    if (request == null || !request.approved || !request.fromModel) return;
    if (!_isLive(request)) {
      _invalidateDismissal();
      return;
    }
    final disposition = popDisposition;
    if (disposition == RoutePopDisposition.pop) {
      navigator!.pop();
    } else {
      _invalidateDismissal();
      if (disposition == RoutePopDisposition.doNotPop) {
        onPopInvokedWithResult(false, null);
      }
    }
  }

  void _invalidateDismissal() {
    final request = _dismissal;
    _dismissal = null;
    final firstMount = request?.firstMount;
    if (firstMount != null && !firstMount.isCompleted) {
      firstMount.complete(false);
    }
    final permission = request?.permission;
    if (permission != null && !permission.isCompleted) {
      permission.complete(RoutePopDisposition.doNotPop);
    }
  }

  @override
  void onPopInvokedWithResult(bool didPop, void result) {
    if (!didPop) _invalidateDismissal();
    super.onPopInvokedWithResult(didPop, result);
  }

  @override
  void didChangeNext(Route<Object?>? nextRoute) {
    if (!identical(_nextRoute, nextRoute)) {
      _nextRoute = nextRoute;
      _invalidateDismissal();
      if (nextRoute != null) _session.revokePointerFor(this);
    }
    super.didChangeNext(nextRoute);
  }

  @override
  void didPopNext(Route<Object?> nextRoute) {
    _nextRoute = null;
    _invalidateDismissal();
    super.didPopNext(nextRoute);
  }

  @override
  bool get requestFocus => !disposed && _revealed.value;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  bool get finishedWhenPopped => false;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  String get barrierLabel => 'Dismiss prototype menu';

  @override
  Animation<double> createAnimation() => _projection;

  @override
  void install() {
    super.install();
    _clock = ProbeMotionClock(
      vsync: navigator!,
      now: _session.now,
      pointerOffset: _session.pointerOffset,
      onFrame: _sample,
    );
  }

  @override
  TickerFuture didPush() {
    super.didPush();
    _pushSignal.muted = true;
    final signal = _pushSignal.start();
    _session.acquire(this);
    if (_session.transfer.isOpen) _reveal();
    _projection.update(frame.progress, .forward);
    return signal;
  }

  @override
  bool didPop(void result) {
    final approved = _dismissal?.approved ?? false;
    _invalidateDismissal();
    final popped = super.didPop(result);
    if (!popped) return false;
    _session._pointer = null;
    closing = true;
    deferredClose = approved;
    _pushSignal.stop(canceled: false);
    final modelClosing = _session.transfer.isClosing;
    if (!modelClosing) {
      _session.command(() => _session.transfer.close(_lease, _clock.time));
      _session.emit(.close);
    }
    closedAt = _admittedCloseTime ?? frame.time;
    _projection.update(frame.progress, .reverse);
    if (!modelClosing) _clock.resumeAt(_session.now());
    return true;
  }

  ProbeFrameOutcome _sample(double time) {
    if (!_session.advance(_lease, time) ||
        disposed ||
        !identical(_session.transfer.owner, _lease)) {
      return (settled: true, wakeTime: null);
    }
    motionFrames++;
    _session.emit(.frame);
    _session.syncInputPhase();
    _consumeApprovedDismissal();
    if (!identical(_session.transfer.owner, _lease)) {
      return (settled: true, wakeTime: null);
    }
    final settled = _session.transfer.isSettled;
    if (!_revealed.value && !closing) {
      _projection.update(0, .forward);
      _session.frames.value++;
      return (settled: settled, wakeTime: null);
    }
    if (closing &&
        ((_session.transfer.readyToHandBack && _session.land(this, time)) ||
            settled)) {
      _projection.update(0, .dismissed);
      return (settled: true, wakeTime: null);
    }
    _projection.update(
      settled ? 1 : frame.progress,
      closing ? .reverse : (settled ? .completed : .forward),
    );
    _session.frames.value++;
    if (settled) _pushSignal.stop(canceled: false);
    return (settled: settled, wakeTime: null);
  }

  void _relinquish() {
    _invalidateDismissal();
    _pushSignal.stop(canceled: false);
    _projection.update(0, .dismissed);
  }

  void _reveal() {
    if (_revealed.value) return;
    _revealed.value = true;
    changedInternalState();
  }

  void _updatePendingBarrier() {
    final armed = _session.transfer.isOpenPending;
    if (_pendingBarrier == armed) return;
    _pendingBarrier = armed;
    changedInternalState();
  }

  Widget _inputGate(Widget child) =>
      _session.pointerInput ? _MenuHitGate(route: this, child: child) : child;

  @override
  Widget buildModalBarrier() => _inputGate(
    _session.pointerInput
        ? IgnorePointer(
            ignoring: !_revealed.value && !_pendingBarrier,
            child: ModalBarrier(
              dismissible: false,
              semanticsLabel: barrierLabel,
            ),
          )
        : super.buildModalBarrier(),
  );

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    pageBuilds++;
    return _inputGate(
      Stack(
        fit: .expand,
        children: [
          IgnorePointer(
            child: CustomPaint(painter: _MenuPainter(_session, _lease)),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _revealed,
            builder: (context, revealed, _) => revealed
                ? Flow(
                    delegate: _MenuContentFlow(_session, _lease),
                    children: [
                      _MountedMenuPolicy(route: this, builder: _builder),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    disposed = true;
    _invalidateDismissal();
    _clock.dispose();
    _pushSignal.dispose();
    super.dispose();
    _projection.dispose();
    _revealed.dispose();
    _session.routeDisposed(this);
  }
}

class _MenuHitGate extends SingleChildRenderObjectWidget {
  const _MenuHitGate({required this.route, required super.child});

  final ProbeMenuRoute route;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MenuHitGateRender(route);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _MenuHitGateRender renderObject,
  ) => renderObject.route = route;
}

class _MenuHitGateRender extends RenderProxyBox {
  _MenuHitGateRender(this.route);

  ProbeMenuRoute route;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !route.closing &&
      !route.disposed &&
      super.hitTest(result, position: position);
}

class _MountedMenuPolicy extends StatefulWidget {
  const _MountedMenuPolicy({required this.route, required this.builder});

  final ProbeMenuRoute route;
  final WidgetBuilder builder;

  @override
  State<_MountedMenuPolicy> createState() => _MountedMenuPolicyState();
}

class _MountedMenuPolicyState extends State<_MountedMenuPolicy> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    widget.route._policyMount = this;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = widget.route;
      if (!mounted || !identical(route._policyMount, this)) return;
      _ready = true;
      final request = route._dismissal;
      final firstMount = request?.firstMount;
      if (request != null &&
          route._isLive(request) &&
          firstMount != null &&
          !firstMount.isCompleted) {
        firstMount.complete(true);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);

  @override
  void dispose() {
    final route = widget.route;
    if (identical(route._policyMount, this)) {
      route._policyMount = null;
      route._invalidateDismissal();
    }
    super.dispose();
  }
}

class _MenuPainter extends CustomPainter {
  _MenuPainter(this.session, this.lease) : super(repaint: session.frames);

  final _MenuSession session;
  final ProbeMenuLease lease;

  @override
  void paint(Canvas canvas, Size size) {
    if (!identical(session.transfer.owner, lease)) return;
    final frame = session.transfer.frame;
    final paint = Paint();
    paint.color = const Color(0xFF8888AA);
    final bar = morphGlassContainerOutline(
      [...session.neighbors, frame.button],
      12,
      withField: false,
    ).path;
    final carried = session.transfer.flatOutline;
    final path = carried == null
        ? bar
        : Path.combine(.union, bar, carried.path);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MenuPainter oldDelegate) =>
      session != oldDelegate.session || lease != oldDelegate.lease;
}

class _MenuContentFlow extends FlowDelegate {
  _MenuContentFlow(this.session, this.lease) : super(repaint: session.frames);

  final _MenuSession session;
  final ProbeMenuLease lease;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      const BoxConstraints.tightFor(width: 250, height: 146);

  @override
  void paintChildren(FlowPaintingContext context) {
    if (!identical(session.transfer.owner, lease)) return;
    final frame = session.transfer.frame;
    final rect = frame.menu.outerRect;
    final size = context.getChildSize(0)!;
    final matrix = Matrix4.translationValues(rect.left, rect.top, 0);
    matrix.scaleByDouble(
      rect.width / size.width,
      rect.height / size.height,
      1,
      1,
    );
    context.paintChild(
      0,
      transform: matrix,
      opacity: frame.contentOpacity.clamp(0.0, 1.0),
    );
  }

  @override
  bool shouldRepaint(_MenuContentFlow oldDelegate) =>
      session != oldDelegate.session || lease != oldDelegate.lease;
}

class _MenuAnimation extends Animation<double> with ChangeNotifier {
  final _statuses = <AnimationStatusListener>[];
  double _value = 0;
  AnimationStatus _status = .dismissed;

  @override
  double get value => _value;

  @override
  AnimationStatus get status => _status;

  @override
  void addStatusListener(AnimationStatusListener listener) =>
      _statuses.add(listener);

  @override
  void removeStatusListener(AnimationStatusListener listener) =>
      _statuses.remove(listener);

  void update(double value, AnimationStatus status) {
    final next = value.clamp(0.0, 1.0);
    final changed = next != _value;
    final statusChanged = status != _status;
    _value = next;
    _status = status;
    if (changed) notifyListeners();
    if (statusChanged) {
      for (final listener in List.of(_statuses)) {
        listener(status);
      }
    }
  }
}

Duration _engineNow() => Duration(microseconds: Timeline.now);

Duration? _unknownOffset() => null;

// ignore_for_file: implementation_imports, invalid_use_of_internal_member, deprecated_member_use
