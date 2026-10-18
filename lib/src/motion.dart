import 'package:morph/src/spring.dart';

/// A morph's motion profile: an open and a close [MorphSpring].
///
/// The default, [liquid], is UIKit's own: the progress spring of the
/// iOS 27 liquid morph a glass button runs into its menu, measured on the
/// simulator and on device. It opens on `MorphSpring(0.35, 0.75)` - it
/// overshoots slightly, by about 3 percent - and closes on
/// `MorphSpring(0.49, 0.80)`, which dips about 1.5 percent below zero
/// before it rests. A close during the open retargets with the velocity
/// carried over, exactly as UIKit does.
///
/// Character can only be changed as a whole profile; a mid-flight profile
/// swap retargets the simulation.
class MorphMotion {
  /// Creates a profile from two UIKit-style springs.
  const MorphMotion({
    required this.name,
    required this.openSpring,
    required this.closeSpring,
  });

  /// Profile name, for debugging and toString.
  final String name;

  /// The spring toward the open state.
  final MorphSpring openSpring;

  /// The spring toward the closed state.
  final MorphSpring closeSpring;

  /// UIKit's liquid morph, measured on the simulator and on device.
  static const MorphMotion liquid = MorphMotion(
    name: 'liquid',
    openSpring: MorphSpring(0.35, 0.75),
    closeSpring: MorphSpring(0.49, 0.80),
  );

  /// [liquid] five times slower, for inspecting a transition by eye.
  static const MorphMotion glacial = MorphMotion(
    name: 'glacial',
    openSpring: MorphSpring(1.75, 0.75),
    closeSpring: MorphSpring(2.45, 0.80),
  );

  /// A short critically damped spring both ways, used under reduced
  /// motion.
  static const MorphMotion instant = MorphMotion(
    name: 'instant',
    openSpring: MorphSpring(0.281, 1),
    closeSpring: MorphSpring(0.281, 1),
  );

  // Value equality, because ambient plumbing compares profiles by ==:
  // MorphTheme equality feeds ThemeData change detection, and the
  // controller's motion setter short-circuits on an equal profile.
  @override
  bool operator ==(Object other) {
    return other is MorphMotion &&
        other.name == name &&
        other.openSpring == openSpring &&
        other.closeSpring == closeSpring;
  }

  @override
  int get hashCode => Object.hash(name, openSpring, closeSpring);

  @override
  String toString() => 'MorphMotion.$name';
}
