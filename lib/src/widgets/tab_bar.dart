import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderFlex;
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/badge.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/control_host.dart';
import 'package:morph/src/motion/flex_spec.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_glow.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/glyph_scale.dart';
import 'package:morph/src/widgets/lens_driver.dart';
import 'package:morph/src/widgets/lens_motion.dart';
import 'package:morph/src/widgets/press.dart';
import 'package:morph/src/widgets/tab_bar_chrome.dart';
import 'package:morph/src/widgets/tab_bar_minimize.dart';
import 'package:morph/src/widgets/typography.dart';
import 'package:morph/src/theme/theme.dart';

/// What a [MorphTabItem] stands for beyond an ordinary tab (SwiftUI
/// `TabRole`).
enum MorphTabRole {
  /// The search tab (UIKit `UISearchTab` without
  /// `automaticallyActivatesSearch`, SwiftUI `Tab(role: .search)`): an
  /// ordinary tab while the bar is expanded, whose page carries a stacked
  /// search field; a minimized bar sets it apart as a circle of its own at
  /// the trailing side. Tapping that circle when selected expands the
  /// bar without changing the page (iPhone 16 Pro capture). For the search
  /// tab that turns into a field on selection, use [MorphSearchTabBar].
  search,
}

/// One item of a [MorphTabBar].
class MorphTabItem {
  /// Creates a tab item.
  const MorphTabItem({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.badge,
    this.enabled = true,
    this.role,
  });

  /// The item's role, or null for an ordinary tab. At most one item of a
  /// bar is the [MorphTabRole.search] tab, conventionally the last.
  final MorphTabRole? role;

  /// The item's glyph.
  final IconData icon;

  /// The glyph the item shows inside the selection lens (UIKit
  /// `UITabBarItem.selectedImage`), or null for [icon]: a tab half under
  /// the lens shows each glyph on its side of the lens outline.
  final IconData? selectedIcon;

  /// The badge at the top trailing corner of the glyph (UIKit
  /// `UITabBarItem.badgeValue`, SwiftUI `badge(_:)`), or null; see
  /// [MorphBadge] for what is not yet measured. It rides the bar's swell
  /// above the lens, without refraction (iPhone 16 Pro capture).
  final MorphBadge? badge;

  /// The item's title.
  final String label;

  /// Whether the tab can be selected.
  ///
  /// A disabled tab looks exactly like an enabled one, as UIKit's
  /// `UITabBarItem.isEnabled = NO` does on iOS 27. A touch on it does not
  /// select it and the lens stays where it is, but the bar still swells
  /// under the finger.
  final bool enabled;
}

/// A floating tab bar whose selection lens moves exactly like iOS 27's
/// UITabBar.
///
/// A touch selects on contact and keeps the lens lifted while the finger
/// is down; a touch on the selected tab lifts it in place. Dragging
/// carries the lens by the finger's travel, with a tight rubber band past
/// the first and last tabs, and the release picks the tab nearest the
/// finger. While pressed, the whole bar swells around its center, lens
/// included, and brightens: a wash over the whole bar and a soft spot
/// under the finger that spreads and fades when the finger lifts.
///
/// The tabs inside the lens wear the selected style and the others the
/// regular one, cut along the lens outline, so the selection's tint
/// travels with the lens and a tab half under it is half tinted.
///
/// Inside a [Scrollable] the bar reacts to a touch only once the touch
/// is its own, as UIKit delays the touches of a scroll view's content:
/// after it has been held for 0.15 s, dragged along the bar past the
/// touch slop in a list that scrolls the other way, or lifted. Until
/// then nothing moves, so a swipe that scrolls the list never selects
/// the tab it started on. A floating bar outside any scrollable selects
/// on contact.
///
/// The bar is focusable and the arrow keys move the selection; screen
/// readers see a tab bar of tabs. In a right-to-left context the first
/// tab is on the right. Labels follow the text scale up to
/// [maxTextScale], and the tabs widen to fit the widest label. With the
/// platform's reduced motion on, the lens travels without lifting or
/// deforming and the bar does not swell.
///
/// ## Minimizing and the bottom accessory
///
/// With a [minimizeBehavior] that minimizes, the bar follows the scrolls
/// of the content under it ([contentScroll], or the nearest
/// [MorphContentScrollScope]): a user's scroll in the minimizing
/// direction shrinks the bar slightly as it goes and, after 64 points,
/// collapses the bar into a circle holding the selected tab's glyph; a
/// scroll to the top, pushing the
/// content past its far end or a tap on the circle expands it (a scroll
/// back in the middle of the content does not, as on iOS 27). A finger held on the circle for 0.22 s
/// expands the bar under it, and one that moves 4 points along it expands
/// it at once; from that move the touch scrubs the tabs as the expanded
/// bar's drag does and its release selects, while a hold lifted in place
/// lets the bar collapse back (UIKit's interactive expansion). A tab with
/// [MorphTabRole.search] becomes a circle of its own at the trailing side
/// while the bar is minimized, its glyph tinted while it is selected;
/// the leading circle then shows the last other tab selected, and a tap
/// on it expands the bar and selects that tab, as iOS 27 does (filmed on
/// the simulator). A tap on the search circle selects the search tab and
/// leaves the bar minimized (not yet measured). A
/// [bottomAccessory] floats in its own glass above the bar and moves
/// inline next to the minimized circle; its content reads where it is
/// from [MorphTabAccessoryEnvironment.of].
///
/// With either, the bar lays itself out across the width it is given, as
/// UIKit's tab bar group spans the screen: place it at the bottom of a
/// [Stack] that fills the screen (`Positioned(left: 0, right: 0, bottom:
/// 21)`); the expanded bar stays centered, the minimized circle and the
/// accessory keep 21 points from the sides. Without either, nothing of
/// this exists and the bar is as wide as its tabs.
class MorphTabBar extends StatefulWidget {
  /// Creates a tab bar.
  const MorphTabBar({
    required this.items,
    required this.selected,
    required this.onChanged,
    this.onReselected,
    this.appearance,
    this.minimizeBehavior = MorphTabBarMinimizeBehavior.automatic,
    this.bottomAccessory,
    this.contentScroll,
    super.key,
  });

  /// When the bar minimizes to its selected tab as the content scrolls
  /// (UIKit `tabBarMinimizeBehavior`);
  /// [MorphTabBarMinimizeBehavior.automatic] does not minimize, as an
  /// iPhone tab bar that does not opt in.
  final MorphTabBarMinimizeBehavior minimizeBehavior;

  /// The content of the glass accessory above the bar, a mini player for
  /// example (UIKit `bottomAccessory`, SwiftUI `tabViewBottomAccessory`),
  /// or null. It is laid out 48 points tall across the bar group, and
  /// inline between the minimized bar and the group's trailing side; its
  /// geometry is not yet measured.
  final Widget? bottomAccessory;

  /// The scrolls the bar follows to minimize; null follows the nearest
  /// [MorphContentScrollScope].
  final MorphContentScroll? contentScroll;

  /// The tabs, two to five.
  final List<MorphTabItem> items;

  /// The index of the selected tab, clamped to the available items.
  final int selected;

  /// Called with the new index when the user selects a tab; null disables
  /// every tab ([MorphTabItem.enabled]): the bar keeps its look and still
  /// swells under a finger, but nothing selects.
  final ValueChanged<int>? onChanged;

  /// Called with the selected tab's index when the user taps it again
  /// (UIKit's `tabBarController(_:didSelect:)` for the selected tab),
  /// where an app scrolls the tab's content to the top or pops it to its
  /// root. A touch that starts and lifts on the selected tab reports it,
  /// as do Space, Enter and a screen reader's activation; when it fires
  /// during the release is not measured.
  final ValueChanged<int>? onReselected;

  /// The colors of the bar; null resolves them from the theme.
  final MorphTabBarAppearance? appearance;

  /// The largest text scale the labels follow.
  static const double maxTextScale = 1.25;

  @override
  State<MorphTabBar> createState() => _MorphTabBarState();
}

/// The look of a [MorphTabBar].
@immutable
class MorphTabBarAppearance implements MorphAppearance {
  /// Creates an appearance; the defaults are the iOS 27 light appearance.
  ///
  /// The platter and the tab colors are what UIKit's color matrices make
  /// of the measured bar: the platter darkens the bar under the selection
  /// and the tab glyphs are vibrant, so their exact color follows the
  /// backdrop; these are their values over a bar on a plain page.
  const MorphTabBarAppearance({
    this.barColor = const Color(0xB8FFFFFF),
    this.shadowColor = const Color(0x24000000),
    this.platterColor = const Color(0x13000000),
    this.liftedLensColor = const Color(0x33FFFFFF),
    this.lensBorderColor = const Color(0x40000000),
    this.selectedColor = const Color(0xFF0082FC),
    this.color = const Color(0xFF0D0D0D),
    this.blurSigma = 12,
  });

  /// The translucent fill of the bar.
  final Color barColor;

  /// The shadow under the bar.
  final Color shadowColor;

  /// The fill of the resting selection.
  final Color platterColor;

  /// The fill of the lifted lens.
  final Color liftedLensColor;

  /// The outline of the lifted lens.
  final Color lensBorderColor;

  /// The tint of the tabs inside the selection lens.
  final Color selectedColor;

  /// The tint of the tabs outside the selection lens.
  final Color color;

  /// The blur of the backdrop behind the bar.
  final double blurSigma;

  /// The light appearance.
  static const light = MorphTabBarAppearance();

  /// The dark appearance, from the iOS dark system colors.
  static const dark = MorphTabBarAppearance(
    barColor: Color(0xB81C1C1E),
    shadowColor: Color(0x66000000),
    platterColor: Color(0xAF000000),
    liftedLensColor: Color(0x1FFFFFFF),
    lensBorderColor: Color(0x40FFFFFF),
    selectedColor: Color(0xFF0397FF),
    color: Color(0xFFFAFAFA),
  );

  /// Copies this appearance with the given fields replaced.
  MorphTabBarAppearance copyWith({
    Color? barColor,
    Color? shadowColor,
    Color? platterColor,
    Color? liftedLensColor,
    Color? lensBorderColor,
    Color? selectedColor,
    Color? color,
    double? blurSigma,
  }) => MorphTabBarAppearance(
    barColor: barColor ?? this.barColor,
    shadowColor: shadowColor ?? this.shadowColor,
    platterColor: platterColor ?? this.platterColor,
    liftedLensColor: liftedLensColor ?? this.liftedLensColor,
    lensBorderColor: lensBorderColor ?? this.lensBorderColor,
    selectedColor: selectedColor ?? this.selectedColor,
    color: color ?? this.color,
    blurSigma: blurSigma ?? this.blurSigma,
  );

  /// Resolves [explicit], then the ambient [MorphTheme], then the
  /// table for the ambient brightness with [MorphThemeData.tint] as its
  /// [selectedColor].
  static MorphTabBarAppearance resolve(
    BuildContext context,
    MorphTabBarAppearance? explicit,
  ) => morphResolveAppearance(
    context,
    explicit,
    light: light,
    dark: dark,
    tinted: (table, tint) => table.copyWith(selectedColor: tint),
  );

  @override
  bool operator ==(Object other) =>
      other is MorphTabBarAppearance &&
      other.barColor == barColor &&
      other.shadowColor == shadowColor &&
      other.platterColor == platterColor &&
      other.liftedLensColor == liftedLensColor &&
      other.lensBorderColor == lensBorderColor &&
      other.selectedColor == selectedColor &&
      other.color == color &&
      other.blurSigma == blurSigma;

  @override
  int get hashCode => Object.hash(
    barColor,
    shadowColor,
    platterColor,
    liftedLensColor,
    lensBorderColor,
    selectedColor,
    color,
    blurSigma,
  );
}

typedef _Geometry = ({double pitch, double lens, double width});

/// Geometry measured from iOS 27 tab bar view trees on the simulator and
/// iPhone: 62 pixel bar, 54 pixel lens, 86/68 pixel pitch and 94/98/77
/// pixel lens widths for two through five tabs (tab-bar.md).
@internal
abstract final class MorphTabBarMetrics {
  /// The resting bar height.
  static const double height = 62;

  /// The resting lens height.
  static const double lensHeight = 54;

  /// The capsule corner radius.
  static const double radius = 31;

  /// The horizontal content inset.
  static const double sideInset = 8;

  /// The icon size measured from native tab content.
  static const double iconSize = 24;

  /// The gap between the icon and label.
  static const double labelGap = 2;

  /// The horizontal space a label keeps inside its tab.
  static const double labelPadding = 12;

  /// The native slot pitch for [count] tabs.
  static double pitch(int count) => count <= 4 ? 86 : 68;

  /// The native lens width for [count] tabs.
  static double lensWidth(int count) => switch (count) {
    <= 3 => 94,
    4 => 98,
    _ => 77,
  };

  /// The bar geometry widened to fit [labelWidth].
  static ({double pitch, double lens, double width}) geometry(
    int count,
    double labelWidth,
  ) {
    final measured = pitch(count);
    final slot = math.max(measured, labelWidth + 2 * labelPadding);
    return (
      pitch: slot,
      lens: lensWidth(count) + slot - measured,
      width: slot * count + 2 * sideInset,
    );
  }
}

class _MorphTabBarState extends MorphControlHost<MorphTabBar>
    with MorphLensDriver<MorphTabBar> {
  static const double _barHeight = MorphTabBarMetrics.height;
  static const double _lensHeight = MorphTabBarMetrics.lensHeight;
  static const double _radius = MorphTabBarMetrics.radius;

  _Geometry _layout = MorphTabBarMetrics.geometry(0, 0);
  MorphLensMotion? _motion;
  final MorphTouchGlowMotion _glow = _createGlow();
  MorphTabBarAppearance _style = MorphTabBarAppearance.light;
  Brightness _brightness = Brightness.light;
  bool _rtl = false;

  @override
  MorphLensMotion get motion => _motion!;

  static MorphTouchGlowMotion _createGlow() {
    final spec = MorphFlexSpec.forSize(const Size(274, _barHeight));
    return MorphTouchGlowMotion(
      washPeak: spec.bigGlowOpacity,
      spotPeak: spec.littleGlowOpacity,
      diameter: MorphTouchGlowMotion.tabBarDiameter,
      riseLag: MorphTouchGlowMotion.tabBarRiseLag,
    );
  }

  @override
  void advanceMotion(double t) {
    super.advanceMotion(t);
    _glow.advance(t);
  }

  @override
  bool get motionSettled => super.motionSettled && _glow.isSettled(clock);

  @override
  double trackPosition(Offset local) =>
      _rtl ? _layout.width - local.dx : local.dx;

  bool get _enabled =>
      widget.onChanged != null && widget.items.any((item) => item.enabled);

  bool _selectable(int index) =>
      widget.onChanged != null &&
      index >= 0 &&
      index < widget.items.length &&
      widget.items[index].enabled;

  List<MorphLensSlot> _slots(_Geometry geometry) => [
    for (var i = 0; i < widget.items.length; i++)
      (
        center: MorphTabBarMetrics.sideInset + geometry.pitch * (i + 0.5),
        width: geometry.lens,
      ),
  ];

  MorphLensMotion _create(_Geometry geometry) {
    final created = MorphLensMotion(
      tuning: MorphLensTuning.tabBar,
      slots: _slots(geometry),
      selected: widget.selected,
      height: _lensHeight,
      frameRate: motionFrameRate,
    );
    created.isSelectable = _selectable;
    return created;
  }

  void _sync(_Geometry geometry) {
    final current = _motion;
    if (current == null || current.slots.length != widget.items.length) {
      _motion = _create(geometry);
    } else if (geometry != _layout) {
      current.slots = _slots(geometry);
    }
    _layout = geometry;
    final selected = widget.items.isEmpty
        ? -1
        : widget.selected.clamp(0, widget.items.length - 1);
    if (motion.selected != selected) {
      motion.select(clock, selected, notify: false);
      wake();
    }
  }

  @override
  void deliverMotionEvents() {
    super.deliverMotionEvents();
    final motion = _motion;
    if (motion == null) return;
    for (final event in motion.drainEvents()) {
      if (!mounted) return;
      switch (event) {
        case MorphLensSelected(:final index):
          _selected(index);
      }
    }
  }

  void _selected(int index) {
    setState(() {});
    if (index != widget.selected) widget.onChanged?.call(index);
    reconcileSelection(
      () => widget.items.isEmpty
          ? -1
          : widget.selected.clamp(0, widget.items.length - 1),
    );
  }

  void _select(int index) {
    if (!_selectable(index)) return;
    if (index == motion.selected) {
      widget.onReselected?.call(index);
      return;
    }
    motion.select(clock, index);
    deliverMotionEvents();
    wake();
  }

  void _step(int delta) {
    final direction = (_rtl ? -delta : delta).sign;
    var next = motion.selected + direction;
    while (next >= 0 && next < widget.items.length && !_selectable(next)) {
      next += direction;
    }
    if (next >= 0 && next < widget.items.length) _select(next);
  }

  final MorphLabelWidths _labelWidths = MorphLabelWidths();

  double _widestLabel(TextScaler scaler) => _labelWidths
      .of(
        [for (final item in widget.items) item.label],
        const [MorphTypography.tabLabelSelected],
        scaler,
      )
      .fold(0.0, math.max);

  RRect _lensShape(Size size) => morphLensShape(motion, size, rtl: _rtl);

  MorphGlassGlow? _glowNow() => _glow.glowAt(clock, _brightness);

  List<MorphGlassSurface> _surfaces() {
    final size = Size(_layout.width, _barHeight);
    final lift = motion.lift.clamp(0.0, 1.0);
    return [
      MorphGlassSurface(
        kind: MorphGlassKind.bar,
        shape: RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(_radius),
        ),
        color: _style.barColor,
        brightness: _brightness,
        enabled: _enabled,
        glow: _glowNow(),
      ),
      MorphGlassSurface(
        kind: MorphGlassKind.lens,
        shape: _lensShape(size),
        color: Color.lerp(_style.platterColor, _style.liftedLensColor, lift)!,
        brightness: _brightness,
        lift: lift,
        scaleX: motion.scaleX,
        scaleY: motion.scaleY,
        optics: MorphGlassOptics.large,
        enabled: _enabled,
      ),
    ];
  }

  @override
  bool get controlEnabled => widget.items.isNotEmpty;

  int? _downSlot;
  int? _downSelected;

  @override
  void onControlDown(double t, PointerDownEvent event) {
    _downSlot = motion.slotAt(trackPosition(event.localPosition));
    _downSelected = motion.selected;
    super.onControlDown(t, event);
    if (_selectable(motion.slotAt(trackPosition(event.localPosition)))) {
      _glow.pointerDown(clock, event.localPosition);
    }
  }

  @override
  void onControlMove(double t, PointerMoveEvent event) {
    super.onControlMove(t, event);
    _glow.pointerMove(clock, event.localPosition);
  }

  @override
  void onControlUp(double t, PointerUpEvent event) {
    final before = _downSelected;
    final down = _downSlot;
    _downSlot = null;
    _downSelected = null;
    super.onControlUp(t, event);
    _glow.pointerUp(clock);
    final up = motion.slotAt(trackPosition(event.localPosition));
    if (down == before &&
        up == before &&
        motion.selected == before &&
        before != null &&
        _selectable(before)) {
      widget.onReselected?.call(before);
    }
  }

  @override
  void onControlCancel(double t) {
    super.onControlCancel(t);
    _glow.pointerUp(clock);
  }

  MorphGlassPainter? _glass;

  late final Listenable _rowChanges = MorphChanges<(double, bool)>(
    frames,
    () => (motion.chromeGrowth, _rowsApart),
  );

  // A row is a repaint boundary of its own while neither the bar swells
  // (its glyphs then snap to the screen scale at paint, every frame) nor
  // a painter records the content to copy it into a lifted lens (the copy
  // replays the content's pictures): then a lens that travels only moves
  // the clips over the rows, and the rows are composited again.
  bool get _rowsApart =>
      motion.chromeGrowth == 0 &&
      (morphGlassKeepsContentLive(_glass) ||
          motion.lift <= GlassBuiltInPainter.restingLift);

  Widget _tabRow(List<Widget> children) => _TabRow(
    changes: _rowChanges,
    apart: () => _rowsApart,
    children: children,
  );

  Widget _row(TextScaler scaler, {required bool selected}) => _tabRow([
    for (final item in widget.items)
      SizedBox(
        width: _layout.pitch,
        child: MorphGlyphs(
          aligned: true,
          child: _TabLabel(
            item: item,
            scaler: scaler,
            selected: selected,
            color: selected ? _style.selectedColor : _style.color,
          ),
        ),
      ),
  ]);

  @override
  bool buildsLike(MorphTabBar oldWidget) =>
      _sameItems(oldWidget.items, widget.items) &&
      oldWidget.selected == widget.selected &&
      (oldWidget.onChanged == null) == (widget.onChanged == null) &&
      (oldWidget.onReselected == null) == (widget.onReselected == null) &&
      oldWidget.appearance == widget.appearance &&
      _chromed(oldWidget) == _chromed(widget);

  static bool _chromed(MorphTabBar bar) =>
      bar.bottomAccessory != null || bar.minimizeBehavior.minimizes;

  // The minimizing group and the accessory wrap the bar's cached build,
  // so a new accessory from the parent rebuilds the group, not the bar.
  @override
  Widget build(BuildContext context) {
    final bar = super.build(context);
    if (!_chromed(widget) || widget.items.isEmpty) return bar;
    return MorphTabBarChrome(
      bar: bar,
      barWidth: _layout.width,
      items: widget.items,
      selected: motion.selected,
      appearance: _style,
      glass: _glass,
      brightness: _brightness,
      rtl: _rtl,
      behavior: widget.minimizeBehavior,
      accessory: widget.bottomAccessory,
      contentScroll: widget.contentScroll,
      barPress: this,
      onSelect: _select,
    );
  }

  static bool _sameItems(List<MorphTabItem> a, List<MorphTabItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (identical(x, y)) continue;
      if (x.icon != y.icon ||
          x.label != y.label ||
          x.enabled != y.enabled ||
          x.selectedIcon != y.selectedIcon ||
          x.badge != y.badge ||
          x.role != y.role) {
        return false;
      }
    }
    return true;
  }

  @override
  Object? get buildInputs => _motion?.selected;

  @override
  Widget buildControl(BuildContext context) {
    _style = MorphTabBarAppearance.resolve(context, widget.appearance);
    _brightness = morphBrightnessOf(context);
    _rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: MorphTabBar.maxTextScale);
    _sync(
      MorphTabBarMetrics.geometry(widget.items.length, _widestLabel(scaler)),
    );
    if (widget.items.isEmpty) return const SizedBox(height: _barHeight);
    motion.reducedMotion = morphReducedMotionOf(context);
    final style = _style;
    final geometry = _layout;
    final glass = _glass = MorphGlassScope.maybeOf(context);
    final Widget tabs = Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            child: ClipPath(
              clipper: _LensClipper(this, inside: false),
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                role: SemanticsRole.tabBar,
                child: _tabRow([
                  for (var i = 0; i < widget.items.length; i++)
                    SizedBox(
                      width: geometry.pitch,
                      child: Semantics(
                        container: true,
                        role: SemanticsRole.tab,
                        selected: i == motion.selected,
                        enabled: _selectable(i),
                        label: widget.items[i].label,
                        onTap: _selectable(i) ? () => _select(i) : null,
                        child: ExcludeSemantics(
                          child: MorphGlyphs(
                            aligned: true,
                            child: _TabLabel(
                              item: widget.items[i],
                              scaler: scaler,
                              selected: false,
                              color: style.color,
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: ExcludeSemantics(
            child: ClipPath(
              clipper: _LensClipper(this, inside: true),
              child: _row(scaler, selected: true),
            ),
          ),
        ),
      ],
    );
    return RepaintBoundary(
      child: MorphPress(
        target: this,
        enabled: _enabled,
        touchEnabled: widget.items.isNotEmpty,
        onHighlight: highlightControlFocus,
        onStep: _step,
        onActivate: widget.onReselected == null
            ? null
            : () => _select(motion.selected),
        dragAxis: .horizontal,
        delaysInScrollable: true,
        child: MorphLiveTransform(
          live: frames,
          writeInto: (Matrix4 into) {
            final grow =
                (geometry.width + motion.chromeGrowth) / geometry.width;
            into.scaleByDouble(grow, grow, 1.0, 1.0);
          },
          child: MorphFocusRing(
            visible: controlFocused,
            child: SizedBox(
              width: geometry.width,
              height: _barHeight,
              child: Stack(
                children: [
                  if (glass == null) ...[
                    Positioned.fill(child: _Glass(style: style)),
                    Positioned.fill(
                      child: CustomPaint(painter: _LensPainter(this)),
                    ),
                    Positioned.fill(
                      left: MorphTabBarMetrics.sideInset,
                      right: MorphTabBarMetrics.sideInset,
                      child: tabs,
                    ),
                  ] else ...[
                    Positioned.fill(
                      child: MorphGlassLayer(
                        painter: glass,
                        frames: frames,
                        surfaces: _surfaces,
                        content: Padding(
                          padding: const .symmetric(
                            horizontal: MorphTabBarMetrics.sideInset,
                          ),
                          child: tabs,
                        ),
                        contentSlots: [
                          for (var i = 0; i < widget.items.length; i++)
                            Rect.fromCenter(
                              center: Offset(
                                MorphTabBarMetrics.sideInset +
                                    geometry.pitch * (i + 0.5),
                                _barHeight / 2,
                              ),
                              width: geometry.pitch,
                              height: _barHeight,
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (widget.items.any((item) => item.badge?.visible ?? false))
                    Positioned.fill(
                      left: MorphTabBarMetrics.sideInset,
                      right: MorphTabBarMetrics.sideInset,
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: Row(
                            children: [
                              for (final item in widget.items)
                                SizedBox(
                                  width: geometry.pitch,
                                  child: _TabBadge(item: item, scaler: scaler),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of tabs that repaints on [changes] and is a repaint boundary of
/// its own while [apart] reads true.
class _TabRow extends Flex {
  const _TabRow({
    required this.changes,
    required this.apart,
    required super.children,
  }) : super(direction: Axis.horizontal);

  final Listenable changes;
  final bool Function() apart;

  @override
  RenderFlex createRenderObject(BuildContext context) {
    final row = _RenderTabRow(apart: apart());
    super.updateRenderObject(context, row);
    row.bindLive(changes, () => row.follow(apart: apart()), now: false);
    return row;
  }

  @override
  void updateRenderObject(BuildContext context, RenderFlex renderObject) {
    super.updateRenderObject(context, renderObject);
    final row = renderObject as _RenderTabRow;
    row.bindLive(changes, () => row.follow(apart: apart()), now: false);
    row.follow(apart: apart(), repaint: false);
  }
}

class _RenderTabRow extends RenderFlex with MorphLiveBinding {
  _RenderTabRow({required this._apart});

  bool _apart;

  @override
  bool get isRepaintBoundary => _apart;

  void follow({required bool apart, bool repaint = true}) {
    if (apart != _apart) {
      _apart = apart;
      markNeedsCompositingBitsUpdate();
    } else if (!repaint) {
      return;
    }
    markNeedsPaint();
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.style});

  final MorphTabBarAppearance style;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(_MorphTabBarState._radius));
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: style.shadowColor,
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: style.blurSigma,
            sigmaY: style.blurSigma,
          ),
          child: ColoredBox(color: style.barColor),
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.item,
    required this.scaler,
    required this.selected,
    required this.color,
  });

  final MorphTabItem item;
  final TextScaler scaler;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = MorphTypography.resolve(
      selected ? MorphTypography.tabLabelSelected : MorphTypography.tabLabel,
    ).copyWith(color: color);
    if (!selected) {
      final Widget glyph = Icon(
        item.icon,
        size: MorphTabBarMetrics.iconSize,
        color: color,
      );
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          glyph,
          const SizedBox(height: MorphTabBarMetrics.labelGap),
          Text(item.label, maxLines: 1, textScaler: scaler, style: style),
        ],
      );
    }
    final icon = item.selectedIcon ?? item.icon;
    final Widget glyph = SizedBox.square(
      dimension: MorphTabBarMetrics.iconSize,
      child: Center(
        child: RichText(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              inherit: false,
              color: color,
              fontSize: MorphTabBarMetrics.iconSize,
              fontFamily: icon.fontFamily,
              fontFamilyFallback: icon.fontFamilyFallback,
              package: icon.fontPackage,
              height: 1,
              leadingDistribution: TextLeadingDistribution.even,
            ),
          ),
        ),
      ),
    );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        glyph,
        const SizedBox(height: MorphTabBarMetrics.labelGap),
        RichText(
          maxLines: 1,
          textScaler: scaler,
          text: TextSpan(
            text: item.label,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
        ),
      ],
    );
  }
}

// Native badges ride the bar's swell but stay above the refracting lens.
class _TabBadge extends StatelessWidget {
  const _TabBadge({required this.item, required this.scaler});

  final MorphTabItem item;
  final TextScaler scaler;

  @override
  Widget build(BuildContext context) {
    if (!(item.badge?.visible ?? false)) return const SizedBox.shrink();
    final style = MorphTypography.resolve(MorphTypography.tabLabel);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        MorphBadged.glyph(
          badge: item.badge,
          glyphSize: const Size.square(MorphTabBarMetrics.iconSize),
          child: const SizedBox.square(dimension: MorphTabBarMetrics.iconSize),
        ),
        const SizedBox(height: MorphTabBarMetrics.labelGap),
        Opacity(
          opacity: 0,
          child: RichText(
            maxLines: 1,
            textScaler: scaler,
            text: TextSpan(
              text: item.label,
              style: DefaultTextStyle.of(context).style.merge(style),
            ),
          ),
        ),
      ],
    );
  }
}

class _LensPainter extends CustomPainter {
  _LensPainter(this.state) : super(repaint: state.frames);

  final _MorphTabBarState state;

  @override
  void paint(Canvas canvas, Size size) {
    final style = state._style;
    final lift = state.motion.lift.clamp(0.0, 1.0);
    final lens = state._lensShape(size);
    final platter = Paint();
    platter.color = style.platterColor.withValues(
      alpha: style.platterColor.a * (1 - lift),
    );
    canvas.drawRRect(lens, platter);
    if (lift <= 0.01) return;
    final glass = Paint();
    glass.color = style.liftedLensColor.withValues(
      alpha: style.liftedLensColor.a * lift,
    );
    canvas.drawRRect(lens, glass);
    final border = Paint();
    border.style = PaintingStyle.stroke;
    border.strokeWidth = 0.75;
    border.color = style.lensBorderColor.withValues(
      alpha: style.lensBorderColor.a * lift,
    );
    canvas.drawRRect(lens.deflate(0.4), border);
  }

  @override
  bool shouldRepaint(_LensPainter oldDelegate) => true;
}

class _LensClipper extends MorphLiveClipper<Path> {
  _LensClipper(_MorphTabBarState state, {required bool inside})
    : super(
        live: state.frames,
        keyOf: () => state._lensShape(
          Size(state._layout.width, _MorphTabBarState._barHeight),
        ),
        clipOf: (Size size) => _clip(state, size, inside: inside),
      );

  static Path _clip(
    _MorphTabBarState state,
    Size size, {
    required bool inside,
  }) {
    final bar = Size(
      size.width + 2 * MorphTabBarMetrics.sideInset,
      _MorphTabBarState._barHeight,
    );
    final lens = Path();
    lens.addRRect(
      state
          ._lensShape(bar)
          .shift(const Offset(-MorphTabBarMetrics.sideInset, 0)),
    );
    if (inside) return lens;
    lens.fillType = PathFillType.evenOdd;
    lens.addRect(Offset.zero & size);
    return lens;
  }
}
