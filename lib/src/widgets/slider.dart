import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/control_host.dart';
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
    this.activeColor = const Color(0xFF0088FF),
    this.trackColor = const Color(0x1A000000),
    this.thumbColor = const Color(0xFFFFFFFF),
    this.tickColor = const Color(0xFFC6C6C8),
    this.disabledOpacity = 0.5,
  });

  /// The fill of the track below the value: iOS 27's systemBlue.
  final Color activeColor;

  /// The fill of the track above the value.
  final Color trackColor;

  /// The fill of the resting thumb.
  final Color thumbColor;

  /// The fill of the tick marks of a stepped slider.
  final Color tickColor;

  /// The opacity of a disabled slider, applied to track, fill, thumb and
  /// ticks as one layer: UIKit sets its glass visual element's opacity to
  /// 0.5 (iPhone 16 Pro, light and dark).
  final double disabledOpacity;

  /// The light appearance.
  static const light = MorphSliderStyle();

  /// The dark appearance, from the iOS dark system colors.
  static const dark = MorphSliderStyle(
    activeColor: Color(0xFF0091FF),
    trackColor: Color(0x1AFFFFFF),
    tickColor: Color(0xFF38383A),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphSliderStyle resolve(
    BuildContext context,
    MorphSliderStyle? explicit,
  ) => morphResolveStyle(
    context,
    explicit,
    themed: (theme) => theme.slider,
    light: light,
    dark: dark,
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
    this.onChangeEnd,
    this.activeColor,
    this.trackColor,
    this.style,
    this.semanticLabel,
    this.ticks = 0,
    super.key,
  });

  /// The number of tick marks the value snaps to, like UIKit's
  /// `numberOfTicks`; below two the slider is continuous.
  final int ticks;

  /// The current value, 0 to 1.
  ///
  /// While the user drags or the value glides, the gesture leads: a value
  /// that differs from the one last reported, such as a rounded or a
  /// rejected one, moves the thumb once the drag and its glide end.
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

  /// How much one arrow key or adjust action moves a continuous slider;
  /// a stepped one moves by one stop.
  static const double keyboardStep = 0.1;

  double get _step => ticks >= 2 ? 1 / (ticks - 1) : keyboardStep;

  @override
  State<MorphSlider> createState() => _MorphSliderState();
}

class _MorphSliderState extends MorphControlHost<MorphSlider> {
  late final MorphSliderMotion _motion = _create();
  late final ValueNotifier<double> _semanticValue = ValueNotifier(widget.value);
  late final _TrackFrames _trackFrames = _TrackFrames(
    frames,
    () => _visual(_frame(_size).track),
  );
  VelocityTracker? _tracker;
  MorphSliderStyle _style = MorphSliderStyle.light;
  Brightness _brightness = Brightness.light;
  bool _rtl = false;

  MorphSliderMotion _create() {
    final motion = MorphSliderMotion(
      width: 0,
      value: widget.value,
      frameRate: motionFrameRate,
      ticks: widget.ticks,
    );
    motion.onChanged = _changed;
    motion.onChangeEnd = _ended;
    return motion;
  }

  void _changed(double value) {
    widget.onChanged?.call(value);
    _reconcile();
  }

  bool get _leading => _motion.isDragging || _motion.isGliding;

  void _reconcile() => reconcileAfterFrame(() {
    if (widget.value == _motion.reportedValue) return false;
    _motion.setValue(clock, widget.value);
    return true;
  }, defer: () => _leading);

  void _ended(double value) => widget.onChangeEnd?.call(value);

  @override
  void advanceMotion(double t) => _motion.advance(t);

  @override
  bool get motionSettled => _motion.isSettled;

  @override
  void didUpdateWidget(MorphSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _semanticValue.value = widget.value;
    _motion.ticks = widget.ticks;
    if (widget.value == _motion.reportedValue) return;
    if (_leading) {
      _reconcile();
      return;
    }
    _motion.setValue(clock, widget.value);
    wake();
  }

  @override
  void dispose() {
    _semanticValue.dispose();
    _trackFrames.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onChanged != null;

  double _x(Offset local) => _rtl ? _motion.width - local.dx : local.dx;

  void _nudge(int delta) {
    if (!_enabled) return;
    final value = (widget.value + delta * widget._step).clamp(0.0, 1.0);
    if (value == widget.value) return;
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
      fill: fill,
      thumb: thumb,
      progress: lens.progress(t).clamp(0.0, 1.0),
    );
  }

  Size get _size => Size(_motion.width, MorphSlider.height);

  RRect _visual(RRect shape) =>
      _rtl ? morphMirror(shape, _motion.width) : shape;

  List<MorphGlassSurface> _trackSurface() => [
    MorphGlassSurface(
      kind: MorphGlassKind.track,
      shape: _trackFrames.read(),
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
      (oldWidget.value == widget.value ||
          widget.value == _motion.reportedValue) &&
      oldWidget.ticks == widget.ticks &&
      (oldWidget.onChanged == null) == (widget.onChanged == null) &&
      oldWidget.activeColor == widget.activeColor &&
      oldWidget.trackColor == widget.trackColor &&
      oldWidget.style == widget.style &&
      oldWidget.semanticLabel == widget.semanticLabel;

  @override
  Widget buildControl(BuildContext context) {
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
          child: MorphControlFocus(
            enabled: _enabled,
            onHighlight: highlightControlFocus,
            onStep: (int delta) => _nudge(_rtl ? -delta : delta),
            verticalSteps: true,
            child: MorphFocusRing(
              visible: controlFocused,
              child: _SliderSemantics(
                value: _semanticValue,
                properties: (double value) => SemanticsProperties(
                  slider: true,
                  enabled: _enabled,
                  label: widget.semanticLabel,
                  value: percent(value),
                  increasedValue: percent(value + widget._step),
                  decreasedValue: percent(value - widget._step),
                  onIncrease: _enabled && value < 1 ? () => _nudge(1) : null,
                  onDecrease: _enabled && value > 0 ? () => _nudge(-1) : null,
                ),
                child: MorphTouchListener(
                  enabled: _enabled,
                  dragAxis: .horizontal,
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: handleDown,
                  onPointerMove: handleMove,
                  onPointerUp: handleUp,
                  onPointerCancel: handleCancel,
                  onPointerLost: handleLost,
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

// The motion's frames on which the track's shape differs from the one its
// glass host last read: the track rests through most of a drag, and its
// host then neither rebuilds nor pushes.
class _TrackFrames extends ChangeNotifier {
  _TrackFrames(this._frames, this._shape) {
    _frames.addListener(_tick);
  }

  final Listenable _frames;
  final RRect Function() _shape;
  RRect? _read;

  RRect read() => _read = _shape();

  void _tick() {
    if (hasListeners && _shape() != _read) notifyListeners();
  }

  @override
  void dispose() {
    _frames.removeListener(_tick);
    super.dispose();
  }
}

// A Semantics container whose properties follow [value] in the render
// object: a value the parent changes on every frame of a drag updates the
// semantics node without a widget rebuild.
class _SliderSemantics extends SingleChildRenderObjectWidget {
  const _SliderSemantics({
    required this.value,
    required this.properties,
    required super.child,
  });

  final ValueListenable<double> value;
  final SemanticsProperties Function(double value) properties;

  @override
  _RenderSliderSemantics createRenderObject(BuildContext context) =>
      _RenderSliderSemantics(
        value: value,
        propertiesOf: properties,
        textDirection: Directionality.maybeOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliderSemantics renderObject,
  ) {
    renderObject.value = value;
    renderObject.propertiesOf = properties;
    renderObject.textDirection = Directionality.maybeOf(context);
  }
}

class _RenderSliderSemantics extends RenderSemanticsAnnotations {
  _RenderSliderSemantics({
    required ValueListenable<double> value,
    required SemanticsProperties Function(double value) propertiesOf,
    super.textDirection,
  }) : _value = value,
       _propertiesOf = propertiesOf,
       super(properties: propertiesOf(value.value), container: true);

  ValueListenable<double> _value;
  ValueListenable<double> get value => _value;
  set value(ValueListenable<double> value) {
    if (identical(value, _value)) return;
    if (attached) {
      _value.removeListener(_changed);
      value.addListener(_changed);
    }
    _value = value;
    _changed();
  }

  SemanticsProperties Function(double value) _propertiesOf;
  SemanticsProperties Function(double value) get propertiesOf => _propertiesOf;
  set propertiesOf(SemanticsProperties Function(double value) value) {
    if (identical(value, _propertiesOf)) return;
    _propertiesOf = value;
    _changed();
  }

  void _changed() => properties = _propertiesOf(_value.value);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _value.addListener(_changed);
  }

  @override
  void detach() {
    _value.removeListener(_changed);
    super.detach();
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
      filled.color = widget.activeColor ?? style.activeColor;
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
