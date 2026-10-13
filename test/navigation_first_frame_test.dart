import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/navigation_motion.dart';
import 'package:morph/src/widgets/navigation_stack.dart';

void main() {
  const period = 1 / 60;
  SpringSimulation spring() => SpringSimulation(
    MorphNavigationTuning.pushSpring.description,
    0,
    1,
    MorphNavigationTuning.pushVelocity,
  );

  test('a push without a slow first frame moves as its spring', () {
    final inner = spring();
    final start = MorphFirstFrameStart(spring(), period: period);
    expect(start.x(0), inner.x(0));
    expect(start.x(0), inner.x(0));
    for (var i = 1; i < 30; i++) {
      expect(start.x(i * period), closeTo(inner.x(i * period), 1e-12));
    }
  });

  test('a slow first frame delays the push instead of skipping its steps', () {
    final inner = spring();
    final start = MorphFirstFrameStart(spring(), period: period);
    expect(start.x(0), inner.x(0));
    // The frame that builds the page: the start of the motion.
    expect(start.x(0), inner.x(0));
    // The page took three periods; the next frame is one step in.
    expect(start.x(3 * period), closeTo(inner.x(period), 1e-12));
    expect(start.x(4 * period), closeTo(inner.x(2 * period), 1e-12));
    expect(start.dx(4 * period), closeTo(inner.dx(2 * period), 1e-12));
    expect(start.isDone(3 + 2 * period), inner.isDone(3));
  });
}
