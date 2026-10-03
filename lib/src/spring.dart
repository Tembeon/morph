import 'package:flutter/physics.dart';
import 'package:motor/motor.dart';

/// A spring in UIKit's vocabulary: a response time and a damping ratio.
///
/// UIKit tunes its springs as `response` (the undamped period, in seconds)
/// and `dampingRatio` (1 is critically damped, below 1 overshoots). With a
/// unit mass that maps to stiffness `(2 pi / response)^2` and damping
/// `4 pi dampingRatio / response`, which is what [description] returns.
class MorphSpring {
  /// Creates a spring from its response time and damping ratio.
  const MorphSpring(this.response, this.dampingRatio);

  /// The undamped period of the spring, in seconds.
  final double response;

  /// The damping ratio; 1 is critically damped.
  final double dampingRatio;

  /// The angular frequency of the undamped spring, in radians per second.
  double get omega => 2 * 3.141592653589793 / response;

  /// The stiffness for a unit mass.
  double get stiffness => omega * omega;

  /// The damping coefficient for a unit mass.
  double get damping => 2 * dampingRatio * omega;

  /// The physical description of this spring for a unit mass.
  SpringDescription get description =>
      SpringDescription(mass: 1, stiffness: stiffness, damping: damping);

  /// This spring as a motor [Motion] with exactly this stiffness and
  /// damping.
  ///
  /// The result is a [SpringMotion] over [description] rather than a
  /// `CupertinoMotion(duration: response, bounce: 1 - dampingRatio)`:
  /// that mapping truncates the duration to whole milliseconds and turns
  /// a damping ratio above 1 into `1 / (2 - dampingRatio)`, so it matches
  /// only some springs.
  Motion toMotion() => SpringMotion(description);

  /// Linearly interpolates response and damping ratio between [a] and [b].
  static MorphSpring lerp(MorphSpring a, MorphSpring b, double t) =>
      MorphSpring(
        a.response + (b.response - a.response) * t,
        a.dampingRatio + (b.dampingRatio - a.dampingRatio) * t,
      );

  @override
  bool operator ==(Object other) =>
      other is MorphSpring &&
      other.response == response &&
      other.dampingRatio == dampingRatio;

  @override
  int get hashCode => Object.hash(response, dampingRatio);

  @override
  String toString() =>
      'MorphSpring(response: $response, dampingRatio: $dampingRatio)';
}
