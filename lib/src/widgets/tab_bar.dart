import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/lens_driver.dart';
import 'package:morph/src/widgets/lens_motion.dart';
import 'package:morph/src/widgets/widgets_theme.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/src/widgets/typography.dart';

/// One item of a [MorphTabBar].
class MorphTabItem {
  /// Creates a tab item.
  const MorphTabItem({required this.icon, required this.label});

  /// The item's glyph.
  final IconData icon;

  /// The item's title.
  final String label;
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
/// included.
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

  /// The index of the selected tab.
  final int selected;

  /// Called with the new index when the user selects a tab; null disables
  /// the bar.
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
  const MorphTabBarStyle({
    this.barColor = const Color(0xB8FFFFFF),
    this.shadowColor = const Color(0x24000000),
    this.platterColor = const Color(0x14000000),
    this.liftedLensColor = const Color(0x33FFFFFF),
    this.lensBorderColor = const Color(0x40000000),
    this.selectedColor = const Color(0xFF007AFF),
    this.color = const Color(0xFF1C1C1E),
    this.blurSigma = 12,
    this.disabledOpacity = 0.35,
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

  /// The tint of the selected tab.
  final Color selectedColor;

  /// The tint of the other tabs.
  final Color color;

  /// The blur of the backdrop behind the bar.
  final double blurSigma;

  /// The opacity of a disabled bar.
  final double disabledOpacity;

  /// The light appearance.
  static const light = MorphTabBarStyle();

  /// The dark appearance, from the iOS dark system colors.
  static const dark = MorphTabBarStyle(
    barColor: Color(0xB81C1C1E),
    shadowColor: Color(0x66000000),
    platterColor: Color(0xB5000000),
    liftedLensColor: Color(0x1FFFFFFF),
    lensBorderColor: Color(0x40FFFFFF),
    selectedColor: Color(0xFF0A84FF),
    color: Color(0xFFF2F2F7),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphTabBarStyle resolve(
    BuildContext context,
    MorphTabBarStyle? explicit,
  ) =>
      explicit ??
      MorphWidgetsTheme.maybeOf(context)?.tabBar ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };
}

typedef _Geometry = ({double pitch, double lens, double width});

/// The horizontal room a label keeps inside its tab.
const double _labelPadding = 12;

/// The bar's measured geometry for a tab count, widened so the widest
/// label of [labelWidth] pixels fits its tab.
_Geometry _geometry(int count, double labelWidth) {
  final measured = count <= 4 ? 86.0 : 68.0;
  final pitch = math.max(measured, labelWidth + 2 * _labelPadding);
  final lens = switch (count) {
    <= 3 => 94.0,
    4 => 98.0,
    _ => 77.0,
  };
  return (
    pitch: pitch,
    lens: lens + pitch - measured,
    width: pitch * count + 16,
  );
}

class _MorphTabBarState extends State<MorphTabBar>
    with
        SingleTickerProviderStateMixin<MorphTabBar>,
        MorphClock<MorphTabBar>,
        MorphLensDriver<MorphTabBar> {
  static const double _barHeight = 62;
  static const double _lensHeight = 54;
  static const double _radius = 31;

  _Geometry _layout = _geometry(0, 0);
  MorphLensMotion? _motion;
  MorphTabBarStyle _style = MorphTabBarStyle.light;
  Brightness _brightness = Brightness.light;
  bool _rtl = false;
  bool _focused = false;

  @override
  MorphLensMotion get motion => _motion!;

  @override
  double trackPosition(Offset local) =>
      _rtl ? _layout.width - local.dx : local.dx;

  bool get _enabled => widget.onChanged != null;

  List<MorphLensSlot> _slots(_Geometry geometry) => [
    for (var i = 0; i < widget.items.length; i++)
      (center: 8 + geometry.pitch * (i + 0.5), width: geometry.lens),
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
  }

  void _selected(int index) {
    setState(() {});
    if (index != widget.selected) widget.onChanged?.call(index);
  }

  void _select(int index) {
    if (!_enabled) return;
    motion.select(clock, index);
    wake();
  }

  void _step(int delta) {
    final next = (motion.selected + (_rtl ? -delta : delta)).clamp(
      0,
      widget.items.length - 1,
    );
    if (next != motion.selected) _select(next);
  }

  @override
  void didUpdateWidget(MorphTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = _motion;
    if (current != null &&
        oldWidget.items.length == widget.items.length &&
        widget.selected != current.selected) {
      current.select(clock, widget.selected);
      wake();
    }
  }

  double _widestLabel(TextScaler scaler) {
    var widest = 0.0;
    for (final item in widget.items) {
      final painter = TextPainter(
        text: TextSpan(
          text: item.label,
          style: MorphTypography.resolve(MorphTypography.tabLabelSelected),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      );
      painter.layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  }

  RRect _lensShape(Size size) {
    final motion = this.motion;
    final lensSize = motion.size;
    final width = lensSize.width * motion.scaleX;
    final height = lensSize.height * motion.scaleY;
    final center = _rtl ? size.width - motion.center : motion.center;
    return RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center, size.height / 2),
        width: width,
        height: height,
      ),
      Radius.circular(math.min(width, height) / 2),
    );
  }

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

  void _down(PointerDownEvent event) {
    if (_enabled) handleDown(event);
  }

  @override
  Widget build(BuildContext context) {
    _style = MorphTabBarStyle.resolve(context, widget.style);
    _brightness = morphBrightnessOf(context);
    _rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: MorphTabBar.maxTextScale);
    _sync(_geometry(widget.items.length, _widestLabel(scaler)));
    motion.reducedMotion = morphReducedMotionOf(context);
    final style = _style;
    final geometry = _layout;
    final glass = MorphGlass.maybeOf(context);
    final Widget tabs = Semantics(
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
                enabled: _enabled,
                label: widget.items[i].label,
                onTap: _enabled ? () => _select(i) : null,
                child: ExcludeSemantics(
                  child: _TabLabel(
                    item: widget.items[i],
                    scaler: scaler,
                    selected: i == motion.selected,
                    color: i == motion.selected
                        ? style.selectedColor
                        : style.color,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return MorphDisabled(
      enabled: _enabled,
      opacity: style.disabledOpacity,
      child: MorphControlFocus(
        enabled: _enabled,
        onHighlight: (bool focused) => setState(() => _focused = focused),
        onStep: _step,
        child: MorphTouchListener(
          enabled: _enabled,
          dragAxis: .horizontal,
          onPointerDown: _down,
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
              visible: _focused,
              child: SizedBox(
                width: geometry.width,
                height: _barHeight,
                child: Stack(
                  children: glass == null
                      ? [
                          Positioned.fill(child: _Glass(style: style)),
                          Positioned.fill(
                            child: CustomPaint(painter: _LensPainter(this)),
                          ),
                          Positioned.fill(left: 8, right: 8, child: tabs),
                        ]
                      : [
                          Positioned.fill(
                            child: MorphGlassLayer(
                              painter: glass,
                              frames: frames,
                              surfaces: _surfaces,
                              content: Padding(
                                padding: const .symmetric(horizontal: 8),
                                child: tabs,
                              ),
                              contentSlots: [
                                for (var i = 0; i < widget.items.length; i++)
                                  Rect.fromCenter(
                                    center: Offset(
                                      8 + geometry.pitch * (i + 0.5),
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(item.icon, size: 24, color: color),
        const SizedBox(height: 2),
        Text(
          item.label,
          maxLines: 1,
          textScaler: scaler,
          style: MorphTypography.resolve(
            selected
                ? MorphTypography.tabLabelSelected
                : MorphTypography.tabLabel,
          ).copyWith(color: color),
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
