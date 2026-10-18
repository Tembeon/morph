import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:math' as math;
import 'dart:ui' as ui;

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
    this.semanticLabel = 'Open prototype menu',
    this.menuSemanticLabel = 'Prototype menu',
    super.key,
  }) : _measured = false,
       sourceHeight = 64,
       sourceRadius = 22,
       onMotionReady = null;

  /// Measures a source-local button into its root overlay before interaction.
  ///
  /// Supports positive uniform scale and translation. System safe area and
  /// keyboard edges are projected from the presentation View into the overlay.
  /// Observed active placement changes retire the endpoint rather than retargeting.
  const ProbeMenuSource.measured({
    required this.menuBuilder,
    this.button = const Rect.fromLTWH(24, 80, 44, 44),
    this.sourceHeight = 64,
    this.sourceRadius = 22,
    this.onMotionReady,
    this.now,
    this.pointerInput = false,
    this.pointerOffset,
    this.onSample,
    this.semanticLabel = 'Open prototype menu',
    this.menuSemanticLabel = 'Prototype menu',
    super.key,
  }) : _measured = true,
       bounds = const Size(402, 874),
       neighbors = const [],
       createMotion = null;

  final bool _measured;

  /// The local height from which the menu shape grows.
  final double sourceHeight;

  /// The resting source's local corner radius.
  final double sourceRadius;

  /// Configures a measured model once, after safe geometry admission.
  ///
  /// Runs before the first interaction command. Admission during build, layout
  /// or painting is rejected before this callback.
  final ValueChanged<MorphMenuMotion>? onMotionReady;

  /// Builds content in the popup context with the source's local themes.
  ///
  /// Theme values follow the source within its root/View attachment while
  /// captured theme kinds and wrap topology stay stable. A detached popup keeps
  /// its last capture. New theme kinds apply to the next presentation.
  /// Other inherited values come from the root route.
  final WidgetBuilder menuBuilder;

  /// The accessible name of the source button.
  final String semanticLabel;

  /// The accessible name of the presented menu route.
  final String menuSemanticLabel;

  /// The button in root-overlay coordinates for fixed mode, source-local when measured.
  final Rect button;

  /// The fixed-mode presentation size; measured mode uses the actual overlay.
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
    with TickerProviderStateMixin {
  _MenuSession? _current;
  bool _elementActive = true;

  _MenuSession get _session =>
      _current ?? (throw StateError('Menu source attachment is changing.'));

  _MenuAffinity _readAffinity() {
    final navigator = Navigator.of(context, rootNavigator: true);
    return _MenuAffinity(
      navigator,
      View.of(context),
      View.of(navigator.overlay!.context),
    );
  }

  bool _isAttached(_MenuSession session) =>
      mounted &&
      _elementActive &&
      identical(_current, session) &&
      session.affinity.canPresent &&
      session.affinity.sameSpace(_readAffinity());

  void _refreshAttachment() {
    if (!mounted || !_elementActive) {
      throw StateError('Menu source is not attached to an active element.');
    }
    final affinity = _readAffinity();
    if (_current?.affinity.sameSpace(affinity) ?? false) return;
    final previous = _current;
    _current = null;
    previous?.detachSource();
    final session = _MenuSession(this, widget, affinity);
    _current = session;
    session.sourceAttached = () => _isAttached(session);
    if (widget._measured) {
      session.readGeometry = () => _readGeometry(session);
      session.loseGeometry = () => _loseGeometry(session);
    }
    session.sourceEligible = ({coveredRoot}) =>
        _sourceCanAcquire(session, coveredRoot: coveredRoot);
    session.present = () {
      if (_isAttached(session)) _prepare(session);
    };
  }

  _MenuGeometry? _readGeometry(_MenuSession session) {
    if (!_isAttached(session)) return null;
    final source = context.findRenderObject();
    final overlay = session.affinity.navigator.overlay?.context
        .findRenderObject();
    if (source is! RenderBox ||
        overlay is! RenderBox ||
        !source.attached ||
        !overlay.attached ||
        !source.hasSize ||
        !overlay.hasSize ||
        !source.size.isFinite ||
        !overlay.size.isFinite ||
        source.size.isEmpty ||
        overlay.size.isEmpty) {
      return null;
    }
    var offstage = false;
    context.visitAncestorElements((element) {
      if (element.widget case Offstage(offstage: true)) {
        offstage = true;
        return false;
      }
      return true;
    });
    if (offstage) return null;
    final map = _UniformMap.read(source.getTransformTo(overlay));
    final overlayMap = _UniformMap.read(overlay.getTransformTo(null));
    if (map == null || overlayMap == null) return null;
    final button = map.rect(widget.button);
    if (!button.isFinite ||
        button.isEmpty ||
        !widget.sourceHeight.isFinite ||
        widget.sourceHeight <= 0 ||
        !widget.sourceRadius.isFinite ||
        widget.sourceRadius < 0 ||
        !(widget.sourceHeight * map.scale).isFinite ||
        !(widget.sourceRadius * map.scale).isFinite) {
      return null;
    }
    final tuning = session._motion.tuning;
    final available = _admitMenuPlacement(
      session.affinity.presentationView,
      overlay.size,
      overlayMap,
      button: button,
      minimum: Size(
        tuning.menuWidth,
        tuning.rowHeight + 2 * tuning.verticalPadding,
      ),
    );
    if (available == null) return null;
    return _MenuGeometry(
      source,
      overlay,
      map,
      button,
      overlay.size,
      available,
      widget.sourceHeight * map.scale,
      widget.sourceRadius * map.scale,
    );
  }

  void _loseGeometry(_MenuSession session) {
    if (!identical(_current, session)) return;
    _current = null;
    scheduleMicrotask(() {
      if (!mounted || !_elementActive || _current != null) return;
      _refreshAttachment();
      setState(() {});
    });
    session.detachSource();
  }

  /// The model's most recent frame, nominal source-local before measured admission.
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshAttachment();
    final session = _session;
    if (session._routes.isEmpty) return;
    final navigator = session.affinity.navigator;
    final themes = _captureThemes(navigator);
    for (final route in session._routes) {
      if (identical(route.navigator, navigator)) route._queueThemes(themes);
    }
  }

  @override
  void deactivate() {
    _elementActive = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _elementActive = true;
  }

  _SourceThemes _captureThemes(NavigatorState navigator) {
    final themes = <InheritedTheme>[];
    final kinds = <Type>{};
    context.visitAncestorElements((element) {
      if (identical(element, navigator.context)) return false;
      if (element case InheritedElement(widget: final InheritedTheme theme)) {
        if (kinds.add(theme.runtimeType)) {
          context.dependOnInheritedElement(element);
          themes.add(theme);
        }
      }
      return true;
    });
    return _SourceThemes(
      InheritedTheme.capture(from: context, to: navigator.context),
      List.unmodifiable(themes),
    );
  }

  bool _sourceCanAcquire(
    _MenuSession session, {
    ModalRoute<Object?>? coveredRoot,
  }) {
    if (!_isAttached(session)) return false;
    final retainedRoot = coveredRoot?.isActive == true ? coveredRoot : null;
    final local = ModalRoute.of(context);
    if (local?.isCurrent == false && !identical(local, retainedRoot)) {
      return false;
    }
    var eligible = true;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is NavigatorState) {
        final route = ModalRoute.of(element);
        if (route != null &&
            !route.isCurrent &&
            !identical(route, retainedRoot)) {
          eligible = false;
          return false;
        }
      }
      return true;
    });
    return eligible;
  }

  /// Opens on the root navigator, or reverses the current closing owner.
  ///
  /// Throws [StateError] before pushing when the source is unattached or its
  /// FlutterView differs from the root overlay's View. Measured mode also
  /// rejects unavailable or unsupported geometry and build/layout/paint calls.
  ProbeMenuRoute open() {
    if (_current == null) {
      throw StateError('Menu source attachment is changing.');
    }
    _refreshAttachment();
    final session = _session;
    final route = _prepare(session);
    if (widget.pointerInput) {
      session.activate(route, eligible: () => _isAttached(session));
    }
    return route;
  }

  ModalRoute<Object?>? _rootSourceRoute() {
    var route = ModalRoute.of(context);
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is NavigatorState) {
        final parent = ModalRoute.of(element);
        if (parent != null) route = parent;
      }
      return true;
    });
    return route;
  }

  bool _canActivateSemantically(_MenuSession session) {
    if (!_isAttached(session)) return false;
    final route = session._reservation?.route ?? session.activeRoute;
    if (route == null) return _sourceCanAcquire(session);
    return route._stage.value == _MenuStage.preparing &&
        route._acceptsActivation &&
        _sourceCanAcquire(session, coveredRoot: route._sourcePage);
  }

  void _semanticOpen(_MenuSession session) {
    if (!_canActivateSemantically(session) || !session.admitGeometry()) return;
    if (!_canActivateSemantically(session)) return;
    final route = _prepare(session);
    if (widget.pointerInput) {
      session.activate(
        route,
        eligible: () => _canActivateSemantically(session),
      );
    }
  }

  ProbeMenuRoute _prepare(_MenuSession session, {bool reserve = false}) {
    if (!_isAttached(session)) {
      throw StateError(
        'Menu source and root overlay must share an active FlutterView.',
      );
    }
    if (!session.admitGeometry()) {
      throw StateError('Menu source geometry is unavailable or unsupported.');
    }
    final reserved = session._reservation?.route;
    if (reserved != null) return reserved;
    final current = session.activeRoute;
    if (current != null && !current.closing) return current;
    final navigator = session.affinity.navigator;
    final route = ProbeMenuRoute._(
      session,
      widget.menuBuilder,
      _captureThemes(navigator),
      _rootSourceRoute(),
      widget.menuSemanticLabel,
    );
    if (reserve) {
      session._reservation = _MenuReservation(
        route,
        session.transfer,
        session._pointer!,
      );
    }
    unawaited(navigator.push<void>(route));
    return route;
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Stack(
      fit: .expand,
      children: [
        IgnorePointer(
          child: CustomPaint(
            painter: _MenuPainter(
              session,
              session.source,
              restingButton: widget.button,
              restingRadius: widget.sourceRadius,
            ),
          ),
        ),
        Positioned.fromRect(
          rect: widget.button,
          child: Semantics(
            label: widget.semanticLabel,
            button: true,
            expanded: session.activeRoute?._stage.value == _MenuStage.shown,
            onTap: () => _semanticOpen(session),
            child: widget.pointerInput
                ? Listener(
                    behavior: .opaque,
                    onPointerDown: (event) {
                      if (!_isAttached(session) || !session.admitGeometry()) {
                        return;
                      }
                      if (!_isAttached(session)) return;
                      final accepted = session.handlePointer(
                        event,
                        sourceHit: true,
                      );
                      final owner = session.activeRoute;
                      // Push before Navigator's ancestor Listener records this down.
                      if (accepted &&
                          mounted &&
                          session._pointer?.matches(event) == true &&
                          _sourceCanAcquire(session) &&
                          (owner == null ||
                              (owner.closing && owner._stage.value.revealed))) {
                        _prepare(session, reserve: owner != null);
                      }
                    },
                  )
                : GestureDetector(
                    behavior: .opaque,
                    excludeFromSemantics: true,
                    onTap: () {
                      if (_isAttached(session) &&
                          session.admitGeometry() &&
                          _isAttached(session)) {
                        _prepare(session);
                      }
                    },
                  ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    final session = _current;
    _current = null;
    session?.detachSource();
    super.dispose();
  }
}

class _MenuAffinity {
  const _MenuAffinity(this.navigator, this.sourceView, this.presentationView);

  final NavigatorState navigator;
  final ui.FlutterView sourceView;
  final ui.FlutterView presentationView;

  bool get canPresent => identical(sourceView, presentationView);

  bool sameSpace(_MenuAffinity other) =>
      identical(navigator, other.navigator) &&
      identical(sourceView, other.sourceView) &&
      identical(presentationView, other.presentationView);
}

const _geometryEpsilon = 1e-8;

class _UniformMap {
  const _UniformMap(this.scale, this.offset);

  final double scale;
  final Offset offset;

  static _UniformMap? read(Matrix4 matrix) {
    final values = matrix.storage;
    if (!values.every((value) => value.isFinite)) return null;
    final scale = values[0];
    if (scale <= 0) return null;
    final expected = [
      scale,
      0.0,
      0.0,
      0.0,
      0.0,
      scale,
      0.0,
      0.0,
      0.0,
      0.0,
      1.0,
      0.0,
      values[12],
      values[13],
      0.0,
      1.0,
    ];
    for (var i = 0; i < 16; i++) {
      if (values[i] != expected[i]) return null;
    }
    return _UniformMap(scale, Offset(values[12], values[13]));
  }

  Rect rect(Rect local) => Rect.fromLTWH(
    local.left * scale + offset.dx,
    local.top * scale + offset.dy,
    local.width * scale,
    local.height * scale,
  );

  Offset inverse(Offset point) => (point - offset) / scale;

  bool agrees(_UniformMap other) =>
      (scale - other.scale).abs() <= _geometryEpsilon &&
      (offset - other.offset).distance <= _geometryEpsilon;
}

Rect? _admitMenuPlacement(
  ui.FlutterView view,
  Size bounds,
  _UniformMap overlayToView, {
  required Rect button,
  required Size minimum,
}) {
  final ratio = view.devicePixelRatio;
  if (!ratio.isFinite ||
      ratio <= 0 ||
      !view.physicalSize.isFinite ||
      view.physicalSize.isEmpty) {
    return null;
  }
  final safe = view.viewPadding;
  final keyboard = view.viewInsets;
  final edges = [
    (safe.left, keyboard.left),
    (safe.top, keyboard.top),
    (safe.right, keyboard.right),
    (safe.bottom, keyboard.bottom),
  ];
  if (edges.any(
    (edge) =>
        !edge.$1.isFinite || edge.$1 < 0 || !edge.$2.isFinite || edge.$2 < 0,
  )) {
    return null;
  }
  final size = view.physicalSize / ratio;
  final obstructed = edges
      .map((edge) => math.max(edge.$1, edge.$2) / ratio)
      .toList();
  final safeView = Rect.fromLTRB(
    obstructed[0],
    obstructed[1],
    size.width - obstructed[2],
    size.height - obstructed[3],
  );
  if (!size.isFinite ||
      size.isEmpty ||
      !safeView.isFinite ||
      !safeView.size.isFinite ||
      safeView.isEmpty) {
    return null;
  }
  final projected = Rect.fromPoints(
    overlayToView.inverse(safeView.topLeft),
    overlayToView.inverse(safeView.bottomRight),
  );
  if (!projected.isFinite || !projected.size.isFinite || projected.isEmpty) {
    return null;
  }
  final available = projected.intersect(Offset.zero & bounds);
  if (!available.isFinite || !available.size.isFinite || available.isEmpty) {
    return null;
  }
  final right = bounds.width - available.right;
  final bottom = bounds.height - available.bottom;
  if (!right.isFinite || right < 0 || !bottom.isFinite || bottom < 0) {
    return null;
  }
  if (!minimum.isFinite ||
      minimum.isEmpty ||
      available.width < minimum.width ||
      available.height < minimum.height ||
      button.left < available.left ||
      button.top < available.top ||
      button.right > available.right ||
      button.bottom > available.bottom) {
    return null;
  }
  return available;
}

class _MenuGeometry {
  const _MenuGeometry(
    this.source,
    this.overlay,
    this.map,
    this.button,
    this.bounds,
    this.available,
    this.sourceHeight,
    this.sourceRadius,
  );

  final RenderBox source;
  final RenderBox overlay;
  final _UniformMap map;
  final Rect button;
  final Size bounds;
  final Rect available;
  final double sourceHeight;
  final double sourceRadius;

  EdgeInsets get padding => EdgeInsets.fromLTRB(
    available.left,
    available.top,
    bounds.width - available.right,
    bounds.height - available.bottom,
  );

  bool agrees(_MenuGeometry other) =>
      identical(source, other.source) &&
      identical(overlay, other.overlay) &&
      map.agrees(other.map) &&
      button == other.button &&
      bounds == other.bounds &&
      available == other.available &&
      sourceHeight == other.sourceHeight &&
      sourceRadius == other.sourceRadius;

  Offset? position(Offset global) {
    if (!overlay.attached || !overlay.hasSize) return null;
    final current = _UniformMap.read(overlay.getTransformTo(null));
    if (current == null) return null;
    final result = current.inverse(global);
    return result.dx.isFinite && result.dy.isFinite ? result : null;
  }
}

class _MenuSession {
  _MenuSession(TickerProvider vsync, ProbeMenuSource widget, this.affinity)
    : button = widget.button,
      bounds = widget.bounds,
      pointerInput = widget.pointerInput,
      now = widget.now ?? _engineNow,
      pointerOffset = widget.pointerOffset ?? _unknownOffset,
      createMotion = widget.createMotion,
      neighbors = List.unmodifiable(widget.neighbors),
      onSample = widget.onSample,
      measured = widget._measured,
      sourceHeight = widget.sourceHeight,
      sourceRadius = widget.sourceRadius,
      onMotionReady = widget.onMotionReady {
    transfer = _newMotion();
    sourceClock = ProbeMotionClock(
      vsync: vsync,
      now: now,
      pointerOffset: pointerOffset,
      onFrame: (time) {
        if (!checkGeometry() || !advance(source, time)) {
          return (settled: true, wakeTime: null);
        }
        sourceFrames++;
        final target = transfer;
        emit(.frame);
        syncInputPhase();
        if (sourceClock == null ||
            !identical(target, transfer) ||
            !identical(transfer.owner, source)) {
          return (settled: true, wakeTime: null);
        }
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

  final _MenuAffinity affinity;
  final bool measured;
  final double sourceHeight;
  final double sourceRadius;
  final ValueChanged<MorphMenuMotion>? onMotionReady;
  _MenuGeometry? geometry;
  _MenuGeometry? Function()? readGeometry;
  VoidCallback? loseGeometry;
  late MorphMenuMotion _motion;
  bool _motionReady = false;
  final Rect button;
  final Size bounds;
  final Duration Function() now;
  final bool pointerInput;
  final Duration? Function() pointerOffset;
  final MorphMenuMotion Function()? createMotion;
  final ValueChanged<ProbeMenuSample>? onSample;
  final List<RRect> neighbors;
  VoidCallback? present;
  bool Function()? sourceAttached;
  bool Function({ModalRoute<Object?>? coveredRoot})? sourceEligible;
  _PointerSequence? _pointer;
  bool _retiringSource = false;
  bool _disposed = false;
  int _modelDepth = 0;
  ProbeMenuTransfer? _cancelAfterCommand;
  final source = ProbeMenuLease(.source);
  final frames = ValueNotifier<int>(0);
  final _routes = <ProbeMenuRoute>{};
  late ProbeMenuTransfer transfer;
  ProbeMotionClock? sourceClock;
  ProbeMenuRoute? activeRoute;
  _MenuReservation? _reservation;
  int sourceFrames = 0;
  MorphMenuMotion? _admittedMotion;
  final _closeRequests =
      <({ProbeMenuRoute route, bool admitted, double time})>[];

  bool get _canRelayout =>
      identical(transfer.owner, source) &&
      _routes.isEmpty &&
      activeRoute == null &&
      _reservation == null &&
      _pointer == null &&
      !transfer.isPresented &&
      !transfer.isArming &&
      !transfer.isOpenPending &&
      transfer.isSettled;

  bool checkGeometry() {
    if (!measured || geometry == null) return true;
    if (sourceClock == null) return false;
    final current = readGeometry?.call();
    if (current != null && geometry!.agrees(current)) return true;
    if (_canRelayout) return true;
    loseGeometry?.call();
    return false;
  }

  _MenuGeometry? readSourcePaintGeometry() {
    final admitted = geometry;
    if (!checkGeometry() || admitted == null) return null;
    if (_canRelayout && !(readGeometry?.call()?.agrees(admitted) ?? false)) {
      return null;
    }
    return admitted;
  }

  bool admitGeometry() {
    if (!measured) return true;
    if (SchedulerBinding.instance.schedulerPhase == .persistentCallbacks) {
      return false;
    }
    final current = readGeometry?.call();
    if (current == null) {
      if (geometry != null && !_canRelayout) loseGeometry?.call();
      return false;
    }
    if (geometry == null || !geometry!.agrees(current)) {
      if (!_canRelayout) {
        loseGeometry?.call();
        return false;
      }
      _motion.relayout(
        button: current.button,
        bounds: current.bounds,
        padding: current.padding,
        sourceHeight: current.sourceHeight,
        sourceRadius: current.sourceRadius,
      );
      geometry = current;
    }
    final target = _motion;
    if (!_motionReady) {
      _motionReady = true;
      onMotionReady?.call(target);
    }
    if (!identical(target, _motion) ||
        sourceClock == null ||
        !(sourceAttached?.call() ?? false)) {
      return false;
    }
    final latest = readGeometry?.call();
    if (latest != null && geometry!.agrees(latest)) return true;
    if (!_canRelayout) loseGeometry?.call();
    return false;
  }

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

  bool get _menuCanAcquire {
    if (_reservation != null) {
      return _reservationCanContinue && transfer.isOpenPending;
    }
    final route = activeRoute;
    return route != null &&
        !route.closing &&
        !route.disposed &&
        route.isCurrent;
  }

  bool get _reservationCanContinue {
    final reservation = _reservation;
    return reservation != null &&
        identical(reservation.transfer, transfer) &&
        reservation.route.isCurrent &&
        !reservation.route.closing &&
        !reservation.route.disposed &&
        (sourceEligible?.call(coveredRoot: reservation.route._sourcePage) ??
            false);
  }

  bool get _sourceCanContinue {
    if (_reservation case final reservation?) {
      return _reservationCanContinue &&
          identical(_pointer, reservation.sequence);
    }
    final route = activeRoute;
    return (route == null || (route.closing && route._stage.value.revealed)) &&
        (sourceEligible?.call() ?? false);
  }

  void revokePointerFor(ProbeMenuRoute route) {
    if (identical(_reservation?.route, route) ||
        (identical(activeRoute, route) && !_reservationCanContinue)) {
      _revokePointer();
    }
  }

  void _revokePointer() {
    if (_pointer == null) return;
    _pointer = null;
    _cancelAfterCommand = transfer;
    if (_modelDepth == 0) _drainPointerCancel();
  }

  void _drainPointerCancel() {
    if (_retiringSource) return;
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
          sourceHeight: sourceHeight,
          sourceRadius: sourceRadius,
        );
    _motion = motion;
    geometry = null;
    _motionReady = false;
    if (pointerInput) {
      _admittedMotion = motion;
      morphMenuSetCloseAdmission(motion, (time) {
        final route = _reservation?.route ?? activeRoute;
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

  void _retireReservation(
    _MenuReservation reservation, {
    _ReservationExit exit = .abandoned,
  }) {
    if (!identical(_reservation, reservation)) return;
    _reservation = null;
    final target = reservation.transfer;
    final lease = target.owner;
    if (identical(transfer, reservation.transfer)) _revokePointer();
    if (identical(transfer, target) &&
        identical(target.owner, lease) &&
        (exit == .popped ||
            (exit == .removed && (target.isOpen || target.isOpenPending)))) {
      final clock = activeRoute?._clock ?? sourceClock;
      if (clock != null) {
        final time = clock.resumeAt(now());
        command(() => target.close(lease, time));
        if (identical(target, transfer) && identical(target.owner, lease)) {
          emit(.close);
        }
      }
    }
    final route = reservation.route;
    if (route.disposed) return;
    route._invalidateDismissal();
    route._pushSignal.stop(canceled: false);
    scheduleMicrotask(() {
      if (route.disposed) return;
      if (route.isActive) {
        route._stage.value = _MenuStage.closingPreparation;
        route.navigator!.removeRoute(route);
      } else if (exit == .popped) {
        route._projection.update(0, .dismissed);
      }
    });
  }

  void _promoteReservation(_MenuReservation reservation) {
    if (!identical(_reservation, reservation) ||
        !identical(reservation.transfer, transfer) ||
        reservation.route.disposed ||
        reservation.route.closing ||
        !reservation.route.isActive) {
      _retireReservation(reservation, exit: .removed);
      return;
    }
    _reservation = null;
    acquire(reservation.route);
    reservation.route._reveal();
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

  void activate(ProbeMenuRoute route, {bool Function()? eligible}) {
    if (!route._acceptsActivation || transfer.isOpen) return;
    final target = transfer;
    final lease = target.owner;
    bool valid() =>
        identical(transfer, target) &&
        route._acceptsActivation &&
        (eligible?.call() ?? true);
    _revokePointer();
    if (!valid()) return;
    final clock = activeRoute?._clock ?? sourceClock!;
    final time = clock.resumeAt(now());
    command(() {
      target.advance(lease, time);
      if (!valid()) return;
      target.open(lease, time);
      if (valid()) emit(.open);
    });
    if (!valid()) return;
    syncInputPhase();
    frames.value++;
  }

  bool land(ProbeMenuRoute route, double localTime) {
    final clock = sourceClock;
    if (clock == null ||
        !identical(activeRoute, route) ||
        !identical(transfer.owner, route._lease) ||
        !identical(route.navigator, affinity.navigator) ||
        !(sourceAttached?.call() ?? false) ||
        !checkGeometry()) {
      return false;
    }
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
    if (sourceClock == null) return;
    present = null;
    sourceEligible = null;
    sourceAttached = null;
    readGeometry = null;
    loseGeometry = null;
    _retiringSource = true;
    _revokePointer();
    sourceClock!.dispose();
    sourceClock = null;
    scheduleMicrotask(() {
      _retiringSource = false;
      _drainPointerCancel();
      if (_reservation case final reservation?) {
        _retireReservation(reservation, exit: .removed);
      }
      final route = activeRoute;
      if (route != null &&
          !route.disposed &&
          !route.closing &&
          !route._stage.value.revealed) {
        route._abandonCoveredPreparation();
      }
      _disposeIfUnused();
    });
  }

  void routeDisposed(ProbeMenuRoute route) {
    _routes.remove(route);
    final reservation = _reservation;
    if (reservation != null &&
        (identical(reservation.route, route) ||
            identical(activeRoute, route))) {
      _retireReservation(reservation, exit: .removed);
    }
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
    if (!_disposed &&
        !_retiringSource &&
        sourceClock == null &&
        _routes.isEmpty) {
      _disposed = true;
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
    if (measured && geometry == null) return;
    onSample?.call((
      kind: kind,
      time: time ?? transfer.frame.time,
      event: event,
      frame: transfer.frame,
    ));
  }

  void syncInputPhase() {
    if (!pointerInput || _retiringSource) return;
    if (_reservation case final reservation?) {
      if (!identical(reservation.transfer, transfer) ||
          sourceEligible == null ||
          reservation.route._sourcePage?.isActive == false) {
        _retireReservation(reservation, exit: .removed);
      } else if (transfer.isOpen) {
        _promoteReservation(reservation);
      } else if (_pointer == null && !transfer.isOpenPending) {
        _retireReservation(reservation);
      }
    }
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
        !route._stage.value.revealed &&
        !transfer.isArming &&
        !transfer.isPresented &&
        !route.closing) {
      if (route.isCurrent) {
        route.navigator!.pop();
      } else {
        route._abandonCoveredPreparation();
      }
    }
    activeRoute?._updatePendingBarrier();
  }

  bool handlePointer(PointerEvent event, {bool sourceHit = false}) {
    if (measured && geometry == null) return false;
    checkGeometry();
    if (_retiringSource) return false;
    final position = measured
        ? geometry!.position(event.position)
        : event.position;
    if (position == null) {
      _revokePointer();
      return false;
    }
    final route = activeRoute;
    if (route != null && route.closing && !route._stage.value.revealed) {
      if (_pointer?.matches(event) == true &&
          (event is PointerUpEvent || event is PointerCancelEvent)) {
        _pointer = null;
      }
      emit(.ignoredPointer, event: event);
      return false;
    }
    if (event is PointerDownEvent) {
      if (_pointer != null || event.buttons != kPrimaryButton) return false;
      if (event.viewId != affinity.presentationView.viewId ||
          (!_menuCanAcquire && !(sourceHit && _sourceCanContinue))) {
        emit(.ignoredPointer, event: event);
        return false;
      }
      _pointer = _PointerSequence(event.pointer, event.viewId);
    } else if (_pointer?.matches(event) != true) {
      if (event is PointerMoveEvent ||
          event is PointerUpEvent ||
          event is PointerCancelEvent) {
        emit(.ignoredPointer, event: event);
      }
      return false;
    }
    final sequence = _pointer!;
    if (!_menuCanAcquire && !_sourceCanContinue) {
      _revokePointer();
      emit(.ignoredPointer, event: event);
      return false;
    }
    final clock = activeRoute?._clock ?? sourceClock;
    if (clock == null) return false;
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
      final time = target.pointer(
        lease,
        local,
        measured ? event.copyWith(position: position) : event,
      );
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
      return false;
    }
    if (!identical(target, transfer)) return false;
    syncInputPhase();
    frames.value++;
    return true;
  }
}

enum _ReservationExit { abandoned, popped, removed }

class _MenuReservation {
  _MenuReservation(this.route, this.transfer, this.sequence);

  final ProbeMenuRoute route;
  final ProbeMenuTransfer transfer;
  final _PointerSequence sequence;
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

class _SourceThemes {
  const _SourceThemes(this.capture, this.widgets);

  final CapturedThemes capture;
  final List<InheritedTheme> widgets;

  bool sameKinds(_SourceThemes other) {
    if (widgets.length != other.widgets.length) return false;
    for (var i = 0; i < widgets.length; i++) {
      if (widgets[i].runtimeType != other.widgets[i].runtimeType) return false;
    }
    return true;
  }

  bool sameWidgets(_SourceThemes other) {
    if (widgets.length != other.widgets.length) return false;
    for (var i = 0; i < widgets.length; i++) {
      if (!identical(widgets[i], other.widgets[i])) return false;
    }
    return true;
  }
}

enum _MenuStage {
  preparing,
  shown,
  closingPreparation,
  closingContent;

  bool get revealed => this == shown || this == closingContent;
  bool get closing => this == closingPreparation || this == closingContent;
}

/// A real PopupRoute sharing its model with the source while attached.
///
/// A detached popup completes on its own clock without returning the model.
class ProbeMenuRoute extends PopupRoute<void> {
  ProbeMenuRoute._(
    this._session,
    this._builder,
    _SourceThemes themes,
    this._sourcePage,
    this._semanticLabel,
  ) : _themes = ValueNotifier(themes),
      _stage = ValueNotifier(
        _session.pointerInput ? _MenuStage.preparing : _MenuStage.shown,
      );

  final _MenuSession _session;
  final WidgetBuilder _builder;
  final ModalRoute<Object?>? _sourcePage;
  final String _semanticLabel;
  final ValueNotifier<_SourceThemes> _themes;
  _SourceThemes? _pendingThemes;
  final _lease = ProbeMenuLease(.route);
  final _projection = _MenuAnimation();
  final _pushSignal = Ticker((_) {});
  final ValueNotifier<_MenuStage> _stage;
  bool _pendingBarrier = false;
  double? _admittedCloseTime;
  Route<Object?>? _nextRoute;
  _DismissAttempt? _dismissal;
  _MountedMenuPolicyState? _policyMount;
  late final ProbeMotionClock _clock;

  /// Whether logical pop has started closing this presentation.
  bool get closing => _stage.value.closing;

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

  bool get _acceptsActivation =>
      !disposed &&
      !closing &&
      isCurrent &&
      ((identical(_session.activeRoute, this) &&
              identical(_session.transfer.owner, _lease)) ||
          (identical(_session._reservation?.route, this) &&
              identical(_session._reservation?.transfer, _session.transfer)));

  void _semanticDismiss() {
    if (_stage.value != _MenuStage.shown || !_acceptsActivation) return;
    unawaited(navigator!.maybePop());
  }

  void _queueThemes(_SourceThemes latest) {
    if (disposed || !_themes.value.sameKinds(latest)) return;
    if (_pendingThemes != null) {
      _pendingThemes = latest;
      return;
    }
    if (_themes.value.sameWidgets(latest)) return;
    _pendingThemes = latest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = _pendingThemes;
      _pendingThemes = null;
      if (disposed || pending == null || _themes.value.sameWidgets(pending)) {
        return;
      }
      _themes.value = pending;
    });
  }

  bool get _policyReady => _policyMount?._ready ?? false;

  bool _isLive(_DismissAttempt request) =>
      identical(_dismissal, request) &&
      !disposed &&
      !closing &&
      navigator?.mounted == true &&
      isCurrent &&
      ((identical(_session.activeRoute, this) &&
              identical(_session.transfer.owner, _lease)) ||
          (identical(_session._reservation?.route, this) &&
              identical(_session._reservation?.transfer, _session.transfer)));

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
      consultPolicy: _stage.value.revealed || _session.transfer.isOpen,
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
    if (!request.consultPolicy &&
        _session.transfer.isOpen &&
        _isLive(request)) {
      _session.syncInputPhase();
      _invalidateDismissal();
      return willPop();
    }
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
    if (_stage.value == _MenuStage.preparing &&
        identical(_session.activeRoute, this) &&
        _session.transfer.isOpen) {
      _reveal();
      _clock.resumeAt(_session.now());
    }
  }

  @override
  bool get requestFocus => !disposed && _stage.value.revealed;

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
  bool get semanticsDismissible => false;

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
    _session._routes.add(this);
    if (identical(_session._reservation?.route, this)) {
      _projection.update(0, .forward);
      return signal;
    }
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
    final reservation = _session._reservation;
    if (reservation != null && identical(reservation.route, this)) {
      _session._retireReservation(reservation, exit: .popped);
      return true;
    }
    _beginClosing(approved);
    return true;
  }

  void _abandonCoveredPreparation() {
    _invalidateDismissal();
    _beginClosing(false);
  }

  void _beginClosing(bool approved) {
    _session._pointer = null;
    _stage.value = _stage.value.revealed
        ? _MenuStage.closingContent
        : _MenuStage.closingPreparation;
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
  }

  ProbeFrameOutcome _sample(double time) {
    _session.checkGeometry();
    if (!_session.advance(_lease, time) ||
        disposed ||
        !identical(_session.transfer.owner, _lease)) {
      return (settled: true, wakeTime: null);
    }
    motionFrames++;
    _session.emit(.frame);
    _session.syncInputPhase();
    _consumeApprovedDismissal();
    if (disposed || !identical(_session.transfer.owner, _lease)) {
      return (settled: true, wakeTime: null);
    }
    final settled = _session.transfer.isSettled;
    if (!_stage.value.revealed && !closing) {
      _projection.update(0, .forward);
      _session.frames.value++;
      return (settled: settled, wakeTime: null);
    }
    if (closing &&
        ((_session.transfer.readyToHandBack && _session.land(this, time)) ||
            settled)) {
      if (isActive) {
        navigator!.removeRoute(this);
        return (settled: true, wakeTime: null);
      }
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
    if (_stage.value != _MenuStage.preparing || !isCurrent) return;
    _stage.value = _MenuStage.shown;
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
  Widget buildModalBarrier() => ValueListenableBuilder<_MenuStage>(
    valueListenable: _stage,
    builder: (_, stage, child) =>
        ExcludeSemantics(excluding: stage != _MenuStage.shown, child: child!),
    child: _inputGate(
      _session.pointerInput
          ? IgnorePointer(
              ignoring: !_stage.value.revealed && !_pendingBarrier,
              child: ModalBarrier(
                dismissible: false,
                semanticsLabel: barrierLabel,
              ),
            )
          : super.buildModalBarrier(),
    ),
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
          ValueListenableBuilder<_MenuStage>(
            valueListenable: _stage,
            builder: (_, stage, child) => stage.revealed
                ? ExcludeSemantics(
                    excluding: stage != _MenuStage.shown,
                    child: child!,
                  )
                : const SizedBox.shrink(),
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              child: Semantics(
                namesRoute: true,
                label: _semanticLabel,
                onDismiss: _semanticDismiss,
                child: _MenuFlow(
                  delegate: _MenuContentFlow(_session, _lease),
                  children: [
                    ValueListenableBuilder<_SourceThemes>(
                      valueListenable: _themes,
                      child: _MountedMenuPolicy(route: this, builder: _builder),
                      builder: (_, themes, child) =>
                          themes.capture.wrap(child!),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    disposed = true;
    _pendingThemes = null;
    _themes.dispose();
    _invalidateDismissal();
    _clock.dispose();
    _pushSignal.dispose();
    super.dispose();
    _projection.dispose();
    _stage.dispose();
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
  _MenuPainter(
    this.session,
    this.lease, {
    this.restingButton,
    this.restingRadius,
  }) : super(repaint: session.frames);

  final _MenuSession session;
  final ProbeMenuLease lease;
  final Rect? restingButton;
  final double? restingRadius;

  @override
  void paint(Canvas canvas, Size size) {
    _MenuGeometry? geometry;
    if (session.measured && restingButton != null) {
      geometry = session.readSourcePaintGeometry();
      if (geometry == null) {
        final paint = Paint();
        paint.color = const Color(0xFF8888AA);
        final outline = morphGlassContainerOutline(
          [
            RRect.fromRectAndRadius(
              restingButton!,
              Radius.circular(restingRadius!),
            ),
          ],
          12,
          withField: false,
        );
        canvas.drawPath(outline.path, paint);
        return;
      }
    }
    if (!identical(session.transfer.owner, lease)) return;
    canvas.save();
    if (session.measured && restingButton != null) {
      final map = geometry!.map;
      canvas.scale(1 / map.scale);
      canvas.translate(-map.offset.dx, -map.offset.dy);
    }
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
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MenuPainter oldDelegate) =>
      session != oldDelegate.session ||
      lease != oldDelegate.lease ||
      restingButton != oldDelegate.restingButton ||
      restingRadius != oldDelegate.restingRadius;
}

class _MenuFlow extends Flow {
  _MenuFlow({required super.delegate, required super.children});

  @override
  RenderFlow createRenderObject(BuildContext context) =>
      _MenuRenderFlow(delegate: delegate, clipBehavior: clipBehavior);
}

class _MenuRenderFlow extends RenderFlow {
  _MenuRenderFlow({required super.delegate, required super.clipBehavior});

  @override
  void markNeedsPaint() {
    super.markNeedsPaint();
    markNeedsSemanticsUpdate();
  }
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
