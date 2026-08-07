import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';

Future<void> pumpUntilRest(
  WidgetTester tester,
  MorphController controller,
) async {
  for (int i = 0; i < 1600 && controller.isAnimating; i++) {
    await tester.pump(const Duration(milliseconds: 8));
  }
  expect(controller.isAnimating, isFalse, reason: 'the spring did not settle');
}

void main() {
  testWidgets('retarget open->close carries velocity over', (
    WidgetTester tester,
  ) async {
    final MorphController c = MorphController(vsync: const TestVSync());
    addTearDown(c.dispose);

    c.open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final double vBefore = c.velocity;
    expect(vBefore, greaterThan(0));

    c.close();
    expect(c.target, 0);
    expect(c.velocity, moreOrLessEquals(vBefore));
    await pumpUntilRest(tester, c);
  });

  testWidgets('close from rest injects closeVelocityHint', (
    WidgetTester tester,
  ) async {
    final MorphController c = MorphController(vsync: const TestVSync());
    addTearDown(c.dispose);

    c.open();
    await pumpUntilRest(tester, c);
    expect(c.value, 1);
    expect(c.phase, MorphPhase.settled);

    c.close();
    expect(c.velocity, MorphMotion.normal.closeVelocityHint);
    await pumpUntilRest(tester, c);
  });

  testWidgets('the handoff latch fires exactly once per close', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    final MorphController c = MorphController(vsync: const TestVSync());
    addTearDown(c.dispose);
    c.onHandoff = () => calls++;
    c.open();
    expect(c.hasHandedOff, isFalse);
    await pumpUntilRest(tester, c);
    expect(calls, 0);

    c.close();
    await pumpUntilRest(tester, c);
    expect(calls, 1);
    expect(c.hasHandedOff, isTrue);
    expect(c.value, 0);

    c.open();
    expect(c.hasHandedOff, isFalse);
    await pumpUntilRest(tester, c);
    c.close();
    await pumpUntilRest(tester, c);
    expect(calls, 2);
  });

  testWidgets('open has no overshoot on any profile: no jitter on opening', (
    WidgetTester tester,
  ) async {
    for (final MorphMotion motion in MorphMotion.values) {
      final List<double> trace = <double>[];
      final MorphController c = MorphController(
        vsync: const TestVSync(),
        motion: motion,
      );
      addTearDown(c.dispose);
      c
        ..addListener(() => trace.add(c.value))
        ..open();
      await pumpUntilRest(tester, c);
      expect(
        trace.every((double v) => v <= 1.0001),
        isTrue,
        reason:
            'open on $motion overshot the target: ${trace.reduce((double a, double b) => a > b ? a : b)}',
      );
    }
  });

  testWidgets('bounce lives on close only: undershoot dips below zero', (
    WidgetTester tester,
  ) async {
    final List<double> closeTrace = <double>[];
    final MorphController normal = MorphController(vsync: const TestVSync());
    addTearDown(normal.dispose);
    normal.open();
    await pumpUntilRest(tester, normal);
    normal
      ..addListener(() => closeTrace.add(normal.value))
      ..close();
    await pumpUntilRest(tester, normal);
    expect(
      closeTrace.reduce((double a, double b) => a < b ? a : b),
      lessThan(-0.005),
      reason: 'an underdamped close must dip below zero (the button bounce)',
    );

    final List<double> instantTrace = <double>[];
    final MorphController instant = MorphController(
      vsync: const TestVSync(),
      motion: .instant,
    );
    addTearDown(instant.dispose);
    instant.open();
    await pumpUntilRest(tester, instant);
    instant
      ..addListener(() => instantTrace.add(instant.value))
      ..close();
    await pumpUntilRest(tester, instant);
    expect(
      instantTrace.every((double v) => v >= -0.0001),
      isTrue,
      reason: 'instant (reduced motion) must not bounce',
    );
  });

  testWidgets('phases are monotonic across their ranges during open', (
    WidgetTester tester,
  ) async {
    final MorphController c = MorphController(vsync: const TestVSync());
    addTearDown(c.dispose);
    final List<MorphPhase> seen = <MorphPhase>[c.phase];
    c
      ..addListener(() {
        if (seen.last != c.phase) {
          seen.add(c.phase);
        }
      })
      ..open();
    await pumpUntilRest(tester, c);

    expect(seen.first, MorphPhase.idle);
    expect(seen.last, MorphPhase.settled);
    final List<int> order = seen
        .map((MorphPhase p) => MorphPhase.values.indexOf(p))
        .toList();
    for (int i = 1; i < order.length; i++) {
      expect(
        order[i],
        greaterThanOrEqualTo(order[i - 1]),
        reason: 'phase rolled backwards: $seen',
      );
    }
  });

  testWidgets('animation view: statuses, including scrub', (
    WidgetTester tester,
  ) async {
    final MorphController c = MorphController(vsync: const TestVSync());
    addTearDown(c.dispose);
    final List<AnimationStatus> statuses = <AnimationStatus>[];
    c.animation.addStatusListener(statuses.add);

    expect(c.animation.status, AnimationStatus.dismissed);
    c.open();
    await tester.pump();
    expect(c.animation.status, AnimationStatus.forward);
    await pumpUntilRest(tester, c);
    expect(c.animation.status, AnimationStatus.completed);

    c
      ..beginScrub()
      ..updateScrub(0.5);
    expect(
      c.animation.status,
      AnimationStatus.forward,
      reason: 'a scrub is not rest: derived listeners must not see completed',
    );
    expect(c.animation.value, 0.5);

    c.close();
    await tester.pump();
    expect(c.animation.status, AnimationStatus.reverse);
    await pumpUntilRest(tester, c);
    expect(c.animation.status, AnimationStatus.dismissed);
    expect(
      statuses,
      containsAllInOrder(<AnimationStatus>[
        .forward,
        .completed,
        .reverse,
        .dismissed,
      ]),
    );
  });

  testWidgets('reduced motion switches to instant while keeping velocity', (
    WidgetTester tester,
  ) async {
    final MorphController c = MorphController(vsync: const TestVSync());
    addTearDown(c.dispose);

    c.open();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final double v = c.velocity;

    c.disableAnimations = true;
    expect(c.effectiveMotion, MorphMotion.instant);
    expect(c.velocity, moreOrLessEquals(v));
    expect(c.motion, MorphMotion.normal);

    c.disableAnimations = false;
    expect(c.effectiveMotion, MorphMotion.normal);
    await pumpUntilRest(tester, c);
  });
}
