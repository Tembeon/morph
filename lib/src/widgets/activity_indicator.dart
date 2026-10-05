import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

/// The look of a [MorphActivityIndicator].
@immutable
class MorphActivityIndicatorStyle {
  /// Creates a style; the default is the iOS light appearance.
  const MorphActivityIndicatorStyle({this.color = const Color(0x993C3C43)});

  /// The color of the spokes at full strength: secondaryLabel.
  final Color color;

  /// The light appearance.
  static const light = MorphActivityIndicatorStyle();

  /// The dark appearance: the dark secondaryLabel. Measured on an iPhone
  /// 16 Pro (iOS 27.0.1): the head spoke renders 120, 120, 125 on black,
  /// the same coverage of 0xEBEBF5 as the light head's of 0x3C3C43.
  static const dark = MorphActivityIndicatorStyle(color: Color(0x99EBEBF5));

  /// Resolves [explicit], then the ambient [MorphWidgetsTheme], then the
  /// table for the ambient brightness.
  static MorphActivityIndicatorStyle resolve(
    BuildContext context,
    MorphActivityIndicatorStyle? explicit,
  ) => morphResolveStyle(
    context,
    explicit,
    themed: (theme) => theme.activityIndicator,
    light: light,
    dark: dark,
  );
}

/// The two sizes of a [MorphActivityIndicator], after
/// UIActivityIndicatorView.Style.
enum MorphActivityIndicatorSize {
  /// A 20 point spinner.
  medium,

  /// A 37 point spinner.
  large,
}

/// The frames of iOS 27's UIActivityIndicatorView.
///
/// Eight rounded spokes; a bright head travels clockwise around them,
/// one full turn per [loopDuration] (`_UIActivityIndicatorSettings
/// .fullLoopDuration`). The animation is a sequence of [frameCount]
/// images, so the head moves in half-spoke steps. Behind the head the
/// strength falls linearly over [tailSpokes] spokes to [restStrength];
/// between two images a spoke takes the strength of its fractional
/// distance behind the head, and the spoke the head is about to reach
/// stays at rest.
/// Strengths are read from the rendered pixels of the simulator: the head
/// draws the spoke color at 84 percent of its own opacity.
abstract final class MorphActivityIndicatorFrames {
  /// Seconds per full turn of the head.
  static const double loopDuration = 0.8;

  /// Images per turn.
  static const int frameCount = 16;

  /// Spokes around the circle.
  static const int spokes = 8;

  /// Spokes behind the head over which the strength falls.
  static const int tailSpokes = 4;

  /// The strength of the head, as a fraction of the color's opacity.
  static const double headStrength = 0.843;

  /// The strength of the spokes away from the head.
  static const double restStrength = 0.275;

  /// The image shown at time [t] seconds.
  static int frameAt(double t) {
    final f = (t / loopDuration * frameCount).floor() % frameCount;
    return f < 0 ? f + frameCount : f;
  }

  /// The strength of spoke [spoke] (0 at the top, counted clockwise) in
  /// image [frame].
  static double strength(int spoke, int frame) {
    final head = frame / (frameCount / spokes);
    var behind = (head - spoke) % spokes;
    if (behind < 0) behind += spokes;
    return _ramp(behind);
  }

  static double _ramp(double behind) {
    if (behind >= tailSpokes) return restStrength;
    return headStrength - (headStrength - restStrength) * behind / tailSpokes;
  }
}

/// A spinner that looks and turns like iOS 27's UIActivityIndicatorView.
///
/// See [MorphActivityIndicatorFrames] for the measured animation. A
/// stopped indicator is hidden when [hidesWhenStopped] is set and shows
/// its first image otherwise; with the platform's reduced motion on, it
/// keeps turning, as UIKit's does.
class MorphActivityIndicator extends StatefulWidget {
  /// Creates an activity indicator.
  const MorphActivityIndicator({
    this.animating = true,
    this.hidesWhenStopped = true,
    this.size = MorphActivityIndicatorSize.medium,
    this.color,
    this.style,
    this.semanticLabel = 'In progress',
    super.key,
  });

  /// Whether the spinner turns.
  final bool animating;

  /// Whether a stopped spinner is hidden.
  final bool hidesWhenStopped;

  /// The spinner's size.
  final MorphActivityIndicatorSize size;

  /// The color of the spokes, overriding [style].
  final Color? color;

  /// The look of the spinner; null resolves it from the theme.
  final MorphActivityIndicatorStyle? style;

  /// The label screen readers announce while it turns.
  final String semanticLabel;

  /// The box of a spinner of [size], with the spoke width and the inner
  /// and outer radius of each spoke, caps included.
  static ({double box, double width, double inner, double outer}) metrics(
    MorphActivityIndicatorSize size,
  ) => switch (size) {
    MorphActivityIndicatorSize.medium => (
      box: 20,
      width: 2.5,
      inner: 3.33,
      outer: 10,
    ),
    MorphActivityIndicatorSize.large => (
      box: 37,
      width: 5,
      inner: 5.33,
      outer: 17.33,
    ),
  };

  @override
  State<MorphActivityIndicator> createState() => _MorphActivityIndicatorState();
}

class _MorphActivityIndicatorState extends State<MorphActivityIndicator>
    with
        SingleTickerProviderStateMixin<MorphActivityIndicator>,
        MorphClock<MorphActivityIndicator> {
  final ValueNotifier<int> _image = ValueNotifier<int>(0);
  double _startedAt = 0;

  @override
  void dispose() {
    _image.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.animating) wake();
  }

  @override
  void advanceMotion(double t) {
    if (!widget.animating) return;
    _image.value = MorphActivityIndicatorFrames.frameAt(t - _startedAt);
  }

  @override
  bool get motionSettled => !widget.animating;

  @override
  double? get motionWakeTime {
    const period =
        MorphActivityIndicatorFrames.loopDuration /
        MorphActivityIndicatorFrames.frameCount;
    final shown = clock - _startedAt;
    return _startedAt + ((shown / period).floor() + 1) * period;
  }

  @override
  void didUpdateWidget(MorphActivityIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animating != oldWidget.animating) {
      _image.value = 0;
      if (widget.animating) {
        _startedAt = clock;
        wake();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = MorphActivityIndicatorStyle.resolve(context, widget.style);
    final m = MorphActivityIndicator.metrics(widget.size);
    final hidden = !widget.animating && widget.hidesWhenStopped;
    return Semantics(
      container: true,
      label: widget.animating ? widget.semanticLabel : null,
      child: SizedBox.square(
        dimension: m.box,
        child: hidden
            ? null
            : RepaintBoundary(
                child: CustomPaint(
                  painter: _SpinnerPainter(
                    state: this,
                    color: widget.color ?? style.color,
                    size: widget.size,
                  ),
                ),
              ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({
    required this.state,
    required this.color,
    required this.size,
  }) : super(repaint: state._image) {
    final metrics = MorphActivityIndicator.metrics(size);
    _paints = [
      for (
        var frame = 0;
        frame < MorphActivityIndicatorFrames.frameCount;
        frame++
      )
        [
          for (var i = 0; i < MorphActivityIndicatorFrames.spokes; i++)
            _paint(
              color,
              metrics.width,
              MorphActivityIndicatorFrames.strength(i, frame),
            ),
        ],
    ];
  }

  static Paint _paint(Color color, double width, double strength) {
    final paint = Paint();
    paint.color = color.withValues(alpha: color.a * strength);
    paint.strokeWidth = width;
    paint.strokeCap = StrokeCap.round;
    return paint;
  }

  late final List<List<Paint>> _paints;

  final _MorphActivityIndicatorState state;
  final Color color;
  final MorphActivityIndicatorSize size;

  @override
  void paint(Canvas canvas, Size box) {
    final m = MorphActivityIndicator.metrics(size);
    final frame = state.widget.animating ? state._image.value : 0;
    final center = box.center(Offset.zero);
    final half = m.width / 2;
    for (var i = 0; i < MorphActivityIndicatorFrames.spokes; i++) {
      final angle = i * 2 * math.pi / MorphActivityIndicatorFrames.spokes;
      final dir = Offset(math.sin(angle), -math.cos(angle));
      final paint = _paints[frame][i];
      canvas.drawLine(
        center + dir * (m.inner + half),
        center + dir * (m.outer - half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.color != color ||
      oldDelegate.size != size;
}
