import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/spring.dart';

/// The lift tuning of a liquid selection lens.
///
/// A lens lifts off its track while it is pressed or travelling and
/// settles back when it lands. UIKit keeps a [small] and a [large]
/// variant; the large one lifts and lands without overshoot. Their
/// refraction lives in [optics].
class MorphLensSpec {
  /// Creates a lens spec from explicit values.
  const MorphLensSpec({
    required this.liftSpring,
    required this.unliftSpring,
    this.hangTime = 0.22,
    this.optics = MorphGlassOptics.large,
  });

  /// The spring that lifts the lens.
  final MorphSpring liftSpring;

  /// The spring that lands the lens.
  final MorphSpring unliftSpring;

  /// How long, in seconds, a lifted lens stays up before it may land.
  final double hangTime;

  /// The refraction of the lens.
  final MorphGlassOptics optics;

  /// The variant whose lift overshoots slightly and lands softly.
  static const small = MorphLensSpec(
    liftSpring: MorphSpring(0.27, 0.625),
    unliftSpring: MorphSpring(0.5, 0.7),
    optics: MorphGlassOptics.small,
  );

  /// The variant that lifts and lands critically damped.
  static const large = MorphLensSpec(
    liftSpring: MorphSpring(0.25, 1),
    unliftSpring: MorphSpring(0.25, 1),
  );
}
