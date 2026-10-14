import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart'
    show BoxHitTestResult, RenderRepaintBoundary, RenderTransform;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/bar_items.dart';
import 'package:morph/src/widgets/chrome_group.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/menu_entries.dart';
import 'package:morph/src/widgets/navigation_bar.dart';
import 'package:morph/src/presentation.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/widgets/navigation_motion.dart';
import 'package:morph/src/widgets/navigation_snapshot.dart';
import 'package:morph/src/widgets/motion_route.dart';
import 'package:morph/src/widgets/push_zoom.dart';
import 'package:morph/src/widgets/push_zoom_motion.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/scroll_edge_effect.dart';
import 'package:morph/src/widgets/search_stacked.dart';
import 'package:morph/src/widgets/scroll_indicator.dart';
import 'package:morph/src/widgets/toolbar.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/widgets/widgets_theme.dart';
import 'package:morph/src/widgets/zoom_source.dart';

/// What one screen of a [MorphNavigationStack] shows in the shared bars.
@immutable
class MorphNavigationConfig {
  /// Creates a configuration.
  const MorphNavigationConfig({
    this.title,
    this.leading = const [],
    this.trailing = const [],
    this.toolbarLeading = const [],
    this.toolbarTrailing = const [],
    this.titleVisible = true,
    this.scrolledUnder = false,
    this.animate = true,
    this.edgeEffect = MorphScrollEdgeEffectStyle.hard,
    this.backButtonTitle,
    this.subtitle,
    this.backButtonDisplayMode = MorphBackButtonDisplayMode.standard,
    this.hidesBackButton = false,
    this.largeTitleDisplayMode = MorphLargeTitleDisplayMode.never,
    this.navigationBarHidden = false,
    this.barHiding,
  });

  /// Whether the navigation bar steps aside for this screen: it shows
  /// neither title nor buttons and lets touches through to the page, as
  /// while a page's stacked search is presented (UIKit
  /// `hidesNavigationBarDuringPresentation`).
  final bool navigationBarHidden;

  /// The screen's title.
  final String? title;

  /// The motion that hides the navigation bar while the screen asks for
  /// it ([MorphNavigationScaffold.navigationBarHidden]), or null for a bar
  /// that always shows. Compared by identity.
  final MorphNavigationBarHiding? barHiding;

  /// The line under the inline title (UIKit `UINavigationItem.subtitle`,
  /// iOS 26), or null.
  final String? subtitle;

  /// How the next screen's back button shows this screen (UIKit
  /// `backButtonDisplayMode`).
  final MorphBackButtonDisplayMode backButtonDisplayMode;

  /// Whether the screen shows no back button (UIKit `hidesBackButton`).
  final bool hidesBackButton;

  /// Whether the screen shows its title large, resolved: never
  /// [MorphLargeTitleDisplayMode.automatic]. A screen pushed with
  /// `automatic` above this one takes it.
  final MorphLargeTitleDisplayMode largeTitleDisplayMode;

  /// The groups at the leading edge of the navigation bar (UIKit
  /// `leftBarButtonItems`); they replace the back button, as UIKit's do
  /// while `leftItemsSupplementBackButton` is off. Empty shows a back
  /// button when the screen is not the first.
  final List<MorphBarButtonGroup> leading;

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
  final String? backButtonTitle;

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
      listEquals(other.leading, leading) &&
      listEquals(other.trailing, trailing) &&
      listEquals(other.toolbarLeading, toolbarLeading) &&
      listEquals(other.toolbarTrailing, toolbarTrailing) &&
      other.titleVisible == titleVisible &&
      other.scrolledUnder == scrolledUnder &&
      other.animate == animate &&
      other.edgeEffect == edgeEffect &&
      other.backButtonTitle == backButtonTitle &&
      other.subtitle == subtitle &&
      other.backButtonDisplayMode == backButtonDisplayMode &&
      other.hidesBackButton == hidesBackButton &&
      other.largeTitleDisplayMode == largeTitleDisplayMode &&
      other.navigationBarHidden == navigationBarHidden &&
      identical(other.barHiding, barHiding);

  @override
  int get hashCode => Object.hash(
    title,
    Object.hashAll(leading),
    Object.hashAll(trailing),
    Object.hashAll(toolbarLeading),
    Object.hashAll(toolbarTrailing),
    titleVisible,
    scrolledUnder,
    animate,
    edgeEffect,
    backButtonTitle,
    subtitle,
    backButtonDisplayMode,
    hidesBackButton,
    largeTitleDisplayMode,
    navigationBarHidden,
    barHiding,
  );
}

final Expando<ValueNotifier<bool>> _barHideRequests =
    Expando<ValueNotifier<bool>>('MorphNavigationScaffold bar hiding');

/// How far a screen's navigation bar is hidden, 0 shown and 1 hidden,
/// following [MorphNavigationScaffold.navigationBarHidden] and
/// [MorphNavigationScaffold.setNavigationBarHidden].
///
/// Measured on a UIKit search controller presenting from a toolbar search
/// field (`hidesNavigationBarDuringPresentation`, iPhone 17 Pro simulator,
/// iOS 27.0, film of the 2026-10-14 sweep): on the focus the content moves
/// up to the status bar on one spring, fitted response 0.36 s, damping
/// 0.76 (1.2 pt rms over 17 frames, 102 points of travel), starting at
/// once - 0.33 s before the keyboard starts to rise; the large title rides
/// up with the content and is gone by half the travel. Not measured: the
/// way back, and a bar with buttons or an inline title (morph slides the
/// whole bar up off the screen on the same progress: APPROXIMATION,
/// pending the iPhone).
class MorphNavigationBarHiding {
  MorphNavigationBarHiding._(this.progress, this.hidden);

  /// The progress, 0 shown and 1 hidden; it leaves 0 to 1 when the spring
  /// overshoots.
  final Animation<double> progress;

  /// Whether the bar is asked to hide: it takes no touches then.
  final ValueListenable<bool> hidden;

  /// The spring the content and the bar move on (fit, see the class).
  static const MorphSpring spring = MorphSpring(0.36, 0.76);

  /// How fast the large title fades: its opacity is
  /// `1 - largeTitleFade * progress` (read by eye from the film: faint at
  /// 0.5 of the travel, gone at 0.6).
  static const double largeTitleFade = 2;
}

/// How a back button shows the title of the screen it returns to, after
/// UIKit's `UINavigationItem.BackButtonDisplayMode`.
enum MorphBackButtonDisplayMode {
  /// The screen's back button title, else its title (UIKit `.default`).
  standard,

  /// A generic title: the stack's `backButtonSemanticLabel`, "Back" by
  /// default (UIKit `.generic`).
  generic,

  /// The chevron alone (UIKit `.minimal`).
  minimal,
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
///
/// [MorphNavigationStack.pages] builds the stack from a list of
/// [MorphNavigationPage]s instead, as UIKit's `viewControllers` and
/// SwiftUI's `NavigationStack(path:)` do: the Navigator 2 form that a
/// router such as go_router drives.
class MorphNavigationStack extends StatefulWidget {
  /// Creates a stack showing [home] first.
  const MorphNavigationStack({
    required Widget this.home,
    this.appearance,
    this.menuAppearance,
    this.menuTuning = MorphBarMenuTuning.standard,
    this.menuOverlay,
    this.backButtonSemanticLabel = 'Back',
    this.navigatorKey,
    this.observers = const [],
    this.prefersLargeTitles = false,
    this.contentPopGestureEnabled = true,
    super.key,
  }) : pages = null,
       onDidRemovePage = null;

  /// Creates a stack showing [pages], the last on top
  /// (`UINavigationController.viewControllers`).
  ///
  /// Use [MorphNavigationPage]s for the slide and zoom of this stack; any
  /// other [Page] shows its own route. A page added at the top is pushed
  /// and one removed from the top is popped, with the measured motion. A
  /// page the user removes - the back button, its menu, the edge swipe,
  /// the system back - is reported to [onDidRemovePage], which must drop
  /// it from [pages], as [Navigator.onDidRemovePage] asks.
  const MorphNavigationStack.pages({
    required List<Page<Object?>> this.pages,
    required void Function(Page<Object?> page) this.onDidRemovePage,
    this.appearance,
    this.menuAppearance,
    this.menuTuning = MorphBarMenuTuning.standard,
    this.menuOverlay,
    this.backButtonSemanticLabel = 'Back',
    this.navigatorKey,
    this.observers = const [],
    this.prefersLargeTitles = false,
    this.contentPopGestureEnabled = true,
    super.key,
  }) : home = null;

  /// The first screen, or null for a stack built from [pages].
  ///
  /// Read once, when the stack's navigator is created, like [navigatorKey]
  /// and [observers].
  final Widget? home;

  /// The screens of a [MorphNavigationStack.pages] stack, or null.
  final List<Page<Object?>>? pages;

  /// Called when the user removes a page of [pages], or null.
  final void Function(Page<Object?> page)? onDidRemovePage;

  /// Whether a first screen whose [MorphNavigationScaffold] asks for
  /// [MorphLargeTitleDisplayMode.automatic] shows its title large (UIKit
  /// `UINavigationBar.prefersLargeTitles`); later automatic screens take
  /// the mode of the screen below.
  final bool prefersLargeTitles;

  /// Whether a horizontal drag toward the trailing side from anywhere in
  /// a pushed page's content pops it interactively, as UIKit's
  /// `interactiveContentPopGestureRecognizer` (iOS 26, on by default);
  /// false leaves only the swipe from the leading edge.
  ///
  /// The content swipe moves and releases the page exactly as the edge
  /// swipe does. A horizontal scrollable, slider or other horizontal drag
  /// under the finger keeps its drag; a drag toward the leading side never
  /// starts the swipe. A touch starts after 30 points of radial travel,
  /// within 30 degrees of horizontal (device-fitted boundary, NEAR).
  /// Native horizontal-strip captures keep the scroll gesture at its
  /// leading end and when already scrolled.
  final bool contentPopGestureEnabled;

  /// The look of the bars; null resolves it from the theme.
  final MorphBarAppearance? appearance;

  /// The look of the back button's menu; null resolves it from the theme.
  final MorphMenuAppearance? menuAppearance;

  /// The bar buttons' menu recognition, opening delay and menu motion.
  final MorphBarMenuTuning menuTuning;

  /// The overlay the bars' menus fly in; null uses
  /// [morphPresentationOverlayOf], the overlay around the stack.
  final OverlayState? menuOverlay;

  /// The label screen readers announce for the back button.
  final String backButtonSemanticLabel;

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
  late final List<NavigatorObserver> _observers = [
    _observer,
    ...widget.observers,
  ];
  Widget? _navigatorBuilt;
  List<Page<Object?>>? _navigatorPages;

  Widget get _navigatorWidget {
    final pages = widget.pages;
    final built = _navigatorBuilt;
    // Rebuilding the navigator calls changedExternalState on every route,
    // whose scaffolds then publish again: only a changed list of pages
    // rebuilds it.
    if (built != null && listEquals(pages, _navigatorPages)) return built;
    _navigatorPages = pages;
    return _navigatorBuilt = NavigatorPopHandler<Object?>(
      onPopWithResult: (Object? result) =>
          _navigator.currentState?.maybePop(result),
      child: pages == null
          ? Navigator(
              key: _navigator,
              observers: _observers,
              onGenerateInitialRoutes: (NavigatorState navigator, String _) => [
                MorphNavigationRoute<void>(builder: (_) => widget.home!),
              ],
            )
          : Navigator(
              key: _navigator,
              observers: _observers,
              pages: pages,
              onDidRemovePage: (Page<Object?> page) =>
                  widget.onDidRemovePage?.call(page),
            ),
    );
  }

  /// Whether the screen below [route] shows its title large, or for the
  /// first screen [MorphNavigationStack.prefersLargeTitles].
  bool _largeTitleBelow(Route<Object?> route) {
    final pages = [
      for (final r in _routes)
        if (r is PageRoute<Object?>) r,
    ];
    var i = route is PageRoute<Object?> ? pages.indexOf(route) : -1;
    if (i < 0) i = pages.length;
    if (i == 0) return widget.prefersLargeTitles;
    return _configs[pages[i - 1]]?.largeTitleDisplayMode ==
        MorphLargeTitleDisplayMode.always;
  }

  bool _scheduled = false;
  double _titleExit = -MorphNavigationTuning.parallax;
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
    assert(
      (oldWidget.pages == null) == (widget.pages == null),
      'A MorphNavigationStack cannot switch between home and pages.',
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
    _titleExit = -MorphNavigationTuning.parallax;
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

  final BackdropKey _barsBackdrop = BackdropKey();

  // A bar repaints on its own: its motion leaves the pages and the
  // navigator around it unpainted.
  Widget _bars(Widget bar, {bool hidden = false}) => _BarBoundary(
    hidden: hidden,
    child: MorphChromeBackdropScope(backdropKey: _barsBackdrop, child: bar),
  );

  List<MorphBarButtonGroup> _leadingOf(
    List<PageRoute<Object?>> pages,
    int index,
  ) {
    final config = _configs[pages[index]];
    final leading = config?.leading ?? const [];
    if (leading.isNotEmpty || index == 0) return leading;
    if (config?.hidesBackButton ?? false) return leading;
    final below = _configs[pages[index - 1]];
    final back = MorphBarButtonGroup([
      MorphBarButton.back(
        label: switch (below?.backButtonDisplayMode) {
          MorphBackButtonDisplayMode.minimal => null,
          MorphBackButtonDisplayMode.generic => widget.backButtonSemanticLabel,
          _ => below?.backButtonTitle ?? below?.title,
        },
        semanticLabel: widget.backButtonSemanticLabel,
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
    return [back];
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
    final leading = top == null
        ? const <MorphBarButtonGroup>[]
        : _leadingOf(pages, index);
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
      child: MorphPresentationBoundary(
        child: Stack(
          children: [
            Positioned.fill(child: _navigatorWidget),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _bars(
                hidden: config?.navigationBarHidden ?? false,
                MorphNavigationBar(
                  title: config?.title,
                  subtitle: config?.subtitle,
                  leading: leading,
                  trailing: config?.trailing ?? const [],
                  titleVisible: config?.titleVisible ?? true,
                  scrolledUnder: config?.scrolledUnder ?? false,
                  animate: config?.animate ?? true,
                  edgeEffect: config?.edgeEffect,
                  titleExitShift: _titleExit,
                  drift: drift,
                  hiding: config?.barHiding?.progress,
                  hidden: config?.barHiding?.hidden,
                  appearance: widget.appearance,
                  menuAppearance: widget.menuAppearance,
                  menuTuning: widget.menuTuning,
                  menuOverlay: widget.menuOverlay,
                ),
              ),
            ),
            if (hasToolbar)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _bars(
                  MorphToolbar(
                    leading: config?.toolbarLeading ?? const [],
                    trailing: config?.toolbarTrailing ?? const [],
                    appearance: widget.appearance,
                    menuAppearance: widget.menuAppearance,
                    menuTuning: widget.menuTuning,
                    menuOverlay: widget.menuOverlay,
                  ),
                ),
              ),
          ],
        ),
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
/// [MorphNavigationTuning.pushSpring], starting at full speed. A swipe
/// that starts within [MorphNavigationTuning.edgeWidth] of the leading
/// edge moves the page with the finger; on release it pops when the page
/// is more than [MorphNavigationTuning.popDistance] of the width out
/// or the finger flicks out, and settles on
/// [MorphNavigationTuning.interactiveSpring]: a popping page from
/// rest, a returning one carrying the release speed scaled by
/// [MorphNavigationTuning.cancelVelocityScale]. Inside a
/// [MorphNavigationStack] whose
/// [MorphNavigationStack.contentPopGestureEnabled] is on (and outside
/// any stack) a drag toward the trailing side from anywhere in the page
/// does the same. Right-to-left text mirrors everything.
///
/// While the page slides it is a card with the display's continuous
/// corners ([MediaQueryData.displayCornerRadii], else
/// [MorphNavigationTuning.fallbackCardRadius]), and the page underneath
/// dims with black up to [MorphNavigationTuning.underDimOpacity] as the
/// page on top covers it (APPROXIMATION, see that constant).
///
/// With a [from] the page instead zooms out of that tag, as a UIKit
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
    this.from,
    this.zoom = MorphPushZoomTuning.standard,
    super.settings,
  });

  /// Builds the page.
  final WidgetBuilder builder;

  /// The source tag's id, or null for a page that slides in.
  ///
  /// An absent or unlaid-out tag shows the page in place.
  final Object? from;

  MorphZoomSource? _zoomSource;
  late final _NavigationZoomHost<T> _zoomHost = _NavigationZoomHost<T>(this);

  /// The measured zoom used when there is a [from].
  final MorphPushZoomTuning zoom;

  bool _interactivePop = false;
  MorphPushZoomPageState? _zoomView;
  Listenable? _slide;
  Animation<double>? _slideAnimation;
  Animation<double>? _slideSecondary;

  /// The one merged source of the slide for the route's two animations:
  /// a fresh merge per transition build would rebind the live transform's
  /// listeners on every frame.
  Listenable _slideOf(
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final slide = _slide;
    if (slide != null &&
        identical(animation, _slideAnimation) &&
        identical(secondaryAnimation, _slideSecondary)) {
      return slide;
    }
    _slideAnimation = animation;
    _slideSecondary = secondaryAnimation;
    return _slide = Listenable.merge([animation, secondaryAnimation]);
  }

  bool get _zooms => from != null;

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
      MorphFirstFrameStart(
        _reduced
            ? _CrossFade(c.value, 1)
            : SpringSimulation(
                MorphNavigationTuning.pushSpring.description,
                c.value,
                1,
                MorphNavigationTuning.pushVelocity,
              ),
        period: _framePeriod,
      ),
    );
  }

  double get _framePeriod {
    final context = navigator?.context;
    final rate = context == null
        ? 0.0
        : View.maybeOf(context)?.display.refreshRate ?? 0.0;
    return rate > 0 ? 1 / rate : 1 / 60;
  }

  bool get _reduced {
    final context = navigator?.context;
    return context != null && morphReducedMotionOf(context);
  }

  // Under Reduce Motion the pages cross-fade, except while an edge swipe
  // drags them and settles them: UIKit keeps the slide for a finger.
  bool _crossFades(BuildContext context) =>
      morphReducedMotionOf(context) &&
      !(navigator?.userGestureInProgress ?? false);

  Animation<double>? _leavingFrom;
  Animation<double>? _leaving;

  // The swipe's state survives the switch between the cross-fade and the
  // slide when a finger takes a page under Reduce Motion.
  final GlobalKey _edgeKey = GlobalKey();

  Animation<double> _leavingOf(Animation<double> secondaryAnimation) {
    final leaving = _leaving;
    if (leaving != null && identical(_leavingFrom, secondaryAnimation)) {
      return leaving;
    }
    _leavingFrom = secondaryAnimation;
    return _leaving = ReverseAnimation(secondaryAnimation);
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
      !interactive && _reduced
          ? _CrossFade(c.value, 0)
          : SpringSimulation(
              interactive
                  ? MorphNavigationTuning.interactiveSpring.description
                  : MorphNavigationTuning.pushSpring.description,
              c.value,
              0,
              interactive ? 0 : -MorphNavigationTuning.pushVelocity,
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

  Object? _transitionInputs;
  Widget? _transition;

  // The route's scope builds the transition on every tick of either
  // animation and hands it a fresh wrapper of the same page each time.
  // Handing back the transition built before stops the rebuild there: the
  // slide follows the animations through live render objects, and the
  // wrapper only reads the animation's status and the user gesture, which
  // it follows itself.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final page = switch (child) {
      final ListenableBuilder wrapper => wrapper.child,
      _ => null,
    };
    final inputs = page == null
        ? null
        : (
            page,
            animation,
            secondaryAnimation,
            animation.status,
            Directionality.maybeOf(context),
            _crossFades(context),
            MorphNavigationSnapshot.enabled,
            _cardRadiusOf(context),
          );
    final kept = _transition;
    if (inputs != null && kept != null && inputs == _transitionInputs) {
      return kept;
    }
    _transitionInputs = inputs;
    return _transition = _buildTransition(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }

  Widget _buildTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (_zooms) {
      _zoomSource ??= MorphZoomSource.resolve(context, from);
      return MorphPushZoomPage(host: _zoomHost, child: child);
    }
    if (_crossFades(context)) {
      return FadeTransition(
        opacity: animation,
        child: FadeTransition(
          opacity: _leavingOf(secondaryAnimation),
          child: _EdgePop(key: _edgeKey, route: this, child: child),
        ),
      );
    }
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final page = _EdgePop(key: _edgeKey, route: this, child: child);
    final slid = MorphNavigationSnapshot.enabled
        ? MorphNavigationSnapshotHost(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            child: page,
          )
        : page;
    final radius = Radius.circular(_cardRadiusOf(context));
    final slide = _slideOf(animation, secondaryAnimation);
    var pageSize = Size.zero;
    // The page's own width, the unit the edge swipe measures the finger
    // in, so a stack narrower than the screen still tracks it 1:1.
    return MorphLiveTransform.sized(
      live: slide,
      writeSizedInto: (Matrix4 into, Size size) {
        pageSize = size;
        final x =
            size.width *
            ((1 - animation.value) -
                MorphNavigationTuning.parallax * secondaryAnimation.value);
        into.setTranslationRaw(rtl ? -x : x, 0, 0);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          MorphLiveBox(
            live: animation,
            clip: () => animation.isAnimating
                ? RRect.fromRectAndRadius(Offset.zero & pageSize, radius)
                : null,
            continuous: true,
            child: slid,
          ),
          CustomPaint(
            key: const ValueKey<String>('morph.navigation.dim'),
            painter: _NavigationDim(secondaryAnimation),
          ),
        ],
      ),
    );
  }

  /// The radius of the moving page's card: the display's own corner
  /// radius where the platform reports one.
  static double _cardRadiusOf(BuildContext context) =>
      MediaQuery.maybeDisplayCornerRadiiOf(context)?.topLeft.x ??
      MorphNavigationTuning.fallbackCardRadius;
}

/// Pushes the page [builder] builds onto the navigator around [context],
/// zoomed out of the [MorphTag] with id [from] under the [MorphScope]
/// around [context], as UIKit pushes a view controller whose
/// `preferredTransition` is `.zoom`; see [MorphNavigationRoute.from].
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
    from: from,
    zoom: zoom,
    settings: settings,
  );
  route._zoomSource = MorphZoomSource.resolve(context, from);
  return Navigator.of(context).push<T>(route);
}

class _NavigationDim extends CustomPainter {
  _NavigationDim(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = MorphNavigationTuning.underDimOpacity * animation.value;
    if (opacity <= 0) return;
    final paint = Paint();
    // Match the former opacity layer's eight-bit alpha exactly.
    paint.color = const Color(
      0xFF000000,
    ).withAlpha(Color.getAlphaFromOpacity(opacity.clamp(0.0, 1.0)));
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_NavigationDim oldDelegate) =>
      oldDelegate.animation != animation;
}

/// A page of a [MorphNavigationStack.pages] stack (or of any Navigator 2
/// navigator) that shows [child] in a [MorphNavigationRoute]: it slides in
/// and pops by the edge swipe, or with a [from] zooms out of that tag.
///
/// A router builds one per screen, keyed so the navigator matches it to
/// its route when the list changes; an updated page with the same key
/// rebuilds its route's [child].
class MorphNavigationPage<T> extends Page<T> {
  /// Creates a page showing [child].
  const MorphNavigationPage({
    required this.child,
    this.from,
    this.zoom = MorphPushZoomTuning.standard,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// The screen, usually a [MorphNavigationScaffold].
  final Widget child;

  /// The source tag's id the page zooms out of, or null for a page that
  /// slides in; see [MorphNavigationRoute.from].
  final Object? from;

  /// The measured zoom used when there is a [from].
  final MorphPushZoomTuning zoom;

  @override
  Route<T> createRoute(BuildContext context) => _PageRoute<T>(this);
}

class _PageRoute<T> extends MorphNavigationRoute<T> {
  _PageRoute(MorphNavigationPage<T> page)
    : super(builder: _never, from: page.from, zoom: page.zoom, settings: page);

  static Widget _never(BuildContext context) =>
      throw StateError('A page route builds its page.');

  MorphNavigationPage<T> get _page => settings as MorphNavigationPage<T>;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    child: _page.child,
  );
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
  bool get zoomCanPop => route.popGestureEnabled;

  @override
  Future<void> zoomPop() => route.popMotionRoute();

  @override
  void zoomClosed() => route.finishMotionRoute();

  @override
  void attachZoomView(MorphPushZoomPageState? view) => route._zoomView = view;
}

class _EdgePop extends StatefulWidget {
  const _EdgePop({required this.route, required this.child, super.key});

  final MorphNavigationRoute<Object?> route;
  final Widget child;

  @override
  State<_EdgePop> createState() => _EdgePopState();
}

class _EdgePopState extends State<_EdgePop> {
  HorizontalDragGestureRecognizer? _drag;
  _ContentPopDrag? _content;

  bool get _contentPopEnabled =>
      context
          .getInheritedWidgetOfExactType<_StackScope>()
          ?.state
          .widget
          .contentPopGestureEnabled ??
      true;
  bool _active = false;
  _MorphNavigationStackState? _stack;
  NavigatorState? _navigator;
  VoidCallback? _detach;

  @override
  void dispose() {
    _drag?.dispose();
    _content?.dispose();
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
    final HorizontalDragGestureRecognizer drag;
    if (edge <= MorphNavigationTuning.edgeWidth) {
      drag = _drag ??= HorizontalDragGestureRecognizer(debugOwner: this);
    } else if (_contentPopEnabled) {
      final content = _content ??= _ContentPopDrag(debugOwner: this);
      content.forward = _rtl ? -1 : 1;
      drag = content;
    } else {
      return;
    }
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
    const flick = MorphNavigationTuning.popVelocity;
    final commit =
        v > flick ||
        (v > -flick && c.value < 1 - MorphNavigationTuning.popDistance);
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
          MorphNavigationTuning.interactiveSpring.description,
          c.value,
          1,
          -v * MorphNavigationTuning.cancelVelocityScale,
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
        MorphNavigationTuning.interactiveSpring.description,
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

/// The back swipe from inside a page's content: a horizontal drag that
/// claims the pointer only once it has travelled the content-pop slop toward the
/// trailing side ([forward] is 1 left to right, -1 right to left), so a
/// drag the other way stays with whatever else wants it. A horizontal
/// scrollable, pan or scale recognizer under the finger sits deeper in
/// the hit test and reaches its own slop no later, so it keeps its drags.
class _ContentPopDrag extends HorizontalDragGestureRecognizer {
  _ContentPopDrag({super.debugOwner});

  double forward = 1;
  double _travel = 0;
  double _crossTravel = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _travel = 0;
    _crossTravel = 0;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _travel += event.delta.dx * forward;
      _crossTravel += event.delta.dy;
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    final slop = pointerDeviceKind == PointerDeviceKind.touch
        ? MorphNavigationTuning.contentPopTouchSlop
        : computePanSlop(pointerDeviceKind, gestureSettings);
    final angle = math.atan2(_crossTravel.abs(), _travel) * 180 / math.pi;
    return _travel > 0 &&
        angle < MorphNavigationTuning.contentPopMaxAngle &&
        _travel * _travel + _crossTravel * _crossTravel > slop * slop &&
        super.hasSufficientGlobalDistanceToAccept(
          pointerDeviceKind,
          deviceTouchSlop,
        );
  }
}

/// When a [MorphNavigationScaffold] shows its title large, after UIKit's
/// `UINavigationItem.LargeTitleDisplayMode`.
enum MorphLargeTitleDisplayMode {
  /// The screen takes the mode of the screen below it in its
  /// [MorphNavigationStack]; the first screen takes the stack's
  /// [MorphNavigationStack.prefersLargeTitles]. Outside a stack the title
  /// shows only inline.
  automatic,

  /// The title shows large above the content until it scrolls under the
  /// bar.
  always,

  /// The title shows only inline, in the bar.
  never,
}

/// One screen of an iOS 27 app: a scroll view under a navigation bar
/// with an optional large title, the scroll edge effect, and an optional
/// toolbar.
///
/// Inside a [MorphNavigationStack] the scaffold hands its title, buttons
/// and scroll state to the stack's shared bars; on its own it draws its
/// bars itself. With [largeTitleDisplayMode] `always` the title first
/// shows large at the top
/// of the content; once it has scrolled fully under the bar, the bar's
/// inline title rises in, and a drag released halfway settles it to
/// either side ([MorphLargeTitleScrollPhysics]). The edge effect shows
/// once content lies under the bar.
///
/// Text in the content reads in UIKit's body style ([MorphTypography.body]
/// in the label color of the bar style), so a plain [Text] on the page
/// needs no Material ancestor.
///
/// A [search] stacks a search field under the large title and presents it
/// over the page when tapped ([MorphNavigationSearch]).
class MorphNavigationScaffold extends StatefulWidget {
  /// Creates a scaffold scrolling [slivers].
  const MorphNavigationScaffold({
    required this.title,
    required this.slivers,
    this.largeTitleDisplayMode = MorphLargeTitleDisplayMode.automatic,
    this.subtitle,
    this.largeSubtitle,
    this.leading = const [],
    this.trailing = const [],
    this.toolbarLeading = const [],
    this.toolbarTrailing = const [],
    this.edgeEffect = MorphScrollEdgeEffectStyle.hard,
    this.backgroundColor,
    this.backButtonTitle,
    this.backButtonDisplayMode = MorphBackButtonDisplayMode.standard,
    this.hidesBackButton = false,
    this.backButtonSemanticLabel = 'Back',
    this.controller,
    this.appearance,
    this.search,
    this.navigationBarHidden = false,
    this.showsVerticalScrollIndicator = true,
    super.key,
  });

  /// Hides (or shows again) the navigation bar of the
  /// [MorphNavigationScaffold] on the route around [context], as
  /// [navigationBarHidden] does: what UIKit's search controller does while
  /// it presents (`hidesNavigationBarDuringPresentation`). The call may come
  /// from anywhere on that route, such as a search toolbar stacked over
  /// the scaffold; without a route it does nothing. A hidden
  /// [navigationBarHidden] stays hidden.
  static void setNavigationBarHidden(
    BuildContext context, {
    required bool hidden,
  }) {
    final route = ModalRoute.of(context);
    if (route == null) return;
    final request = _barHideRequests[route] ??= ValueNotifier<bool>(false);
    // A controlled search may change during its parent's build, after
    // the scaffold and the shared bar have already built this frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        request.value = hidden;
      });
      return;
    }
    request.value = hidden;
  }

  /// The page's search, a field stacked under the large title (UIKit
  /// `UINavigationItem.searchController` with the stacked placement), or
  /// null.
  final MorphNavigationSearch? search;

  /// The screen's title.
  final String title;

  /// The content.
  final List<Widget> slivers;

  /// Whether the title shows large above the content until it scrolls
  /// under the bar (UIKit `largeTitleDisplayMode`). The default,
  /// [MorphLargeTitleDisplayMode.automatic], is UIKit's: a stack's first
  /// screen follows [MorphNavigationStack.prefersLargeTitles] and every
  /// later one the screen below it, so a stack that prefers large titles
  /// shows them on every screen that does not opt out with `never`.
  final MorphLargeTitleDisplayMode largeTitleDisplayMode;

  /// Whether the navigation bar is hidden (UIKit
  /// `setNavigationBarHidden(_:animated:)`, SwiftUI
  /// `toolbarVisibility(.hidden, for: .navigationBar)`): the bar slides up
  /// off the screen and the content moves up to the status bar, on
  /// [MorphNavigationBarHiding]'s measured motion.
  /// [MorphNavigationScaffold.setNavigationBarHidden] hides it from below
  /// the scaffold's route, as a search toolbar does while it searches.
  final bool navigationBarHidden;

  /// Whether a vertical scroll indicator shows while the content scrolls
  /// (UIKit `showsVerticalScrollIndicator`, on by default): see
  /// [MorphScrollIndicator].
  final bool showsVerticalScrollIndicator;

  /// The line under the inline title (UIKit `UINavigationItem.subtitle`,
  /// iOS 26), or null; not yet measured on a device.
  final String? subtitle;

  /// The line under the large title (UIKit `largeSubtitle`, iOS 26), or
  /// null for [subtitle]; not yet measured on a device.
  final String? largeSubtitle;

  /// How the next screen's back button shows this screen (UIKit
  /// `backButtonDisplayMode`): its title, "Back", or the chevron alone.
  final MorphBackButtonDisplayMode backButtonDisplayMode;

  /// Whether this screen shows no back button (UIKit `hidesBackButton`).
  /// The leading edge swipe still pops; wrap the screen in a `PopScope`
  /// to block it too.
  final bool hidesBackButton;

  /// The groups at the leading edge of the navigation bar (UIKit
  /// `leftBarButtonItems`); they replace the back button. Empty shows a
  /// back button when the screen is not the first of its stack.
  final List<MorphBarButtonGroup> leading;

  /// The groups at the trailing edge of the navigation bar.
  final List<MorphBarButtonGroup> trailing;

  /// The groups at the leading edge of the toolbar.
  final List<MorphBarButtonGroup> toolbarLeading;

  /// The groups at the trailing edge of the toolbar.
  final List<MorphBarButtonGroup> toolbarTrailing;

  /// The scroll edge effect under the navigation bar; null draws none.
  final MorphScrollEdgeEffectStyle? edgeEffect;

  /// The color behind the content; defaults to the
  /// [MorphScrollEdgeEffectAppearance.backgroundColor] of the ambient theme
  /// (the system background), the color the edge effect fades toward.
  final Color? backgroundColor;

  /// The label of the next screen's back button; defaults to [title].
  final String? backButtonTitle;

  /// The label screen readers announce for the back button the scaffold
  /// draws itself, outside a [MorphNavigationStack].
  final String backButtonSemanticLabel;

  /// The controller of the scroll view.
  final ScrollController? controller;

  /// The look of the bars; null resolves it from the theme.
  final MorphBarAppearance? appearance;

  @override
  State<MorphNavigationScaffold> createState() =>
      _MorphNavigationScaffoldState();
}

class _MorphNavigationScaffoldState extends State<MorphNavigationScaffold>
    with SingleTickerProviderStateMixin<MorphNavigationScaffold> {
  ScrollController? _own;
  late final AnimationController _hiding = AnimationController.unbounded(
    vsync: this,
  );
  ValueNotifier<bool>? _request;
  bool _hidden = false;
  // How far the content moves up while the bar is hidden; set when the
  // bar starts to hide, so the motion never rebuilds the page.
  double _shift = 0;
  // The scroll view is laid out [_shift] taller while the bar is hidden or
  // moving, so the content it uncovers at the bottom is built.
  bool _extended = false;
  final BackdropKey _barsBackdrop = BackdropKey();

  // A bar repaints on its own: its motion leaves the pages and the
  // navigator around it unpainted.
  Widget _bars(Widget bar, {bool hidden = false}) => _BarBoundary(
    hidden: hidden,
    child: MorphChromeBackdropScope(backdropKey: _barsBackdrop, child: bar),
  );

  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());
  bool _scrolledUnder = false;
  bool _titleVisible = false;
  bool _animate = true;
  bool? _large;
  bool _searchPresented = false;

  bool get _hidesBar =>
      _searchPresented &&
      (widget.search?.hidesNavigationBarDuringPresentation ?? false);

  void _presented(bool presented) {
    if (presented == _searchPresented) return;
    setState(() => _searchPresented = presented);
  }

  bool get _largeTitle => _large ?? false;

  String? get _largeSubtitle => widget.largeSubtitle ?? widget.subtitle;

  double get _largeExtent =>
      MorphLargeTitle.extentFor(subtitle: _largeSubtitle != null);

  bool _resolveLarge() {
    switch (widget.largeTitleDisplayMode) {
      case MorphLargeTitleDisplayMode.always:
        return true;
      case MorphLargeTitleDisplayMode.never:
        return false;
      case MorphLargeTitleDisplayMode.automatic:
        final stack = context
            .getInheritedWidgetOfExactType<_StackScope>()
            ?.state;
        final route = ModalRoute.of(context);
        if (stack == null || route == null || !stack._owns(route)) {
          return false;
        }
        return stack._largeTitleBelow(route);
    }
  }

  void _updateLarge() {
    final large = _resolveLarge();
    final before = _large;
    if (before == large) return;
    _large = large;
    if (before == null) {
      _titleVisible = !large;
    } else {
      _scrolled();
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_scrolled);
    _hiding.addStatusListener(_hidingStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateLarge();
    final route = ModalRoute.of(context);
    final request = route == null
        ? null
        : _barHideRequests[route] ??= ValueNotifier<bool>(false);
    if (!identical(request, _request)) {
      _request?.removeListener(_requestChanged);
      _request = request;
      request?.addListener(_requestChanged);
      _updateHidden();
    }
  }

  // From a listener the change rebuilds the scaffold; from
  // didChangeDependencies / didUpdateWidget the build that follows reads
  // it.
  void _requestChanged() => _updateHidden(rebuild: true);

  void _updateHidden({bool rebuild = false}) {
    final hidden = widget.navigationBarHidden || (_request?.value ?? false);
    if (hidden == _hidden) return;
    _hidden = hidden;
    _hiddenNow.value = hidden;
    if (hidden) _shift = _hiddenShift();
    final target = hidden ? 1.0 : 0.0;
    final reduced = morphReducedMotionOf(context);
    final extended = hidden || !reduced;
    if (reduced) {
      _hiding.value = target;
    } else {
      _hiding.animateWith(
        SpringSimulation(
          MorphNavigationBarHiding.spring.description,
          _hiding.value,
          target,
          _hiding.velocity,
        ),
      );
    }
    if (extended == _extended) return;
    if (rebuild) {
      setState(() => _extended = extended);
    } else {
      _extended = extended;
    }
  }

  void _hidingStatus(AnimationStatus status) {
    if (_hidden || _hiding.isAnimating || !_extended) return;
    if (_hiding.value.abs() > 1e-3) return;
    _hiding.value = 0;
    setState(() => _extended = false);
  }

  // The bar's height plus what is left of the large title above the
  // content: UIKit moves the content up to the status bar.
  double _hiddenShift() {
    var shift = MorphNavigationBarMetrics.barHeight;
    if (_largeTitle && _controller.hasClients) {
      final position = _controller.position;
      final offset = position.pixels - position.minScrollExtent;
      shift += (_largeExtent - offset).clamp(0.0, _largeExtent);
    } else if (_largeTitle) {
      shift += _largeExtent;
    }
    return shift;
  }

  @override
  void didUpdateWidget(MorphNavigationScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _own)?.removeListener(_scrolled);
      _controller.addListener(_scrolled);
    }
    _updateLarge();
    if ((oldWidget.largeSubtitle ?? oldWidget.subtitle) != _largeSubtitle) {
      _scrolled();
    }
    if (oldWidget.navigationBarHidden != widget.navigationBarHidden) {
      _updateHidden();
    }
  }

  @override
  void dispose() {
    _request?.removeListener(_requestChanged);
    _hiding.dispose();
    _hiddenNow.dispose();
    _controller.removeListener(_scrolled);
    _own?.dispose();
    super.dispose();
  }

  void _scrolled() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final offset = position.pixels - position.minScrollExtent;
    final threshold = _largeTitle ? _largeExtent : 0.0;
    final under = offset > threshold + 0.5 || (!_largeTitle && offset > 0.5);
    final title = !_largeTitle || offset >= threshold - 0.5;
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
    subtitle: widget.subtitle,
    backButtonDisplayMode: widget.backButtonDisplayMode,
    hidesBackButton: widget.hidesBackButton || _hidesBar,
    largeTitleDisplayMode: _largeTitle
        ? MorphLargeTitleDisplayMode.always
        : MorphLargeTitleDisplayMode.never,
    leading: _hidesBar ? const [] : widget.leading,
    trailing: _hidesBar ? const [] : widget.trailing,
    toolbarLeading: widget.toolbarLeading,
    toolbarTrailing: widget.toolbarTrailing,
    titleVisible: _titleVisible && !_hidesBar,
    scrolledUnder: _scrolledUnder && !_hidesBar,
    animate: _animate,
    edgeEffect: widget.edgeEffect,
    backButtonTitle: widget.backButtonTitle,
    navigationBarHidden: _hidesBar,
    barHiding: _barHiding,
  );

  final ValueNotifier<bool> _hiddenNow = ValueNotifier<bool>(false);
  late final MorphNavigationBarHiding _barHiding = MorphNavigationBarHiding._(
    _hiding,
    _hiddenNow,
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
        MorphScrollEdgeEffectAppearance.resolve(context, null).backgroundColor;
    final physics = !_largeTitle
        ? const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics())
        : _largeSubtitle == null
        ? const MorphLargeTitleScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
          )
        : MorphLargeTitleScrollPhysics(
            collapseExtent: _largeExtent,
            parent: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
          );
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
          if (_largeTitle)
            SliverToBoxAdapter(
              child: MorphLiveOpacity(
                live: _hiding,
                opacityOf: () =>
                    (1 -
                            MorphNavigationBarHiding.largeTitleFade *
                                _hiding.value)
                        .clamp(0.0, 1.0),
                child: MorphLargeTitle(
                  widget.title,
                  subtitle: _largeSubtitle,
                  appearance: widget.appearance,
                ),
              ),
            ),
          if (widget.search != null)
            const SliverToBoxAdapter(child: MorphStackedSearchSlot()),
          ...widget.slivers,
          SliverPadding(padding: EdgeInsets.only(bottom: toolbarExtent)),
        ],
      ),
    );
    final barExtent = MorphNavigationBar.heightFor(top);
    Widget content = scroll;
    if (widget.showsVerticalScrollIndicator) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          scroll,
          MorphScrollIndicator(
            controller: _controller,
            padding: EdgeInsets.only(top: barExtent, bottom: toolbarExtent),
            contentPadding: EdgeInsets.only(
              top: barExtent,
              bottom: toolbarExtent,
            ),
          ),
        ],
      );
    }
    // One structure whether or not the bar hides, so hiding it never
    // remounts the scroll view.
    final shift = _extended ? _shift : 0.0;
    content = _BarContent(live: _hiding, shift: shift, child: content);
    final search = widget.search;
    Widget body = ColoredBox(
      color: background,
      child: DefaultTextStyle(
        style: MorphTypography.resolve(
          MorphTypography.body.copyWith(
            color: MorphBarAppearance.resolve(
              context,
              widget.appearance,
            ).titleColor,
          ),
        ),
        child: content,
      ),
    );
    if (search != null) {
      body = MorphStackedSearchHost(
        search: search,
        background: background,
        top: search.hidesNavigationBarDuringPresentation
            ? top
            : MorphNavigationBar.heightFor(top),
        onPresented: _presented,
        child: body,
      );
    }
    if (shared) return body;
    var leading = _hidesBar ? const <MorphBarButtonGroup>[] : widget.leading;
    if (leading.isEmpty &&
        !widget.hidesBackButton &&
        !_hidesBar &&
        (route?.canPop ?? false)) {
      leading = [
        MorphBarButtonGroup([
          MorphBarButton.back(
            semanticLabel: widget.backButtonSemanticLabel,
            onPressed: () => Navigator.maybePop(context),
          ),
        ]),
      ];
    }
    return Stack(
      children: [
        Positioned.fill(child: body),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: _bars(
            hidden: _hidesBar,
            MorphNavigationBar(
              title: widget.title,
              subtitle: widget.subtitle,
              leading: leading,
              trailing: _hidesBar ? const [] : widget.trailing,
              titleVisible: _titleVisible && !_hidesBar,
              scrolledUnder: _scrolledUnder && !_hidesBar,
              animate: _animate,
              edgeEffect: widget.edgeEffect,
              appearance: widget.appearance,
              hiding: _hiding,
              hidden: _hiddenNow,
            ),
          ),
        ),
        if (hasToolbar)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _bars(
              MorphToolbar(
                leading: widget.toolbarLeading,
                trailing: widget.toolbarTrailing,
                appearance: widget.appearance,
              ),
            ),
          ),
      ],
    );
  }
}

// Extends the scroll viewport by the hidden bar's height, then follows
// its translation without rebuilding or remounting the scroll view.
class _BarContent extends SingleChildRenderObjectWidget {
  const _BarContent({required this.live, required this.shift, super.child});

  final Animation<double> live;
  final double shift;

  @override
  _RenderBarContent createRenderObject(BuildContext context) {
    final render = _RenderBarContent();
    render.bind(live, shift);
    return render;
  }

  @override
  void updateRenderObject(BuildContext context, _RenderBarContent render) =>
      render.bind(live, shift);
}

class _RenderBarContent extends RenderTransform with MorphLiveBinding {
  _RenderBarContent() : super(transform: Matrix4.identity());

  double _shift = 0;

  void bind(Animation<double> live, double shift) {
    if (_shift != shift) {
      _shift = shift;
      markNeedsLayout();
    }
    bindLive(live, () {
      transform = Matrix4.translationValues(0, -_shift * live.value, 0);
    });
  }

  @override
  void performLayout() {
    child?.layout(
      constraints.hasBoundedHeight
          ? constraints.copyWith(
              minHeight: constraints.minHeight + _shift,
              maxHeight: constraints.maxHeight + _shift,
            )
          : constraints,
      parentUsesSize: true,
    );
    size = constraints.constrain(child?.size ?? Size.zero);
  }
}

// A push or pop under Reduce Motion: progress eases from [from] to [to]
// over MorphNavigationTuning.crossFadeDuration.
class _CrossFade extends Simulation {
  _CrossFade(this.from, this.to);

  final double from;
  final double to;

  double get _duration => MorphNavigationTuning.crossFadeDuration;

  @override
  double x(double time) {
    final f = (time / _duration).clamp(0.0, 1.0);
    return from +
        (to - from) * MorphNavigationTuning.crossFadeCurve.transform(f);
  }

  @override
  double dx(double time) {
    const step = 1e-3;
    return (x(time + step) - x(time)) / step;
  }

  @override
  bool isDone(double time) => time >= _duration;
}

/// Starts [inner] as UIKit starts a push: the frame that builds the new
/// page shows the motion's start, and the motion counts from the frame
/// after it as if that first frame had lasted one display [period].
///
/// A slow first frame (the new page's first build and layout) then
/// delays the motion instead of skipping its first steps. Measured on an
/// iPhone 16 Pro, iOS 27.0.1: a push whose page takes 60 ms in
/// `layoutSubviews`, or 60 ms before the transaction commits, shows the
/// incoming page at the start of its path on the first frame after the
/// stall and then moves by its usual 60 - 67 pt a frame, as a push without
/// a stall does. Without a slow first frame the motion is unchanged.
@internal
class MorphFirstFrameStart extends Simulation {
  /// Starts [inner] after its first frame; [period] is the display's frame
  /// period in seconds.
  MorphFirstFrameStart(this.inner, {required this.period});

  /// The motion.
  final Simulation inner;

  /// The display's frame period, in seconds.
  final double period;

  double? _first;
  double? _offset;

  double _time(double t) {
    final first = _first;
    if (first == null) {
      _first = t;
      return debugEnabled ? 0 : t;
    }
    if (!debugEnabled) {
      if (t > first) debugObserver?.call(t, t);
      return t;
    }
    if (t <= first) return 0;
    final offset = _offset ??= (t - first - period).clamp(0.0, double.infinity);
    debugObserver?.call(t, t - offset);
    return t - offset;
  }

  /// Whether pushes start after their first frame; false counts them from
  /// the push, the reference this is measured against.
  @visibleForTesting
  static bool debugEnabled = true;

  /// Receives each frame's time since the push and the time the motion
  /// is sampled at, for a bench report.
  @visibleForTesting
  static void Function(double raw, double motion)? debugObserver;

  @override
  double x(double time) => inner.x(_time(time));

  @override
  double dx(double time) => inner.dx(_time(time));

  @override
  bool isDone(double time) => inner.isDone(_time(time));
}

/// A bar's repaint boundary, which lets touches through to the page while
/// the bar is [hidden]: one render object for both, so a bar costs no more
/// paints than its boundary did.
class _BarBoundary extends SingleChildRenderObjectWidget {
  const _BarBoundary({required this.hidden, super.child});

  final bool hidden;

  @override
  _RenderBarBoundary createRenderObject(BuildContext context) =>
      _RenderBarBoundary(hidden: hidden);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBarBoundary renderObject,
  ) => renderObject.hidden = hidden;
}

class _RenderBarBoundary extends RenderRepaintBoundary {
  _RenderBarBoundary({required this.hidden});

  bool hidden;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !hidden && super.hitTest(result, position: position);
}
