import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/bar_items.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/menu_entries.dart';
import 'package:morph/src/widgets/navigation_bar.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/widgets/navigation_motion.dart';
import 'package:morph/src/widgets/motion_route.dart';
import 'package:morph/src/widgets/push_zoom.dart';
import 'package:morph/src/widgets/push_zoom_motion.dart';
import 'package:morph/src/widgets/scroll_edge_effect.dart';
import 'package:morph/src/widgets/toolbar.dart';
import 'package:morph/src/widgets/widgets_theme.dart';
import 'package:morph/src/widgets/zoom_source.dart';

/// What one screen of a [MorphNavigationStack] shows in the shared bars.
@immutable
class MorphNavigationConfig {
  /// Creates a configuration.
  const MorphNavigationConfig({
    this.title,
    this.leading,
    this.trailing = const [],
    this.toolbarLeading = const [],
    this.toolbarTrailing = const [],
    this.titleVisible = true,
    this.scrolledUnder = false,
    this.animate = true,
    this.edgeEffect = MorphScrollEdgeEffectStyle.hard,
    this.backTitle,
  });

  /// The screen's title.
  final String? title;

  /// The group at the leading edge of the navigation bar; null shows a
  /// back button when the screen is not the first.
  final MorphBarButtonGroup? leading;

  /// The groups at the trailing edge of the navigation bar.
  final List<MorphBarButtonGroup> trailing;

  /// The groups at the leading edge of the toolbar.
  final List<MorphBarButtonGroup> toolbarLeading;

  /// The groups at the trailing edge of the toolbar.
  final List<MorphBarButtonGroup> toolbarTrailing;

  /// Whether the bar's inline title shows.
  final bool titleVisible;

  /// Whether content is under the navigation bar.
  final bool scrolledUnder;

  /// Whether changes of [titleVisible] and [scrolledUnder] animate.
  final bool animate;

  /// The scroll edge effect under the navigation bar.
  final MorphScrollEdgeEffectStyle? edgeEffect;

  /// The label of the back button on the next screen; defaults to
  /// [title].
  final String? backTitle;

  /// Whether the screen shows a toolbar.
  bool get hasToolbar =>
      toolbarLeading.isNotEmpty || toolbarTrailing.isNotEmpty;

  /// Whether [other] shows the same bars with the same callbacks: buttons
  /// compare by value, their callbacks and icon widgets by identity, so a
  /// screen that rebuilds with new closures hands them to the bars.
  @override
  bool operator ==(Object other) =>
      other is MorphNavigationConfig &&
      other.title == title &&
      other.leading == leading &&
      listEquals(other.trailing, trailing) &&
      listEquals(other.toolbarLeading, toolbarLeading) &&
      listEquals(other.toolbarTrailing, toolbarTrailing) &&
      other.titleVisible == titleVisible &&
      other.scrolledUnder == scrolledUnder &&
      other.animate == animate &&
      other.edgeEffect == edgeEffect &&
      other.backTitle == backTitle;

  @override
  int get hashCode => Object.hash(
    title,
    leading,
    Object.hashAll(trailing),
    Object.hashAll(toolbarLeading),
    Object.hashAll(toolbarTrailing),
    titleVisible,
    scrolledUnder,
    animate,
    edgeEffect,
    backTitle,
  );
}

class _StackScope extends InheritedWidget {
  const _StackScope({required this.state, required super.child});

  final _MorphNavigationStackState state;

  @override
  bool updateShouldNotify(_StackScope oldWidget) => oldWidget.state != state;
}

/// A navigation stack in the iOS 27 manner: one navigation bar and one
/// toolbar shared by every screen, whose glass buttons morph from one
/// screen's into the next one's as screens are pushed and popped.
///
/// Screens are [MorphNavigationScaffold]s pushed as [MorphNavigationRoute]s
/// (through `Navigator.of(context)`); each one publishes its title, buttons
/// and scroll state, and the stack shows the top screen's in its bars,
/// with a back button labelled with the previous screen's title. Pages
/// slide in on the measured push spring, and a swipe from the leading
/// edge pops interactively; see [MorphNavigationRoute].
class MorphNavigationStack extends StatefulWidget {
  /// Creates a stack showing [home] first.
  const MorphNavigationStack({
    required this.home,
    this.style,
    this.menuStyle,
    this.menuTuning = MorphBarMenuTuning.standard,
    this.menuOverlay,
    this.backLabel = 'Back',
    this.navigatorKey,
    this.observers = const [],
    super.key,
  });

  /// The first screen.
  ///
  /// Read once, when the stack's navigator is created, like [navigatorKey]
  /// and [observers].
  final Widget home;

  /// The look of the bars; null resolves it from the theme.
  final MorphBarStyle? style;

  /// The look of the back button's menu; null resolves it from the theme.
  final MorphMenuStyle? menuStyle;

  /// The bar buttons' menu recognition, opening delay and menu motion.
  final MorphBarMenuTuning menuTuning;

  /// The overlay the back button's menu flies in; null uses the nearest
  /// one around the bar.
  final OverlayState? menuOverlay;

  /// The label screen readers announce for the back button.
  final String backLabel;

  /// The key of the stack's navigator.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Observers of the stack's navigator.
  final List<NavigatorObserver> observers;

  @override
  State<MorphNavigationStack> createState() => _MorphNavigationStackState();
}

class _MorphNavigationStackState extends State<MorphNavigationStack> {
  late final GlobalKey<NavigatorState> _navigator =
      widget.navigatorKey ?? GlobalKey<NavigatorState>();
  late final _Observer _observer = _Observer(this);
  final List<Route<Object?>> _routes = [];
  final Map<Route<Object?>, MorphNavigationConfig> _configs = {};
  final Set<Route<Object?>> _pending = {};
  late final Widget _navigatorWidget = NavigatorPopHandler<Object?>(
    onPopWithResult: (Object? result) =>
        _navigator.currentState?.maybePop(result),
    child: Navigator(
      key: _navigator,
      observers: [_observer, ...widget.observers],
      onGenerateInitialRoutes: (NavigatorState navigator, String _) => [
        MorphNavigationRoute<void>(builder: (_) => widget.home),
      ],
    ),
  );
  bool _scheduled = false;
  double _titleExit = -MorphNavigationTransition.parallax;
  Route<Object?>? _swiped;
  Animation<double>? _swipeProgress;

  @override
  void didUpdateWidget(MorphNavigationStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      oldWidget.navigatorKey == widget.navigatorKey,
      'MorphNavigationStack.navigatorKey cannot change: the navigator is '
      'created once.',
    );
  }

  /// Whether [route] is a screen of this stack's own navigator.
  bool _owns(Route<Object?> route) =>
      route.navigator != null && route.navigator == _navigator.currentState;

  void _publish(Route<Object?> route, MorphNavigationConfig config) {
    if (!_owns(route)) return;
    final before = _configs[route];
    _configs[route] = config;
    final waited = _pending.remove(route);
    if (!waited && before == config) return;
    _refresh();
  }

  void _refresh() {
    if (_scheduled) return;
    _scheduled = true;
    final phase = SchedulerBinding.instance.schedulerPhase;
    void run() {
      _scheduled = false;
      if (mounted) setState(() {});
    }

    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      scheduleMicrotask(run);
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => run());
    }
  }

  void _await(Route<Object?> route) {
    _pending.add(route);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_pending.remove(route)) _refresh();
    });
  }

  void _pushed(Route<Object?> route) {
    _routes.add(route);
    _await(route);
    _titleExit = -MorphNavigationTransition.parallax;
    _refresh();
  }

  void _removed(Route<Object?> route) {
    if (_routes.isNotEmpty && _routes.last == route) _titleExit = 1;
    _routes.remove(route);
    _configs.remove(route);
    _pending.remove(route);
    if (_swiped == route) {
      _swiped = null;
      _swipeProgress = null;
    }
    _refresh();
  }

  void _replaced(Route<Object?>? oldRoute, Route<Object?>? newRoute) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (oldRoute != null) {
      _configs.remove(oldRoute);
      _pending.remove(oldRoute);
    }
    if (newRoute != null) _await(newRoute);
    if (i >= 0 && newRoute != null) {
      _routes[i] = newRoute;
    } else if (i >= 0) {
      _routes.removeAt(i);
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
    _refresh();
  }

  void _swipeStarted(Route<Object?> route, Animation<double> animation) {
    _swiped = route;
    _swipeProgress = ReverseAnimation(animation);
    _refresh();
  }

  void _swipeEnded(Route<Object?> route) {
    if (_swiped != route) return;
    _swiped = null;
    _swipeProgress = null;
    _refresh();
  }

  MorphBarButtonGroup? _leadingOf(List<PageRoute<Object?>> pages, int index) {
    final config = _configs[pages[index]];
    final leading = config?.leading;
    if (leading != null || index == 0) return leading;
    final below = _configs[pages[index - 1]];
    return MorphBarButtonGroup([
      MorphBarButton.back(
        label: below?.backTitle ?? below?.title,
        semanticLabel: widget.backLabel,
        onPressed: () => _navigator.currentState?.maybePop(),
        menu: [
          for (var i = index - 1; i >= 0; i--)
            MorphMenuItem(
              title: _configs[pages[i]]?.title ?? '',
              onSelected: () {
                final target = pages[i];
                final navigator = _navigator.currentState;
                if (navigator == null || !target.isActive) return;
                navigator.popUntil((Route<Object?> route) => route == target);
              },
            ),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final all = [
      for (final r in _routes)
        if (r is PageRoute<Object?>) r,
    ];
    var shown = all.length;
    while (shown > 1 &&
        _pending.contains(all[shown - 1]) &&
        _configs[all[shown - 1]] == null) {
      shown--;
    }
    final pages = all.sublist(0, shown);
    final index = pages.length - 1;
    final top = pages.isEmpty ? null : pages.last;
    final config = top == null ? null : _configs[top];
    final leading = top == null ? null : _leadingOf(pages, index);
    MorphNavigationBarDrift? drift;
    final progress = _swipeProgress;
    if (top != null && top == _swiped && progress != null && index >= 1) {
      drift = MorphNavigationBarDrift(
        leading: _leadingOf(pages, index - 1),
        trailing: _configs[pages[index - 1]]?.trailing ?? const [],
        progress: progress,
      );
    }
    final hasToolbar = config?.hasToolbar ?? false;
    return _StackScope(
      state: this,
      child: Stack(
        children: [
          Positioned.fill(child: _navigatorWidget),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: MorphNavigationBar(
              title: config?.title,
              leading: leading,
              trailing: config?.trailing ?? const [],
              titleVisible: config?.titleVisible ?? true,
              scrolledUnder: config?.scrolledUnder ?? false,
              animate: config?.animate ?? true,
              edgeEffect: config?.edgeEffect,
              titleExitShift: _titleExit,
              drift: drift,
              style: widget.style,
              menuStyle: widget.menuStyle,
              menuTuning: widget.menuTuning,
              menuOverlay: widget.menuOverlay,
            ),
          ),
          if (hasToolbar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MorphToolbar(
                leading: config?.toolbarLeading ?? const [],
                trailing: config?.toolbarTrailing ?? const [],
                style: widget.style,
                menuStyle: widget.menuStyle,
                menuTuning: widget.menuTuning,
                menuOverlay: widget.menuOverlay,
              ),
            ),
        ],
      ),
    );
  }
}

class _Observer extends NavigatorObserver {
  _Observer(this.state);

  final _MorphNavigationStackState state;

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) =>
      state._pushed(route);

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) =>
      state._removed(route);

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) =>
      state._removed(route);

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) =>
      state._replaced(oldRoute, newRoute);
}

/// A page of a [MorphNavigationStack] (or of any navigator) that moves
/// like a UIKit navigation controller's.
///
/// A push slides the page in from the trailing edge while the page below
/// slides 30 percent of the width the other way; both ride
/// [MorphNavigationTransition.pushSpring], starting at full speed. A swipe
/// that starts within [MorphNavigationTransition.edgeWidth] of the leading
/// edge moves the page with the finger; on release it pops when the page
/// is more than [MorphNavigationTransition.popDistance] of the width out
/// or the finger flicks out, and settles on
/// [MorphNavigationTransition.interactiveSpring]: a popping page from
/// rest, a returning one carrying the release speed scaled by
/// [MorphNavigationTransition.cancelVelocityScale]. Right-to-left text
/// mirrors everything.
///
/// With a [zoomSource] the page instead zooms out of that tag, as a UIKit
/// page pushed with `preferredTransition = .zoom`: the source hides, a
/// container grows from its frame to the screen while the source's look
/// crossfades into the page, the page underneath dims and stays put. A
/// pop zooms the page back into the source, which shows again once the
/// zoom rests; a finger dragging the page down, or from the leading edge
/// in any direction, shrinks it under the finger and on release either
/// zooms it back into the source or returns it. See
/// [MorphPushZoomMotion]; [pushMorphZoom] pushes such a page.
class MorphNavigationRoute<T> extends PageRoute<T>
    with MorphMotionRouteMixin<T> {
  /// Creates a route for the page [builder] builds.
  MorphNavigationRoute({
    required this.builder,
    this.zoomSource,
    this.zoom = MorphPushZoomTuning.standard,
    super.settings,
  });

  /// Builds the page.
  final WidgetBuilder builder;

  /// The source tag's id, or null for a page that slides in.
  ///
  /// An absent or unlaid-out tag shows the page in place.
  final Object? zoomSource;

  MorphZoomSource? _zoomSource;
  late final _NavigationZoomHost<T> _zoomHost = _NavigationZoomHost<T>(this);

  /// The measured zoom used when there is a [zoomSource].
  final MorphPushZoomTuning zoom;

  bool _interactivePop = false;
  MorphPushZoomPageState? _zoomView;

  bool get _zooms => zoomSource != null;

  AnimationController? get _gestureController => controller;

  @override
  bool get usesMotionRoute => _zooms;

  @override
  bool leaveMotionRoute() {
    final view = _zoomView;
    if (view == null || !view.mounted) return false;
    view.leave();
    return true;
  }

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  bool get opaque => !_zooms;

  /// The duration of the route's controller when nothing drives it with
  /// a spring: it only bounds a pop the navigator runs on its own.
  static const Duration _slideDuration = Duration(milliseconds: 600);

  /// The reverse duration of a zoomed page's controller, which the zoom
  /// sets to 0 itself when it rests.
  static const Duration _zoomReverseDuration = Duration(seconds: 1);

  @override
  Duration get transitionDuration => _zooms ? Duration.zero : _slideDuration;

  @override
  Duration get reverseTransitionDuration =>
      _zooms ? _zoomReverseDuration : transitionDuration;

  @override
  bool get popGestureEnabled => super.popGestureEnabled && !isFirst;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      !(nextRoute is MorphNavigationRoute && nextRoute._zooms);

  @override
  TickerFuture didPush() {
    final future = super.didPush();
    final c = controller;
    if (c == null || _zooms) return future;
    return c.animateWith(
      SpringSimulation(
        MorphNavigationTransition.pushSpring.description,
        c.value,
        1,
        _reduced ? 0 : MorphNavigationTransition.pushVelocity,
      ),
    );
  }

  bool get _reduced {
    final context = navigator?.context;
    return context != null && morphReducedMotionOf(context);
  }

  @override
  bool didPop(T? result) {
    final popped = super.didPop(result);
    final c = controller;
    if (_zooms) return popped;
    if (c == null) return popped;
    final interactive = _interactivePop;
    _interactivePop = false;
    c.animateBackWith(
      SpringSimulation(
        interactive
            ? MorphNavigationTransition.interactiveSpring.description
            : MorphNavigationTransition.pushSpring.description,
        c.value,
        0,
        interactive || _reduced ? 0 : -MorphNavigationTransition.pushVelocity,
      ),
    );
    return popped;
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    child: builder(context),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (_zooms) {
      _zoomSource ??= MorphZoomSource.resolve(context, zoomSource);
      return MorphPushZoomPage(host: _zoomHost, child: child);
    }
    if (morphReducedMotionOf(context)) {
      return FadeTransition(
        opacity: animation,
        child: _EdgePop(route: this, child: child),
      );
    }
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      builder: (BuildContext context, Widget? child) {
        final width = MediaQuery.maybeSizeOf(context)?.width ?? 0;
        final x =
            width *
            ((1 - animation.value) -
                MorphNavigationTransition.parallax * secondaryAnimation.value);
        return Transform.translate(
          offset: Offset(rtl ? -x : x, 0),
          child: child,
        );
      },
      child: _EdgePop(route: this, child: child),
    );
  }
}

/// Pushes the page [builder] builds onto the navigator around [context],
/// zoomed out of the [MorphTag] with id [from] under the [MorphScope]
/// around [context], as UIKit pushes a view controller whose
/// `preferredTransition` is `.zoom`; see [MorphNavigationRoute.zoomSource].
///
/// An absent or unlaid-out source shows the page in place. If the source
/// disappears while the page is open, its content stays usable and its
/// dismissal dissolves instead of landing on the old source frame.
Future<T?> pushMorphZoom<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  required Object from,
  MorphPushZoomTuning zoom = MorphPushZoomTuning.standard,
  RouteSettings? settings,
}) {
  final route = MorphNavigationRoute<T>(
    builder: builder,
    zoomSource: from,
    zoom: zoom,
    settings: settings,
  );
  route._zoomSource = MorphZoomSource.resolve(context, from);
  return Navigator.of(context).push<T>(route);
}

class _NavigationZoomHost<T> implements MorphPushZoomHost {
  _NavigationZoomHost(this.route);

  final MorphNavigationRoute<T> route;

  @override
  MorphZoomSource get zoomFrom => route._zoomSource!;

  @override
  MorphPushZoomTuning get zoomTuning => route.zoom;

  @override
  bool get zoomIsCurrent => route.isCurrent;

  @override
  void zoomPop() => route.popMotionRoute();

  @override
  void zoomClosed() => route.finishMotionRoute();

  @override
  void attachZoomView(MorphPushZoomPageState? view) => route._zoomView = view;
}

class _EdgePop extends StatefulWidget {
  const _EdgePop({required this.route, required this.child});

  final MorphNavigationRoute<Object?> route;
  final Widget child;

  @override
  State<_EdgePop> createState() => _EdgePopState();
}

class _EdgePopState extends State<_EdgePop> {
  HorizontalDragGestureRecognizer? _drag;
  bool _active = false;
  _MorphNavigationStackState? _stack;
  NavigatorState? _navigator;
  VoidCallback? _detach;

  @override
  void dispose() {
    _drag?.dispose();
    _detach?.call();
    _detach = null;
    if (_navigator != null) {
      final navigator = _navigator;
      final stack = _stack;
      final route = widget.route;
      _navigator = null;
      _stack = null;
      _active = false;
      SchedulerBinding.instance.addPostFrameCallback((Duration _) {
        if (navigator != null && navigator.mounted) {
          navigator.didStopUserGesture();
        }
        stack?._swipeEnded(route);
      });
    }
    super.dispose();
  }

  bool get _rtl => Directionality.maybeOf(context) == TextDirection.rtl;

  double get _width => context.size?.width ?? 1;

  void _down(PointerDownEvent event) {
    final route = widget.route;
    if (!route.isCurrent || !route.popGestureEnabled) return;
    final edge = _rtl
        ? _width - event.localPosition.dx
        : event.localPosition.dx;
    if (edge > MorphNavigationTransition.edgeWidth) return;
    final drag = _drag ??= HorizontalDragGestureRecognizer(debugOwner: this);
    drag.onStart = _start;
    drag.onUpdate = _update;
    drag.onEnd = _end;
    drag.onCancel = _cancel;
    drag.addPointer(event);
  }

  void _start(DragStartDetails details) {
    final route = widget.route;
    _active = true;
    final navigator = route.navigator;
    _navigator = navigator;
    navigator?.didStartUserGesture();
    final animation = route.animation;
    final stack = context.getInheritedWidgetOfExactType<_StackScope>()?.state;
    _stack = stack;
    if (stack != null && animation != null) {
      stack._swipeStarted(route, animation);
    }
  }

  void _update(DragUpdateDetails details) {
    final c = widget.route._gestureController;
    if (!_active || c == null) return;
    final d = (details.primaryDelta ?? 0) / _width;
    c.value = (c.value - (_rtl ? -d : d)).clamp(0.0, 1.0);
  }

  void _end(DragEndDetails details) {
    final route = widget.route;
    final c = route._gestureController;
    if (!_active || c == null) return;
    _active = false;
    final v = (details.primaryVelocity ?? 0) / _width * (_rtl ? -1 : 1);
    const flick = MorphNavigationTransition.popVelocity;
    final commit =
        v > flick ||
        (v > -flick && c.value < 1 - MorphNavigationTransition.popDistance);
    if (commit) {
      final navigator = route.navigator;
      if (route.isCurrent) {
        route._interactivePop = true;
        navigator?.pop();
      } else if (route.isActive) {
        navigator?.removeRoute(route);
      }
    } else {
      c.animateWith(
        SpringSimulation(
          MorphNavigationTransition.interactiveSpring.description,
          c.value,
          1,
          -v * MorphNavigationTransition.cancelVelocityScale,
        ),
      );
    }
    _stopWhenSettled(c);
  }

  void _cancel() {
    final c = widget.route._gestureController;
    if (!_active || c == null) return;
    _active = false;
    c.animateWith(
      SpringSimulation(
        MorphNavigationTransition.interactiveSpring.description,
        c.value,
        1,
        0,
      ),
    );
    _stopWhenSettled(c);
  }

  void _stopWhenSettled(AnimationController c) {
    final route = widget.route;
    void stop() {
      _detach = null;
      final navigator = _navigator;
      final stack = _stack;
      _navigator = null;
      _stack = null;
      navigator?.didStopUserGesture();
      stack?._swipeEnded(route);
    }

    if (!mounted || !c.isAnimating) {
      stop();
      return;
    }
    void listener(AnimationStatus status) {
      if (c.isAnimating) return;
      c.removeStatusListener(listener);
      stop();
    }

    c.addStatusListener(listener);
    _detach = () => c.removeStatusListener(listener);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    behavior: HitTestBehavior.translucent,
    child: widget.child,
  );
}

/// One screen of an iOS 27 app: a scroll view under a navigation bar
/// with an optional large title, the scroll edge effect, and an optional
/// toolbar.
///
/// Inside a [MorphNavigationStack] the scaffold hands its title, buttons
/// and scroll state to the stack's shared bars; on its own it draws its
/// bars itself. With [largeTitle] the title first shows large at the top
/// of the content; once it has scrolled fully under the bar, the bar's
/// inline title rises in, and a drag released halfway settles it to
/// either side ([MorphLargeTitleScrollPhysics]). The edge effect shows
/// once content lies under the bar.
class MorphNavigationScaffold extends StatefulWidget {
  /// Creates a scaffold scrolling [slivers].
  const MorphNavigationScaffold({
    required this.title,
    required this.slivers,
    this.largeTitle = false,
    this.leading,
    this.trailing = const [],
    this.toolbarLeading = const [],
    this.toolbarTrailing = const [],
    this.edgeEffect = MorphScrollEdgeEffectStyle.hard,
    this.backgroundColor,
    this.backTitle,
    this.backLabel = 'Back',
    this.controller,
    this.style,
    super.key,
  });

  /// The screen's title.
  final String title;

  /// The content.
  final List<Widget> slivers;

  /// Whether the title shows large above the content until it scrolls
  /// under the bar.
  final bool largeTitle;

  /// The group at the leading edge of the navigation bar; null shows a
  /// back button when the screen is not the first of its stack.
  final MorphBarButtonGroup? leading;

  /// The groups at the trailing edge of the navigation bar.
  final List<MorphBarButtonGroup> trailing;

  /// The groups at the leading edge of the toolbar.
  final List<MorphBarButtonGroup> toolbarLeading;

  /// The groups at the trailing edge of the toolbar.
  final List<MorphBarButtonGroup> toolbarTrailing;

  /// The scroll edge effect under the navigation bar; null draws none.
  final MorphScrollEdgeEffectStyle? edgeEffect;

  /// The color behind the content; defaults to the
  /// [MorphScrollEdgeEffectThemeData.backgroundColor] of the ambient theme
  /// (the system background), the color the edge effect fades toward.
  final Color? backgroundColor;

  /// The label of the next screen's back button; defaults to [title].
  final String? backTitle;

  /// The label screen readers announce for the back button the scaffold
  /// draws itself, outside a [MorphNavigationStack].
  final String backLabel;

  /// The controller of the scroll view.
  final ScrollController? controller;

  /// The look of the bars; null resolves it from the theme.
  final MorphBarStyle? style;

  @override
  State<MorphNavigationScaffold> createState() =>
      _MorphNavigationScaffoldState();
}

class _MorphNavigationScaffoldState extends State<MorphNavigationScaffold> {
  ScrollController? _own;
  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());
  bool _scrolledUnder = false;
  bool _titleVisible = false;
  bool _animate = true;

  @override
  void initState() {
    super.initState();
    _titleVisible = !widget.largeTitle;
    _controller.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(MorphNavigationScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _own)?.removeListener(_scrolled);
      _controller.addListener(_scrolled);
    }
    if (oldWidget.largeTitle != widget.largeTitle) _scrolled();
  }

  @override
  void dispose() {
    _controller.removeListener(_scrolled);
    _own?.dispose();
    super.dispose();
  }

  void _scrolled() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final offset = position.pixels - position.minScrollExtent;
    final threshold = widget.largeTitle
        ? MorphNavigationBarMetrics.largeTitleHeight
        : 0.0;
    final under =
        offset > threshold + 0.5 || (!widget.largeTitle && offset > 0.5);
    final title = !widget.largeTitle || offset >= threshold - 0.5;
    if (under == _scrolledUnder && title == _titleVisible) return;
    final animate = position.isScrollingNotifier.value;
    setState(() {
      _scrolledUnder = under;
      _titleVisible = title;
      _animate = animate;
    });
  }

  MorphNavigationConfig get _config => MorphNavigationConfig(
    title: widget.title,
    leading: widget.leading,
    trailing: widget.trailing,
    toolbarLeading: widget.toolbarLeading,
    toolbarTrailing: widget.toolbarTrailing,
    titleVisible: _titleVisible,
    scrolledUnder: _scrolledUnder,
    animate: _animate,
    edgeEffect: widget.edgeEffect,
    backTitle: widget.backTitle,
  );

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final stack = context
        .dependOnInheritedWidgetOfExactType<_StackScope>()
        ?.state;
    final shared = stack != null && route != null && stack._owns(route);
    final config = _config;
    if (shared) stack._publish(route, config);
    final media = MediaQuery.maybeOf(context);
    final top = media?.padding.top ?? 0;
    final hasToolbar = config.hasToolbar;
    final background =
        widget.backgroundColor ??
        MorphScrollEdgeEffectThemeData.resolve(context, null).backgroundColor;
    final physics = widget.largeTitle
        ? const MorphLargeTitleScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
          )
        : const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics());
    final toolbarExtent = hasToolbar
        ? const MorphToolbar().extentFor(media?.viewInsets.bottom ?? 0)
        : (media?.padding.bottom ?? 0);
    final scroll = MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: CustomScrollView(
        controller: _controller,
        physics: physics,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(top: MorphNavigationBar.heightFor(top)),
          ),
          if (widget.largeTitle)
            SliverToBoxAdapter(
              child: MorphLargeTitle(widget.title, style: widget.style),
            ),
          ...widget.slivers,
          SliverPadding(padding: EdgeInsets.only(bottom: toolbarExtent)),
        ],
      ),
    );
    final body = ColoredBox(color: background, child: scroll);
    if (shared) return body;
    var leading = widget.leading;
    if (leading == null && (route?.canPop ?? false)) {
      leading = MorphBarButtonGroup([
        MorphBarButton.back(
          semanticLabel: widget.backLabel,
          onPressed: () => Navigator.maybePop(context),
        ),
      ]);
    }
    return Stack(
      children: [
        Positioned.fill(child: body),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: MorphNavigationBar(
            title: widget.title,
            leading: leading,
            trailing: widget.trailing,
            titleVisible: _titleVisible,
            scrolledUnder: _scrolledUnder,
            animate: _animate,
            edgeEffect: widget.edgeEffect,
            style: widget.style,
          ),
        ),
        if (hasToolbar)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MorphToolbar(
              leading: widget.toolbarLeading,
              trailing: widget.toolbarTrailing,
              style: widget.style,
            ),
          ),
      ],
    );
  }
}
