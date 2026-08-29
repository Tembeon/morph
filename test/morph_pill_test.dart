import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

/// A three-slot track, slot width 100: rest centers at 50 / 150 / 250.
MorphPillHost host({void Function(double, {required bool byCarry})? onTarget}) {
  double clampCenter(int slot) => (slot.clamp(0, 2)) * 100.0 + 50.0;
  final MorphPillHost pill = MorphPillHost(
    vsync: const TestVSync(),
    hit: (double fingerX) => clampCenter((fingerX / 100).floor()),
    snap: (double centerX) => clampCenter(((centerX - 50) / 100).round()),
    onTarget: onTarget,
  );
  pill.carryMin = 50;
  pill.carryMax = 250;
  return pill;
}

Future<void> ticks(WidgetTester tester, int frames) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('a touch lifts in place and the lift holds under the finger', (
    WidgetTester tester,
  ) async {
    final MorphPillHost pill = host();
    addTearDown(pill.dispose);
    pill.jumpTo(50);

    // A hold BETWEEN slots: the pill grows where it lives and does not
    // slide under the finger - the native grab.
    pill.down(120);
    await ticks(tester, 20);
    expect(pill.lifted, isTrue);
    expect(pill.liftX, greaterThan(0.5));
    expect(pill.centerX, closeTo(50, 0.5));
    // The lift may not come down while the finger holds it.
    await ticks(tester, 40);
    expect(pill.lifted, isTrue);
    pill.up(120);
    await ticks(tester, 160);
    expect(pill.lifted, isFalse);
  });

  testWidgets('a tap commits immediately and the pill lands on its slot', (
    WidgetTester tester,
  ) async {
    final List<(double, bool)> commits = <(double, bool)>[];
    final MorphPillHost pill = host(
      onTarget: (double c, {required bool byCarry}) =>
          commits.add((c, byCarry)),
    );
    addTearDown(pill.dispose);
    pill.jumpTo(50);

    pill.down(250);
    await ticks(tester, 2);
    pill.up(250);
    // The commit fires with the release, not with the landing.
    expect(commits, <(double, bool)>[(250.0, false)]);
    await ticks(tester, 120);
    expect(pill.centerX, closeTo(250, 0.5));
    expect(pill.lifted, isFalse);
    expect(pill.liftX, 0);
  });

  testWidgets('a carry is relative and honest past the track edges', (
    WidgetTester tester,
  ) async {
    final List<(double, bool)> commits = <(double, bool)>[];
    final MorphPillHost pill = host(
      onTarget: (double c, {required bool byCarry}) =>
          commits.add((c, byCarry)),
    );
    addTearDown(pill.dispose);
    pill.jumpTo(50);

    pill.down(40);
    await ticks(tester, 2);
    // Wander OFF the track and back: the delta must stay honest.
    pill.move(-60);
    await ticks(tester, 2);
    pill.move(240);
    // Target = grab(50) + (240 - 40) = 250: the pill is carried by the
    // finger's displacement, not centered under the finger.
    await ticks(tester, 40);
    expect(pill.carrying, isTrue);
    expect(pill.centerX, closeTo(250, 8));
    // Way past the edge: the delta stays honest, the pill does not -
    // the carry is confined to the rest centers' span.
    pill.move(1000);
    await ticks(tester, 40);
    expect(pill.centerX, lessThanOrEqualTo(250.5));
    pill.move(240);
    await ticks(tester, 20);
    pill.up(240);
    expect(commits.single.$2, isTrue);
    expect(commits.single.$1, 250);
    await ticks(tester, 120);
    expect(pill.centerX, closeTo(250, 0.5));
  });

  testWidgets('a down freezes a flight and a release never strands it', (
    WidgetTester tester,
  ) async {
    final MorphPillHost pill = host();
    addTearDown(pill.dispose);
    pill.jumpTo(50);

    pill.settleTo(250);
    await ticks(tester, 6);
    final double midway = pill.centerX;
    expect(midway, greaterThan(55));
    expect(midway, lessThan(245));

    // The hand takes over mid-flight, then lets go over slot 0: the
    // journey resumes through the one door - the pill cannot be left
    // parked between slots.
    pill.down(60);
    await ticks(tester, 2);
    expect(pill.centerX, closeTo(midway, 5));
    pill.up(60);
    await ticks(tester, 140);
    expect(pill.centerX, closeTo(50, 0.5));
    expect(pill.lifted, isFalse);
  });

  testWidgets('the chrome breathes while the pill is up and settles after', (
    WidgetTester tester,
  ) async {
    final MorphPillHost pill = host();
    addTearDown(pill.dispose);
    pill.jumpTo(50);

    pill.down(50);
    await ticks(tester, 20);
    expect(pill.chromeBreath(300), greaterThan(1.02));
    pill.move(90);
    pill.move(130);
    await ticks(tester, 4);
    expect(pill.chromeShift(300).abs(), greaterThan(0.3));
    pill.up(130);
    await ticks(tester, 200);
    expect(pill.chromeBreath(300), closeTo(1, 0.001));
    expect(pill.chromeShift(300), 0);
  });
}
