import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// The look of a [MorphProgressView].
@immutable
class MorphProgressStyle {
  /// Creates a style; the defaults are the iOS light appearance.
  const MorphProgressStyle({
    this.trackColor = const Color(0x33787880),
    this.progressColor = const Color(0xFF0088FF),
  });

  /// The fill of the unfilled track: systemFill.
  final Color trackColor;

  /// The fill of the filled part: iOS 27's systemBlue, as rendered.
  final Color progressColor;

  /// The light appearance.
  static const light = MorphProgressStyle();

  /// The dark appearance, from the iOS dark system colors.
  static const dark = MorphProgressStyle(
    trackColor: Color(0x5C787880),
    progressColor: Color(0xFF0091FF),
  );

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphProgressStyle resolve(
    BuildContext context,
    MorphProgressStyle? explicit,
  ) => morphResolveStyle(
    context,
    explicit,
    themed: (theme) => theme.progress,
    light: light,
    dark: dark,
  );
}

/// The two looks of a [MorphProgressView], after UIProgressView.Style.
enum MorphProgressViewStyle {
  /// A capsule track, 4 points tall.
  standard,

  /// A thinner bar without a visible track, for toolbars.
  bar,
}

/// The motion of an iOS 27 UIProgressView's fill.
///
/// An animated change runs linearly for as many seconds as the progress
/// changes (a change of 0.6 takes 0.6 seconds), and a change that shows
/// or hides the fill takes at least [fadeDuration], over which the fill
/// fades in or out: an empty progress view shows no fill. The fill is
/// never narrower than [minFillWidth]. A change while another runs adds
/// on top of it, as UIKit's additive animations do, so the fill never
/// jumps. Times are seconds and widths pixels.
class MorphProgressMotion {
  /// Creates a motion resting at [value].
  MorphProgressMotion({required double value}) : _value = value.clamp(0.0, 1.0);

  /// The narrowest the fill gets, at a progress of 0 or just above.
  static const double minFillWidth = 8;

  /// The shortest change that shows or hides the fill.
  static const double fadeDuration = 0.2;

  /// Seconds per unit of progress change.
  static const double secondsPerProgress = 1;

  double _value;
  final List<_Additive> _fill = [];
  final List<_Additive> _alpha = [];
  double _now = 0;

  /// The progress the fill is heading to, 0 to 1.
  double get value => _value;

  /// The time the motion was last advanced to.
  double get time => _now;

  /// Whether no change is running.
  bool get isSettled => _fill.isEmpty && _alpha.isEmpty;

  /// Sets the progress to [value] at time [t], animated or at once.
  void setValue(double t, double value, {bool animated = true}) {
    advance(t);
    final next = value.clamp(0.0, 1.0);
    if (next == _value) return;
    final previous = _value;
    _value = next;
    if (!animated) {
      _fill.clear();
      _alpha.clear();
      return;
    }
    final flips = (previous == 0) != (next == 0);
    var duration = (next - previous).abs() * secondsPerProgress;
    if (flips) duration = math.max(duration, fadeDuration);
    if (duration <= 0) return;
    _fill.add(_Additive(t, duration, previous, next));
    if (flips) {
      _alpha.add(
        _Additive(t, duration, _opacityOf(previous), _opacityOf(next)),
      );
    }
  }

  /// Advances the motion to time [t].
  void advance(double t) {
    if (t < _now) return;
    _now = t;
    _fill.removeWhere((_Additive a) => a.isDone(t));
    _alpha.removeWhere((_Additive a) => a.isDone(t));
  }

  static double _opacityOf(double value) => value > 0 ? 1 : 0;

  /// The progress the fill shows at time [t], 0 to 1.
  double shownValue(double t) {
    var v = _value;
    for (final a in _fill) {
      v += a.offset(t, (double x) => x);
    }
    return v.clamp(0.0, 1.0);
  }

  /// The width of the fill on a track [trackWidth] wide at time [t].
  double fillWidth(double t, double trackWidth) {
    double widthOf(double value) =>
        math.min(trackWidth, math.max(minFillWidth, value * trackWidth));
    var w = widthOf(_value);
    for (final a in _fill) {
      w += a.offset(t, widthOf);
    }
    return w.clamp(math.min(minFillWidth, trackWidth), trackWidth);
  }

  /// The opacity of the fill at time [t].
  double fillOpacity(double t) {
    var a = _opacityOf(_value);
    for (final s in _alpha) {
      a += s.offset(t, (double x) => x);
    }
    return a.clamp(0.0, 1.0);
  }
}

class _Additive {
  _Additive(this.start, this.duration, this.from, this.to);

  final double start;
  final double duration;
  final double from;
  final double to;

  bool isDone(double t) => t >= start + duration;

  double offset(double t, double Function(double) map) {
    final f = ((t - start) / duration).clamp(0.0, 1.0);
    return (map(from) - map(to)) * (1 - f);
  }
}

/// A progress bar that looks and animates like iOS 27's UIProgressView.
///
/// The track is a capsule [MorphProgressViewStyle.standard] 4 points
/// tall, or a 2.67 point bar without a track; the fill grows from the
/// leading edge, so it starts at the right in a right-to-left context.
/// See [MorphProgressMotion] for the measured animation: linear, one
/// second per unit of progress, with the fill fading out at 0.
class MorphProgressView extends StatefulWidget {
  /// Creates a progress view.
  const MorphProgressView({
    required this.value,
    this.animated = true,
    this.viewStyle = MorphProgressViewStyle.standard,
    this.progressColor,
    this.trackColor,
    this.style,
    this.semanticLabel,
    super.key,
  });

  /// The progress, 0 to 1.
  final double value;

  /// Whether a change of [value] animates.
  final bool animated;

  /// The shape of the bar.
  final MorphProgressViewStyle viewStyle;

  /// The fill of the filled part, overriding [style].
  final Color? progressColor;

  /// The fill of the track, overriding [style].
  final Color? trackColor;

  /// The look of the bar; null resolves it from the theme.
  final MorphProgressStyle? style;

  /// The label screen readers announce for the bar.
  final String? semanticLabel;

  /// The height of a [MorphProgressViewStyle.standard] bar.
  static const double standardHeight = 4;

  /// The height of a [MorphProgressViewStyle.bar] bar.
  static const double barHeight = 2.67;

  @override
  State<MorphProgressView> createState() => _MorphProgressViewState();
}

class _MorphProgressViewState extends State<MorphProgressView>
    with
        SingleTickerProviderStateMixin<MorphProgressView>,
        MorphClock<MorphProgressView> {
  late final MorphProgressMotion _motion = MorphProgressMotion(
    value: widget.value,
  );

  @override
  void advanceMotion(double t) => _motion.advance(t);

  @override
  bool get motionSettled => _motion.isSettled;

  @override
  void didUpdateWidget(MorphProgressView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _motion.value) {
      final animated = widget.animated && !morphReducedMotionOf(context);
      _motion.setValue(clock, widget.value, animated: animated);
      if (animated) wake();
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphProgressStyle.resolve(context, widget.style);
    final height = switch (widget.viewStyle) {
      MorphProgressViewStyle.standard => MorphProgressView.standardHeight,
      MorphProgressViewStyle.bar => MorphProgressView.barHeight,
    };
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final percent = '${(widget.value.clamp(0.0, 1.0) * 100).round()}%';
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      value: percent,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _ProgressPainter(
            state: this,
            track: widget.viewStyle == MorphProgressViewStyle.standard
                ? widget.trackColor ?? style.trackColor
                : null,
            fill: widget.progressColor ?? style.progressColor,
            rtl: rtl,
          ),
        ),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter({
    required this.state,
    required this.track,
    required this.fill,
    required this.rtl,
  }) : super(repaint: state.frames);

  final _MorphProgressViewState state;
  final Color? track;
  final Color fill;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final trackColor = track;
    if (trackColor != null) {
      final paint = Paint();
      paint.color = trackColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, radius),
        paint,
      );
    }
    final motion = state._motion;
    final t = motion.time;
    final opacity = motion.fillOpacity(t);
    if (opacity <= 0) return;
    final width = motion.fillWidth(t, size.width);
    final left = rtl ? size.width - width : 0.0;
    final paint = Paint();
    paint.color = fill.withValues(alpha: fill.a * opacity);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 0, width, size.height),
        radius,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter oldDelegate) => true;
}
