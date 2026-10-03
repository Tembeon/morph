import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';
import 'package:morph/src/widgets/flex_integrator.dart';
import 'package:morph/src/spring.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';

/// Paints the flat look of a small lens lifted by [progress], from 0 at
/// rest to 1 fully lifted: the resting [color] fades to a fifth of its
/// opacity and a rim appears, dark on a light appearance and light on a
/// dark one, so the clear lens stays visible on either.
@internal
void paintMorphSmallLens(
  Canvas canvas,
  RRect shape, {
  required Color color,
  required double progress,
  required Brightness brightness,
}) {
  final fill = Paint();
  fill.color = color.withValues(alpha: color.a * (1 - 0.8 * progress));
  canvas.drawRRect(shape, fill);
  if (progress <= 0.01) return;
  final rim = Paint();
  rim.style = PaintingStyle.stroke;
  rim.strokeWidth = 0.75;
  rim.color = switch (brightness) {
    Brightness.light => Color.fromRGBO(0, 0, 0, 0.18 * progress),
    Brightness.dark => Color.fromRGBO(255, 255, 255, 0.28 * progress),
  };
  canvas.drawRRect(shape.deflate(0.4), rim);
}

/// The small liquid lens of a switch knob or a slider thumb.
///
/// A touch lifts it on a slightly bouncy spring (it grows and turns from
/// solid white to clear glass); the landing waits at least [hangTime]
/// after the lift, fades the glass back on a critically damped spring and
/// shrinks the lens on its own underdamped spring, so it dips below its
/// rest size before it settles. While it moves, the lens stretches along
/// its motion in proportion to its acceleration and squashes across it.
///
/// The owner calls [advance] with the frame time and the lens position
/// as a function of time; the stretch filter steps once per frame of
/// [frameRate] in motion time, at the position of each frame. The
/// outputs can be read at any time.
class MorphSmallLens {
  /// Creates a lens that rests at [restSize] and lifts to [liftedSize],
  /// filtering its motion at [frameRate] frames per second.
  MorphSmallLens({
    required this.restSize,
    required this.liftedSize,
    this.frameRate = 120,
  }) : _frames = MorphSubClock(frameRate);

  /// The resting size of the lens.
  final Size restSize;

  /// The size of the fully lifted lens.
  final Size liftedSize;

  /// The frames per second of motion time the stretch filter steps at:
  /// 120 for a ProMotion display, 60 for a 60 Hz one.
  final double frameRate;

  /// Whether the lens moves for Reduce Motion: it never lifts or
  /// stretches and stays a solid knob. This approximates the platform's
  /// behavior; it is not measured.
  bool reducedMotion = false;

  /// The spring that lifts the lens.
  static const liftSpring = MorphSpring(0.27, 0.625);

  /// The spring that fades the glass back to solid on landing.
  static const unliftSpring = MorphSpring(0.4, 1);

  /// The spring that shrinks the lens on landing.
  static const sizeUnliftSpring = MorphSpring(0.48, 0.7);

  /// The spring the stretch follows its target on.
  static const stretchSpring = MorphSpring(0.444, 0.56);

  /// The lift's starting speed, in progress per second.
  static const double liftVelocity = 18;

  /// The shortest time, in seconds, a lifted lens stays lifted.
  static const double hangTime = 0.22;

  /// Stretch per pixel per second squared of acceleration.
  static const double stretchGain = 5e-5;

  final MorphSpringState _progress = MorphSpringState(liftSpring, 0);
  final MorphSpringState _size = MorphSpringState(liftSpring, 0);
  final MorphSpringState _stretch = MorphSpringState(stretchSpring, 1);

  final MorphTimeline _timeline = MorphTimeline();
  final MorphSubClock _frames;
  final MorphFlexIntegrator _flex = MorphFlexIntegrator();
  double _liftStart = -double.infinity;
  double? _previous;

  /// Seconds the size trails the lift progress by: one frame.
  double get sizeLag => _frames.frame;

  /// Whether the lens is lifted or lifting.
  bool get isLifted => _progress.target == 1;

  /// Lifts the lens at time [t].
  void lift(double t) {
    _timeline.clear();
    if (isLifted || reducedMotion) return;
    _liftStart = t;
    _progress.retarget(t, 1, spring: liftSpring);
    _progress.setState(t, _progress.value(t), liftVelocity);
    final at = t + sizeLag;
    _size.retarget(at, 1, spring: liftSpring);
    _size.setState(at, _size.value(at), liftVelocity);
  }

  /// Lands the lens at time [t], or once it has hung for [hangTime].
  void unlift(double t) {
    if (!isLifted) return;
    final at = math.max(t, _liftStart + hangTime);
    if (at <= t) {
      _land(t);
    } else {
      _timeline.clear();
      _timeline.insert(at, _land);
    }
  }

  void _land(double t) {
    _timeline.clear();
    _progress.retarget(t, 0, spring: unliftSpring);
    _size.retarget(t, 0, spring: sizeUnliftSpring);
  }

  /// Advances the lens to time [t]: applies a landing that came due and
  /// steps the stretch filter through every frame since the last call,
  /// reading the lens position at each frame from [position].
  ///
  /// UIKit's filters weigh each frame the same whatever the frame rate, so
  /// the stretch reacts twice as fast at 120 Hz as at 60 Hz.
  void advance(double t, [double Function(double t)? position]) {
    if (position != null) {
      _frames.run(t, (double s) {
        _timeline.runDue(s);
        _sample(s, position(s));
      });
    }
    _timeline.runDue(t);
  }

  void _sample(double t, double position) {
    final previous = _previous ?? position;
    final af = _flex.step(previous, _frames.frame);
    _previous = position;
    _stretch.retarget(t, reducedMotion ? 1 : 1 + stretchGain * af);
  }

  /// The lift progress at time [t]: 0 solid and resting, 1 clear and
  /// lifted; it may overshoot slightly.
  double progress(double t) => _progress.value(t);

  /// The lens size at time [t], stretch excluded.
  Size size(double t) {
    final q = _size.value(t);
    return Size(
      restSize.width + (liftedSize.width - restSize.width) * q,
      restSize.height + (liftedSize.height - restSize.height) * q,
    );
  }

  /// The stretch along the track at time [t].
  double scaleX(double t) => _stretch.value(t);

  /// The squash across the track at time [t].
  double scaleY(double t) => 2 - _stretch.value(t);

  /// Whether the lens is at rest at time [t].
  bool isSettled(double t) =>
      _timeline.isEmpty &&
      _progress.isAtRest(t, 0.002) &&
      _size.isAtRest(t, 0.002) &&
      _stretch.isAtRest(t, 1e-4);
}
