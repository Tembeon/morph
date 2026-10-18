import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/control_host.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/haptics.dart';
import 'package:morph/src/widgets/press.dart';
import 'package:morph/src/widgets/slider_motion.dart';
import 'package:morph/src/widgets/small_lens.dart';
import 'package:morph/src/theme/theme.dart';

/// The look of a [MorphSlider].
@immutable
class MorphSliderAppearance implements MorphAppearance {
  /// Creates an appearance; the defaults are the iOS light appearance.
  const MorphSliderAppearance({
    this.activeTrackColor = const Color(0xFF0088FF),
    this.inactiveTrackColor = const Color(0x1A000000),
    this.thumbColor = const Color(0xFFFFFFFF),
    this.tickColor = const Color(0xFFC6C6C8),
    this.disabledOpacity = 0.5,
  });

  /// The fill of the track below the value: iOS 27's systemBlue (UIKit
  /// `minimumTrackTintColor`).
  final Color activeTrackColor;

  /// The fill of the track above the value (UIKit
  /// `maximumTrackTintColor`).
  final Color inactiveTrackColor;

  /// The fill of the resting thumb (UIKit `thumbTintColor`).
  final Color thumbColor;

  /// The fill of the tick marks of a stepped slider.
  final Color tickColor;

  /// The opacity of a disabled slider, applied to track, fill, thumb and
  /// ticks as one layer: UIKit sets its glass visual element's opacity to
  /// 0.5 (iPhone 16 Pro, light and dark).
  final double disabledOpacity;

  /// The light appearance.
  static const light = MorphSliderAppearance();

  /// The dark appearance, from the iOS dark system colors.
  static const dark = MorphSliderAppearance(
    activeTrackColor: Color(0xFF0091FF),
    inactiveTrackColor: Color(0x1AFFFFFF),
    tickColor: Color(0xFF38383A),
  );

  /// The light appearance under Increase Contrast: the fill takes
  /// systemBlue's increased-contrast variant; the tick color has none
  /// (read from UIKit's color tables, notes private). The unfilled track
  /// keeps its standard color until the device records it.
  static const lightHighContrast = MorphSliderAppearance(
    activeTrackColor: Color(0xFF1E6EF4),
  );

  /// The dark appearance under Increase Contrast: the fill takes the dark
  /// systemBlue's increased-contrast variant (read from UIKit's color
  /// tables, notes private).
  static const darkHighContrast = MorphSliderAppearance(
    activeTrackColor: Color(0xFF5CB8FF),
    inactiveTrackColor: Color(0x1AFFFFFF),
    tickColor: Color(0xFF38383A),
  );

  /// Copies this appearance with the given fields replaced.
  MorphSliderAppearance copyWith({
    Color? activeTrackColor,
    Color? inactiveTrackColor,
    Color? thumbColor,
    Color? tickColor,
    double? disabledOpacity,
  }) => MorphSliderAppearance(
    activeTrackColor: activeTrackColor ?? this.activeTrackColor,
    inactiveTrackColor: inactiveTrackColor ?? this.inactiveTrackColor,
    thumbColor: thumbColor ?? this.thumbColor,
    tickColor: tickColor ?? this.tickColor,
    disabledOpacity: disabledOpacity ?? this.disabledOpacity,
  );

  /// Resolves [explicit], then the ambient [MorphTheme], then the
  /// table for the ambient brightness and contrast with
  /// [MorphThemeData.tint] as its [activeTrackColor].
  static MorphSliderAppearance resolve(
    BuildContext context,
    MorphSliderAppearance? explicit,
  ) => morphResolveAppearance(
    context,
    explicit,
    light: light,
    dark: dark,
    lightHighContrast: lightHighContrast,
    darkHighContrast: darkHighContrast,
    tinted: (table, tint) => table.copyWith(activeTrackColor: tint),
  );

  @override
  bool operator ==(Object other) =>
      other is MorphSliderAppearance &&
      other.activeTrackColor == activeTrackColor &&
      other.inactiveTrackColor == inactiveTrackColor &&
      other.thumbColor == thumbColor &&
      other.tickColor == tickColor &&
      other.disabledOpacity == disabledOpacity;

  @override
  int get hashCode => Object.hash(
    activeTrackColor,
    inactiveTrackColor,
    thumbColor,
    tickColor,
    disabledOpacity,
  );
}

/// A slider that moves exactly like iOS 27's UISlider.
///
/// Only the thumb is a handle: pressing it lifts it into a clear lens,
/// dragging it moves the value by the finger's travel over the full track
/// width, a release with speed lets the value glide on, and dragging past
/// an end stretches the whole track. A tap on the track does nothing. With
/// [ticks] the value snaps to that many evenly spaced stops marked under
/// the track. See
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
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.appearance,
    this.semanticLabel,
    this.ticks = 0,
    this.animated = false,
    super.key,
  }) : assert(min < max, 'min must be less than max');

  /// Whether a [value] the parent changes moves the thumb on a spring, as
  /// UIKit's `setValue(_:animated: true)` does
  /// ([MorphSliderMotion.programmaticSpring]), instead of jumping as the
  /// `value` setter does. A stepped slider always jumps.
  final bool animated;

  /// The number of tick marks the value snaps to, like UIKit's
  /// `numberOfTicks`; below two the slider is continuous.
  final int ticks;

  /// The current value, [min] to [max].
  ///
  /// While the user drags or the value glides, the gesture leads: a value
  /// that differs from the one last reported, such as a rounded or a
  /// rejected one, moves the thumb once the drag and its glide end.
  final double value;

  /// Called with the new value while the user drags or the value glides;
  /// null disables the slider.
  final ValueChanged<double>? onChanged;

  /// Called with the value when the user grabs the thumb, before any
  /// [onChanged] (UIKit `.touchDown` / `.editingDidBegin`), and before a
  /// keyboard or screen reader step.
  final ValueChanged<double>? onChangeStart;

  /// Called with the final value when a drag and its glide end.
  final ValueChanged<double>? onChangeEnd;

  /// The value at the leading end of the track (UIKit `minimumValue`).
  final double min;

  /// The value at the trailing end of the track (UIKit `maximumValue`).
  final double max;

  /// The fill of the track below the value, overriding [appearance]
  /// (UIKit `minimumTrackTintColor`).
  final Color? activeTrackColor;

  /// The fill of the track above the value, overriding [appearance]
  /// (UIKit `maximumTrackTintColor`).
  final Color? inactiveTrackColor;

  /// The look of the slider; null resolves it from the theme.
  final MorphSliderAppearance? appearance;

  /// The label screen readers announce for the slider.
  final String? semanticLabel;

  /// The height of the control.
  static const double height = 34;

  /// How much one arrow key or adjust action moves a continuous slider;
  /// a stepped one moves to the next stop on that side, so a value set
  /// between stops lands on one.
  static const double keyboardStep = 0.1;

  /// The track position, 0 to 1, one step from [from] in the direction
  /// of [delta]: [keyboardStep] further for a continuous slider, the next
  /// stop on that side for a stepped one.
  double _stepFrom(double from, int delta) {
    if (ticks < 2) return (from + delta * keyboardStep).clamp(0.0, 1.0);
    final steps = ticks - 1;
    final at = from * steps;
    // A stop the parent rounded sits a hair off it and still counts as it.
    final base = delta > 0 ? (at + 1e-6).floor() : (at - 1e-6).ceil();
    return (base + delta).clamp(0, steps) / steps;
  }

  @override
  State<MorphSlider> createState() => _MorphSliderState();
}

class _MorphSliderState extends MorphControlHost<MorphSlider> {
  late final MorphSliderMotion _motion = _create();
  late final ValueNotifier<double> _semanticValue = ValueNotifier(
    _unit(widget.value),
  );
  double? _reportedOut;
  // The track rests through most of a drag; its glass host then neither
  // rebuilds nor pushes.
  late final MorphChanges<RRect> _trackFrames = MorphChanges<RRect>(
    frames,
    _trackShape,
  );
  VelocityTracker? _tracker;
  MorphSliderAppearance _style = MorphSliderAppearance.light;
  Brightness _brightness = Brightness.light;
  bool _rtl = false;

  MorphSliderMotion _create() {
    final motion = MorphSliderMotion(
      width: 0,
      value: _unit(widget.value),
      frameRate: motionFrameRate,
      ticks: widget.ticks,
    );
    motion.onChanged = _changed;
    motion.onChangeEnd = _ended;
    motion.onFeel = _feel;
    return motion;
  }

  void _feel(bool detent) {
    if (!mounted) return;
    morphPlayHaptic(context, detent ? MorphHaptic.detent : MorphHaptic.edge);
  }

  /// [value] in the track's 0 to 1.
  double _unit(double value) {
    final min = widget.min;
    final max = widget.max;
    if (min == 0 && max == 1) return value;
    return ((value - min) / (max - min)).clamp(0.0, 1.0);
  }

  /// The value at [unit] of the track.
  double _out(double unit) {
    final min = widget.min;
    final max = widget.max;
    if (min == 0 && max == 1) return unit;
    return min + unit * (max - min);
  }

  /// Whether the widget's value is the one the motion last reported.
  bool get _inSync =>
      widget.value == _reportedOut ||
      _unit(widget.value) == _motion.reportedValue;

  void _changed(double value) {
    final out = _reportedOut = _out(value);
    widget.onChanged?.call(out);
    _reconcile();
  }

  bool get _leading => _motion.isDragging || _motion.isGliding;

  void _reconcile() => reconcileAfterFrame(() {
    if (_inSync) return false;
    _motion.setValue(clock, _unit(widget.value));
    _reportedOut = widget.value;
    return true;
  }, defer: () => _leading);

  void _ended(double value) => widget.onChangeEnd?.call(_out(value));

  @override
  void advanceMotion(double t) => _motion.advance(t);

  @override
  bool get motionSettled => _motion.isSettled;

  @override
  void settleMotion() => _motion.settle();

  @override
  void didUpdateWidget(MorphSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _semanticValue.value = _unit(widget.value);
    _motion.ticks = widget.ticks;
    if (_inSync) return;
    if (_leading) {
      _reconcile();
      return;
    }
    _motion.setValue(clock, _unit(widget.value), animated: widget.animated);
    _reportedOut = widget.value;
    wake();
  }

  @override
  void dispose() {
    _semanticValue.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onChanged != null;

  double _x(Offset local) => _rtl ? _motion.width - local.dx : local.dx;

  void _nudge(int delta) {
    if (!_enabled) return;
    final from = _unit(widget.value);
    final unit = widget._stepFrom(from, delta);
    if (unit == from) return;
    final value = _out(unit);
    widget.onChangeStart?.call(widget.value);
    widget.onChanged?.call(value);
    widget.onChangeEnd?.call(value);
  }

  @override
  bool get controlEnabled => _enabled;

  @override
  bool acceptsControlPointer(PointerDownEvent event) =>
      _motion.hitsThumb(_x(event.localPosition));

  @override
  void onControlDown(double t, PointerDownEvent event) {
    final tracker = VelocityTracker.withKind(event.kind);
    tracker.addPosition(event.timeStamp, event.localPosition);
    _tracker = tracker;
    widget.onChangeStart?.call(widget.value);
    _motion.pointerDown(t, _x(event.localPosition));
  }

  @override
  void onControlMove(double t, PointerMoveEvent event) {
    final tracker = _tracker;
    if (tracker == null) return;
    tracker.addPosition(event.timeStamp, event.localPosition);
    _motion.pointerMove(t, _x(event.localPosition));
  }

  @override
  void onControlUp(double t, PointerUpEvent event) {
    final tracker = _tracker;
    if (tracker == null) return;
    _tracker = null;
    tracker.addPosition(event.timeStamp, event.localPosition);
    final velocity = tracker.getVelocity().pixelsPerSecond.dx;
    _motion.pointerUp(
      t,
      _x(event.localPosition),
      velocity: _rtl ? -velocity : velocity,
    );
  }

  @override
  void onControlCancel(double t) {
    if (_tracker == null) return;
    _tracker = null;
    _motion.pointerCancel(t);
  }

  @override
  void onControlLost(double t) {
    if (_tracker == null) return;
    _tracker = null;
    _motion.pointerCancel(t, revert: true);
  }

  ({RRect track, RRect fill, RRect thumb, double progress}) _frame(Size size) {
    final motion = _motion;
    final t = motion.time;
    final y = size.height / 2;
    final ends = motion.trackEnds;
    final height = math.max(0.0, motion.currentTrackHeight);
    final track = RRect.fromRectAndRadius(
      Rect.fromLTRB(ends.left, y - height / 2, ends.right, y + height / 2),
      Radius.circular(height / 2),
    );
    final fillEnd = math.max(ends.left, motion.fillEnd);
    final fill = RRect.fromRectAndRadius(
      Rect.fromLTRB(ends.left, y - height / 2, fillEnd, y + height / 2),
      Radius.circular(math.min(height, fillEnd - ends.left) / 2),
    );
    final lens = motion.lens;
    final thumbX = motion.thumbCenter + lens.shift(t);
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
      fill: fill,
      thumb: thumb,
      progress: lens.progress(t).clamp(0.0, 1.0),
    );
  }

  Size get _size => Size(_motion.width, MorphSlider.height);

  RRect _visual(RRect shape) =>
      _rtl ? morphMirror(shape, _motion.width) : shape;

  RRect _trackShape() => _visual(_frame(_size).track);

  List<MorphGlassSurface> _trackSurface() => [
    MorphGlassSurface(
      kind: MorphGlassKind.track,
      shape: _trackShape(),
      color: widget.inactiveTrackColor ?? _style.inactiveTrackColor,
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
        color: morphSmallLensFill(color, frame.progress, liftedOpacity: 0),
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
  bool buildsLike(MorphSlider oldWidget) =>
      (oldWidget.value == widget.value || _inSync) &&
      oldWidget.min == widget.min &&
      oldWidget.max == widget.max &&
      oldWidget.ticks == widget.ticks &&
      (oldWidget.onChanged == null) == (widget.onChanged == null) &&
      oldWidget.activeTrackColor == widget.activeTrackColor &&
      oldWidget.inactiveTrackColor == widget.inactiveTrackColor &&
      oldWidget.appearance == widget.appearance &&
      oldWidget.semanticLabel == widget.semanticLabel;

  @override
  Widget buildControl(BuildContext context) {
    _style = MorphSliderAppearance.resolve(context, widget.appearance);
    _brightness = morphBrightnessOf(context);
    _rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    _motion.lens.reducedMotion = morphReducedMotionOf(context);
    final glass = MorphGlassScope.maybeOf(context);
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
                    frames: _trackFrames,
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
        String percent(double v) => '${(v.clamp(0.0, 1.0) * 100).round()}%';
        return MorphDisabled(
          enabled: _enabled,
          opacity: _style.disabledOpacity,
          child: MorphPress(
            target: this,
            enabled: _enabled,
            onHighlight: highlightControlFocus,
            onStep: (int delta) => _nudge(_rtl ? -delta : delta),
            verticalSteps: true,
            dragAxis: .horizontal,
            behavior: HitTestBehavior.opaque,
            child: MorphLiveSemantics(
              live: _semanticValue,
              container: true,
              propertiesOf: () {
                final value = _semanticValue.value;
                return SemanticsProperties(
                  slider: true,
                  enabled: _enabled,
                  label: widget.semanticLabel,
                  value: percent(value),
                  increasedValue: percent(widget._stepFrom(value, 1)),
                  decreasedValue: percent(widget._stepFrom(value, -1)),
                  onIncrease: _enabled && value < 1 ? () => _nudge(1) : null,
                  onDecrease: _enabled && value > 0 ? () => _nudge(-1) : null,
                );
              },
              child: MorphFocusRing(visible: controlFocused, child: visual),
            ),
          ),
        );
      },
    );
  }
}

// A Semantics container whose properties follow [value] in the render
// object: a value the parent changes on every frame of a drag updates the
// semantics node without a widget rebuild.
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
      rest.color = widget.inactiveTrackColor ?? style.inactiveTrackColor;
      canvas.drawRRect(frame.track, rest);
    }
    final ticks = Paint();
    ticks.color = style.tickColor;
    final tickY = size.height / 2 + MorphSliderMotion.tickOffset;
    for (final x in state._motion.tickCenters) {
      canvas.drawCircle(
        Offset(x, tickY),
        MorphSliderMotion.tickSize / 2,
        ticks,
      );
    }
    if (frame.fill.width > 0) {
      final filled = Paint();
      filled.color = widget.activeTrackColor ?? style.activeTrackColor;
      canvas.drawRRect(frame.fill, filled);
    }

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
