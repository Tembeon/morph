import 'package:motor/motor.dart';

import 'package:morph/src/spring.dart';

/// A morph's motion profile: a pair of [Motion]s from the motor package.
///
/// The default, [liquid], is UIKit's own: the progress spring of the
/// iOS 27 liquid morph a glass button runs into its menu, measured on the
/// simulator and on device. It opens on `MorphSpring(0.35, 0.75)` - it
/// overshoots slightly, by about 3 percent - and closes on
/// `MorphSpring(0.49, 0.80)`, which dips about 1.5 percent below zero
/// before it rests. A close during the open retargets with the velocity
/// carried over, exactly as UIKit does.
///
/// Character can only be changed as a whole profile (a mid-flight
/// profile swap retargets the simulation); custom profiles are built
/// through the public constructor from any Motions (Cupertino presets,
/// Material tokens, curves, custom springs), or through
/// [MorphMotion.springs] from UIKit-style [MorphSpring]s.
///
/// Contract constraints:
///  - snapToEnd on springs must stay false - the handoff latch lives on
///    the zero crossing.
class MorphMotion {
  /// Creates a custom profile from any two Motions.
  const MorphMotion({
    required this.name,
    required Motion this._openMotion,
    required Motion this._closeMotion,
  }) : openSpring = null,
       closeSpring = null;

  /// Creates a profile from two UIKit-style springs; [openMotion] and
  /// [closeMotion] are their [MorphSpring.toMotion].
  const MorphMotion.springs({
    required this.name,
    required MorphSpring open,
    required MorphSpring close,
  }) : _openMotion = null,
       _closeMotion = null,
       openSpring = open,
       closeSpring = close;

  /// Profile name, for debugging and toString.
  final String name;

  final Motion? _openMotion;
  final Motion? _closeMotion;

  /// The open spring this profile was built from, or null when it was
  /// built from arbitrary Motions.
  final MorphSpring? openSpring;

  /// The close spring this profile was built from, or null when it was
  /// built from arbitrary Motions.
  final MorphSpring? closeSpring;

  /// The contract violation of this profile, or null when it is valid;
  /// [MorphController] checks it in an assert whenever a profile is
  /// installed. The one hard rule: a spring [closeMotion] must keep
  /// snapToEnd false - the handoff latch fires on the close spring's
  /// zero crossing, so snapping to the end would clip it. The open may
  /// overshoot, as UIKit's does.
  String? get debugContractViolation {
    final Motion close = closeMotion;
    if (close is SpringMotion && close.snapToEnd) {
      return 'MorphMotion "$name": closeMotion has snapToEnd: true. '
          'The handoff latch fires on the close spring\'s zero crossing - '
          'snapToEnd clips it. Recreate the Motion with snapToEnd: false '
          '(the default).';
    }
    return null;
  }

  /// Drives open retargets. It may overshoot 1: the geometry stretches
  /// past the target and settles back.
  Motion get openMotion => openSpring?.toMotion() ?? _openMotion!;

  /// Drives close retargets; the handoff latch fires on its first zero
  /// crossing.
  Motion get closeMotion => closeSpring?.toMotion() ?? _closeMotion!;

  /// UIKit's liquid morph, measured on iOS 27: the default profile.
  ///
  /// Open is the morph's eject spring (0.5 s, damping ratio 0.75) and
  /// close its absorb spring (0.7 s, 0.8), both at the morph's speed of
  /// 0.7, which UIKit applies by dividing time.
  static const MorphMotion liquid = MorphMotion.springs(
    name: 'liquid',
    open: MorphSpring(0.35, 0.75),
    close: MorphSpring(0.49, 0.80),
  );

  /// [liquid] five times slower: the same springs with every response
  /// times five, a magnifier for the eye to inspect the flight
  /// and the landing frame by frame. Not a design choice of its own.
  static const MorphMotion glacial = MorphMotion.springs(
    name: 'glacial',
    open: MorphSpring(1.75, 0.75),
    close: MorphSpring(2.45, 0.80),
  );

  /// ~0.28s, critically damped both ways: reduced motion and tests.
  static const MorphMotion instant = MorphMotion(
    name: 'instant',
    openMotion: CupertinoMotion.smooth(duration: Duration(milliseconds: 281)),
    closeMotion: CupertinoMotion.smooth(duration: Duration(milliseconds: 281)),
  );

  /// The built-in profiles.
  static const List<MorphMotion> values = <MorphMotion>[
    liquid,
    glacial,
    instant,
  ];

  // Value equality, because ambient plumbing compares profiles by ==:
  // MorphTheme equality feeds ThemeData change detection, and the
  // controller's motion setter short-circuits on an equal profile. An
  // identity-compared runtime-built profile would make every theme
  // rebuild "a change" and every re-install a spurious retarget.
  @override
  bool operator ==(Object other) {
    return other is MorphMotion &&
        other.name == name &&
        other.openMotion == openMotion &&
        other.closeMotion == closeMotion;
  }

  @override
  int get hashCode => Object.hash(name, openMotion, closeMotion);

  @override
  String toString() => 'MorphMotion.$name';
}
