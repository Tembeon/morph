import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/switch_motion.dart';
import 'package:morph/src/widgets/widgets_theme.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/src/widgets/small_lens.dart';

/// The look of a [MorphSwitch].
@immutable
class MorphSwitchStyle {
  /// Creates a style; the defaults are the iOS light appearance.
  const MorphSwitchStyle({
    this.activeColor = const Color(0xFF34C759),
    this.trackColor = const Color(0x29787880),
    this.knobColor = const Color(0xFFFFFFFF),
    this.disabledOpacity = 0.5,
  });

  /// The track color when on: systemGreen.
  final Color activeColor;

  /// The track color when off: secondarySystemFill.
  final Color trackColor;

  /// The fill of the resting knob.
  final Color knobColor;

  /// The opacity of a disabled switch, applied to track and knob as one
  /// layer: UIKit sets its visual element's opacity to 0.5 (iPhone 16 Pro,
  /// light and dark, on and off).
  final double disabledOpacity;

  /// The light appearance.
  static const light = MorphSwitchStyle();

  /// The dark appearance, from the iOS dark system colors.
  static const dark = MorphSwitchStyle(
    activeColor: Color(0xFF30D158),
    trackColor: Color(0x52787880),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphSwitchStyle resolve(
    BuildContext context,
    MorphSwitchStyle? explicit,
  ) => morphResolveStyle(
    context,
    explicit,
    themed: (theme) => theme.switchStyle,
    light: light,
    dark: dark,
  );
}

/// A switch that moves exactly like iOS 27's UISwitch.
///
/// See [MorphSwitchMotion] for the measured behavior: the knob
/// lifts into a clear lens under the finger, a tap toggles on release and
/// a drag carries the knob with a rubber band past the ends. In a
/// right-to-left context the switch is mirrored: on is to the left.
///
/// The switch is focusable; Space and Enter toggle it. With the
/// platform's reduced motion on, the knob travels without lifting or
/// stretching.
class MorphSwitch extends StatefulWidget {
  /// Creates a switch.
  const MorphSwitch({
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.trackColor,
    this.style,
    this.semanticLabel,
    super.key,
  });

  /// Whether the switch is on.
  final bool value;

  /// Called with the new value when the user toggles the switch; null
  /// disables the switch.
  final ValueChanged<bool>? onChanged;

  /// The track color when on, overriding [style].
  final Color? activeColor;

  /// The track color when off, overriding [style].
  final Color? trackColor;

  /// The look of the switch; null resolves it from the theme.
  final MorphSwitchStyle? style;

  /// The label screen readers announce for the switch.
  final String? semanticLabel;

  @override
  State<MorphSwitch> createState() => _MorphSwitchState();
}

class _MorphSwitchState extends State<MorphSwitch>
    with SingleTickerProviderStateMixin<MorphSwitch>, MorphClock<MorphSwitch> {
  static const Size _trackSize = MorphSwitchMotion.trackSize;
  static const double _inset = MorphSwitchMotion.inset;

  late final MorphSwitchMotion _motion = _create();
  MorphSwitchStyle _style = MorphSwitchStyle.light;
  Brightness _brightness = Brightness.light;
  bool _rtl = false;
  bool _focused = false;
  int? _pointer;
  bool _reconcilePending = false;

  MorphSwitchMotion _create() {
    final motion = MorphSwitchMotion(
      value: widget.value,
      frameRate: motionFrameRate,
    );
    motion.onChanged = _changed;
    return motion;
  }

  void _changed(bool value) {
    if (value != widget.value) widget.onChanged?.call(value);
    if (_reconcilePending) return;
    _reconcilePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reconcilePending = false;
      if (!mounted || widget.value == _motion.value) return;
      _motion.setValue(clock, value: widget.value);
      wake();
    });
  }

  @override
  void advanceMotion(double t) => _motion.advance(t);

  @override
  bool get motionSettled => _motion.isSettled;

  @override
  void didUpdateWidget(MorphSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _motion.value) {
      _motion.setValue(clock, value: widget.value);
      wake();
    }
  }

  bool get _enabled => widget.onChanged != null;

  double _x(Offset local) => _rtl ? _trackSize.width - local.dx : local.dx;

  void _toggle() => widget.onChanged?.call(!widget.value);

  Color get _activeColor => widget.activeColor ?? _style.activeColor;

  Color get _offColor => widget.trackColor ?? _style.trackColor;

  ({RRect track, RRect knob, double progress, Color trackColor}) _frame(
    Size size,
  ) {
    final motion = _motion;
    final t = motion.time;
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final lens = motion.lens;
    final knobSize = lens.size(t);
    final width = knobSize.width * lens.scaleX(t);
    final height = knobSize.height * lens.scaleY(t);
    final center = Offset(
      _inset + MorphSwitchMotion.knobSize.width / 2 + motion.knob,
      size.height / 2,
    );
    var knob = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      Radius.circular(math.min(width, height) / 2),
    );
    if (_rtl) knob = morphMirror(knob, size.width);
    return (
      track: track,
      knob: knob,
      progress: lens.progress(t).clamp(0.0, 1.0),
      trackColor: Color.lerp(_offColor, _activeColor, motion.color)!,
    );
  }

  List<MorphGlassSurface> _surfaces() {
    final frame = _frame(_trackSize);
    final t = _motion.time;
    return [
      MorphGlassSurface(
        kind: MorphGlassKind.track,
        shape: frame.track,
        color: frame.trackColor,
        brightness: _brightness,
        enabled: _enabled,
        glass: false,
      ),
      MorphGlassSurface(
        kind: MorphGlassKind.knob,
        shape: frame.knob,
        color: morphSmallLensFill(_style.knobColor, frame.progress),
        brightness: _brightness,
        lift: frame.progress,
        scaleX: _motion.lens.scaleX(t),
        scaleY: _motion.lens.scaleY(t),
        optics: MorphGlassOptics.small,
        enabled: _enabled,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _style = MorphSwitchStyle.resolve(context, widget.style);
    _brightness = morphBrightnessOf(context);
    _rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    _motion.lens.reducedMotion = morphReducedMotionOf(context);
    final glass = MorphGlass.maybeOf(context);
    return MorphDisabled(
      enabled: _enabled,
      opacity: _style.disabledOpacity,
      child: MorphControlFocus(
        enabled: _enabled,
        onHighlight: (bool value) => setState(() => _focused = value),
        onActivate: _toggle,
        child: MorphFocusRing(
          visible: _focused,
          child: Semantics(
            container: true,
            toggled: widget.value,
            enabled: _enabled,
            label: widget.semanticLabel,
            onTap: _enabled ? _toggle : null,
            child: MorphTouchListener(
              enabled: _enabled,
              dragAxis: .horizontal,
              onPointerDown: (PointerDownEvent e) {
                if (!_enabled ||
                    e.buttons != kPrimaryButton ||
                    _pointer != null) {
                  return;
                }
                _pointer = e.pointer;
                _motion.pointerDown(stamp(e), _x(e.localPosition));
              },
              onPointerMove: (PointerMoveEvent e) {
                if (e.pointer != _pointer) return;
                _motion.pointerMove(stamp(e), _x(e.localPosition));
              },
              onPointerUp: (PointerUpEvent e) {
                if (e.pointer != _pointer) return;
                _pointer = null;
                _motion.pointerUp(stamp(e), _x(e.localPosition));
              },
              onPointerCancel: (PointerCancelEvent e) {
                if (e.pointer != _pointer) return;
                _pointer = null;
                _motion.pointerCancel(stamp(e));
              },
              child: glass == null
                  ? CustomPaint(size: _trackSize, painter: _SwitchPainter(this))
                  : SizedBox.fromSize(
                      size: _trackSize,
                      child: MorphGlassLayer(
                        painter: glass,
                        frames: frames,
                        surfaces: _surfaces,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchPainter extends CustomPainter {
  _SwitchPainter(this.state) : super(repaint: state.frames);

  final _MorphSwitchState state;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = state._frame(size);
    final trackPaint = Paint();
    trackPaint.color = frame.trackColor;
    canvas.drawRRect(frame.track, trackPaint);
    final knob = frame.knob;
    final progress = frame.progress;
    final shadow = Paint();
    shadow.color = Color.fromRGBO(0, 0, 0, 0.15 + 0.1 * progress);
    shadow.maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 4 * progress);
    canvas.drawRRect(knob.shift(const Offset(0, 1.5)), shadow);
    paintMorphSmallLens(
      canvas,
      knob,
      color: state._style.knobColor,
      progress: progress,
      brightness: state._brightness,
    );
  }

  @override
  bool shouldRepaint(_SwitchPainter oldDelegate) => true;
}
