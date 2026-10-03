import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/timeline.dart';
import 'package:morph/src/widgets/widgets_theme.dart';
import 'package:morph/src/widgets/touch_listener.dart';

/// The look of a [MorphStepper].
@immutable
class MorphStepperStyle {
  /// Creates a style; the defaults are the iOS light appearance.
  const MorphStepperStyle({
    this.backgroundColor = const Color(0x1F767680),
    this.foregroundColor = const Color(0xFF000000),
    this.pressedOverlay = const Color(0x14000000),
    this.dividerColor = const Color(0x4C3C3C43),
    this.disabledOpacity = 0.35,
  });

  /// The fill of the control: tertiarySystemFill.
  final Color backgroundColor;

  /// The color of the minus and plus glyphs.
  final Color foregroundColor;

  /// The overlay on the pressed half.
  final Color pressedOverlay;

  /// The color of the divider between the halves: separator.
  final Color dividerColor;

  /// The opacity of a disabled stepper.
  final double disabledOpacity;

  /// The light appearance.
  static const light = MorphStepperStyle();

  /// The dark appearance, from the iOS dark system colors.
  static const dark = MorphStepperStyle(
    backgroundColor: Color(0x3D767680),
    foregroundColor: Color(0xFFFFFFFF),
    pressedOverlay: Color(0x1FFFFFFF),
    dividerColor: Color(0x99545458),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphStepperStyle resolve(
    BuildContext context,
    MorphStepperStyle? explicit,
  ) =>
      explicit ??
      MorphWidgetsTheme.maybeOf(context)?.stepper ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };
}

/// A stepper that responds to touch exactly like iOS 27's UIStepper.
///
/// The control has no motion: the pressed half darkens instantly under
/// an 8 percent black overlay and clears instantly on release. A tap
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

  /// The size of the control.
  static const Size size = Size(94, 32);

  /// The delay before the first repeat and between repeats.
  static const Duration repeatInterval = Duration(milliseconds: 500);

  /// The overlay on the pressed half in the light appearance.
  static const Color pressedOverlay = Color(0x14000000);

  /// The color of the divider between the halves in the light appearance.
  static const Color dividerColor = Color(0x4C3C3C43);

  @override
  State<MorphStepper> createState() => _MorphStepperState();
}

enum _Half { minus, plus }

class _MorphStepperState extends State<MorphStepper>
    with
        SingleTickerProviderStateMixin<MorphStepper>,
        MorphClock<MorphStepper> {
  static final double _interval =
      MorphStepper.repeatInterval.inMicroseconds / 1e6;

  int? _pointer;
  _Half? _pressed;
  bool _repeated = false;
  final MorphTimeline _repeats = MorphTimeline();
  double _value = 0;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(MorphStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    _value = widget.value;
  }

  @override
  void advanceMotion(double t) => _repeats.runDue(t);

  @override
  bool get motionSettled => _repeats.isEmpty;

  bool _canStep(_Half half) => switch (half) {
    _Half.minus => _value > widget.min,
    _Half.plus => _value < widget.max,
  };

  _Half? _halfAt(Offset local) {
    const size = MorphStepper.size;
    if (!(Offset.zero & size).contains(local)) return null;
    return local.dx < size.width / 2 ? _Half.minus : _Half.plus;
  }

  void _stepBy(_Half half) {
    if (!_canStep(half)) return;
    final delta = half == _Half.plus ? widget.step : -widget.step;
    _value = (_value + delta).clamp(widget.min, widget.max);
    widget.onChanged?.call(_value);
  }

  void _down(PointerDownEvent event) {
    if (widget.onChanged == null ||
        _pointer != null ||
        event.buttons != kPrimaryButton) {
      return;
    }
    final half = _halfAt(event.localPosition);
    if (half == null) return;
    _pointer = event.pointer;
    _repeated = false;
    setState(() => _pressed = half);
    _repeats.insert(stamp(event) + _interval, _repeat);
  }

  void _repeat(double t) {
    final half = _pressed;
    if (half == null) return;
    _repeated = true;
    _stepBy(half);
    _repeats.insert(t + _interval, _repeat);
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final half = _halfAt(event.localPosition);
    if (half == null) {
      _end();
      return;
    }
    if (half != _pressed) setState(() => _pressed = half);
  }

  void _up(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final half = _pressed;
    final repeated = _repeated;
    _end();
    if (half != null && !repeated) _stepBy(half);
  }

  void _cancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) _end();
  }

  void _end() {
    _repeats.clear();
    _pointer = null;
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
    final value = _format(widget.value);
    final painter = _StepperPainter(
      pressed: _pressed,
      background: glass == null ? background : null,
      foreground: widget.foregroundColor ?? style.foregroundColor,
      overlay: style.pressedOverlay,
      divider: style.dividerColor,
      minusEnabled: _canStep(_Half.minus),
      plusEnabled: _canStep(_Half.plus),
    );
    final brightness = morphBrightnessOf(context);
    return MorphDisabled(
      enabled: enabled,
      opacity: style.disabledOpacity,
      child: MorphControlFocus(
        enabled: enabled,
        onHighlight: (bool focused) => setState(() => _focused = focused),
        onActivate: () => _key(_Half.plus),
        onStep: (int delta) => _key(delta > 0 ? _Half.plus : _Half.minus),
        verticalSteps: true,
        child: MorphFocusRing(
          visible: _focused,
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: MorphTouchListener(
              enabled: enabled,
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _cancel,
              child: SizedBox.fromSize(
                size: size,
                child: Stack(
                  children: [
                    if (glass != null)
                      Positioned.fill(
                        child: glass.buildFill(
                          context,
                          MorphGlassSurface(
                            kind: MorphGlassKind.track,
                            shape: RRect.fromRectAndRadius(
                              Offset.zero & size,
                              Radius.circular(size.height / 2),
                            ),
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

  static String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
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
    required this.overlay,
    required this.divider,
    required this.minusEnabled,
    required this.plusEnabled,
  });

  final _Half? pressed;
  final Color? background;
  final Color foreground;
  final Color overlay;
  final Color divider;
  final bool minusEnabled;
  final bool plusEnabled;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final fill = background;
    if (fill != null) {
      final paint = Paint();
      paint.color = fill;
      canvas.drawRRect(shape, paint);
    }
    final half = size.width / 2;
    final pressedHalf = pressed;
    if (pressedHalf != null) {
      canvas.save();
      canvas.clipRRect(shape);
      final paint = Paint();
      paint.color = overlay;
      canvas.drawRect(
        pressedHalf == _Half.minus
            ? Rect.fromLTWH(0, 0, half, size.height)
            : Rect.fromLTWH(half, 0, half, size.height),
        paint,
      );
      canvas.restore();
    }
    final line = Paint();
    line.color = divider;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(half, size.height / 2),
        width: 1,
        height: size.height * 0.56,
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
    glyph.color = _dimmed(enabled: minusEnabled);
    canvas.drawLine(Offset(minusX - arm, y), Offset(minusX + arm, y), glyph);
    glyph.color = _dimmed(enabled: plusEnabled);
    canvas.drawLine(Offset(plusX - arm, y), Offset(plusX + arm, y), glyph);
    canvas.drawLine(Offset(plusX, y - arm), Offset(plusX, y + arm), glyph);
  }

  Color _dimmed({required bool enabled}) =>
      enabled ? foreground : foreground.withValues(alpha: foreground.a * 0.3);

  @override
  bool shouldRepaint(_StepperPainter oldDelegate) =>
      oldDelegate.pressed != pressed ||
      oldDelegate.background != background ||
      oldDelegate.foreground != foreground ||
      oldDelegate.overlay != overlay ||
      oldDelegate.divider != divider ||
      oldDelegate.minusEnabled != minusEnabled ||
      oldDelegate.plusEnabled != plusEnabled;
}
