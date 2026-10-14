import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/control_host.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/press.dart';
import 'package:morph/src/widgets/small_lens.dart';
import 'package:morph/src/widgets/switch_motion.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// The look of a [MorphSwitch].
@immutable
class MorphSwitchAppearance {
  /// Creates an appearance; the defaults are the iOS light appearance.
  const MorphSwitchAppearance({
    this.activeTrackColor = const Color(0xFF34C759),
    this.inactiveTrackColor = const Color(0x29787880),
    this.thumbColor = const Color(0xFFFFFFFF),
    this.disabledOpacity = 0.5,
  });

  /// The track color when on: systemGreen (UIKit `onTintColor`).
  final Color activeTrackColor;

  /// The track color when off: secondarySystemFill.
  final Color inactiveTrackColor;

  /// The fill of the resting knob (UIKit `thumbTintColor`).
  final Color thumbColor;

  /// The opacity of a disabled switch, applied to track and knob as one
  /// layer: UIKit sets its visual element's opacity to 0.5 (iPhone 16 Pro,
  /// light and dark, on and off).
  final double disabledOpacity;

  /// The light appearance.
  static const light = MorphSwitchAppearance();

  /// The dark appearance, from the iOS dark system colors.
  static const dark = MorphSwitchAppearance(
    activeTrackColor: Color(0xFF30D158),
    inactiveTrackColor: Color(0x52787880),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphSwitchAppearance resolve(
    BuildContext context,
    MorphSwitchAppearance? explicit,
  ) => morphResolveAppearance(
    context,
    explicit,
    themed: (theme) => theme.switchAppearance,
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
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.appearance,
    this.semanticLabel,
    super.key,
  });

  /// Whether the switch is on.
  final bool value;

  /// Called with the new value when the user toggles the switch; null
  /// disables the switch.
  final ValueChanged<bool>? onChanged;

  /// The track color when on, overriding [appearance] (UIKit
  /// `onTintColor`).
  final Color? activeTrackColor;

  /// The track color when off, overriding [appearance].
  final Color? inactiveTrackColor;

  /// The look of the switch; null resolves it from the theme.
  final MorphSwitchAppearance? appearance;

  /// The label screen readers announce for the switch.
  final String? semanticLabel;

  @override
  State<MorphSwitch> createState() => _MorphSwitchState();
}

class _MorphSwitchState extends MorphControlHost<MorphSwitch> {
  static const Size _trackSize = MorphSwitchMotion.trackSize;
  static const double _inset = MorphSwitchMotion.inset;

  late final MorphSwitchMotion _motion = _create();
  MorphSwitchAppearance _style = MorphSwitchAppearance.light;
  Brightness _brightness = Brightness.light;
  bool _rtl = false;

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
    reconcileAfterFrame(() {
      if (widget.value == _motion.value) return false;
      _motion.setValue(clock, value: widget.value);
      return true;
    });
  }

  @override
  void advanceMotion(double t) => _motion.advance(t);

  @override
  bool get motionSettled => _motion.isSettled;

  @override
  void settleMotion() => _motion.settle();

  @override
  void didUpdateWidget(MorphSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _motion.value) {
      _motion.setValue(clock, value: widget.value);
      wake();
    }
  }

  bool get _enabled => widget.onChanged != null;

  @override
  bool get controlEnabled => _enabled;

  @override
  void onControlDown(double t, PointerDownEvent event) =>
      _motion.pointerDown(t, _x(event.localPosition));

  @override
  void onControlMove(double t, PointerMoveEvent event) =>
      _motion.pointerMove(t, _x(event.localPosition));

  @override
  void onControlUp(double t, PointerUpEvent event) =>
      _motion.pointerUp(t, _x(event.localPosition));

  @override
  void onControlCancel(double t) => _motion.pointerCancel(t);

  double _x(Offset local) => _rtl ? _trackSize.width - local.dx : local.dx;

  void _toggle() => widget.onChanged?.call(!widget.value);

  Color get _activeColor => widget.activeTrackColor ?? _style.activeTrackColor;

  Color get _offColor => widget.inactiveTrackColor ?? _style.inactiveTrackColor;

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
      _inset +
          MorphSwitchMotion.knobSize.width / 2 +
          motion.knob +
          lens.shift(t),
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
        color: morphSmallLensFill(_style.thumbColor, frame.progress),
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
  bool buildsLike(MorphSwitch oldWidget) =>
      oldWidget.value == widget.value &&
      (oldWidget.onChanged == null) == (widget.onChanged == null) &&
      oldWidget.activeTrackColor == widget.activeTrackColor &&
      oldWidget.inactiveTrackColor == widget.inactiveTrackColor &&
      oldWidget.appearance == widget.appearance &&
      oldWidget.semanticLabel == widget.semanticLabel;

  @override
  Widget buildControl(BuildContext context) {
    _style = MorphSwitchAppearance.resolve(context, widget.appearance);
    _brightness = morphBrightnessOf(context);
    _rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    _motion.lens.reducedMotion = morphReducedMotionOf(context);
    final glass = MorphGlassScope.maybeOf(context);
    return RepaintBoundary(
      child: MorphDisabled(
        enabled: _enabled,
        opacity: _style.disabledOpacity,
        child: MorphPress(
          target: this,
          enabled: _enabled,
          onHighlight: highlightControlFocus,
          onActivate: _toggle,
          semantics: SemanticsProperties(
            toggled: widget.value,
            enabled: _enabled,
            label: widget.semanticLabel,
            onTap: _enabled ? _toggle : null,
          ),
          semanticsContainer: true,
          dragAxis: .horizontal,
          child: MorphFocusRing(
            visible: controlFocused,
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
      color: state._style.thumbColor,
      progress: progress,
      brightness: state._brightness,
    );
  }

  @override
  bool shouldRepaint(_SwitchPainter oldDelegate) => true;
}
