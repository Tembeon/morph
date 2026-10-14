import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/chrome_group.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
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
  });

  /// Lays out a bar [barWidth] wide in a group [width] wide, with an
  /// accessory above it when [accessory]: the bar centered at the bottom,
  /// the minimized circle [MorphTabBarMinimizeTuning.collapsedInset]
  /// inside the bar group's leading side and bottom, the accessory
  /// [MorphTabBarMinimizeTuning.spacing] above the bar across the group
  /// and, inline, between the circle and the group's trailing side.
  /// [rtl] mirrors it.
  factory MorphTabBarGroupGeometry.of({
    required double width,
    required double barWidth,
    required bool accessory,
    bool rtl = false,
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
    final inline = Rect.fromLTRB(
      collapsed.right + gap,
      collapsed.top,
      width - side - inset,
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
    super.key,
  });

  /// The expanded bar, built by the tab bar.
  final Widget bar;

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

typedef _Structure = ({bool resting, bool minimized});

class _MorphTabBarChromeState extends State<MorphTabBarChrome>
    with
        SingleTickerProviderStateMixin<MorphTabBarChrome>,
        MorphClock<MorphTabBarChrome>
    implements MorphContentScrollClient {
  late final MorphTabBarMinimizeMotion _motion = MorphTabBarMinimizeMotion(
    behavior: widget.behavior,
  );
  MorphContentScroll? _source;
  MorphTabBarGroupGeometry? _geometry;
  Rect _bar = Rect.zero;
  Rect _accessory = Rect.zero;
  final ValueNotifier<bool> _labelShown = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _collapsedEnabled = ValueNotifier<bool>(false);

  late final MorphFrameSync<_Structure?> _ticks = MorphFrameSync<_Structure?>(
    structure: () => _geometry == null ? null : _readFrame(),
    rebuild: (_Structure? _) => setState(() {}),
  );

  @override
  void initState() {
    super.initState();
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
    _follow();
    if (oldWidget.behavior != widget.behavior) {
      _motion.setBehavior(clock, widget.behavior);
      wake();
    }
  }

  void _follow() {
    final source =
        widget.contentScroll ?? MorphContentScrollScope.maybeOf(context);
    if (identical(source, _source)) return;
    _source?.removeClient(this);
    _source = source;
    source?.addClient(this);
  }

  @override
  void dispose() {
    _source?.removeClient(this);
    _ticks.dispose();
    _labelShown.dispose();
    _collapsedEnabled.dispose();
    super.dispose();
  }

  @override
  void advanceMotion(double t) => _motion.advance(t);

  @override
  bool get motionSettled =>
      _motion.isSettled(_motion.time, extent: _geometry?.size.width ?? 400);

  @override
  void settleMotion() => _motion.settle(_motion.time);

  void _input(void Function(double t) action) {
    final t = clock;
    _motion.advance(t);
    action(t);
    wake();
  }

  @override
  void contentDragStarted() => _input((_) => _motion.scrollAway.beginDrag());

  @override
  void contentScrolled(
    double offset, {
    required double min,
    required double max,
    required bool tracking,
  }) {
    if (!_motion.behavior.minimizes) {
      _motion.scrollAway.record(offset);
      return;
    }
    _input(
      (_) => _motion.scrollAway.scroll(
        offset,
        min: min,
        max: max,
        tracking: tracking,
      ),
    );
  }

  @override
  void contentDragEnded({required bool decelerates}) =>
      _input((_) => _motion.scrollAway.endDrag(decelerates: decelerates));

  @override
  void contentDecelerationEnded() =>
      _input((_) => _motion.scrollAway.endDeceleration());

  @override
  void contentRecorded(double offset) => _motion.scrollAway.record(offset);

  @override
  void contentReachedTop() {
    if (!_motion.minimized) return;
    _input((_) => _motion.scrollAway.scrollToTop());
  }

  void _expand() {
    if (!_motion.minimized) return;
    _input((double t) => _motion.setMinimized(t, minimized: false));
  }

  _Structure _readFrame() {
    final geometry = _geometry!;
    final t = _motion.time;
    final shape = _motion.shape(t);
    final content = _motion.content(t);
    _bar = Rect.lerp(geometry.bar, geometry.collapsed, shape)!;
    _accessory = Rect.lerp(
      geometry.accessory,
      geometry.inlineAccessory,
      shape,
    )!;
    final q = content.clamp(0.0, 1.0);
    _labelShown.value = (1 - q * 2).clamp(0.0, 1.0) > 0.01;
    _collapsedEnabled.value = _motion.minimized;
    return (resting: _motion.restsExpanded(t), minimized: _motion.minimized);
  }

  void _writeHint(Matrix4 into) {
    final scale = _motion.hint(_motion.time);
    if (scale == 1) return;
    into.scaleByDouble(scale, scale, 1, 1);
  }

  static RRect _capsule(Rect rect) => RRect.fromRectAndRadius(
    rect,
    Radius.circular((rect.shortestSide / 2).clamp(0.0, double.infinity)),
  );

  List<MorphGlassSurface> _surfaces({required bool resting}) {
    final style = widget.appearance;
    return [
      if (!resting)
        MorphGlassSurface(
          kind: MorphGlassKind.bar,
          shape: _capsule(_bar),
          color: style.barColor,
          brightness: widget.brightness,
        ),
      if (widget.accessory != null)
        MorphGlassSurface(
          kind: MorphGlassKind.bar,
          shape: _capsule(_accessory),
          color: style.barColor,
          brightness: widget.brightness,
        ),
    ];
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
    );
    final structure = _ticks.read()!;
    final resting = structure.resting;
    final glass = widget.glass;
    final style = widget.appearance;
    final selected = widget.selected.clamp(0, widget.items.length - 1);
    final children = <Widget>[
      if (glass != null && (!resting || accessory != null))
        Positioned.fill(
          key: const ValueKey<String>('glass'),
          child: IgnorePointer(
            child: MorphGlassHost(
              painter: glass,
              mode: MorphGlassMode.layer,
              frames: _ticks,
              frame: () => MorphGlassFrame(
                _surfaces(resting: resting),
                spacing: MorphTabBarMinimizeTuning.fusionSpacing,
              ),
            ),
          ),
        )
      else if (glass == null && accessory != null)
        Positioned.fill(
          key: const ValueKey<String>('glass'),
          child: IgnorePointer(
            child: CustomPaint(
              painter: MorphCapsulePainter(
                live: _ticks,
                shape: () => _capsule(_accessory),
                color: () => style.barColor,
                shadow: style.shadowColor,
              ),
            ),
          ),
        ),
      // Hidden while it collapses, but kept: the expanded bar returns at
      // the end of the morph without building again.
      Positioned.fromRect(
        key: const ValueKey<String>('bar'),
        rect: geometry.bar,
        child: ExcludeSemantics(
          excluding: !resting,
          child: IgnorePointer(
            ignoring: !resting,
            child: Opacity(opacity: resting ? 1 : 0, child: widget.bar),
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
          progress: () => _motion.content(_motion.time),
          restRect: geometry.bar,
          rect: () => _bar,
          labelShown: _labelShown,
          style: style,
          glass: glass,
          brightness: widget.brightness,
          rtl: widget.rtl,
          label: widget.items[selected].label,
          onTap: _expand,
          enabled: _collapsedEnabled,
          drawsGlass: glass == null,
        );
      }
      children.add(
        MorphLivePositionedTemplate(
          key: const ValueKey<String>('collapsed'),
          live: _ticks,
          template: () => Positioned.fromRect(rect: _bar, child: morphLiveSlot),
          child: _collapsed!,
        ),
      );
    }
    if (accessory != null) {
      children.add(
        MorphLivePositionedTemplate(
          key: const ValueKey<String>('accessory'),
          live: _ticks,
          template: () =>
              Positioned.fromRect(rect: _accessory, child: morphLiveSlot),
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: const BorderRadius.all(
                Radius.circular(MorphTabBarMinimizeTuning.accessoryHeight / 2),
              ),
              child: _TabAccessoryScope(
                environment: structure.minimized
                    ? MorphTabAccessoryEnvironment.inline
                    : MorphTabAccessoryEnvironment.regular,
                child: DefaultTextStyle(
                  style: MorphTypography.resolve(
                    MorphTypography.body.copyWith(color: style.color),
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(color: style.color),
                    child: accessory,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: MorphChromeBackdrop(
        child: MorphLiveTransform(
          live: _ticks,
          writeInto: _writeHint,
          child: SizedBox.fromSize(
            size: geometry.size,
            child: Stack(clipBehavior: Clip.none, children: children),
          ),
        ),
      ),
    );
  }
}
