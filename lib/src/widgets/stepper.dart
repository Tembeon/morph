import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/control_host.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/timeline.dart';
import 'package:morph/src/widgets/widgets_theme.dart';
import 'package:morph/src/widgets/touch_listener.dart';

/// The look of a [MorphStepper].
///
/// The colors are UIKit's on iOS 27, read from the SwiftUI stepper's
/// layers on an iPhone 16 Pro (iOS 27.0.1): each half is a masked fill, the
/// divider a 1 x 24 point tertiaryLabel line, a half at its limit draws its
/// glyph in tertiaryLabel.
@immutable
class MorphStepperStyle {
  /// Creates a style; the defaults are the iOS light appearance.
  const MorphStepperStyle({
    this.backgroundColor = const Color(0x163C3C43),
    this.foregroundColor = const Color(0xFF000000),
    this.limitForegroundColor = const Color(0x4C3C3C43),
    this.pressedOverlay = const Color(0x14000000),
    this.pressedReplacesFill = false,
    this.dividerColor = const Color(0x4C3C3C43),
    this.dividerHeight = 24,
  });

  /// The fill of each half.
  final Color backgroundColor;

  /// The color of the minus and plus glyphs.
  final Color foregroundColor;

  /// The color of the glyph of a half that cannot step further: the minus
  /// at the minimum, the plus at the maximum, whether the stepper is
  /// enabled or not.
  final Color limitForegroundColor;

  /// The overlay on the pressed half.
  final Color pressedOverlay;

  /// Whether the pressed half drops its fill under [pressedOverlay]: the
  /// dark stepper replaces the fill by the overlay, the light one draws
  /// the overlay over the fill.
  final bool pressedReplacesFill;

  /// The color of the divider between the halves: tertiaryLabel.
  final Color dividerColor;

  /// The height of the divider between the halves.
  final double dividerHeight;

  /// The light appearance.
  static const light = MorphStepperStyle();

  /// The dark appearance.
  static const dark = MorphStepperStyle(
    backgroundColor: Color(0x14EBEBF5),
    foregroundColor: Color(0xFFFFFFFF),
    limitForegroundColor: Color(0x4CEBEBF5),
    pressedReplacesFill: true,
    dividerColor: Color(0x4CEBEBF5),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphStepperStyle resolve(
    BuildContext context,
    MorphStepperStyle? explicit,
  ) => morphResolveStyle(
    context,
    explicit,
    themed: (theme) => theme.stepper,
    light: light,
    dark: dark,
  );
}

/// A stepper that responds to touch exactly like iOS 27's UIStepper.
///
/// The control has no motion: the pressed half darkens instantly under
/// an 8 percent black overlay and clears instantly on release. A disabled
/// stepper looks exactly like an enabled one and ignores input, as UIKit's
/// does; a half that cannot step further dims its glyph either way. A tap
/// commits on release; a held half repeats [repeatInterval] after the
/// touch and then every [repeatInterval] again, without acceleration.
/// Sliding to the other half moves the highlight and the repeat with it,
/// and leaving the control cancels the touch. The repeat runs on the
/// motion clock, so it follows the app's time dilation.
///
/// Screen readers see two buttons, [decrementLabel] and
/// [incrementLabel], each announcing the value. The stepper is focusable:
/// the left and down arrows decrement, the right and up arrows, Space and
/// Enter increment. It keeps minus on the left in a right-to-left
/// context too.
class MorphStepper extends StatefulWidget {
  /// Creates a stepper.
  const MorphStepper({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.backgroundColor,
    this.foregroundColor,
    this.style,
    this.decrementLabel = 'Decrement',
    this.incrementLabel = 'Increment',
    this.semanticValueFormatter,
    super.key,
  });

  /// The current value.
  final double value;

  /// Called with the new value when the user steps; null disables the
  /// stepper.
  final ValueChanged<double>? onChanged;

  /// The lowest value.
  final double min;

  /// The highest value.
  final double max;

  /// How much one step changes the value.
  final double step;

  /// The fill of the control, overriding [style].
  final Color? backgroundColor;

  /// The color of the minus and plus glyphs, overriding [style].
  final Color? foregroundColor;

  /// The look of the stepper; null resolves it from the theme.
  final MorphStepperStyle? style;

  /// The label screen readers announce for the minus half.
  final String decrementLabel;

  /// The label screen readers announce for the plus half.
  final String incrementLabel;

  /// Formats the value announced by each half. Null uses up to twelve
  /// significant digits, without binary floating-point tails.
  final String Function(double)? semanticValueFormatter;

  /// The size of the control.
  static const Size size = Size(94, 32);

  /// The delay before the first repeat and between repeats.
  static const Duration repeatInterval = Duration(milliseconds: 500);

  @override
  State<MorphStepper> createState() => _MorphStepperState();
}

enum _Half { minus, plus }

class _MorphStepperState extends MorphControlHost<MorphStepper> {
  static final double _interval =
      MorphStepper.repeatInterval.inMicroseconds / 1e6;

  _Half? _pressed;
  bool _repeated = false;
  final MorphTimeline _repeats = MorphTimeline();
  double get _minimum => widget.min.isFinite ? widget.min : 0;

  double get _maximum =>
      widget.max.isFinite && widget.max >= _minimum ? widget.max : _minimum;

  double get _value =>
      widget.value.isFinite ? widget.value.clamp(_minimum, _maximum) : _minimum;

  @override
  bool get controlEnabled => widget.onChanged != null;

  @override
  bool get stampPointerUpdates => false;

  @override
  void advanceMotion(double t) => _repeats.runDue(t);

  @override
  bool get motionSettled => _repeats.isEmpty;

  bool _canStep(_Half half) => switch (half) {
    _Half.minus => _value > _minimum,
    _Half.plus => _value < _maximum,
  };

  _Half? _halfAt(Offset local) {
    const size = MorphStepper.size;
    if (!(Offset.zero & size).contains(local)) return null;
    return local.dx < size.width / 2 ? _Half.minus : _Half.plus;
  }

  void _stepBy(_Half half) {
    if (widget.onChanged == null ||
        !widget.step.isFinite ||
        widget.step <= 0 ||
        !_canStep(half)) {
      return;
    }
    final delta = half == _Half.plus ? widget.step : -widget.step;
    final next = (_value + delta).clamp(_minimum, _maximum);
    widget.onChanged?.call(next);
  }

  @override
  bool acceptsControlPointer(PointerDownEvent event) =>
      _halfAt(event.localPosition) != null;

  @override
  void onControlDown(double t, PointerDownEvent event) {
    final half = _halfAt(event.localPosition)!;
    _repeated = false;
    setState(() => _pressed = half);
    _repeats.insert(t + _interval, _repeat);
  }

  void _repeat(double t) {
    final half = _pressed;
    if (half == null) return;
    _repeated = true;
    _stepBy(half);
    _repeats.insert(t + _interval, _repeat);
  }

  @override
  void onControlMove(double t, PointerMoveEvent event) {
    final half = _halfAt(event.localPosition);
    if (half == null) {
      _end();
      return;
    }
    if (half != _pressed) setState(() => _pressed = half);
  }

  @override
  void onControlUp(double t, PointerUpEvent event) {
    final half = _pressed;
    final repeated = _repeated;
    _end();
    if (half != null && !repeated) _stepBy(half);
  }

  @override
  void onControlCancel(double t) => _end();

  void _end() {
    _repeats.clear();
    releaseControlPointer();
    if (_pressed != null) setState(() => _pressed = null);
  }

  void _key(_Half half) {
    if (widget.onChanged == null) return;
    _stepBy(half);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onChanged != null;
    final style = MorphStepperStyle.resolve(context, widget.style);
    final background = widget.backgroundColor ?? style.backgroundColor;
    final glass = MorphGlass.maybeOf(context);
    const size = MorphStepper.size;
    final value =
        widget.semanticValueFormatter?.call(_value) ?? _format(_value);
    final foreground = widget.foregroundColor ?? style.foregroundColor;
    final painter = _StepperPainter(
      pressed: _pressed,
      background: glass == null ? background : null,
      foreground: foreground,
      limitForeground: widget.foregroundColor == null
          ? style.limitForegroundColor
          : foreground.withValues(alpha: foreground.a * 0.3),
      overlay: style.pressedOverlay,
      replacesFill: style.pressedReplacesFill,
      divider: style.dividerColor,
      dividerHeight: style.dividerHeight,
      minusEnabled: _canStep(_Half.minus),
      plusEnabled: _canStep(_Half.plus),
    );
    final brightness = morphBrightnessOf(context);
    final radius = Radius.circular(size.height / 2);
    final halves = [
      (
        half: _Half.minus,
        shape: RRect.fromRectAndCorners(
          Rect.fromLTWH(0, 0, size.width / 2, size.height),
          topLeft: radius,
          bottomLeft: radius,
        ),
      ),
      (
        half: _Half.plus,
        shape: RRect.fromRectAndCorners(
          Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height),
          topRight: radius,
          bottomRight: radius,
        ),
      ),
    ];
    return RepaintBoundary(
      child: MorphControlFocus(
        enabled: enabled,
        onHighlight: highlightControlFocus,
        onActivate: () => _key(_Half.plus),
        onStep: (int delta) => _key(delta > 0 ? _Half.plus : _Half.minus),
        verticalSteps: true,
        child: MorphFocusRing(
          visible: controlFocused,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: MorphTouchListener(
              enabled: enabled,
              behavior: HitTestBehavior.opaque,
              onPointerDown: handleDown,
              onPointerMove: handleMove,
              onPointerUp: handleUp,
              onPointerCancel: handleCancel,
              child: SizedBox.fromSize(
                size: size,
                child: Stack(
                  children: [
                    if (glass != null)
                      for (final h in halves)
                        if (!(style.pressedReplacesFill && _pressed == h.half))
                          Positioned.fromRect(
                            rect: h.shape.outerRect,
                            child: glass.buildFill(
                              context,
                              MorphGlassSurface(
                                kind: MorphGlassKind.track,
                                shape: h.shape,
                                color: background,
                                brightness: brightness,
                                enabled: enabled,
                                glass: false,
                              ),
                            ),
                          ),
                    Positioned.fill(child: CustomPaint(painter: painter)),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: size.width / 2,
                      child: _HalfSemantics(
                        label: widget.decrementLabel,
                        value: value,
                        enabled: enabled && _canStep(_Half.minus),
                        onTap: () => _key(_Half.minus),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: size.width / 2,
                      child: _HalfSemantics(
                        label: widget.incrementLabel,
                        value: value,
                        enabled: enabled && _canStep(_Half.plus),
                        onTap: () => _key(_Half.plus),
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

  static String _format(double value) {
    if (!value.isFinite) return '$value';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return double.parse(value.toStringAsPrecision(12)).toString();
  }
}

class _HalfSemantics extends StatelessWidget {
  const _HalfSemantics({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      value: value,
      onTap: enabled ? onTap : null,
      child: const SizedBox.expand(),
    );
  }
}

class _StepperPainter extends CustomPainter {
  _StepperPainter({
    required this.pressed,
    required this.background,
    required this.foreground,
    required this.limitForeground,
    required this.overlay,
    required this.replacesFill,
    required this.divider,
    required this.dividerHeight,
    required this.minusEnabled,
    required this.plusEnabled,
  });

  final _Half? pressed;
  final Color? background;
  final Color foreground;
  final Color limitForeground;
  final Color overlay;
  final bool replacesFill;
  final Color divider;
  final double dividerHeight;
  final bool minusEnabled;
  final bool plusEnabled;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final half = size.width / 2;
    final minusRect = Rect.fromLTWH(0, 0, half, size.height);
    final plusRect = Rect.fromLTWH(half, 0, half, size.height);
    final pressedHalf = pressed;
    canvas.save();
    canvas.clipRRect(shape);
    final fill = background;
    if (fill != null) {
      final paint = Paint();
      paint.color = fill;
      if (!(replacesFill && pressedHalf == _Half.minus)) {
        canvas.drawRect(minusRect, paint);
      }
      if (!(replacesFill && pressedHalf == _Half.plus)) {
        canvas.drawRect(plusRect, paint);
      }
    }
    if (pressedHalf != null) {
      final paint = Paint();
      paint.color = overlay;
      canvas.drawRect(pressedHalf == _Half.minus ? minusRect : plusRect, paint);
    }
    canvas.restore();
    final line = Paint();
    line.color = divider;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(half, size.height / 2),
        width: 1,
        height: dividerHeight,
      ),
      line,
    );
    final glyph = Paint();
    glyph.strokeWidth = 2;
    glyph.strokeCap = StrokeCap.round;
    const arm = 7.0;
    final y = size.height / 2;
    final minusX = half / 2;
    final plusX = half + half / 2;
    glyph.color = minusEnabled ? foreground : limitForeground;
    canvas.drawLine(Offset(minusX - arm, y), Offset(minusX + arm, y), glyph);
    glyph.color = plusEnabled ? foreground : limitForeground;
    canvas.drawLine(Offset(plusX - arm, y), Offset(plusX + arm, y), glyph);
    canvas.drawLine(Offset(plusX, y - arm), Offset(plusX, y + arm), glyph);
  }

  @override
  bool shouldRepaint(_StepperPainter oldDelegate) =>
      oldDelegate.pressed != pressed ||
      oldDelegate.background != background ||
      oldDelegate.foreground != foreground ||
      oldDelegate.limitForeground != limitForeground ||
      oldDelegate.overlay != overlay ||
      oldDelegate.replacesFill != replacesFill ||
      oldDelegate.divider != divider ||
      oldDelegate.dividerHeight != dividerHeight ||
      oldDelegate.minusEnabled != minusEnabled ||
      oldDelegate.plusEnabled != plusEnabled;
}
