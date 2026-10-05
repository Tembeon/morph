import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/control_host.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/lens_driver.dart';
import 'package:morph/src/widgets/lens_motion.dart';
import 'package:morph/src/widgets/widgets_theme.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/src/widgets/typography.dart';

/// A segmented control whose selection lens moves exactly like
/// UISegmentedControl's on iOS 27.
///
/// The selection changes when the finger lifts; pressing the selected
/// segment lifts the lens and lets the finger drag it, with a rubber band
/// past the ends. The lens's travel, lift and deformation come from
/// [MorphLensTuning.segmented].
///
/// The control is focusable and the arrow keys move the selection; screen
/// readers see one selectable button per segment. In a right-to-left
/// context the first segment is on the right. Labels follow the text
/// scale up to [maxTextScale]. With the platform's reduced motion on,
/// the lens travels without lifting or deforming.
class MorphSegmentedControl extends StatefulWidget {
  /// Creates a segmented control.
  const MorphSegmentedControl({
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.sizeByContent = false,
    this.style,
    super.key,
  });

  /// The labels of the segments; an empty list draws an inert empty control.
  final List<String> segments;

  /// The index of the selected segment, clamped to the available segments.
  final int selected;

  /// Called with the new index when the user selects a segment; null
  /// disables the control.
  final ValueChanged<int>? onChanged;

  /// Whether segments are as wide as their labels instead of equal.
  final bool sizeByContent;

  /// The colors and metrics of the control; null resolves them from the
  /// theme.
  final MorphSegmentedStyle? style;

  /// The largest text scale the labels follow.
  static const double maxTextScale = 1.4;

  @override
  State<MorphSegmentedControl> createState() => _MorphSegmentedControlState();
}

/// The look of a [MorphSegmentedControl].
@immutable
class MorphSegmentedStyle {
  /// Creates a style; the defaults are the iOS 27 light appearance.
  const MorphSegmentedStyle({
    this.height = 32,
    this.inset = 2,
    this.trackColor = const Color(0x1F767680),
    this.lensColor = const Color(0xFFFFFFFF),
    this.liftedLensColor = const Color(0x40FFFFFF),
    this.lensBorderColor = const Color(0x33000000),
    this.shadowColor = const Color(0x1F000000),
    this.textStyle = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: Color(0xFF000000),
    ),
    this.selectedTextStyle = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Color(0xFF000000),
    ),
    this.contentPadding = 16,
    this.disabledOpacity = 0.5,
  });

  /// The height of the control.
  final double height;

  /// The gap between the track and the resting lens.
  final double inset;

  /// The fill of the track: tertiarySystemFill.
  final Color trackColor;

  /// The fill of the resting lens.
  final Color lensColor;

  /// The fill of the fully lifted lens.
  final Color liftedLensColor;

  /// The outline the lens gains while lifted.
  final Color lensBorderColor;

  /// The shadow under the lens.
  final Color shadowColor;

  /// The label style of unselected segments, painted through
  /// [MorphTypography.resolve]; UIKit's is [MorphTypography.segment].
  final TextStyle textStyle;

  /// The label style of the selected segment, painted through
  /// [MorphTypography.resolve]; UIKit's is
  /// [MorphTypography.segmentSelected].
  final TextStyle selectedTextStyle;

  /// The horizontal padding around a label when sizing by content.
  final double contentPadding;

  /// The opacity of a disabled control, applied to the whole control as
  /// one layer: UIKit sets the segmented control's alpha to 0.5 (iPhone 16
  /// Pro, light and dark).
  final double disabledOpacity;

  /// The light appearance.
  static const light = MorphSegmentedStyle();

  /// The dark appearance, from the iOS dark system colors.
  static const dark = MorphSegmentedStyle(
    trackColor: Color(0x3D767680),
    lensColor: Color(0xFF636366),
    liftedLensColor: Color(0x33FFFFFF),
    lensBorderColor: Color(0x40FFFFFF),
    shadowColor: Color(0x33000000),
    textStyle: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: Color(0xFFFFFFFF),
    ),
    selectedTextStyle: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Color(0xFFFFFFFF),
    ),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphSegmentedStyle resolve(
    BuildContext context,
    MorphSegmentedStyle? explicit,
  ) => morphResolveStyle(
    context,
    explicit,
    themed: (theme) => theme.segmented,
    light: light,
    dark: dark,
  );
}

class _MorphSegmentedControlState
    extends MorphControlHost<MorphSegmentedControl>
    with MorphLensDriver<MorphSegmentedControl> {
  MorphLensMotion? _motion;
  List<MorphLensSlot> _slots = const [];
  MorphSegmentedStyle _style = MorphSegmentedStyle.light;
  Brightness _brightness = Brightness.light;
  TextScaler _scaler = TextScaler.noScaling;
  bool _rtl = false;
  double _width = 0;

  @override
  MorphLensMotion get motion => _motion!;

  @override
  double trackPosition(Offset local) => _rtl ? _width - local.dx : local.dx;

  bool get _enabled => widget.onChanged != null;

  List<MorphLensSlot> _layout(double width) {
    final style = _style;
    final count = widget.segments.length;
    final List<double> widths;
    if (widget.sizeByContent) {
      final natural = [
        for (final label in widget.segments)
          math.max(
                _measure(label, style.textStyle),
                _measure(label, style.selectedTextStyle),
              ) +
              2 * style.contentPadding,
      ];
      final total = natural.fold<double>(0, (a, b) => a + b);
      widths = [for (final w in natural) w * width / total];
    } else {
      widths = List.filled(count, width / count);
    }
    final slots = <MorphLensSlot>[];
    var left = 0.0;
    for (final w in widths) {
      slots.add((center: left + w / 2, width: w - 2 * style.inset));
      left += w;
    }
    return slots;
  }

  double _measure(String text, TextStyle style) =>
      morphLensLabelWidth(text, style, _scaler);

  double _naturalWidth() => widget.segments.fold<double>(
    0,
    (total, label) =>
        total +
        math.max(
          _measure(label, _style.textStyle),
          _measure(label, _style.selectedTextStyle),
        ) +
        2 * _style.contentPadding,
  );

  void _sync(double width) {
    _width = width;
    final slots = _layout(width);
    final current = _motion;
    if (current == null) {
      final created = MorphLensMotion(
        tuning: MorphLensTuning.segmented,
        slots: slots,
        selected: widget.selected,
        height: _style.height - 2 * _style.inset,
        frameRate: motionFrameRate,
      );
      created.onSelect = _selected;
      _motion = created;
    } else if (!_sameSlots(slots, _slots)) {
      current.slots = slots;
    }
    _slots = slots;
    final selected = slots.isEmpty
        ? -1
        : widget.selected.clamp(0, slots.length - 1);
    if (motion.selected != selected) {
      motion.select(clock, selected, notify: false);
      wake();
    }
  }

  void _selected(int index) {
    if (index != widget.selected) widget.onChanged?.call(index);
    reconcileSelection(
      () => widget.segments.isEmpty
          ? -1
          : widget.selected.clamp(0, widget.segments.length - 1),
    );
  }

  void _select(int index) {
    if (!_enabled || _motion == null) return;
    motion.select(clock, index);
    wake();
  }

  void _step(int delta) {
    final current = _motion;
    if (current == null || _slots.isEmpty) return;
    final next = (current.selected + (_rtl ? -delta : delta)).clamp(
      0,
      _slots.length - 1,
    );
    if (next != current.selected) _select(next);
  }

  static bool _sameSlots(List<MorphLensSlot> a, List<MorphLensSlot> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  ({RRect track, RRect lens, double lift}) _frame(Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final lens = morphLensShape(motion, size, rtl: _rtl);
    return (track: track, lens: lens, lift: motion.lift.clamp(0.0, 1.0));
  }

  List<Rect> _contentSlots(double width) => [
    for (final slot in _slots)
      Rect.fromCenter(
        center: Offset(
          _rtl ? width - slot.center : slot.center,
          _style.height / 2,
        ),
        width: slot.width + 2 * _style.inset,
        height: _style.height,
      ),
  ];

  List<MorphGlassSurface> _surfaces() {
    final frame = _frame(Size(_width, _style.height));
    final style = _style;
    return [
      MorphGlassSurface(
        kind: MorphGlassKind.track,
        shape: frame.track,
        color: style.trackColor,
        brightness: _brightness,
        enabled: _enabled,
        glass: false,
      ),
      MorphGlassSurface(
        kind: MorphGlassKind.lens,
        shape: frame.lens,
        color: Color.lerp(style.lensColor, style.liftedLensColor, frame.lift)!,
        brightness: _brightness,
        lift: frame.lift,
        scaleX: motion.scaleX,
        scaleY: motion.scaleY,
        optics: MorphGlassOptics.large,
        enabled: _enabled,
      ),
    ];
  }

  @override
  bool get controlEnabled => _enabled;

  @override
  bool buildsLike(MorphSegmentedControl oldWidget) =>
      listEquals(oldWidget.segments, widget.segments) &&
      oldWidget.selected == widget.selected &&
      (oldWidget.onChanged == null) == (widget.onChanged == null) &&
      oldWidget.sizeByContent == widget.sizeByContent &&
      oldWidget.style == widget.style;

  @override
  Object? get buildInputs => _motion?.selected;

  @override
  Widget buildControl(BuildContext context) {
    _style = MorphSegmentedStyle.resolve(context, widget.style);
    _brightness = morphBrightnessOf(context);
    _rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    _scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: MorphSegmentedControl.maxTextScale);
    final glass = MorphGlass.maybeOf(context);
    final style = _style;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : _naturalWidth();
        _sync(width);
        if (widget.segments.isEmpty) {
          return SizedBox(width: width, height: style.height);
        }
        motion.reducedMotion = morphReducedMotionOf(context);
        final selected = motion.selected;
        final labels = Row(
          children: [
            for (var i = 0; i < widget.segments.length; i++)
              SizedBox(
                width: _slots[i].width + 2 * style.inset,
                child: Semantics(
                  container: true,
                  button: true,
                  inMutuallyExclusiveGroup: true,
                  selected: i == selected,
                  enabled: _enabled,
                  label: widget.segments[i],
                  onTap: _enabled ? () => _select(i) : null,
                  child: ExcludeSemantics(
                    child: Center(
                      child: Text(
                        widget.segments[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: _scaler,
                        style: MorphTypography.resolve(
                          i == selected
                              ? style.selectedTextStyle
                              : style.textStyle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
        return MorphDisabled(
          enabled: _enabled,
          opacity: style.disabledOpacity,
          child: MorphControlFocus(
            enabled: _enabled,
            onHighlight: highlightControlFocus,
            onStep: _step,
            child: MorphFocusRing(
              visible: controlFocused,
              child: MorphTouchListener(
                enabled: _enabled,
                dragAxis: .horizontal,
                onPointerDown: handleDown,
                onPointerMove: handleMove,
                onPointerUp: handleUp,
                onPointerCancel: handleCancel,
                child: SizedBox(
                  height: style.height,
                  width: width,
                  child: glass == null
                      ? CustomPaint(
                          painter: _SegmentedPainter(this),
                          child: labels,
                        )
                      : MorphGlassLayer(
                          painter: glass,
                          frames: frames,
                          surfaces: _surfaces,
                          content: labels,
                          contentSlots: _contentSlots(width),
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SegmentedPainter extends CustomPainter {
  _SegmentedPainter(this.state) : super(repaint: state.frames);

  final _MorphSegmentedControlState state;

  @override
  void paint(Canvas canvas, Size size) {
    final style = state._style;
    final frame = state._frame(size);
    final trackPaint = Paint();
    trackPaint.color = style.trackColor;
    canvas.drawRRect(frame.track, trackPaint);
    final lift = frame.lift;
    final lens = frame.lens;
    final shadow = Paint();
    shadow.color = style.shadowColor;
    shadow.maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 5 * lift);
    canvas.drawRRect(lens.shift(const Offset(0, 1.5)), shadow);
    final fill = Paint();
    fill.color = Color.lerp(style.lensColor, style.liftedLensColor, lift)!;
    canvas.drawRRect(lens, fill);
    if (lift > 0.01) {
      final border = Paint();
      border.style = PaintingStyle.stroke;
      border.strokeWidth = 0.5;
      border.color = style.lensBorderColor.withValues(
        alpha: style.lensBorderColor.a * lift,
      );
      canvas.drawRRect(lens.deflate(0.25), border);
    }
  }

  @override
  bool shouldRepaint(_SegmentedPainter oldDelegate) => true;
}
