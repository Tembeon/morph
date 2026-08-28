import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

/// Feeds [squash] a trajectory x(t) sampled at [fps] for [seconds],
/// returning the final deviation.
double run(
  MorphSquash squash,
  Offset Function(double t) trajectory, {
  double seconds = 0.5,
  double fps = 120,
  double t0 = 0,
}) {
  final double dt = 1 / fps;
  double deviation = 0;
  for (double t = t0; t < t0 + seconds; t += dt) {
    deviation = squash.track(trajectory(t), now: t, dt: dt);
  }
  return deviation;
}

void main() {
  test('constant velocity leaves the body undeformed', () {
    final MorphSquash squash = MorphSquash();
    final double deviation = run(squash, (double t) => Offset(400 * t, 0));
    expect(deviation.abs(), lessThan(0.005));
  });

  test('gaining speed stretches, braking squashes', () {
    final MorphSquash squash = MorphSquash();
    // Accelerating rightward: x = a t^2 / 2.
    final double launch = run(
      squash,
      (double t) => Offset(2000 * t * t / 2, 0),
    );
    expect(launch, greaterThan(0.02));

    squash.reset();
    // Arriving: fast, then decelerating to rest.
    final double arrive = run(
      squash,
      (double t) => Offset(1000 * t - 2000 * t * t / 2, 0),
    );
    expect(arrive, lessThan(-0.02));
  });

  test('downward acceleration reads as the opposite axis', () {
    final MorphSquash squash = MorphSquash();
    final double deviation = run(
      squash,
      (double t) => Offset(0, 2000 * t * t / 2),
    );
    expect(deviation, lessThan(-0.02));
  });

  test('the deviation is clamped for visual stability', () {
    final MorphSquash squash = MorphSquash(responseTime: 0);
    final double deviation = run(
      squash,
      (double t) => Offset(1e6 * t * t / 2, 0),
    );
    expect(deviation, squash.maxDeviation);
  });

  test('responseTime eases the answer instead of snapping to it', () {
    // The same accelerating trajectory, sampled identically: the eased
    // tracker must lag the frame-locked one early on.
    final MorphSquash locked = MorphSquash(responseTime: 0);
    final MorphSquash eased = MorphSquash();
    Offset trajectory(double t) => Offset(3000 * t * t / 2, 0);
    final double lockedEarly = run(locked, trajectory, seconds: 0.1);
    final double easedEarly = run(eased, trajectory, seconds: 0.1);
    expect(easedEarly, greaterThan(0));
    expect(easedEarly, lessThan(lockedEarly * 0.8));
  });

  test('a stopped body unsquashes on its own and settles', () {
    final MorphSquash squash = MorphSquash();
    final double moving = run(
      squash,
      (double t) => Offset(3000 * t * t / 2, 0),
    );
    expect(moving.abs(), greaterThan(0.02));
    // Stationary samples AT the final position (a teleport would read
    // as its own violent acceleration): the window ages the motion out
    // and the ease drains the deviation - no separate animation.
    run(squash, (double t) => const Offset(375, 0), t0: 0.5, seconds: 1.5);
    expect(squash.deviation.abs(), lessThan(0.001));
    expect(squash.isSettled, isTrue);
  });

  test('reset drops stale motion', () {
    final MorphSquash squash = MorphSquash();
    run(squash, (double t) => Offset(3000 * t * t / 2, 0));
    squash.reset();
    expect(squash.deviation, 0);
    expect(squash.isSettled, isTrue);
    expect(squash.scaleX, 1);
    expect(squash.scaleY, 1);
  });
}
