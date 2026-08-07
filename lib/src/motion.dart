import 'package:motor/motor.dart';

/// A morph's motion profile: a pair of [Motion]s from the motor package
/// plus closeVelocityHint. Character can only be changed as a whole
/// profile (a mid-flight profile swap retargets the simulation); custom
/// profiles are built through the public constructor from any Motions
/// (Cupertino presets, Material tokens, curves, custom springs).
///
/// The direction asymmetry is deliberate, on two axes:
///  - duration: open is faster than close - what unfolds responds
///    instantly; the return is slightly lazier and has character;
///  - damping:
///  - open: critically damped (CupertinoMotion.smooth) - what the user
///    is about to look at unfolds without jitter;
///  - close: underdamped (bounce 0.27, zeta ~0.73) + closeVelocityHint -
///    a "rubbery" return bounce that the button itself finishes playing
///    after the handoff latch.
///
/// The presets are byte-for-byte equivalent to hand-tuned
/// SpringDescriptions: stiffness = (2pi/duration)^2,
/// damping = (1-bounce)*2*sqrt(stiffness).
///
/// Contract constraints:
///  - closeMotion must be able to go below zero (a spring with bounce),
///    otherwise the landing bump of the button simply cannot play
///    (CurvedMotion degrades gracefully: the morph works, no bump);
///  - snapToEnd on springs must stay false - the handoff latch lives on
///    the zero crossing.
class MorphMotion {
  /// Creates a custom profile from any two Motions.
  const MorphMotion({
    required this.name,
    required this.openMotion,
    required this.closeMotion,
    this.closeVelocityHint = 0,
  });

  /// Profile name, for debugging and toString.
  final String name;

  /// The contract violation of this profile, or null when it is valid;
  /// [MorphController] checks it in an assert whenever a profile is
  /// installed. The one hard rule: a spring [closeMotion] must keep
  /// snapToEnd false - the handoff latch fires on the close spring's
  /// zero crossing and the landing bump is the undershoot below zero,
  /// so snapping to the end clips both.
  String? get debugContractViolation {
    final Motion close = closeMotion;
    if (close is SpringMotion && close.snapToEnd) {
      return 'MorphMotion "$name": closeMotion has snapToEnd: true. '
          'The handoff latch fires on the close spring\'s zero crossing '
          'and the landing bump is the undershoot below zero - snapToEnd '
          'clips both. Recreate the Motion with snapToEnd: false (the '
          'default).';
    }
    return null;
  }

  /// Drives open retargets; keep it overshoot-free.
  final Motion openMotion;

  /// Drives close retargets; must be a spring able to cross zero, or
  /// the landing bump cannot play.
  final Motion closeMotion;

  /// A negative velocity injection when closing from rest - it amplifies
  /// the return bounce. The controller applies it UNSCALED; distance
  /// scaling (a far close lands heavier) is the responsibility of
  /// flight.close, the only owner of pixel geometry.
  final double closeVelocityHint;

  /// Magnifier mode: inspect the cascade and the landing frame by frame.
  static const MorphMotion glacial = MorphMotion(
    name: 'glacial',
    openMotion: CupertinoMotion.smooth(duration: Duration(milliseconds: 2800)),
    closeMotion: CupertinoMotion(
      duration: Duration(milliseconds: 4000),
      bounce: 0.27,
    ),
    closeVelocityHint: -0.4,
  );

  /// A relaxed profile for larger surfaces.
  static const MorphMotion slow = MorphMotion(
    name: 'slow',
    openMotion: CupertinoMotion.smooth(duration: Duration(milliseconds: 550)),
    closeMotion: CupertinoMotion(
      duration: Duration(milliseconds: 800),
      bounce: 0.27,
    ),
    closeVelocityHint: -1.6,
  );

  /// The default: open at snappy response tempo, close at a perceptual
  /// duration.
  static const MorphMotion normal = MorphMotion(
    name: 'normal',
    openMotion: CupertinoMotion.smooth(duration: Duration(milliseconds: 400)),
    closeMotion: CupertinoMotion(
      duration: Duration(milliseconds: 550),
      bounce: 0.27,
    ),
    closeVelocityHint: -2.5,
  );

  /// A brisk profile for small controls.
  static const MorphMotion fast = MorphMotion(
    name: 'fast',
    openMotion: CupertinoMotion.smooth(duration: Duration(milliseconds: 280)),
    closeMotion: CupertinoMotion(
      duration: Duration(milliseconds: 400),
      bounce: 0.27,
    ),
    closeVelocityHint: -3.2,
  );

  /// ~0.28s, critically damped both ways: reduced motion and tests.
  static const MorphMotion instant = MorphMotion(
    name: 'instant',
    openMotion: CupertinoMotion.smooth(duration: Duration(milliseconds: 281)),
    closeMotion: CupertinoMotion.smooth(duration: Duration(milliseconds: 281)),
    closeVelocityHint: 0,
  );

  /// The built-in presets.
  static const List<MorphMotion> values = <MorphMotion>[
    glacial,
    slow,
    normal,
    fast,
    instant,
  ];

  @override
  String toString() => 'MorphMotion.$name';
}
