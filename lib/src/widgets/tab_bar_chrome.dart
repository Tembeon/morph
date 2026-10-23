import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/press.dart';
import 'package:morph/src/widgets/tab_bar.dart';
import 'package:morph/src/widgets/tab_bar_minimize.dart';
import 'package:morph/src/widgets/tab_collapse.dart';
import 'package:morph/src/widgets/typography.dart';

/// The scrolls of the content under a tab bar, which a minimizing
/// [MorphTabBar] follows (UIKit observes the tab's content scroll view,
/// `setContentScrollView(_:for:)`).
///
/// Feed it the content's scroll notifications: pass [handle] as a
/// `NotificationListener<ScrollNotification>.onNotification` around the
/// content and give the object to [MorphTabBar.contentScroll], or put a
/// [MorphContentScrollScope] above both the content and the bar, which
/// does both.
///
/// Only the vertical scrollable nearest the listener counts (notification
/// depth 0). A drag and the deceleration after it are the user's scroll; a
/// programmatic scroll (`animateTo`, `jumpTo`) never minimizes the bar,
/// as UIKit's does not, but one that reaches the content's top expands it,
/// as UIKit's scroll to top does.
class MorphContentScroll {
  final List<MorphContentScrollClient> _clients = [];
  bool _user = false;
  bool _dragging = false;

  /// Adds [client].
  @internal
  void addClient(MorphContentScrollClient client) => _clients.add(client);

  /// Removes [client].
  @internal
  void removeClient(MorphContentScrollClient client) => _clients.remove(client);

  /// Reports [notification] to the bars that follow this content; never
  /// stops it, so it suits `NotificationListener.onNotification`.
  bool handle(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth != 0 || metrics.axis != Axis.vertical) {
      return false;
    }
    if (!metrics.hasPixels || !metrics.hasContentDimensions) return false;
    final up = metrics.axisDirection == AxisDirection.up;
    final offset = up ? -metrics.pixels : metrics.pixels;
    final min = up ? -metrics.maxScrollExtent : metrics.minScrollExtent;
    final max = up ? -metrics.minScrollExtent : metrics.maxScrollExtent;
    final clients = List.of(_clients);
    switch (notification) {
      case ScrollStartNotification(:final dragDetails):
        _user = dragDetails != null;
        _dragging = _user;
        for (final c in clients) {
          c.contentRecorded(offset);
          if (_user) c.contentDragStarted();
        }
      case ScrollUpdateNotification(:final dragDetails):
        final tracking = dragDetails != null;
        if (tracking && !_dragging) {
          _user = true;
          _dragging = true;
          for (final c in clients) {
            c.contentDragStarted();
          }
        } else if (!tracking && _dragging) {
          _dragging = false;
          for (final c in clients) {
            c.contentDragEnded(decelerates: true);
          }
        }
        for (final c in clients) {
          if (_user) {
            c.contentScrolled(offset, min: min, max: max, tracking: tracking);
          } else {
            c.contentRecorded(offset);
            if (offset <= min) c.contentReachedTop();
          }
        }
      case ScrollEndNotification():
        if (_user) {
          final dragged = _dragging;
          for (final c in clients) {
            if (dragged) {
              c.contentDragEnded(decelerates: false);
            } else {
              c.contentDecelerationEnded();
            }
          }
        }
        _user = false;
        _dragging = false;
      default:
    }
    return false;
  }
}

/// What a [MorphContentScroll] reports to a bar that follows it.
@internal
abstract interface class MorphContentScrollClient {
  /// A finger started to drag the content.
  void contentDragStarted();

  /// The user scrolled the content to [offset] (dragging when [tracking]),
  /// its ends at [min] and [max].
  void contentScrolled(
    double offset, {
    required double min,
    required double max,
    required bool tracking,
  });

  /// The finger lifted; [decelerates] when the content goes on moving.
  void contentDragEnded({required bool decelerates});

  /// The content stopped after a deceleration.
  void contentDecelerationEnded();

  /// The content moved to [offset] without the user.
  void contentRecorded(double offset);

  /// A programmatic scroll reached the content's top.
  void contentReachedTop();
}

/// Feeds the scrolls of the content below it to the minimizing
/// [MorphTabBar]s below it: put it above a screen's content and its bar.
class MorphContentScrollScope extends StatefulWidget {
  /// Observes the scrolls in [child] through [scroll], or one of its own.
  const MorphContentScrollScope({required this.child, this.scroll, super.key});

  /// The observer; null keeps one inside.
  final MorphContentScroll? scroll;

  /// The content and its bar.
  final Widget child;

  /// The observer of the nearest scope above [context], or null.
  static MorphContentScroll? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ContentScrollScope>()?.scroll;

  @override
  State<MorphContentScrollScope> createState() =>
      _MorphContentScrollScopeState();
}

class _MorphContentScrollScopeState extends State<MorphContentScrollScope> {
  final MorphContentScroll _own = MorphContentScroll();

  @override
  Widget build(BuildContext context) {
    final scroll = widget.scroll ?? _own;
    return NotificationListener<ScrollNotification>(
      onNotification: scroll.handle,
      child: _ContentScrollScope(scroll: scroll, child: widget.child),
    );
  }
}

class _ContentScrollScope extends InheritedWidget {
  const _ContentScrollScope({required this.scroll, required super.child});

  final MorphContentScroll scroll;

  @override
  bool updateShouldNotify(_ContentScrollScope oldWidget) =>
      !identical(oldWidget.scroll, scroll);
}

/// Where a tab bar's bottom accessory is laid out (UIKit
/// `UITabAccessory.Environment`, the `tabAccessoryEnvironment` trait;
/// SwiftUI `TabViewBottomAccessoryPlacement`).
enum MorphTabAccessoryEnvironment {
  /// Not inside a bottom accessory.
  none,

  /// Above the expanded tab bar, as wide as the bar group.
  regular,

  /// Inline next to the minimized tab bar.
  inline;

  /// The environment of the accessory around [context]: content that lays
  /// itself out differently inline (a mini player dropping its secondary
  /// controls) reads it here, and builds again when it changes.
  static MorphTabAccessoryEnvironment of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_TabAccessoryScope>()
          ?.environment ??
      none;
}

class _TabAccessoryScope extends InheritedWidget {
  const _TabAccessoryScope({required this.environment, required super.child});

  final MorphTabAccessoryEnvironment environment;

  @override
  bool updateShouldNotify(_TabAccessoryScope oldWidget) =>
      oldWidget.environment != environment;
}

/// The content of a bottom accessory as the bar group shows it, a [Stack]
/// child: in the [environment] it reads, with the body text style and the
/// bar's content color, laid out once at [end] (the box the accessory
/// heads to) and carried to [rect]'s center and clipped to its capsule by
/// paint alone, so a frame of the morph neither lays it out nor repaints
/// it.
///
/// NEAR: UIKit resizes the content view with the accessory; here the
/// content takes its end layout as the morph starts (when its environment
/// changes anyway) and travels with the capsule's center.
@internal
Widget morphTabAccessoryContent({
  BuildContext? context,
  required Listenable live,
  required Rect Function() rect,
  required Rect end,
  required MorphTabAccessoryEnvironment environment,
  required MorphTabBarAppearance style,
  required Widget child,
  double Function()? opacity,
}) {
  Rect clip() {
    final now = rect();
    return Rect.fromCenter(
      center: end.size.center(Offset.zero),
      width: now.width,
      height: now.height,
    );
  }

  Widget content = ClipRRect(
    clipper: MorphLiveClipper<RRect>(
      live: live,
      keyOf: clip,
      clipOf: (Size _) {
        final r = clip();
        return RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2));
      },
    ),
    child: RepaintBoundary(
      child: _TabAccessoryScope(
        environment: environment,
        child: DefaultTextStyle(
          style: MorphTypography.resolve(
            MorphTypography.body.copyWith(color: style.color),
            context: context,
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: style.color),
            child: child,
          ),
        ),
      ),
    ),
  );
  if (opacity != null) {
    content = MorphLiveOpacity(live: live, opacityOf: opacity, child: content);
  }
  return Positioned.fromRect(
    rect: end,
    child: RepaintBoundary(
      child: MorphLiveTransform.matrix(
        live: live,
        alignment: null,
        matrixOf: () {
          final d = rect().center - end.center;
          return Matrix4.translationValues(d.dx, d.dy, 0);
        },
        child: content,
      ),
    ),
  );
}

/// A bottom accessory in a [Stack] that fills the screen: its glass and
/// content at [rect], faded by [opacity] (none when null), both read on
/// every frame of [live].
@internal
class MorphTabAccessorySlot extends StatelessWidget {
  /// Places [child].
  const MorphTabAccessorySlot({
    required this.live,
    required this.rect,
    required this.takesTouches,
    required this.environment,
    required this.style,
    required this.glass,
    required this.brightness,
    required this.child,
    required this.end,
    this.opacity,
    super.key,
  });

  /// Notifies on every frame of the motion.
  final Listenable live;

  /// The accessory's box now.
  final Rect Function() rect;

  /// The accessory's opacity now; null keeps it opaque.
  final double Function()? opacity;

  /// Whether the content takes touches.
  final bool takesTouches;

  /// Where the accessory is laid out.
  final MorphTabAccessoryEnvironment environment;

  /// The bar's look.
  final MorphTabBarAppearance style;

  /// The installed glass painter, if any.
  final MorphGlassPainter? glass;

  /// The glass's brightness.
  final Brightness brightness;

  /// The accessory's content.
  final Widget child;

  /// The box the accessory heads to; its content is laid out there once.
  final Rect end;

  @override
  Widget build(BuildContext context) {
    final glass = this.glass;
    RRect shape() {
      final r = rect();
      return RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2));
    }

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !takesTouches,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // A boundary of its own: a frame of the morph repaints the
            // moving glass, not the bar group around it.
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: glass == null
                      ? CustomPaint(
                          painter: MorphCapsulePainter(
                            live: live,
                            shape: shape,
                            color: () => style.barColor.withValues(
                              alpha: style.barColor.a * (opacity?.call() ?? 1),
                            ),
                            shadow: style.shadowColor,
                          ),
                        )
                      // A layer, which draws its surfaces where they are in
                      // its box: a surface host draws its one surface at its
                      // own origin, and this host fills the bar group.
                      : MorphGlassHost(
                          painter: glass,
                          mode: MorphGlassMode.layer,
                          frames: live,
                          frame: () => MorphGlassFrame([
                            MorphGlassSurface(
                              kind: MorphGlassKind.bar,
                              shape: shape(),
                              color: style.barColor,
                              brightness: brightness,
                              opacity: opacity?.call() ?? 1,
                            ),
                          ]),
                        ),
                ),
              ),
            ),
            morphTabAccessoryContent(
              live: live,
              rect: rect,
              end: end,
              environment: environment,
              style: style,
              opacity: opacity,
              child: child,
              context: context,
            ),
          ],
        ),
      ),
    );
  }
}

/// The geometry of a tab bar group: the expanded bar, its minimized
/// circle and the bottom accessory in both placements.
@internal
@immutable
class MorphTabBarGroupGeometry {
  /// Creates a geometry.
  const MorphTabBarGroupGeometry({
    required this.size,
    required this.bar,
    required this.collapsed,
    required this.accessory,
    required this.inlineAccessory,
    this.searchCollapsed,
  });

  /// Lays out a bar [barWidth] wide in a group [width] wide, with an
  /// accessory above it when [accessory]: the bar centered at the bottom,
  /// the minimized circle [MorphTabBarMinimizeTuning.collapsedInset]
  /// inside the bar group's leading side and bottom, the accessory
  /// [MorphTabBarMinimizeTuning.spacing] above the bar across the group
  /// and, inline, between the circle and the group's trailing side (or,
  /// with [search], the minimized search tab's circle, the leading
  /// circle mirrored). [rtl] mirrors it.
  factory MorphTabBarGroupGeometry.of({
    required double width,
    required double barWidth,
    required bool accessory,
    bool rtl = false,
    bool search = false,
  }) {
    const barHeight = MorphTabBarMetrics.height;
    const side = MorphTabBarMinimizeTuning.sideInset;
    const inset = MorphTabBarMinimizeTuning.collapsedInset;
    const size = MorphTabBarMinimizeTuning.collapsedSize;
    const gap = MorphTabBarMinimizeTuning.spacing;
    const h = MorphTabBarMinimizeTuning.accessoryHeight;
    final height = barHeight + (accessory ? gap + h : 0);
    final barTop = height - barHeight;
    final bar = Rect.fromLTWH(
      (width - barWidth) / 2,
      barTop,
      barWidth,
      barHeight,
    );
    final collapsed = Rect.fromLTWH(side + inset, barTop + inset, size, size);
    final regular = Rect.fromLTWH(side, barTop - gap - h, width - 2 * side, h);
    final searchCircle = Rect.fromLTWH(
      width - side - inset - size,
      collapsed.top,
      size,
      size,
    );
    final inline = Rect.fromLTRB(
      collapsed.right + gap,
      collapsed.top,
      search ? searchCircle.left - gap : width - side - inset,
      collapsed.top + h,
    );
    Rect mirror(Rect r) => rtl
        ? Rect.fromLTRB(width - r.right, r.top, width - r.left, r.bottom)
        : r;
    return MorphTabBarGroupGeometry(
      size: Size(width, height),
      bar: mirror(bar),
      collapsed: mirror(collapsed),
      accessory: mirror(regular),
      inlineAccessory: mirror(inline),
      searchCollapsed: search ? mirror(searchCircle) : null,
    );
  }

  /// The group's size.
  final Size size;

  /// The expanded bar.
  final Rect bar;

  /// The minimized bar.
  final Rect collapsed;

  /// The accessory above the expanded bar.
  final Rect accessory;

  /// The accessory next to the minimized bar.
  final Rect inlineAccessory;

  /// The minimized search tab's circle at the group's trailing side, or
  /// null when the bar has no [MorphTabRole.search] tab.
  final Rect? searchCollapsed;
}

/// A tab bar with its minimizing behavior and bottom accessory: the
/// expanded [bar] at rest, the bar collapsing into its selected tab's
/// circle while the content scrolls, and the accessory above it or inline.
@internal
class MorphTabBarChrome extends StatefulWidget {
  /// Hosts [bar].
  const MorphTabBarChrome({
    required this.bar,
    required this.barWidth,
    required this.items,
    required this.selected,
    required this.appearance,
    required this.glass,
    required this.brightness,
    required this.rtl,
    required this.behavior,
    required this.accessory,
    required this.contentScroll,
    this.barPress,
    this.onSelect,
    super.key,
  });

  /// Selects a tab, as the expanded bar's own selection does: the
  /// minimized search circle and the leading circle of a bar whose search
  /// tab is selected select through it (null: they only expand the bar).
  final ValueChanged<int>? onSelect;

  /// The expanded bar, built by the tab bar.
  final Widget bar;

  /// The press of the expanded bar: a finger held on the minimized bar
  /// that moves on is handed to it, so the same touch scrubs the tabs and
  /// its release selects (null: the minimized bar only expands).
  final MorphPressTarget? barPress;

  /// The expanded bar's width.
  final double barWidth;

  /// The tabs.
  final List<MorphTabItem> items;

  /// The selected tab.
  final int selected;

  /// The bar's look.
  final MorphTabBarAppearance appearance;

  /// The installed glass painter, if any.
  final MorphGlassPainter? glass;

  /// The glass's brightness.
  final Brightness brightness;

  /// Whether the tabs run right to left.
  final bool rtl;

  /// The resolved minimize behavior.
  final MorphTabBarMinimizeBehavior behavior;

  /// The bottom accessory's content, or null.
  final Widget? accessory;

  /// The content scroll the bar follows, or null.
  final MorphContentScroll? contentScroll;

  @override
  State<MorphTabBarChrome> createState() => _MorphTabBarChromeState();
}

/// A tab bar host that minimizes: it follows a [MorphContentScroll] and
/// feeds [minimizeMotion] the content's scrolls on its clock.
@internal
mixin MorphTabBarMinimizing<T extends StatefulWidget> on MorphClock<T>
    implements MorphContentScrollClient {
  /// The motion the scrolls drive.
  MorphTabBarMinimizeMotion get minimizeMotion;

  MorphContentScroll? _followed;

  /// Follows [source] instead of the scroll followed before.
  void followContentScroll(MorphContentScroll? source) {
    if (identical(source, _followed)) return;
    _followed?.removeClient(this);
    _followed = source;
    source?.addClient(this);
  }

  /// Expands a minimized bar: a tap on its circle.
  void expandMinimized() {
    if (!minimizeMotion.minimized) return;
    _minimizeInput(
      (double t) => minimizeMotion.setMinimized(t, minimized: false),
    );
  }

  /// Changes the behavior to [behavior].
  void changeMinimizeBehavior(MorphTabBarMinimizeBehavior behavior) {
    if (behavior == minimizeMotion.behavior) return;
    _minimizeInput((double t) => minimizeMotion.setBehavior(t, behavior));
  }

  @override
  void dispose() {
    _followed?.removeClient(this);
    _followed = null;
    super.dispose();
  }

  void _minimizeInput(void Function(double t) action) {
    final t = currentTime;
    minimizeMotion.advance(t);
    action(t);
    wake();
  }

  @override
  void contentDragStarted() =>
      _minimizeInput((_) => minimizeMotion.scrollAway.beginDrag());

  @override
  void contentScrolled(
    double offset, {
    required double min,
    required double max,
    required bool tracking,
  }) {
    final motion = minimizeMotion;
    if (!motion.behavior.minimizes) {
      motion.scrollAway.record(offset);
      return;
    }
    _minimizeInput(
      (_) => motion.scrollAway.scroll(
        offset,
        min: min,
        max: max,
        tracking: tracking,
      ),
    );
  }

  @override
  void contentDragEnded({required bool decelerates}) => _minimizeInput(
    (_) => minimizeMotion.scrollAway.endDrag(decelerates: decelerates),
  );

  @override
  void contentDecelerationEnded() =>
      _minimizeInput((_) => minimizeMotion.scrollAway.endDeceleration());

  @override
  void contentRecorded(double offset) =>
      minimizeMotion.scrollAway.record(offset);

  @override
  void contentReachedTop() {
    if (!minimizeMotion.minimized) return;
    _minimizeInput((_) => minimizeMotion.scrollAway.scrollToTop());
  }
}

typedef _Structure = ({bool resting, bool minimized, bool apart});

class _MorphTabBarChromeState extends State<MorphTabBarChrome>
    with
        SingleTickerProviderStateMixin<MorphTabBarChrome>,
        MorphClock<MorphTabBarChrome>,
        MorphTabBarMinimizing<MorphTabBarChrome> {
  late final MorphTabBarMinimizeMotion _motion = MorphTabBarMinimizeMotion(
    behavior: widget.behavior,
  );

  @override
  MorphTabBarMinimizeMotion get minimizeMotion => _motion;

  MorphTabBarGroupGeometry? _geometry;
  Rect _bar = Rect.zero;
  Rect _accessory = Rect.zero;
  Rect _search = Rect.zero;
  double _searchShown = 0;

  // The tab the leading circle shows while the search tab is selected:
  // the last other tab selected, as UIKit's minimized bar keeps it.
  int _lastOther = 0;

  int get _searchIndex =>
      widget.items.indexWhere((item) => item.role == MorphTabRole.search);

  void _noteSelection() {
    final search = _searchIndex;
    final selected = widget.selected;
    if (selected != search && selected >= 0) {
      _lastOther = selected;
    } else if (_lastOther == search || _lastOther >= widget.items.length) {
      _lastOther = search == 0 && widget.items.length > 1 ? 1 : 0;
    }
  }

  int get _lead {
    final selected = widget.selected.clamp(0, widget.items.length - 1);
    return selected == _searchIndex ? _lastOther : selected;
  }

  void _collapsedTapped() {
    final searchSelected = _searchIndex >= 0 && widget.selected == _searchIndex;
    expandMinimized();
    if (searchSelected) widget.onSelect?.call(_lastOther);
  }

  void _searchTapped() {
    final search = _searchIndex;
    if (search < 0) return;
    if (widget.selected == search) {
      expandMinimized();
      return;
    }
    widget.onSelect?.call(search);
  }

  final ValueNotifier<bool> _labelShown = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _collapsedEnabled = ValueNotifier<bool>(false);

  late final MorphFrameSync<_Structure?> _ticks = MorphFrameSync<_Structure?>(
    structure: () => _geometry == null ? null : _readFrame(),
    rebuild: (_Structure? _) => setState(() {}),
    // The parts a structure change keeps (_cached) follow on that frame
    // too, or the accessory's content would trail its glass by one.
    notifiesOnRebuild: true,
  );

  @override
  void initState() {
    super.initState();
    _noteSelection();
    _ticks.follow(frames);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(MorphTabBarChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    _noteSelection();
    _follow();
    changeMinimizeBehavior(widget.behavior);
  }

  void _follow() => followContentScroll(
    widget.contentScroll ?? MorphContentScrollScope.maybeOf(context),
  );

  @override
  void dispose() {
    _ticks.dispose();
    _labelShown.dispose();
    _collapsedEnabled.dispose();
    super.dispose();
  }

  @override
  void advanceMotion(double t) => _motion.advance(t);

  @override
  bool get motionSettled =>
      _motion.isSettled(extent: _geometry?.size.width ?? 400);

  @override
  double? get motionWakeTime =>
      _motion.wakeTime(extent: _geometry?.size.width ?? 400);

  @override
  void settleMotion() => _motion.settle(_motion.time);

  // The finger on the minimized bar, followed here in the group's
  // coordinates; once it moves on, its events go to the expanded bar's
  // press, laid out under [_barKey].
  final GlobalKey _barKey = GlobalKey();
  int? _pointer;
  bool _handed = false;

  void _pointerDown(PointerDownEvent event) {
    if (_pointer != null ||
        event.buttons != kPrimaryButton ||
        !_motion.minimized ||
        !_bar.contains(event.localPosition)) {
      return;
    }
    _pointer = event.pointer;
    _handed = false;
    final t = stamp(event);
    _motion.advance(t);
    _motion.pressDown(t, event.localPosition.dx);
    wake();
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    if (_handed) {
      widget.barPress?.pressMove(_toBar(event) as PointerMoveEvent);
      return;
    }
    final t = stamp(event);
    _motion.advance(t);
    final scrubs = _motion.pressMove(t, event.localPosition.dx);
    wake();
    final press = widget.barPress;
    if (!scrubs || press == null) return;
    _handed = true;
    press.pressDown(
      _toBar(
            PointerDownEvent(
              timeStamp: event.timeStamp,
              pointer: event.pointer,
              kind: event.kind,
              device: event.device,
              position: event.position,
              buttons: event.buttons,
            ),
          )
          as PointerDownEvent,
    );
  }

  void _pointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final t = stamp(event);
    _motion.advance(t);
    final tap = !_motion.held && !_motion.scrubs;
    _motion.pressUp(t);
    if (_handed) widget.barPress?.pressUp(_toBar(event) as PointerUpEvent);
    _handed = false;
    wake();
    final search = _searchIndex;
    if (tap && search >= 0 && widget.selected == search) {
      widget.onSelect?.call(_lastOther);
    }
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final t = stamp(event);
    _motion.advance(t);
    _motion.pressCancel(t);
    if (_handed) widget.barPress?.pressCancel(event);
    _handed = false;
    wake();
  }

  PointerEvent _toBar(PointerEvent event) {
    final box = _barKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return event;
    final toBar = Matrix4.tryInvert(box.getTransformTo(null));
    return toBar == null ? event : event.transformed(toBar);
  }

  _Structure _readFrame() {
    final geometry = _geometry!;
    final shape = _motion.shape;
    final content = _motion.content;
    _bar = Rect.lerp(geometry.bar, geometry.collapsed, shape)!;
    _accessory = Rect.lerp(
      geometry.accessory,
      geometry.inlineAccessory,
      shape,
    )!;
    final searchEnd = geometry.searchCollapsed;
    if (searchEnd != null) {
      _search = Rect.lerp(_searchSlot(geometry), searchEnd, shape)!;
    }
    final q = content.clamp(0.0, 1.0);
    _searchShown = q;
    _labelShown.value = (1 - q * 2).clamp(0.0, 1.0) > 0.01;
    _collapsedEnabled.value = _motion.minimized;
    final resting = _motion.restsExpanded;
    return (
      resting: resting,
      minimized: _motion.minimized,
      apart: resting || !_accessory.inflate(1).overlaps(_bar),
    );
  }

  // Where the search circle starts: a circle as tall as the bar around the
  // search tab's slot, inside the expanded bar's glass.
  Rect _searchSlot(MorphTabBarGroupGeometry geometry) {
    final count = widget.items.length;
    final bar = geometry.bar;
    final pitch = (bar.width - 2 * MorphTabBarMetrics.sideInset) / count;
    final index = widget.rtl ? count - 1 - _searchIndex : _searchIndex;
    return Rect.fromCenter(
      center: Offset(
        bar.left + MorphTabBarMetrics.sideInset + pitch * (index + 0.5),
        bar.center.dy,
      ),
      width: bar.height,
      height: bar.height,
    );
  }

  void _writeHint(Matrix4 into) {
    final scale = _motion.hint;
    if (scale == 1) return;
    into.scaleByDouble(scale, scale, 1, 1);
  }

  static RRect _capsule(Rect rect) => RRect.fromRectAndRadius(
    rect,
    Radius.circular((rect.shortestSide / 2).clamp(0.0, double.infinity)),
  );

  MorphGlassSurface _capsuleSurface(Rect rect) => MorphGlassSurface(
    kind: MorphGlassKind.bar,
    shape: _capsule(rect),
    color: widget.appearance.barColor,
    brightness: widget.brightness,
  );

  final Map<String, (Object, Widget)> _parts = {};

  // A part of the group built once for what it reads: a structure change
  // that only reorders or swaps parts builds nothing inside the others.
  Widget _cached(String slot, Object key, Widget Function() build) {
    final cached = _parts[slot];
    if (cached != null && cached.$1 == key) return cached.$2;
    final built = build();
    _parts[slot] = (key, built);
    return built;
  }

  // The collapsing tabs, built once for what they draw.
  Object? _collapsedKey;
  Widget? _collapsed;

  // The last build, handed back while nothing it reads changed: a parent
  // rebuilding an unchanged bar builds nothing here.
  Object? _builtKey;
  Widget? _built;
  int _structures = 0;

  @override
  void setState(VoidCallback fn) {
    _structures++;
    super.setState(fn);
  }

  @override
  Widget build(BuildContext context) {
    final key = (
      widget.bar,
      widget.barWidth,
      widget.items,
      widget.selected,
      widget.appearance,
      widget.glass,
      widget.brightness,
      widget.rtl,
      widget.accessory,
      _structures,
    );
    final built = _built;
    if (built != null && key == _builtKey) return built;
    _builtKey = key;
    return _built = LayoutBuilder(builder: _buildGroup);
  }

  Widget _buildGroup(BuildContext context, BoxConstraints constraints) {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : widget.barWidth + 2 * MorphTabBarMinimizeTuning.sideInset;
    final accessory = widget.accessory;
    final geometry = _geometry = MorphTabBarGroupGeometry.of(
      width: width,
      barWidth: widget.barWidth,
      accessory: accessory != null,
      rtl: widget.rtl,
      search: _searchIndex >= 0,
    );
    final structure = _ticks.read()!;
    final resting = structure.resting;
    final glass = widget.glass;
    final style = widget.appearance;
    final selected = _lead;
    final searchEnd = geometry.searchCollapsed;
    final searching = !resting && searchEnd != null;
    // Each part is a repaint boundary of its own: a frame of the morph
    // repaints the moving glass and composites the rest. The accessory is
    // glass of its own, never one body with the bar's (as on iOS: fused,
    // the two capsules became one blob while they passed each other
    // mid-morph). While they stand apart both are surfaces of one layer
    // under the accessory's content, which reads the backdrop once; while
    // they overlap the accessory draws its own glass under the bar's.
    final shared = glass != null && structure.apart;
    final minimized = structure.minimized;
    Widget? glassLayer;
    if (glass != null && (!resting || accessory != null)) {
      glassLayer = _cached(
        'glass',
        (glass, resting, shared, accessory != null, searching),
        () => Positioned.fill(
          key: const ValueKey<String>('glass'),
          child: RepaintBoundary(
            child: IgnorePointer(
              child: MorphGlassHost(
                painter: glass,
                mode: MorphGlassMode.layer,
                frames: _ticks,
                frame: () => MorphGlassFrame([
                  if (!resting) _capsuleSurface(_bar),
                  if (searching) _capsuleSurface(_search),
                  if (shared && accessory != null) _capsuleSurface(_accessory),
                ]),
              ),
            ),
          ),
        ),
      );
    }
    Widget? accessoryGlass;
    Widget? accessoryContent;
    if (accessory != null) {
      if (!shared) {
        accessoryGlass = _cached(
          'accessoryGlass',
          (glass, style, widget.brightness),
          () => Positioned.fill(
            key: const ValueKey<String>('accessoryGlass'),
            child: RepaintBoundary(
              child: IgnorePointer(
                child: glass == null
                    ? CustomPaint(
                        painter: MorphCapsulePainter(
                          live: _ticks,
                          shape: () => _capsule(_accessory),
                          color: () => style.barColor,
                          shadow: style.shadowColor,
                        ),
                      )
                    : MorphGlassHost(
                        painter: glass,
                        mode: MorphGlassMode.layer,
                        frames: _ticks,
                        frame: () =>
                            MorphGlassFrame([_capsuleSurface(_accessory)]),
                      ),
              ),
            ),
          ),
        );
      }
      accessoryContent = _cached(
        'accessory',
        (
          accessory,
          minimized,
          geometry.accessory,
          geometry.inlineAccessory,
          style,
        ),
        () => KeyedSubtree(
          key: const ValueKey<String>('accessory'),
          child: morphTabAccessoryContent(
            live: _ticks,
            rect: () => _accessory,
            end: minimized ? geometry.inlineAccessory : geometry.accessory,
            environment: minimized
                ? MorphTabAccessoryEnvironment.inline
                : MorphTabAccessoryEnvironment.regular,
            style: style,
            child: accessory,
            context: context,
          ),
        ),
      );
    }
    // While apart: one layer under the content. While they overlap: the
    // accessory's glass and content, then the bar's glass over them.
    final children = <Widget>[
      if (shared) ?glassLayer else ?accessoryGlass,
      ?accessoryContent,
      if (!shared) ?glassLayer,
      // Hidden while it collapses, but kept: the expanded bar returns at
      // the end of the morph without building again.
      Positioned.fromRect(
        key: const ValueKey<String>('bar'),
        rect: geometry.bar,
        child: RepaintBoundary(
          child: ExcludeSemantics(
            excluding: !resting,
            child: IgnorePointer(
              ignoring: !resting,
              child: Opacity(
                opacity: resting ? 1 : 0,
                child: KeyedSubtree(key: _barKey, child: widget.bar),
              ),
            ),
          ),
        ),
      ),
    ];
    if (!resting && widget.items.isNotEmpty) {
      final collapsedKey = (
        widget.items,
        selected,
        geometry.bar,
        style,
        glass,
        widget.brightness,
        widget.rtl,
      );
      if (_collapsedKey != collapsedKey) {
        _collapsedKey = collapsedKey;
        _collapsed = MorphCollapsingTabs(
          live: _ticks,
          items: widget.items,
          selected: selected,
          progress: () => _motion.content,
          restRect: geometry.bar,
          rect: () => _bar,
          labelShown: _labelShown,
          style: style,
          glass: glass,
          brightness: widget.brightness,
          rtl: widget.rtl,
          label: widget.items[selected].label,
          onTap: _collapsedTapped,
          enabled: _collapsedEnabled,
          drawsGlass: glass == null,
          tapsOnTouch: false,
          layoutBox: geometry.bar.expandToInclude(geometry.collapsed),
        );
      }
      // Laid out once over both ends (the expanded bar and its circle); the
      // collapse moves its glass, clip and glyph by paint.
      children.add(
        Positioned.fromRect(
          key: const ValueKey<String>('collapsed'),
          rect: geometry.bar.expandToInclude(geometry.collapsed),
          child: RepaintBoundary(child: _collapsed),
        ),
      );
    }
    if (searching) {
      final search = widget.items[_searchIndex];
      final searchSelected = widget.selected == _searchIndex;
      children.add(
        _cached(
          'search',
          (search, searchSelected, searchEnd, style, glass, widget.brightness),
          () => KeyedSubtree(
            key: const ValueKey<String>('searchCircle'),
            child: _SearchTabCircle(
              live: _ticks,
              rect: () => _search,
              shown: () => _searchShown,
              end: searchEnd,
              item: search,
              color: searchSelected ? style.selectedColor : style.color,
              style: style,
              drawsGlass: glass == null,
              enabled: _collapsedEnabled,
              onTap: _searchTapped,
            ),
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: GlassPlaneScope.chrome(
        child: MorphLiveTransform(
          live: _ticks,
          writeInto: _writeHint,
          child: Listener(
            onPointerDown: _pointerDown,
            onPointerMove: _pointerMove,
            onPointerUp: _pointerUp,
            onPointerCancel: _pointerCancel,
            child: SizedBox.fromSize(
              size: geometry.size,
              child: Stack(clipBehavior: Clip.none, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// The minimized bar's search tab circle, laid out once at [end] and
/// carried from the search tab's slot to [end] by paint: its glyph fades
/// in as [shown] runs to 1. With [drawsGlass] it paints its flat body
/// itself; otherwise the bar group's glass layer draws it.
class _SearchTabCircle extends StatelessWidget {
  const _SearchTabCircle({
    required this.live,
    required this.rect,
    required this.shown,
    required this.end,
    required this.item,
    required this.color,
    required this.style,
    required this.drawsGlass,
    required this.enabled,
    required this.onTap,
  });

  final Listenable live;
  final Rect Function() rect;
  final double Function() shown;
  final Rect end;
  final MorphTabItem item;
  final Color color;
  final MorphTabBarAppearance style;
  final bool drawsGlass;
  final ValueListenable<bool> enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    RRect shape() {
      final r = rect().shift(-end.topLeft);
      return RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2));
    }

    return Positioned.fromRect(
      rect: end,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          if (drawsGlass)
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: MorphCapsulePainter(
                    live: live,
                    shape: shape,
                    color: () => style.barColor,
                    shadow: style.shadowColor,
                  ),
                ),
              ),
            ),
          RepaintBoundary(
            child: MorphLiveTransform.matrix(
              live: live,
              alignment: null,
              matrixOf: () {
                final d = rect().center - end.center;
                return Matrix4.translationValues(d.dx, d.dy, 0);
              },
              child: MorphLiveOpacity(
                live: live,
                opacityOf: () => shown().clamp(0.0, 1.0),
                child: Semantics(
                  button: true,
                  label: item.semanticLabel ?? item.label,
                  value: item.semanticValue,
                  onTap: onTap,
                  excludeSemantics: true,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: enabled,
                    builder: (BuildContext context, bool on, Widget? child) =>
                        IgnorePointer(
                          ignoring: !on,
                          child: MorphPress(
                            enabled: on,
                            onActivate: onTap,
                            focusRing: true,
                            focusSemantics: false,
                            child: child!,
                          ),
                        ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTap,
                      child: Center(
                        child: morphTabGlyph(
                          context,
                          item,
                          color: color,
                          selected: color == style.selectedColor,
                          minimized: true,
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
    );
  }
}
