import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent;

import 'package:morph/src/controller.dart';
import 'package:morph/src/flight.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/motion.dart';
import 'package:morph/src/target.dart';
import 'package:morph/src/theme.dart';

/// A real Navigator route whose visual transition is a morph flight.
///
/// The route is pushed IMMEDIATELY, so the Navigator owns the truth
/// from the first frame: back button, predictive back, deep links and
/// further pushes all behave normally. The flight plays in the overlay
/// while the route page stays empty; once the open spring settles, the
/// second latch fires - ownership of the target content transfers from
/// the shuttle to the route page. Both sides rebuild in the same frame
/// and the content subtree carries a shared [GlobalKey], so it
/// reparents with its live state (scroll positions, text fields,
/// counters survive). A pop hands the content back to the shuttle the
/// same way and plays the ordinary close flight; a close launched from
/// the flight side (a button calling flight.close) retires the route
/// automatically.
///
/// The scrim swaps between the two owners at full opacity on both
/// latches, so the handovers are invisible.
/// [from] may be omitted when called inside the source tag's subtree,
/// mirroring [showMorph].
Future<T?> showMorphRoute<T>(
  BuildContext context, {
  Object? from,
  required MorphContentBuilder builder,
  MorphTargetSpec? target,
  MorphMotion? motion,
  bool barrierDismissible = true,
  double? maxScrimOpacity,
  String? semanticLabel,
}) {
  final MorphTheme? theme = MorphTheme.maybeOf(context);
  return Navigator.of(context, rootNavigator: true).push(
    MorphPageRoute<T>(
      from: from ?? MorphTag.idOf(context),
      builder: builder,
      target: target ?? MorphTargetSpec.dialog(),
      motion: motion ?? theme?.motion,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      maxScrimOpacity: maxScrimOpacity ?? theme?.maxScrimOpacity ?? 0.45,
      semanticLabel: semanticLabel,
    ),
  );
}

/// The route half of [showMorphRoute]; usable directly with
/// Navigator.push for named-route setups.
///
/// Predictive back (Android): the route claims the system back gesture
/// and scrubs the flight itself - the card visibly starts its journey
/// home under the finger (a short, shallow scrub: value 1 down to
/// 1 - [_predictiveBackDepth], too small for the fade-through
/// midstates to read). The content returns to the shuttle for the
/// whole gesture; a cancel springs back to settled and the second
/// latch re-hands the content to the page, a commit pops and the
/// ordinary close plays from the scrubbed value.
class MorphPageRoute<T> extends PopupRoute<T> {
  /// Creates the route; prefer [showMorphRoute], which also resolves
  /// [MorphTheme] defaults and the localized barrier label.
  MorphPageRoute({
    required this.from,
    required this.builder,
    required this.target,
    this.motion,
    // Private named parameters (callers pass the public names) backing
    // the ModalRoute getter overrides.
    this._barrierDismissible = true,
    this._barrierLabel,
    this.maxScrimOpacity = 0.45,
    this.semanticLabel,
    super.settings,
  });

  /// The source tag id; the tag must be mounted when the route is
  /// pushed.
  final Object from;

  /// Builds the page content (lives in the shuttle until the second
  /// latch).
  final MorphContentBuilder builder;

  /// The destination description.
  final MorphTargetSpec target;

  /// Motion profile; this constructor does not consult [MorphTheme].
  final MorphMotion? motion;

  /// Scrim opacity in the settled state.
  final double maxScrimOpacity;

  /// Accessibility name of the route (screen readers announce it).
  final String? semanticLabel;
  final bool _barrierDismissible;
  final String? _barrierLabel;

  MorphFlight? _flight;

  /// The live flight of this route; null before didPush.
  MorphFlight? get flight => _flight;

  // The flight and the route page own all scrim painting; the modal
  // barrier stays transparent and only contributes dismiss semantics
  // and taps once the route owns the content.
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => _barrierDismissible;

  // The accessibility label of the DISMISS affordance, not the route's
  // name (that is [semanticLabel]): showMorphRoute passes the localized
  // modal-barrier label.
  @override
  String? get barrierLabel => _barrierLabel;

  // The spring animates the visuals; the route machinery is instant.
  @override
  Duration get transitionDuration => .zero;

  // How deep the predictive-back preview scrubs the value at full
  // gesture progress: enough for the card to visibly shrink toward its
  // source, not enough for the content crossfade to expose midstates.
  static const double _predictiveBackDepth = 0.18;

  bool _predictiveBack = false;
  double _predictiveBackFrom = 1;
  late final _RouteBackGestureObserver _backObserver =
      _RouteBackGestureObserver(this);

  // The PredictiveBackRoute hooks, reimplemented on the flight: the
  // default TransitionRoute behavior drives the route's own transition
  // controller, which is a zero-duration shell here - the morph spring
  // is the transition.

  @override
  void handleStartBackGesture({double progress = 0.0}) {
    final MorphFlight? flight = _flight;
    // With an overlay flight stacked above (a local history entry) the
    // back gesture pops that flight, not this route: decline the scrub.
    if (!isCurrent ||
        willHandlePopInternally ||
        flight == null ||
        flight.isFinished) {
      return;
    }
    _predictiveBack = true;
    // The scrub plays in the shuttle: the content comes back for the
    // whole gesture, whichever way it ends.
    flight.routeOwnsContent.value = false;
    flight.refreshSourceRect();
    flight.controller.beginScrub();
    _predictiveBackFrom = flight.controller.value;
    handleUpdateBackGestureProgress(progress: progress);
  }

  @override
  void handleUpdateBackGestureProgress({required double progress}) {
    if (!_predictiveBack) {
      return;
    }
    final double value = _predictiveBackFrom - _predictiveBackDepth * progress;
    _flight?.controller.updateScrub(value < 0 ? 0 : value);
  }

  @override
  void handleCommitBackGesture() {
    if (!_predictiveBack) {
      return;
    }
    _predictiveBack = false;
    if (isCurrent) {
      // didPop plays the close from the scrubbed value.
      navigator?.pop();
    } else {
      _flight?.close();
    }
  }

  @override
  void handleCancelBackGesture() {
    if (!_predictiveBack) {
      return;
    }
    _predictiveBack = false;
    // Spring back to settled; the second latch re-hands the content to
    // the page on its own.
    _flight?.open();
  }

  @override
  TickerFuture didPush() {
    WidgetsBinding.instance.addObserver(_backObserver);
    final NavigatorState nav = navigator!;
    final MorphFlight flight = .launch(
      nav.context,
      from: from,
      target: target,
      builder: builder,
      motion: motion,
      barrierDismissible: _barrierDismissible,
      maxScrimOpacity: maxScrimOpacity,
      semanticLabel: semanticLabel,
      routeMode: true,
      overlay: nav.overlay,
      // Pre-latch the scrim belongs to the shuttle: its dismiss taps
      // route through the Navigator so the route lifecycle stays the
      // single source of truth.
      onDismissRequested: _handleDismissRequest,
    );
    _flight = flight;
    flight.controller.addListener(_onFlightTick);
    return super.didPush();
  }

  void _handleDismissRequest() {
    if (isCurrent) {
      navigator?.pop();
    }
  }

  void _onFlightTick() {
    final MorphFlight? flight = _flight;
    if (flight == null) {
      return;
    }
    final MorphController c = flight.controller;
    if (flight.isFinished) {
      c.removeListener(_onFlightTick);
      if (isActive) {
        navigator?.removeRoute(this);
      }
      return;
    }
    if (!flight.routeOwnsContent.value) {
      // The second latch: the open spring has settled and this route is
      // on top - the page adopts the content.
      if (c.target >= 1 && !c.isAnimating && !c.isScrubbing && isCurrent) {
        flight.routeOwnsContent.value = true;
      }
    } else if (c.target == 0) {
      // A close launched from the flight side (a button calling
      // flight.close): hand the content back for the landing and retire
      // the route without replaying the close.
      flight.routeOwnsContent.value = false;
      if (isActive) {
        navigator?.removeRoute(this);
      }
    }
  }

  @override
  bool didPop(T? result) {
    if (willHandlePopInternally) {
      // A LocalHistoryEntry sits on top of this route - an overlay
      // flight (a menu, a popover) opened above the page. The pop
      // belongs to IT, not to this route's flight.
      return super.didPop(result);
    }
    _predictiveBack = false;
    final MorphFlight? flight = _flight;
    if (flight != null && !flight.isFinished) {
      // Hand the content back to the shuttle in the same frame the page
      // goes away, then play the ordinary close. close() is a no-op if
      // the flight is already closing.
      flight.routeOwnsContent.value = false;
      flight.close();
    }
    return super.didPop(result);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_backObserver);
    _flight?.controller.removeListener(_onFlightTick);
    super.dispose();
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _MorphRoutePage<T>(route: this);
  }
}

/// The settled state of the flight, replicated as a plain page: the
/// same scrim, the same surface, the same content chain - so the
/// shuttle-to-route swap is pixel-identical.
class _MorphRoutePage<T> extends StatefulWidget {
  const _MorphRoutePage({required this.route});

  final MorphPageRoute<T> route;

  @override
  State<_MorphRoutePage<T>> createState() => _MorphRoutePageState<T>();
}

class _MorphRoutePageState<T> extends State<_MorphRoutePage<T>> {
  // The route-side anchor for SharedSideScope: shared elements only
  // measure mid-flight (shuttle-owned), but the wrapper chain must
  // match the shuttle's exactly for the reparent to preserve state.
  final GlobalKey _anchorKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final MorphFlight? flight = widget.route._flight;
    if (flight == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: flight.routeOwnsContent,
      builder: (BuildContext context, Widget? _) {
        if (!flight.routeOwnsContent.value) {
          return const SizedBox.shrink();
        }
        final MorphSurfaceSpec spec = resolveMorphTargetSurface(
          flight,
          Theme.of(context).colorScheme,
        );
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Rect rect = flight.target.rectFor(
              constraints.biggest,
              MediaQuery.paddingOf(context),
            );
            // Keep the flight's belief fresh while the route owns the
            // layout: a pop closes FROM this rect.
            flight.lastTargetRect = rect;
            return Stack(
              children: <Widget>[
                // The visual scrim only: taps fall through to the
                // route's transparent modal barrier, which owns dismiss
                // behavior and semantics.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(
                        alpha: flight.maxScrimOpacity,
                      ),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: Material(
                    color: spec.color,
                    shape: spec.shape,
                    clipBehavior: .antiAlias,
                    elevation: spec.elevation,
                    shadowColor: Colors.black.withValues(alpha: 0.6),
                    // The SAME chain the shuttle mounts, from the one
                    // shared builder: the route-mode reparent preserves
                    // state only while the chains match, and now they
                    // cannot drift.
                    child: buildMorphTargetContent(
                      flight: flight,
                      spec: spec,
                      anchorKey: _anchorKey,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Claims the system back gesture at the binding level and forwards it
/// to the route's PredictiveBackRoute hooks. MorphPageRoute is a
/// PopupRoute, so the material page-transitions detector never wraps
/// it - without this bridge nobody would deliver the events. The claim
/// checks mirror the route hook's own guards, because a false return
/// must leave the gesture to other observers (or to the plain pop).
class _RouteBackGestureObserver with WidgetsBindingObserver {
  _RouteBackGestureObserver(this.route);

  final MorphPageRoute<Object?> route;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    final MorphFlight? flight = route._flight;
    if (!route.isCurrent ||
        route.willHandlePopInternally ||
        flight == null ||
        flight.isFinished) {
      return false;
    }
    route.handleStartBackGesture(progress: backEvent.progress);
    return route._predictiveBack;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) =>
      route.handleUpdateBackGestureProgress(progress: backEvent.progress);

  @override
  void handleCommitBackGesture() => route.handleCommitBackGesture();

  @override
  void handleCancelBackGesture() => route.handleCancelBackGesture();
}
