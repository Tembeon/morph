import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/control_host.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/flex_spec.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_glow.dart';
import 'package:morph/src/widgets/glyph_scale.dart';
import 'package:morph/src/widgets/lens_driver.dart';
import 'package:morph/src/widgets/lens_motion.dart';
import 'package:morph/src/widgets/widgets_theme.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/src/widgets/typography.dart';

/// One item of a [MorphTabBar].
class MorphTabItem {
  /// Creates a tab item.
  const MorphTabItem({
    required this.icon,
    required this.label,
    this.enabled = true,
  });

  /// The item's glyph.
  final IconData icon;

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
/// finger. While pressed, the whole bar swells by
/// [MorphLensTuning.chromeGrowth] pixels around its center, lens
/// included, and brightens: a wash over the whole bar and a soft spot
/// under the finger ([MorphTouchGlowMotion]) that spreads and fades when
/// the finger lifts.
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
class MorphTabBar extends StatefulWidget {
  /// Creates a tab bar.
  const MorphTabBar({
    required this.items,
    required this.selected,
    required this.onChanged,
    this.style,
    super.key,
  });

  /// The tabs, two to five.
  final List<MorphTabItem> items;

  /// The index of the selected tab, clamped to the available items.
  final int selected;

  /// Called with the new index when the user selects a tab; null disables
  /// every tab ([MorphTabItem.enabled]): the bar keeps its look and still
  /// swells under a finger, but nothing selects.
  final ValueChanged<int>? onChanged;

  /// The colors of the bar; null resolves them from the theme.
  final MorphTabBarStyle? style;

  /// The largest text scale the labels follow.
  static const double maxTextScale = 1.25;

  @override
  State<MorphTabBar> createState() => _MorphTabBarState();
}

/// The look of a [MorphTabBar].
@immutable
class MorphTabBarStyle {
  /// Creates a style; the defaults are the iOS 27 light appearance.
  ///
  /// The platter and the tab colors are what UIKit's color matrices make
  /// of the measured bar: the platter darkens the bar under the selection
  /// and the tab glyphs are vibrant, so their exact color follows the
  /// backdrop; these are their values over a bar on a plain page.
  const MorphTabBarStyle({
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
  static const light = MorphTabBarStyle();

  /// The dark appearance, from the iOS dark system colors.
  static const dark = MorphTabBarStyle(
    barColor: Color(0xB81C1C1E),
    shadowColor: Color(0x66000000),
    platterColor: Color(0xAF000000),
    liftedLensColor: Color(0x1FFFFFFF),
    lensBorderColor: Color(0x40FFFFFF),
    selectedColor: Color(0xFF0397FF),
    color: Color(0xFFFAFAFA),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphTabBarStyle resolve(
    BuildContext context,
    MorphTabBarStyle? explicit,
  ) => morphResolveStyle(
    context,
    explicit,
    themed: (theme) => theme.tabBar,
    light: light,
    dark: dark,
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
  MorphTabBarStyle _style = MorphTabBarStyle.light;
  Brightness _brightness = Brightness.light;
  bool _rtl = false;

  @override
  MorphLensMotion get motion => _motion!;

  static MorphTouchGlowMotion _createGlow() {
    final spec = MorphFlexSpec.forSize(const Size(274, _barHeight));
    return MorphTouchGlowMotion(
      washPeak: spec.bigGlowOpacity,
      spotPeak: spec.littleGlowOpacity,
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
    created.onSelect = _selected;
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
    motion.select(clock, index);
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

  double _widestLabel(TextScaler scaler) {
    var widest = 0.0;
    for (final item in widget.items) {
      widest = math.max(
        widest,
        morphLensLabelWidth(
          item.label,
          MorphTypography.tabLabelSelected,
          scaler,
        ),
      );
    }
    return widest;
  }

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

  @override
  void onControlDown(double t, PointerDownEvent event) {
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
    super.onControlUp(t, event);
    _glow.pointerUp(clock);
  }

  @override
  void onControlCancel(double t) {
    super.onControlCancel(t);
    _glow.pointerUp(clock);
  }

  Widget _row(TextScaler scaler, {required bool selected}) => Row(
    children: [
      for (final item in widget.items)
        SizedBox(
          width: _layout.pitch,
          child: MorphGlyphSnap(
            child: _TabLabel(
              item: item,
              scaler: scaler,
              selected: selected,
              color: selected ? _style.selectedColor : _style.color,
            ),
          ),
        ),
    ],
  );

  @override
  Widget buildControl(BuildContext context) {
    _style = MorphTabBarStyle.resolve(context, widget.style);
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
    final glass = MorphGlass.maybeOf(context);
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
                child: Row(
                  children: [
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
                            child: MorphGlyphSnap(
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
                  ],
                ),
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
      child: MorphControlFocus(
        enabled: _enabled,
        onHighlight: highlightControlFocus,
        onStep: _step,
        child: MorphTouchListener(
          enabled: widget.items.isNotEmpty,
          dragAxis: .horizontal,
          delaysInScrollable: true,
          onPointerDown: handleDown,
          onPointerMove: handleMove,
          onPointerUp: handleUp,
          onPointerCancel: handleCancel,
          child: AnimatedBuilder(
            animation: frames,
            builder: (BuildContext context, Widget? child) {
              final grow =
                  (geometry.width + motion.chromeGrowth) / geometry.width;
              return Transform.scale(scale: grow, child: child);
            },
            child: MorphFocusRing(
              visible: controlFocused,
              child: SizedBox(
                width: geometry.width,
                height: _barHeight,
                child: Stack(
                  children: glass == null
                      ? [
                          Positioned.fill(child: _Glass(style: style)),
                          Positioned.fill(
                            child: CustomPaint(painter: _GlowPainter(this)),
                          ),
                          Positioned.fill(
                            child: CustomPaint(painter: _LensPainter(this)),
                          ),
                          Positioned.fill(
                            left: MorphTabBarMetrics.sideInset,
                            right: MorphTabBarMetrics.sideInset,
                            child: tabs,
                          ),
                        ]
                      : [
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.style});

  final MorphTabBarStyle style;

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
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, size: MorphTabBarMetrics.iconSize, color: color),
          const SizedBox(height: MorphTabBarMetrics.labelGap),
          Text(item.label, maxLines: 1, textScaler: scaler, style: style),
        ],
      );
    }
    final icon = item.icon;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox.square(
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
        ),
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

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.state) : super(repaint: state.frames);

  final _MorphTabBarState state;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = state._glowNow();
    if (glow == null) return;
    morphPaintGlassGlow(
      canvas,
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(_MorphTabBarState._radius),
      ),
      glow,
    );
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) => true;
}

class _LensClipper extends CustomClipper<Path> {
  _LensClipper(this.state, {required this.inside})
    : super(reclip: state.frames);

  final _MorphTabBarState state;
  final bool inside;

  @override
  Path getClip(Size size) {
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

  @override
  bool shouldReclip(_LensClipper oldDelegate) =>
      oldDelegate.state != state || oldDelegate.inside != inside;
}
