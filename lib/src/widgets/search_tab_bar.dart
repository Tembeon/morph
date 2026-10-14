import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/chrome_group.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_button.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/press.dart';
import 'package:morph/src/widgets/search_field.dart';
import 'package:morph/src/widgets/search_motion.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/tab_bar.dart';
import 'package:morph/src/widgets/tab_bar_chrome.dart';
import 'package:morph/src/widgets/tab_bar_minimize.dart';
import 'package:morph/src/widgets/tab_collapse.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// A floating [MorphTabBar] with a search tab that turns into a search
/// field, as iOS 27 shows a UITabBarController whose UISearchTab activates
/// search.
///
/// At rest the tab bar floats 21 points from the leading side and the
/// bottom, and the search tab is a separate glass circle at the trailing
/// side. Tapping the circle asks to start searching through
/// [onActiveChanged]; with [active] true, on
/// [MorphSearchTuning.tabSpring], the tab bar shrinks into a circle that
/// keeps the selected tab's glyph while the other tabs fade, and the search
/// circle stretches into a search field whose placeholder fades in; the
/// field takes the focus [MorphSearchTuning.tabActivationDelay] after the
/// tap, while the morph still runs, and, once the keyboard starts to rise,
/// rises above it on [MorphSearchTuning.tabFocusSpring] with a close
/// button, like [MorphSearchToolbar], while the tab circle (which the
/// keyboard covers in UIKit) fades. The close button (or Escape) ends the
/// focus and clears the text, and the field falls straight back to its
/// place above the tab circle as the keyboard leaves; tapping the tab
/// circle asks to stop searching, and the field turns back into the
/// circle; the query clears at the end of that frame. The tab circle takes the tap while the morph into the field
/// still runs (the morph turns around with its velocity, as UIKit's does)
/// until the keyboard covers it; the search circle ignores taps until the
/// morph back to the bar has settled, as UIKit's does. Both circles take
/// keyboard focus while they take taps, and Space or Enter do what a tap
/// does.
///
/// This is UIKit's search tab with `automaticallyActivatesSearch`: only
/// then does iOS 27 set the search tab apart as a circle. A search tab
/// that waits for a tap on its field is an ordinary tab inside the bar
/// (a [MorphTabItem] of [MorphTabBar]).
///
/// The edges were measured at both ends and their timing fitted to video
/// of the real morph; the path between is a straight interpolation of the
/// glass on one spring.
///
/// With a [minimizeBehavior] that minimizes, the bar collapses into the
/// circle of its selected tab and the search circle shrinks to the same
/// size as the content scrolls, as [MorphTabBar] does; the tab circle
/// expands the bar on a tap, the search circle still starts searching.
/// A [bottomAccessory] floats above the bar and the search circle and
/// moves inline between the two circles; it fades out while searching
/// (an approximation, not measured).
///
/// Place it in a [Stack] that fills the screen, with [Positioned.fill]:
/// it takes hits only on its own glass.
class MorphSearchTabBar extends StatefulWidget {
  /// Creates the bar.
  const MorphSearchTabBar({
    required this.items,
    required this.selected,
    required this.onChanged,
    required this.active,
    required this.onActiveChanged,
    this.controller,
    this.focusNode,
    this.placeholder = 'Search',
    this.onQueryChanged,
    this.onSubmitted,
    this.searchLabel = 'Search',
    this.closeLabel = 'Close',
    this.appearance,
    this.searchAppearance,
    this.minimizeBehavior = MorphTabBarMinimizeBehavior.automatic,
    this.bottomAccessory,
    this.contentScroll,
    super.key,
  });

  /// When the bar minimizes as the content scrolls (UIKit
  /// `tabBarMinimizeBehavior`); see [MorphTabBar.minimizeBehavior].
  final MorphTabBarMinimizeBehavior minimizeBehavior;

  /// The content of the glass accessory above the bar (UIKit
  /// `bottomAccessory`); see [MorphTabBar.bottomAccessory].
  final Widget? bottomAccessory;

  /// The scrolls the bar follows to minimize; null follows the nearest
  /// [MorphContentScrollScope].
  final MorphContentScroll? contentScroll;

  /// The tabs, two to four, besides the search tab.
  final List<MorphTabItem> items;

  /// The index of the selected tab.
  final int selected;

  /// Called with the new index when the user selects a tab.
  final ValueChanged<int>? onChanged;

  /// Whether the search tab is active: the field shows instead of the
  /// tabs.
  final bool active;

  /// Called when the user asks to start (true) or stop (false) searching.
  final ValueChanged<bool> onActiveChanged;

  /// The controller of the query; null keeps one inside.
  final TextEditingController? controller;

  /// The focus node of the query; null keeps one inside.
  final FocusNode? focusNode;

  /// The text shown while the field is empty.
  final String placeholder;

  /// Called whenever the query changes, including the empty query when
  /// the close button or the end of the search clears it.
  final ValueChanged<String>? onQueryChanged;

  /// Called when the keyboard's search key is pressed.
  final ValueChanged<String>? onSubmitted;

  /// The label screen readers announce for the search tab.
  final String searchLabel;

  /// The label screen readers announce for the close button.
  final String closeLabel;

  /// The look of the tab bar; null resolves it from the theme.
  final MorphTabBarAppearance? appearance;

  /// The look of the search field; null resolves it from the theme.
  final MorphSearchFieldAppearance? searchAppearance;

  @override
  State<MorphSearchTabBar> createState() => _MorphSearchTabBarState();
}

class _MorphSearchTabBarState extends State<MorphSearchTabBar>
    with
        SingleTickerProviderStateMixin<MorphSearchTabBar>,
        MorphClock<MorphSearchTabBar>,
        MorphTabBarMinimizing<MorphSearchTabBar> {
  final MorphSpringState _morph = MorphSpringState(
    MorphSearchTuning.tabSpring,
    0,
  );
  late final MorphTabBarMinimizeMotion _minimize = MorphTabBarMinimizeMotion(
    behavior: widget.minimizeBehavior,
  );

  @override
  MorphTabBarMinimizeMotion get minimizeMotion => _minimize;
  final MorphSearchMotion _focusMotion = MorphSearchMotion(
    spring: MorphSearchTuning.tabFocusSpring,
  );
  double? _keyboardWait;
  double? _frozenKeyboard;
  final GlobalKey _bar = GlobalKey();
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  FocusNode? _listening;
  double _now = 0;
  double? _barWidth;

  static const MorphSpring _spring = MorphSearchTuning.tabSpring;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  FocusNode get _focus =>
      widget.focusNode ??
      (_ownFocus ??= FocusNode(debugLabel: 'MorphSearchTabBar'));

  @override
  void advanceMotion(double t) {
    if (t > _now) _now = t;
    _minimize.advance(t);
    final wait = _keyboardWait;
    if (wait != null && t - wait >= MorphSearchTuning.keyboardWaitLimit) {
      _keyboardWait = null;
      _focusMotion.focus(t, delay: 0);
    }
    _focusMotion.advance(t);
    _focusMotion.land(t);
    // At rest the morph lands on its target, so the tail it would still
    // swing through (under 0.001 of the morph) neither moves nor lays out
    // anything while the focus transition runs on. NEAR: the shapes jump
    // by at most 0.001 of their travel, once.
    if (_morph.value(t) != _morph.target && _morph.isAtRest(t, 0.001)) {
      _morph.settle(t);
    }
    final activate = _activateAt;
    if (activate != null && t >= activate) {
      _activateAt = null;
      if (widget.active && !_focus.hasFocus) _focus.requestFocus();
    }
  }

  double? _activateAt;

  @override
  bool get motionSettled =>
      _morph.isAtRest(_now, 0.001) &&
      _focusMotion.isSettled &&
      _keyboardWait == null &&
      _activateAt == null &&
      _minimize.isSettled(_now, extent: _geometry?.bar.width ?? 400);

  @override
  void settleMotion() => _minimize.settle(_now);

  @override
  void initState() {
    super.initState();
    if (widget.active) _morph.snap(0, 1);
    _listen();
    _ticks.follow(frames);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _followScroll();
  }

  void _followScroll() => followContentScroll(
    widget.contentScroll ?? MorphContentScrollScope.maybeOf(context),
  );

  void _tabTapped() {
    if (widget.active) {
      widget.onActiveChanged(false);
    } else {
      expandMinimized();
    }
  }

  @override
  void didUpdateWidget(MorphSearchTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _followScroll();
    changeMinimizeBehavior(widget.minimizeBehavior);
    _listen();
    if (oldWidget.active != widget.active) {
      _morph.retarget(clock, widget.active ? 1 : 0, spring: _spring);
      _activateAt = widget.active
          ? clock + MorphSearchTuning.tabActivationDelay
          : null;
      if (!widget.active) {
        _focus.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _controller.text.isEmpty) return;
          _controller.clear();
          widget.onQueryChanged?.call('');
        });
      }
      wake();
    }
  }

  void _listen() {
    final node = _focus;
    if (identical(node, _listening)) return;
    _listening?.removeListener(_focusChanged);
    _listening = node;
    node.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _tabLabel.dispose();
    _placeholder.dispose();
    _tabEnabled.dispose();
    _searchEnabled.dispose();
    _ticks.dispose();
    _listening?.removeListener(_focusChanged);
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (_focus.hasFocus && !_focusMotion.isFocused && _keyboardWait == null) {
      _frozenKeyboard = null;
      final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
      if (keyboard > 0) {
        _focusMotion.focus(clock, delay: MorphSearchTuning.tabKeyboardLag);
      } else {
        _keyboardWait = clock;
      }
      wake();
      setState(() {});
    } else if (!_focus.hasFocus &&
        (_focusMotion.isFocused || _keyboardWait != null)) {
      _keyboardWait = null;
      _frozenKeyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
      _focusMotion.unfocus(clock, delay: MorphSearchTuning.tabUnfocusDelay);
      wake();
      setState(() {});
    }
  }

  void _close() {
    _controller.clear();
    widget.onQueryChanged?.call('');
    _focus.unfocus();
  }

  MorphSearchTabGeometry? _geometry;
  _TabFrame _frame = _TabFrame.zero;
  final ValueNotifier<bool> _tabLabel = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _placeholder = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _tabEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _searchEnabled = ValueNotifier<bool>(true);

  // The tabs and the search circle, built once for what they draw: a
  // change of what they show or take (a label gone, touches on or off)
  // rebuilds only the part that reads it, not the whole morph.
  Object? _tabsKey;
  Widget? _tabs;
  Object? _circleKey;
  Widget? _circle;
  // A keyboard frame rebuilds and reads again with the new geometry.
  late final MorphFrameSync<_TabStructure?> _ticks =
      MorphFrameSync<_TabStructure?>(
        structure: () => _geometry == null ? null : _readFrame(),
        rebuild: (_TabStructure? _) => setState(() {}),
      );

  _TabStructure _readFrame() {
    final geometry = _geometry!;
    final q = _morph.value(_now);
    final p = _focusMotion.progress(_now);
    final m = _minimize.shape(_now);
    final focused = _focusMotion.isFocused;
    final settled = (q - 1).abs() < 0.001 && widget.active;
    final fieldRect = Rect.lerp(geometry.field, geometry.focusedField, p)!;
    final restBar = Rect.lerp(geometry.bar, geometry.tab, m)!;
    final restSearch = Rect.lerp(
      geometry.search,
      _collapsedSearch(geometry),
      m,
    )!;
    final content = math.max(q, _minimize.content(_now));
    _frame = _TabFrame(
      q: q,
      p: p,
      content: content,
      bar: Rect.lerp(restBar, geometry.tab, q)!,
      field: fieldRect,
      search: Rect.lerp(restSearch, fieldRect, q)!,
      close: morphLerpRect(
        Rect.fromLTWH(
          geometry.field.right - MorphSearchTuning.height,
          geometry.field.top,
          MorphSearchTuning.height,
          MorphSearchTuning.height,
        ),
        geometry.close,
        p,
      ),
      accessory: Rect.lerp(
        _accessoryRect(geometry),
        _inlineAccessoryRect(geometry),
        m,
      )!,
    );
    final shown = q.clamp(0.0, 1.0);
    final searchIdle = q.abs() < 0.001 && !widget.active;
    final resting = searchIdle && _minimize.restsExpanded(_now);
    final minimized = _minimize.minimized;
    final tabIgnoring = !(widget.active || minimized) || p >= 0.5;
    // Each of these rebuilds only the part that reads it.
    _tabLabel.value = (1 - content.clamp(0.0, 1.0) * 2).clamp(0.0, 1.0) > 0.01;
    _placeholder.value = shown > 0.01;
    _tabEnabled.value = !tabIgnoring;
    _searchEnabled.value = searchIdle;
    return (
      resting: resting,
      searchIdle: searchIdle,
      minimized: minimized,
      settled: settled,
      tabIgnoring: tabIgnoring,
      closeShown: settled && (p > 0.001 || focused),
      focused: focused,
    );
  }

  /// The search circle of a minimized bar: the size of the tab circle,
  /// mirrored across the screen.
  Rect _collapsedSearch(MorphSearchTabGeometry geometry) {
    final w = _width;
    return Rect.fromLTRB(
      w - geometry.tab.right,
      geometry.tab.top,
      w - geometry.tab.left,
      geometry.tab.bottom,
    );
  }

  Rect _accessoryRect(MorphSearchTabGeometry geometry) {
    const h = MorphTabBarMinimizeTuning.accessoryHeight;
    const side = MorphTabBarMinimizeTuning.sideInset;
    return Rect.fromLTWH(
      side,
      geometry.bar.top - MorphTabBarMinimizeTuning.spacing - h,
      _width - 2 * side,
      h,
    );
  }

  Rect _inlineAccessoryRect(MorphSearchTabGeometry geometry) {
    const gap = MorphTabBarMinimizeTuning.spacing;
    final search = _collapsedSearch(geometry);
    final tab = geometry.tab;
    final left = math.min(tab.right, search.right) + gap;
    final right = math.max(tab.left, search.left) - gap;
    return Rect.fromLTRB(
      left,
      tab.top,
      math.max(left, right),
      tab.top + MorphTabBarMinimizeTuning.accessoryHeight,
    );
  }

  double _width = 0;

  Matrix4 _hintMatrix() {
    final scale = _minimize.hint(_now);
    final into = Matrix4.identity();
    if (scale == 1) return into;
    final geometry = _geometry!;
    final top = widget.bottomAccessory == null
        ? geometry.bar.top
        : _accessoryRect(geometry).top;
    final center = Offset(_width / 2, (top + geometry.bar.bottom) / 2);
    into.translateByDouble(center.dx, center.dy, 0, 1);
    into.scaleByDouble(scale, scale, 1, 1);
    into.translateByDouble(-center.dx, -center.dy, 0, 1);
    return into;
  }

  double _fallbackBarWidth() {
    final count = widget.items.length;
    return MorphTabBarMetrics.geometry(count, 0).width;
  }

  MorphSearchTabBar? _partsFor;
  late MorphTabBar _tabBar;
  late MorphSearchField _field;

  @override
  void reassemble() {
    super.reassemble();
    _partsFor = null;
    _tabsKey = null;
    _circleKey = null;
  }

  void _measureBar() {
    final box = _bar.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize && box.size.width != _barWidth) {
      setState(() => _barWidth = box.size.width);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.items.isEmpty
        ? -1
        : widget.selected.clamp(0, widget.items.length - 1);
    final tabStyle = MorphTabBarAppearance.resolve(context, widget.appearance);
    final searchStyle = MorphSearchFieldAppearance.resolve(
      context,
      widget.searchAppearance,
    );
    final glass = MorphGlassScope.maybeOf(context);
    final brightness = morphBrightnessOf(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final rtl = direction == TextDirection.rtl;
    final keyboard = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    if (_keyboardWait != null && keyboard > 0) {
      _keyboardWait = null;
      _focusMotion.focus(clock, delay: MorphSearchTuning.tabKeyboardLag);
      wake();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureBar();
    });
    // The keyboard's inset rebuilds this on every frame of its rise and
    // fall; the bar and the field depend only on the widget, so those
    // rebuilds reuse them and Flutter skips their subtrees.
    if (!identical(_partsFor, widget)) {
      _partsFor = widget;
      _tabBar = MorphTabBar(
        key: _bar,
        items: widget.items,
        selected: selected,
        onChanged: widget.onChanged,
        appearance: widget.appearance,
      );
      _field = MorphSearchField(
        controller: _controller,
        focusNode: _focus,
        placeholder: widget.placeholder,
        onChanged: widget.onQueryChanged,
        onSubmitted: widget.onSubmitted,
        appearance: widget.searchAppearance,
      );
    }
    final bar = _tabBar;
    final field = _field;
    final shortcuts = CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          _width = constraints.biggest.width;
          final geometry = morphSearchTabLayout(
            size: constraints.biggest,
            barWidth: _barWidth ?? _fallbackBarWidth(),
            keyboard: _focusMotion.isFocused
                ? keyboard
                : _frozenKeyboard ?? keyboard,
            rtl: rtl,
          );
          _geometry = geometry;
          final structure = _ticks.read()!;
          final settled = structure.settled;
          final children = <Widget>[];
          if (structure.resting) {
            children.add(
              Positioned(
                key: const ValueKey<String>('bar'),
                left: geometry.bar.left,
                top: geometry.bar.top,
                child: bar,
              ),
            );
          } else if (widget.items.isNotEmpty) {
            final key = (
              widget.items,
              selected,
              geometry.bar,
              tabStyle,
              glass,
              brightness,
              rtl,
            );
            if (_tabsKey != key) {
              _tabsKey = key;
              _tabs = MorphCollapsingTabs(
                live: _ticks,
                items: widget.items,
                selected: selected,
                progress: () => _frame.content,
                restRect: geometry.bar,
                rect: () => _frame.bar,
                labelShown: _tabLabel,
                style: tabStyle,
                glass: glass,
                brightness: brightness,
                rtl: rtl,
                label: widget.items[selected].label,
                onTap: _tabTapped,
                enabled: _tabEnabled,
              );
            }
            children.add(
              MorphLivePositionedTemplate(
                key: const ValueKey<String>('tab'),
                live: _ticks,
                template: () =>
                    Positioned.fromRect(rect: _frame.bar, child: morphLiveSlot),
                child: IgnorePointer(
                  ignoring: structure.tabIgnoring,
                  child: MorphLiveOpacity(
                    live: _ticks,
                    opacityOf: () => (1 - _frame.p).clamp(0.0, 1.0),
                    child: _tabs,
                  ),
                ),
              ),
            );
          }
          if (!settled) {
            final key = (
              widget.placeholder,
              widget.searchLabel,
              geometry.search,
              searchStyle,
              tabStyle,
              glass,
              brightness,
              rtl,
            );
            if (_circleKey != key) {
              _circleKey = key;
              _circle = _SearchCircle(
                live: _ticks,
                progress: () => _frame.q,
                rect: () => _frame.search,
                restRect: geometry.search,
                placeholderShown: _placeholder,
                placeholder: widget.placeholder,
                label: widget.searchLabel,
                style: searchStyle,
                tabStyle: tabStyle,
                glass: glass,
                brightness: brightness,
                rtl: rtl,
                onTap: () => widget.onActiveChanged(true),
                enabled: _searchEnabled,
              );
            }
            children.add(
              MorphLivePositionedTemplate(
                key: const ValueKey<String>('search'),
                live: _ticks,
                template: () => Positioned.fromRect(
                  rect: _frame.search,
                  child: morphLiveSlot,
                ),
                child: IgnorePointer(
                  ignoring: !structure.searchIdle,
                  child: _circle,
                ),
              ),
            );
          }
          final accessory = widget.bottomAccessory;
          if (accessory != null) {
            children.insert(
              0,
              MorphTabAccessorySlot(
                key: const ValueKey<String>('accessory'),
                live: _ticks,
                rect: () => _frame.accessory,
                end: structure.minimized
                    ? _inlineAccessoryRect(geometry)
                    : _accessoryRect(geometry),
                opacity: () => (1 - _frame.q).clamp(0.0, 1.0),
                takesTouches: structure.searchIdle,
                environment: structure.minimized
                    ? MorphTabAccessoryEnvironment.inline
                    : MorphTabAccessoryEnvironment.regular,
                style: tabStyle,
                glass: glass,
                brightness: brightness,
                child: accessory,
              ),
            );
          }
          if (widget.active || settled) {
            children.add(
              MorphLivePositionedTemplate(
                key: const ValueKey<String>('field'),
                live: _ticks,
                // Hidden, the field only holds the focus; parking it at
                // its settled rect spares a relayout per morph frame.
                template: () => Positioned.fromRect(
                  rect: settled ? _frame.search : _frame.field,
                  child: morphLiveSlot,
                ),
                child: IgnorePointer(
                  ignoring: !settled,
                  child: Opacity(
                    opacity: settled ? 1 : 0,
                    alwaysIncludeSemantics: true,
                    child: field,
                  ),
                ),
              ),
            );
          }
          if (structure.closeShown) {
            children.add(
              MorphLivePositionedTemplate(
                key: const ValueKey<String>('close'),
                live: _ticks,
                template: () => Positioned.fromRect(
                  rect: _frame.close,
                  child: morphLiveSlot,
                ),
                child: IgnorePointer(
                  ignoring: !structure.focused,
                  child: MorphLiveOpacity(
                    live: _ticks,
                    opacityOf: () => _frame.p.clamp(0.0, 1.0),
                    child: MorphLiveTransform(
                      live: _ticks,
                      writeInto: (Matrix4 into) {
                        final scale = MorphSearchMotion.appearScaleFor(
                          _frame.p,
                        );
                        into.scaleByDouble(scale, scale, 1, 1);
                      },
                      child: _RoundGlassButton(
                        label: widget.closeLabel,
                        onPressed: _close,
                        child: _CrossGlyph(color: searchStyle.glyphColor),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          final stack = Stack(clipBehavior: Clip.none, children: children);
          // Only a bar that minimizes pays for the hint's transform.
          if (!_minimize.behavior.minimizes) return stack;
          return MorphLiveTransform.matrix(
            live: _ticks,
            matrixOf: _hintMatrix,
            alignment: null,
            child: stack,
          );
        },
      ),
    );
    // A repaint boundary of its own: a frame of the morph repaints the
    // bar, not the page under it.
    return RepaintBoundary(child: MorphChromeBackdrop(child: shortcuts));
  }
}

class _TabFrame {
  const _TabFrame({
    required this.q,
    required this.p,
    required this.content,
    required this.bar,
    required this.field,
    required this.search,
    required this.close,
    required this.accessory,
  });

  static const zero = _TabFrame(
    q: 0,
    p: 0,
    content: 0,
    bar: Rect.zero,
    field: Rect.zero,
    search: Rect.zero,
    close: Rect.zero,
    accessory: Rect.zero,
  );

  final double q;
  final double p;

  /// The tabs' way into their circle: searching or minimized.
  final double content;
  final Rect bar;
  final Rect field;
  final Rect search;
  final Rect close;
  final Rect accessory;
}

typedef _TabStructure = ({
  bool resting,
  bool searchIdle,
  bool minimized,
  bool settled,
  bool tabIgnoring,
  bool closeShown,
  bool focused,
});

class _SearchCircle extends StatelessWidget {
  const _SearchCircle({
    required this.live,
    required this.progress,
    required this.rect,
    required this.restRect,
    required this.placeholderShown,
    required this.placeholder,
    required this.label,
    required this.style,
    required this.tabStyle,
    required this.glass,
    required this.brightness,
    required this.rtl,
    required this.onTap,
    required this.enabled,
  });

  final Listenable live;
  final double Function() progress;
  final Rect Function() rect;
  final Rect restRect;
  final ValueListenable<bool> placeholderShown;
  final String placeholder;
  final String label;
  final MorphSearchFieldAppearance style;
  final MorphTabBarAppearance tabStyle;
  final MorphGlassPainter? glass;
  final Brightness brightness;
  final bool rtl;
  final VoidCallback onTap;

  /// Whether the circle takes keyboard focus; it does while it takes
  /// touches.
  final ValueListenable<bool> enabled;

  @override
  Widget build(BuildContext context) {
    double q() => progress().clamp(0.0, 1.0);
    Color body() => Color.lerp(tabStyle.barColor, style.capsuleColor, q())!;
    const glyph = MorphSearchTuning.glyphSize;
    final glass = this.glass;
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: ValueListenableBuilder<bool>(
        valueListenable: enabled,
        builder: (BuildContext context, bool enabled, Widget? child) =>
            MorphPress(
              enabled: enabled,
              onActivate: onTap,
              focusRing: true,
              focusSemantics: false,
              child: child!,
            ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: glass == null
                    ? CustomPaint(
                        painter: MorphCapsulePainter(
                          live: live,
                          shape: () => morphCapsuleIn(rect()),
                          color: body,
                          shadow: style.shadowColor,
                        ),
                      )
                    : MorphGlassHost(
                        painter: glass,
                        mode: MorphGlassMode.surface,
                        frames: live,
                        frame: () => MorphGlassFrame([
                          MorphGlassSurface(
                            kind: MorphGlassKind.button,
                            shape: morphCapsuleIn(rect()),
                            color: body(),
                            brightness: brightness,
                          ),
                        ]),
                      ),
              ),
              MorphLivePositionedTemplate(
                live: live,
                template: () {
                  final now = rect();
                  final start = Offset(
                    rtl
                        ? now.width -
                              MorphSearchTuning.glyphInset -
                              glyph.width / 2
                        : MorphSearchTuning.glyphInset + glyph.width / 2,
                    now.height / 2,
                  );
                  final t = q();
                  final center = Offset.lerp(
                    now.size.center(Offset.zero),
                    start,
                    t,
                  )!;
                  return Positioned(
                    left: center.dx - glyph.width / 2 * (1 + 0.15 * (1 - t)),
                    top: center.dy - glyph.height / 2 * (1 + 0.15 * (1 - t)),
                    width: glyph.width * (1 + 0.15 * (1 - t)),
                    height: glyph.height * (1 + 0.15 * (1 - t)),
                    child: morphLiveSlot,
                  );
                },
                child: CustomPaint(
                  painter: _MagnifierGlyph(
                    live: live,
                    color: () =>
                        Color.lerp(tabStyle.color, style.glyphColor, q())!,
                  ),
                ),
              ),
              PositionedDirectional(
                start: MorphSearchTuning.textInset,
                end: 8,
                top: 0,
                bottom: 0,
                child: ValueListenableBuilder<bool>(
                  valueListenable: placeholderShown,
                  builder: (BuildContext context, bool shown, Widget? text) =>
                      shown ? text! : const SizedBox.shrink(),
                  child: ClipRect(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: MorphLiveOpacity(
                        live: live,
                        opacityOf: () => ((q() - 0.4) / 0.6).clamp(0.0, 1.0),
                        child: Text(
                          placeholder,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: MorphTypography.resolve(
                            MorphTypography.searchField.copyWith(
                              height: 1.2,
                              color: style.placeholderColor,
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
    );
  }
}

class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({
    required this.label,
    required this.onPressed,
    required this.child,
  });

  final String label;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      excludeSemantics: true,
      child: MorphGlassButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        minSize: const Size.square(MorphSearchTuning.height),
        child: child,
      ),
    );
  }
}

class _CrossGlyph extends StatelessWidget {
  const _CrossGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: MorphSearchTuning.closeGlyphSize,
    child: CustomPaint(painter: _CrossLines(color: color)),
  );
}

class _CrossLines extends CustomPainter {
  const _CrossLines({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => morphPaintCross(canvas, size, color);

  @override
  bool shouldRepaint(_CrossLines oldDelegate) => oldDelegate.color != color;
}

class _MagnifierGlyph extends CustomPainter {
  _MagnifierGlyph({required Listenable live, required this.color})
    : super(repaint: live);

  final Color Function() color;

  @override
  void paint(Canvas canvas, Size size) =>
      morphPaintMagnifier(canvas, size, color());

  @override
  bool shouldRepaint(_MagnifierGlyph oldDelegate) => true;
}
