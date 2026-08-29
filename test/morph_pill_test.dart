import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

/// A three-slot track, slot width 100: rest centers at 50 / 150 / 250.
MorphPillHost host({void Function(double, {required bool byCarry})? onTarget}) {
  double clampCenter(int slot) => (slot.clamp(0, 2)) * 100.0 + 50.0;
  return MorphPillHost(
    vsync: const TestVSync(),
    hit: (double fingerX) => clampCenter((fingerX / 100).floor()),
    // The snap grid confines the carry: its extremes ARE the track.
    snap: (double centerX) => clampCenter(((centerX - 50) / 100).round()),
    onTarget: onTarget,
  );
}

Future<void> ticks(WidgetTester tester, int frames) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('a hold lifts in place on its own item, travels to another', (
    WidgetTester tester,
  ) async {
    final MorphPillHost pill = host();
    addTearDown(pill.dispose);
    pill.jumpTo(50);

    // A hold on the pill's OWN item: it grows where it lives and does
    // not move - the native grab.
    pill.down(60);
    await ticks(tester, 20);
    expect(pill.lifted, isTrue);
    expect(pill.liftX, greaterThan(0.5));
    expect(pill.centerX, closeTo(50, 0.5));
    // The lift may not come down while the finger holds it.
    await ticks(tester, 40);
    expect(pill.lifted, isTrue);
    pill.up(60);
    await ticks(tester, 160);
    expect(pill.lifted, isFalse);

    // A hold on ANOTHER item: the pill lifts and TRAVELS there, still
    // held - and stays up until the release lands it.
    pill.down(230);
    await ticks(tester, 60);
    expect(pill.lifted, isTrue);
    expect(pill.centerX, closeTo(250, 2));
    pill.up(230);
    await ticks(tester, 160);
    expect(pill.centerX, closeTo(250, 0.5));
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

    // The hand takes over mid-flight with a hold over slot 0: the
    // travel retargets there under the hold, and the release lands it
    // - the pill cannot be left parked between slots.
    pill.down(60);
    await ticks(tester, 12);
    expect(pill.centerX, lessThan(midway));
    pill.up(60);
    await ticks(tester, 140);
    expect(pill.centerX, closeTo(50, 0.5));
    expect(pill.lifted, isFalse);
  });

  testWidgets('the deformation mirrors between the two travel directions', (
    WidgetTester tester,
  ) async {
    // A fresh host per direction: a second journey on the same one
    // would begin mid-reversal, where the crossing is the point.
    Future<List<double>> journey(double from, double to) async {
      final MorphPillHost pill = host();
      addTearDown(pill.dispose);
      pill.jumpTo(from);
      pill.settleTo(to);
      final List<double> seen = <double>[];
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        seen.add(pill.deviation);
      }
      // Let it go quiet: a host still ticking at teardown is an error.
      await ticks(tester, 200);
      return seen;
    }

    final List<double> right = await journey(50, 250);
    final List<double> left = await journey(250, 50);
    // The force is read along the TRAVEL, so the same journey mirrored
    // deforms the same way: the launch stretches (positive) and the
    // arrival squashes (negative) whichever way the pill goes.
    expect(right.reduce(math.max), greaterThan(0.02));
    expect(right.reduce(math.min), lessThan(-0.02));
    for (int i = 0; i < right.length; i++) {
      expect(left[i], closeTo(right[i], 0.02));
    }
  });

  testWidgets('a cancelled gesture returns to the committed target', (
    WidgetTester tester,
  ) async {
    final List<(double, bool)> commits = <(double, bool)>[];
    final MorphPillHost pill = host(
      onTarget: (double c, {required bool byCarry}) =>
          commits.add((c, byCarry)),
    );
    addTearDown(pill.dispose);
    pill.jumpTo(50);

    // Carry two slots over, then let the platform take the touch: the
    // pill must go back where the selection actually is, and say so -
    // an owner that moved a live highlight under the carry has to hear
    // that it is over, or pill, light and screen disagree for good.
    pill.down(40);
    await ticks(tester, 2);
    pill.move(240);
    await ticks(tester, 30);
    pill.cancel();
    await ticks(tester, 160);
    expect(pill.centerX, closeTo(50, 0.5));
    expect(commits.single.$1, 50);

    // The same for a hold that had already travelled to another slot:
    // it must not strand the pill on a slot nobody chose.
    commits.clear();
    pill.down(250);
    await ticks(tester, 8);
    pill.cancel();
    await ticks(tester, 160);
    expect(pill.centerX, closeTo(50, 0.5));
    expect(commits.single.$1, 50);
  });

  testWidgets('a motionless release commits the item the hold showed', (
    WidgetTester tester,
  ) async {
    final List<(double, bool)> commits = <(double, bool)>[];
    final MorphPillHost pill = host(
      onTarget: (double c, {required bool byCarry}) =>
          commits.add((c, byCarry)),
    );
    addTearDown(pill.dispose);
    pill.jumpTo(50);

    // Press just inside slot 1 and drift 3px across its boundary -
    // under the carry slop, so no carry ever starts. The commit is the
    // slot the pill visibly travelled to, not the one the finger
    // happened to end over.
    pill.down(199);
    await ticks(tester, 20);
    pill.up(202);
    await ticks(tester, 120);
    expect(commits.single.$1, 150);
    expect(pill.centerX, closeTo(150, 0.5));
  });

  testWidgets('the carry is confined by the snap grid, unasked', (
    WidgetTester tester,
  ) async {
    final MorphPillHost pill = host();
    addTearDown(pill.dispose);
    pill.jumpTo(50);

    pill.down(40);
    await ticks(tester, 2);
    pill.move(4000);
    await ticks(tester, 40);
    // The finger's delta stays honest, the pill does not leave the
    // track - and the owner never had to say so.
    expect(pill.centerX, lessThanOrEqualTo(250.5));
    pill.up(4000);
    await ticks(tester, 140);
    expect(pill.centerX, closeTo(250, 0.5));
  });

  testWidgets('frames resuming after a gap finish rather than replay', (
    WidgetTester tester,
  ) async {
    final MorphPillHost pill = host();
    addTearDown(pill.dispose);
    pill.jumpTo(50);
    pill.settleTo(250);
    await ticks(tester, 4);
    expect(pill.centerX, lessThan(250));

    // A route covered the chapter (or the app was backgrounded) and
    // the ticker comes back with a minute in one frame: the journey is
    // over, not replayed 14 000 substeps at a time.
    await tester.pump(const Duration(seconds: 60));
    expect(pill.centerX, 250);
    expect(pill.lifted, isFalse);
    expect(pill.deviation, 0);
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
