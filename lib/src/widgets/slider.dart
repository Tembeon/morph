import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/slider_motion.dart';
import 'package:morph/src/widgets/widgets_theme.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/src/widgets/small_lens.dart';

/// The look of a [MorphSlider].
@immutable
class MorphSliderStyle {
  /// Creates a style; the defaults are the iOS light appearance.
  const MorphSliderStyle({
    this.activeColor = const Color(0xFF007AFF),
    this.trackColor = const Color(0x29787880),
    this.thumbColor = const Color(0xFFFFFFFF),
    this.disabledOpacity = 0.5,
  });

  /// The fill of the track below the value: systemBlue.
  final Color activeColor;

  /// The fill of the track above the value: secondarySystemFill.
  final Color trackColor;

  /// The fill of the resting thumb.
  final Color thumbColor;

  /// The opacity of a disabled slider.
  final double disabledOpacity;

  /// The light appearance.
  static const light = MorphSliderStyle();

  /// The dark appearance, from the iOS dark system colors.
  static const dark = MorphSliderStyle(
    activeColor: Color(0xFF0A84FF),
    trackColor: Color(0x52787880),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphSliderStyle resolve(
    BuildContext context,
    MorphSliderStyle? explicit,
  ) =>
      explicit ??
      MorphWidgetsTheme.maybeOf(context)?.slider ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };
}

/// A slider that moves exactly like iOS 27's UISlider.
///
/// Only the thumb is a handle: pressing it lifts it into a clear lens,
/// dragging it moves the value by the finger's travel over the full track
/// width, a release with speed lets the value glide on, and dragging past
/// an end stretches the whole track. A tap on the track does nothing. See
/// [MorphSliderMotion] for the measured behavior. In a right-to-left
/// context the slider is mirrored: the value grows to the left.
///
/// The slider is focusable; the arrow keys and the screen reader's adjust
/// actions move the value by [keyboardStep]. With the platform's reduced
/// motion on, the thumb never lifts or stretches.
class MorphSlider extends StatefulWidget {
  /// Creates a slider.
  const MorphSlider({
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.activeColor,
    this.trackColor,
    this.style,
    this.semanticLabel,
    super.key,
  });

  /// The current value, 0 to 1.
  final double value;

  /// Called with the new value while the user drags or the value glides;
  /// null disables the slider.
  final ValueChanged<double>? onChanged;

  /// Called with the final value when a drag and its glide end.
  final ValueChanged<double>? onChangeEnd;

  /// The fill of the track below the value, overriding [style].
  final Color? activeColor;

  /// The fill of the track above the value, overriding [style].
  final Color? trackColor;

  /// The look of the slider; null resolves it from the theme.
  final MorphSliderStyle? style;

  /// The label screen readers announce for the slider.
  final String? semanticLabel;

  /// The height of the control.
  static const double height = 34;

  /// How much one arrow key or adjust action moves the value.
  static const double keyboardStep = 0.1;

  @override
  State<MorphSlider> createState() => _MorphSliderState();
}

class _MorphSliderState extends State<MorphSlider>
    with SingleTickerProviderStateMixin<MorphSlider>, MorphClock<MorphSlider> {
  late final MorphSliderMotion _motion = _create();
  VelocityTracker? _tracker;
  MorphSliderStyle _style = MorphSliderStyle.light;
  Brightness _brightness = Brightness.light;
  bool _rtl = false;
  bool _focused = false;

  MorphSliderMotion _create() {
    final motion = MorphSliderMotion(
      width: 0,
      value: widget.value,
      frameRate: motionFrameRate,
    );
    motion.onChanged = _changed;
    motion.onChangeEnd = _ended;
    return motion;
  }

  void _changed(double value) => widget.onChanged?.call(value);

  void _ended(double value) => widget.onChangeEnd?.call(value);

  @override
  void advanceMotion(double t) => _motion.advance(t);

  @override
  bool get motionSettled => _motion.isSettled;

  @override
  void didUpdateWidget(MorphSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _motion.reportedValue && !_motion.isDragging) {
      _motion.setValue(clock, widget.value);
      wake();
    }
  }

  bool get _enabled => widget.onChanged != null;

  double _x(Offset local) => _rtl ? _motion.width - local.dx : local.dx;

  void _nudge(int delta) {
    if (!_enabled) return;
    final value = (widget.value + delta * MorphSlider.keyboardStep).clamp(
      0.0,
      1.0,
    );
    if (value == widget.value) return;
    widget.onChanged?.call(value);
    widget.onChangeEnd?.call(value);
  }

  void _down(PointerDownEvent event) {
    if (!_enabled || event.buttons != kPrimaryButton) return;
    if (!_motion.hitsThumb(_x(event.localPosition))) return;
    final tracker = VelocityTracker.withKind(event.kind);
    tracker.addPosition(event.timeStamp, event.localPosition);
    _tracker = tracker;
    _motion.pointerDown(stamp(event), _x(event.localPosition));
  }

  void _move(PointerMoveEvent event) {
    final tracker = _tracker;
    if (tracker == null) return;
    tracker.addPosition(event.timeStamp, event.localPosition);
    _motion.pointerMove(stamp(event), _x(event.localPosition));
  }

  void _up(PointerUpEvent event) {
    final tracker = _tracker;
    if (tracker == null) return;
    _tracker = null;
    tracker.addPosition(event.timeStamp, event.localPosition);
    final velocity = tracker.getVelocity().pixelsPerSecond.dx;
    _motion.pointerUp(
      stamp(event),
      _x(event.localPosition),
      velocity: _rtl ? -velocity : velocity,
    );
  }

  void _cancel(PointerCancelEvent event) {
    if (_tracker == null) return;
    _tracker = null;
    _motion.pointerCancel(stamp(event));
  }

  void _lost(PointerCancelEvent event) {
    if (_tracker == null) return;
    _tracker = null;
    _motion.pointerCancel(stamp(event), revert: true);
  }

  ({RRect track, RRect thumb, double thumbX, double progress}) _frame(
    Size size,
  ) {
    final motion = _motion;
    final t = motion.time;
    final y = size.height / 2;
    final ends = motion.trackEnds;
    final height = math.max(0.0, motion.currentTrackHeight);
    final track = RRect.fromRectAndRadius(
      Rect.fromLTRB(ends.left, y - height / 2, ends.right, y + height / 2),
      Radius.circular(height / 2),
    );
    final thumbX = motion.thumbCenter;
    final lens = motion.lens;
    final thumbSize = lens.size(t);
    final width = thumbSize.width * lens.scaleX(t);
    final thumbHeight = thumbSize.height * lens.scaleY(t);
    final thumb = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(thumbX, y),
        width: width,
        height: thumbHeight,
      ),
      Radius.circular(math.min(width, thumbHeight) / 2),
    );
    return (
      track: track,
      thumb: thumb,
      thumbX: thumbX,
      progress: lens.progress(t).clamp(0.0, 1.0),
    );
  }

  Size get _size => Size(_motion.width, MorphSlider.height);

  RRect _visual(RRect shape) =>
      _rtl ? morphMirror(shape, _motion.width) : shape;

  List<MorphGlassSurface> _trackSurface() => [
    MorphGlassSurface(
      kind: MorphGlassKind.track,
      shape: _visual(_frame(_size).track),
      color: widget.trackColor ?? _style.trackColor,
      brightness: _brightness,
      enabled: _enabled,
      glass: false,
    ),
  ];

  List<MorphGlassSurface> _thumbSurface() {
    final frame = _frame(_size);
    final t = _motion.time;
    final color = _style.thumbColor;
    return [
      MorphGlassSurface(
        kind: MorphGlassKind.thumb,
        shape: _visual(frame.thumb),
        color: color.withValues(alpha: color.a * (1 - frame.progress)),
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
    _style = MorphSliderStyle.resolve(context, widget.style);
    _brightness = morphBrightnessOf(context);
    _rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    _motion.lens.reducedMotion = morphReducedMotionOf(context);
    final glass = MorphGlass.maybeOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 200.0;
        _motion.width = width;
        final size = Size(width, MorphSlider.height);
        final Widget visual;
        if (glass == null) {
          visual = CustomPaint(
            size: size,
            painter: _SliderPainter(this, track: true, thumb: true),
          );
        } else {
          visual = SizedBox.fromSize(
            size: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: MorphGlassLayer(
                    painter: glass,
                    frames: frames,
                    surfaces: _trackSurface,
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SliderPainter(this, track: false, thumb: false),
                  ),
                ),
                Positioned.fill(
                  child: MorphGlassLayer(
                    painter: glass,
                    frames: frames,
                    surfaces: _thumbSurface,
                  ),
                ),
              ],
            ),
          );
        }
        final value = widget.value;
        String percent(double v) => '${(v.clamp(0.0, 1.0) * 100).round()}%';
        return MorphDisabled(
          enabled: _enabled,
          opacity: _style.disabledOpacity,
          child: MorphControlFocus(
            enabled: _enabled,
            onHighlight: (bool focused) => setState(() => _focused = focused),
            onStep: (int delta) => _nudge(_rtl ? -delta : delta),
            verticalSteps: true,
            child: MorphFocusRing(
              visible: _focused,
              child: Semantics(
                container: true,
                slider: true,
                enabled: _enabled,
                label: widget.semanticLabel,
                value: percent(value),
                increasedValue: percent(value + MorphSlider.keyboardStep),
                decreasedValue: percent(value - MorphSlider.keyboardStep),
                onIncrease: _enabled && value < 1 ? () => _nudge(1) : null,
                onDecrease: _enabled && value > 0 ? () => _nudge(-1) : null,
                child: MorphTouchListener(
                  enabled: _enabled,
                  dragAxis: .horizontal,
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: _cancel,
                  onPointerLost: _lost,
                  child: visual,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter(this.state, {required this.track, required this.thumb})
    : super(repaint: state.frames);

  final _MorphSliderState state;
  final bool track;
  final bool thumb;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = state._frame(size);
    final widget = state.widget;
    final style = state._style;
    canvas.save();
    if (state._rtl) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    if (track) {
      final rest = Paint();
      rest.color = widget.trackColor ?? style.trackColor;
      canvas.drawRRect(frame.track, rest);
    }
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(frame.track.left, 0, frame.thumbX, size.height),
    );
    final filled = Paint();
    filled.color = widget.activeColor ?? style.activeColor;
    canvas.drawRRect(frame.track, filled);
    canvas.restore();

    if (thumb) {
      final shape = frame.thumb;
      final progress = frame.progress;
      final shadow = Paint();
      shadow.color = Color.fromRGBO(0, 0, 0, 0.12 * (1 - progress));
      shadow.maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawRRect(shape.shift(const Offset(0, 1.5)), shadow);
      paintMorphSmallLens(
        canvas,
        shape,
        color: style.thumbColor,
        progress: progress,
        brightness: state._brightness,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SliderPainter oldDelegate) => true;
}
