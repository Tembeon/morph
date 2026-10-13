import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/flex_interaction.dart';
import 'package:morph/src/widgets/flex_spec.dart';
import 'package:morph/src/widgets/menu_motion.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/src/widgets/timeline.dart';

const _eps = 1e-12;

MorphFlexValues _targets(
  Size size,
  Offset down,
  Offset at, {
  bool lift = true,
  bool stretch = true,
  MorphFlexSpec? spec,
}) => MorphFlexInteraction.dynamicTargets(
  spec: spec ?? MorphFlexSpec.forSize(size),
  size: size,
  translation: at - down,
  inBounds:
      Offset(at.dx.clamp(0.0, size.width), at.dy.clamp(0.0, size.height)) -
      down,
  lift: lift,
  stretch: stretch,
);

void main() {
  group('dynamic targets', () {
    const size = Size(120, 44);
    final spec = MorphFlexSpec.forSize(size);
    final s = (120 + spec.liftScalePoints) / 120;
    final threshold = spec.scaleDistanceThreshold;
    const down = Offset(60, 22);

    test('a still finger lifts both sides by the lift over the long side', () {
      final v = _targets(size, down, down);
      expect(v.scaleX, moreOrLessEquals(s, epsilon: _eps));
      expect(v.scaleY, moreOrLessEquals(s, epsilon: _eps));
      expect(v.driftX, 0);
      expect(v.driftY, 0);
      expect(s, moreOrLessEquals(136 / 120, epsilon: _eps));
    });

    test('portrait and landscape lift by the same long side', () {
      const tall = Size(44, 120);
      final v = _targets(tall, const Offset(22, 60), const Offset(22, 60));
      expect(v.scaleX, moreOrLessEquals(s, epsilon: _eps));
      expect(v.scaleY, moreOrLessEquals(s, epsilon: _eps));
    });

    test('travel inside counts a quarter of the threshold', () {
      final v = _targets(size, down, down + const Offset(40, 0));
      final k = 40 / (4 * threshold);
      expect(v.scaleX, moreOrLessEquals(s + k, epsilon: _eps));
      expect(v.scaleY, moreOrLessEquals(s - k, epsilon: _eps));
      expect(v.driftX, moreOrLessEquals(120 * k, epsilon: _eps));
      expect(v.driftY, 0);
    });

    test('travel beyond the edge counts in full, toward the finger', () {
      final v = _targets(size, down, down - const Offset(150, 0));
      final k = 60 / (4 * threshold) + 90 / threshold;
      expect(v.scaleX, moreOrLessEquals(s + k, epsilon: _eps));
      expect(v.scaleY, moreOrLessEquals(s - k, epsilon: _eps));
      expect(v.driftX, moreOrLessEquals(-120 * k, epsilon: _eps));
    });

    test('the edge is the boundary between the two rates', () {
      final at = _targets(size, down, down + const Offset(60, 0));
      final past = _targets(size, down, down + const Offset(61, 0));
      expect(at.driftX, moreOrLessEquals(120 * 60 / (4 * threshold)));
      expect(
        past.driftX - at.driftX,
        moreOrLessEquals(120 / threshold, epsilon: 1e-9),
      );
    });

    test('vertical travel stretches the height and drifts by it', () {
      final v = _targets(size, down, down + const Offset(0, 50));
      final k = 22 / (4 * threshold) + 28 / threshold;
      expect(v.scaleY, moreOrLessEquals(s + k, epsilon: _eps));
      expect(v.scaleX, moreOrLessEquals(s - k, epsilon: _eps));
      expect(v.driftY, moreOrLessEquals(44 * k, epsilon: _eps));
      expect(v.driftX, 0);
    });

    test('a diagonal drag combines both axes as written', () {
      final v = _targets(size, down, down + const Offset(100, -40));
      final kx = 60 / (4 * threshold) + 40 / threshold;
      final ky = 22 / (4 * threshold) + 18 / threshold;
      expect(v.scaleX, moreOrLessEquals(s + kx - ky, epsilon: _eps));
      expect(v.scaleY, moreOrLessEquals(s - kx + ky, epsilon: _eps));
      expect(v.driftY, moreOrLessEquals(-44 * ky, epsilon: _eps));
    });

    test('lift and stretch switch off independently', () {
      final noLift = _targets(
        size,
        down,
        down + const Offset(40, 0),
        lift: false,
      );
      expect(noLift.scaleX, moreOrLessEquals(1 + 40 / (4 * threshold)));
      final noStretch = _targets(
        size,
        down,
        down + const Offset(40, 0),
        stretch: false,
      );
      expect(noStretch.scaleX, moreOrLessEquals(s, epsilon: _eps));
      expect(noStretch.driftX, 0);
    });

    test('an empty surface or a zero threshold does not stretch', () {
      expect(
        _targets(Size.zero, Offset.zero, const Offset(10, 10)),
        MorphFlexInteraction.rest,
      );
      final loupe = MorphFlexSpec.loupeForSize(const Size(60, 40));
      final v = _targets(
        const Size(60, 40),
        const Offset(30, 20),
        const Offset(90, 20),
        spec: loupe,
      );
      expect(v.scaleX, 1);
      expect(v.driftX, 0);
    });

    test('no travel stretches nothing whatever the clamp says', () {
      expect(MorphFlexInteraction.stretchOf(0, 12, 6000), 0);
      expect(MorphFlexInteraction.stretchOf(-12, -12, 6000), 3 / 6000);
    });
  });

  group('movement', () {
    test('bounds take the movement points within the scale bounds', () {
      final spec = MorphFlexSpec.forSize(const Size(120, 44));
      final narrow = MorphFlexInteraction.movementBounds(spec, 50);
      expect(narrow.low, 0.9);
      expect(narrow.high, 1.1);
      final wide = MorphFlexInteraction.movementBounds(spec, 200);
      expect(wide.low, moreOrLessEquals(190 / 200, epsilon: _eps));
      expect(wide.high, moreOrLessEquals(210 / 200, epsilon: _eps));
      final edge = MorphFlexInteraction.movementBounds(spec, 100);
      expect(edge.low, moreOrLessEquals(0.9, epsilon: _eps));
      expect(edge.high, moreOrLessEquals(1.1, epsilon: _eps));
    });

    test('the soft clamp eases into a third of the range beyond', () {
      double f(double v) => MorphFlexInteraction.softClamp(v, 0.9, 1.1);
      expect(f(1.05), 1.05);
      expect(f(1.1), 1.1);
      expect(f(0.9), 0.9);
      const h = 1e-7;
      expect((f(1.1 + h) - f(1.1)) / h, moreOrLessEquals(0.55, epsilon: 1e-5));
      expect((f(0.9) - f(0.9 - h)) / h, moreOrLessEquals(0.55, epsilon: 1e-5));
      expect(f(100), moreOrLessEquals(1.1 + 0.2 / 3, epsilon: 1e-9));
      expect(f(-100), moreOrLessEquals(0.9 - 0.2 / 3, epsilon: 1e-9));
      expect(f(1.3) - 1.1, moreOrLessEquals(0.9 - f(0.7), epsilon: 1e-12));
    });

    test('speeding up grows the surface along its motion, trailing behind', () {
      final spec = MorphFlexSpec.loupeForSize(const Size(80, 28));
      const size = Size(80, 28);
      final n = spec.movementNormalizationFactor;
      const m = 0.2;
      final v = MorphFlexInteraction.withMovement(
        MorphFlexInteraction.rest,
        spec: spec,
        size: size,
        acceleration: Offset(m * n, 0),
        velocity: const Offset(-30, 0),
      );
      final x = MorphFlexInteraction.movementBounds(spec, 80);
      final y = MorphFlexInteraction.movementBounds(spec, 28);
      final along = 1 + m * (x.high - 1);
      expect(v.scaleX, moreOrLessEquals(along, epsilon: _eps));
      expect(v.scaleY, moreOrLessEquals(1 + m * (y.low - 1), epsilon: _eps));
      expect(v.driftX, moreOrLessEquals(-(1 - along) * 40, epsilon: _eps));
      expect(v.driftY, 0);
    });

    test('vertical movement swaps the axes', () {
      final spec = MorphFlexSpec.loupeForSize(const Size(40, 40));
      const size = Size(40, 40);
      final n = spec.movementNormalizationFactor;
      final v = MorphFlexInteraction.withMovement(
        MorphFlexInteraction.rest,
        spec: spec,
        size: size,
        acceleration: Offset(0, 0.3 * n),
        velocity: const Offset(0, 5),
      );
      final b = MorphFlexInteraction.movementBounds(spec, 40);
      final along = 1 + 0.3 * (b.high - 1);
      expect(v.scaleY, moreOrLessEquals(along, epsilon: _eps));
      expect(v.scaleX, moreOrLessEquals(1 + 0.3 * (b.low - 1), epsilon: _eps));
      expect(v.driftY, moreOrLessEquals((1 - along) * 20, epsilon: _eps));
    });

    test('no movement or a NaN leaves the base alone', () {
      final spec = MorphFlexSpec.loupeForSize(const Size(40, 40));
      const base = (scaleX: 1.1, scaleY: 0.9, driftX: 2.0, driftY: -1.0);
      for (final a in [Offset.zero, const Offset(double.nan, double.nan)]) {
        expect(
          MorphFlexInteraction.withMovement(
            base,
            spec: spec,
            size: const Size(40, 40),
            acceleration: a,
            velocity: const Offset(1, 1),
          ),
          base,
        );
      }
    });

    test('a hard acceleration saturates softly', () {
      final spec = MorphFlexSpec.loupeForSize(const Size(80, 28));
      final v = MorphFlexInteraction.withMovement(
        MorphFlexInteraction.rest,
        spec: spec,
        size: const Size(80, 28),
        acceleration: const Offset(1e9, 0),
        velocity: const Offset(1, 0),
      );
      final x = MorphFlexInteraction.movementBounds(spec, 80);
      final y = MorphFlexInteraction.movementBounds(spec, 28);
      expect(
        v.scaleX,
        moreOrLessEquals(x.high + (x.high - x.low) / 3, epsilon: 1e-9),
      );
      expect(
        v.scaleY,
        moreOrLessEquals(y.low - (y.high - y.low) / 3, epsilon: 1e-9),
      );
    });
  });

  group('menu variant', () {
    test('the menu tuning reads the shared equation', () {
      const tuning = MorphMenuTuning.standard;
      const size = Size(250, 250);
      const translation = Offset(-180, 75);
      const inBounds = Offset(-120, 75);
      final a = tuning.flexTargets(
        translation: translation,
        inBounds: inBounds,
        size: size,
        velocity: 900,
        side: -1,
      );
      final b = MorphFlexInteraction.menuTargets(
        spec: tuning.flex,
        inBoundsPoints: tuning.flexInBoundsPoints,
        translation: translation,
        inBounds: inBounds,
        size: size,
        velocity: 900,
        side: -1,
      );
      expect(a, b);
      final kx = (180 - 120 + 40 * 120 / 250) / 6000;
      expect(b.driftX, moreOrLessEquals(-kx * 250, epsilon: _eps));
    });
  });

  group('interaction', () {
    const size = Size(120, 44);

    test('press rides the tracking spring, release the scale spring', () {
      final flex = MorphFlexInteraction(size: size);
      final spec = flex.spec;
      final lift = MorphSpringState(spec.trackingSpring, 1);
      flex.pointerDown(0, const Offset(60, 22));
      lift.retarget(0, flex.liftedScale);
      expect(flex.isActive, isTrue);
      expect(flex.scale(0.1), moreOrLessEquals(lift.value(0.1), epsilon: _eps));
      expect(flex.scaleX(0.1), flex.scaleY(0.1));
      flex.pointerUp(0.3);
      lift.retarget(0.3, 1, spring: spec.scaleSpring);
      expect(flex.scale(0.4), moreOrLessEquals(lift.value(0.4), epsilon: _eps));
      expect(flex.isAtRest(5), isTrue);
    });

    test('a drag stretches and shows the drift at the scale', () {
      final flex = MorphFlexInteraction(size: size);
      flex.pointerDown(0, const Offset(60, 22));
      flex.pointerMove(0.1, const Offset(210, 22));
      final v = flex.values(5);
      final target = flex.targets;
      expect(v.scaleX, moreOrLessEquals(target.scaleX, epsilon: 1e-9));
      expect(
        flex.translation(5).dx,
        moreOrLessEquals(target.driftX * target.scaleX, epsilon: 1e-6),
      );
      expect(flex.scale(5), moreOrLessEquals(flex.liftedScale, epsilon: 1e-9));
    });

    test('a delayed activation waits and a quick release skips it', () {
      final timeline = MorphTimeline(now: 0);
      final flex = MorphFlexInteraction(
        size: size,
        stretches: false,
        activationDelay: 0.05,
        timeline: timeline,
      );
      flex.pointerDown(0, const Offset(60, 22));
      timeline.runDue(0.04);
      expect(flex.isActive, isFalse);
      expect(flex.scale(0.04), 1);
      timeline.runDue(0.05);
      expect(flex.isActive, isTrue);
      flex.pointerUp(0.2);
      final quick = MorphFlexInteraction(size: size, activationDelay: 0.05);
      quick.pointerDown(0, const Offset(60, 22));
      quick.pointerUp(0.02);
      quick.advance(0.1);
      expect(quick.isActive, isFalse);
      expect(quick.scale(0.1), 1);
    });

    test('reduced motion glows but never deforms', () {
      final flex = MorphFlexInteraction(size: size, glows: true);
      flex.reducedMotion = true;
      flex.pointerDown(0, const Offset(60, 22));
      flex.pointerMove(0.05, const Offset(200, 22));
      expect(flex.values(0.2), MorphFlexInteraction.rest);
      expect(flex.glow(0.2), greaterThan(0.99));
    });

    test('the glow fades in under the finger and out after it', () {
      final flex = MorphFlexInteraction(size: size, glows: true);
      flex.pointerDown(0, const Offset(30, 10));
      expect(
        flex.glow(0.023),
        moreOrLessEquals(1 - math.exp(-1), epsilon: 1e-9),
      );
      expect(flex.littleGlowCenter(0.01), const Offset(30, 10));
      flex.pointerUp(0.5);
      expect(flex.littleGlowScale(5), moreOrLessEquals(4, epsilon: 1e-3));
      expect(flex.glow(5), lessThan(1e-3));
      final silent = MorphFlexInteraction(size: size);
      silent.pointerDown(0, Offset.zero);
      expect(silent.glow(0.1), 0);
    });
  });
}
