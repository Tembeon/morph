import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/sheet_motion.dart';
import 'support/motion_at.dart';

/// The simulator screen of these captures: an iPhone 17 Pro, 402 x 874
/// points with a 62 point top and a 34 point bottom safe area.
const double _w = 402;
const double _maximum = 874 - 62 - 34;
const double _bottom = 34;
const double _full = _maximum + _bottom;
final double _medium = MorphSheetDetent.medium.resolve(_maximum) + _bottom;

/// The distance the simulator's sheet pan travels before the sheet moves,
/// fitted with the rubber band (6 - 8 points).
const double _slop = 7;

MorphSheetMotion _motion(List<double> heights, {int? docked, int initial = 0}) {
  final motion = MorphSheetMotion(
    heights: heights,
    width: _w,
    initial: initial,
    fullHeight: _full,
    dockedIndex: docked,
  );
  motion.present(0);
  motion.advance(3);
  return motion;
}

/// Drags [motion] from screen y 600 by [travel] points (positive up) in
/// steps, returning the time of the last step.
double _drag(MorphSheetMotion motion, double travel, {double t = 3}) {
  motion.press(t);
  motion.dragStart(t, 600);
  const steps = 40;
  for (var i = 1; i <= steps; i++) {
    motion.dragUpdate(t + i / 120, 600 - travel * i / steps);
  }
  return t + steps / 120;
}

void main() {
  group('stretch above the largest detent', () {
    test('held device drags confirm the floating rubber-band dimensions', () {
      // iPhone 16 Pro, iOS 27.0.1, rec-plan-stretch-{m,h}, 2026-10-14.
      // Actual touch travel (the h gesture reaches the screen edge),
      // held unscaled detent value, and the device's existing 12 pt slop.
      const captures = [(435.67, 240.0, 491.67), (700.0, 181.333, 742.67)];
      for (final (detent, travel, value) in captures) {
        final motion = _motion([detent + _bottom]);
        final t = _drag(motion, travel - 12);
        motion.advance(t + 0.8);
        expect(motion.at(t + 0.8).height - _bottom, closeTo(value, 1.5));
      }
    });

    test('a floating largest detent rubber-bands toward the maximum', () {
      // Medium-only sheet (simulator): finger travel up, value above the
      // detent. UIKit's room is clamp(778 - 435.68, 0, 100) = 100.
      const capture = [(123.7, 38.5), (157.7, 45.4), (197.7, 51.2)];
      for (final (travel, above) in capture) {
        final motion = _motion([_medium]);
        final t = _drag(motion, travel - _slop);
        expect(motion.at(t).height - _medium, closeTo(above, 1.5));
      }
    });

    test('the room left to the maximum bounds the stretch', () {
      // A 700 point custom detent: 78 points of room.
      const capture = [(64.3, 21.6), (146.3, 38.2), (246.0, 48.9)];
      for (final (travel, above) in capture) {
        final motion = _motion([700 + _bottom]);
        final t = _drag(motion, travel - _slop);
        expect(motion.at(t).height - 700 - _bottom, closeTo(above, 1.5));
      }
    });

    test('a docked sheet does not move up', () {
      final motion = _motion([_medium, _full], docked: 1, initial: 1);
      final t = _drag(motion, 200);
      expect(motion.at(t).height, _full);
      expect(motion.at(t).fill, 1);
    });

    test('the stretch springs back to the detent on release', () {
      final motion = _motion([_medium]);
      final t = _drag(motion, 200);
      motion.dragEnd(t, 0);
      motion.advance(t + 2);
      expect(motion.at(t + 2).height, closeTo(_medium, 0.05));
      expect(motion.isSettled, isTrue);
    });

    test('a drag that catches a returning stretch takes it over in place', () {
      final motion = _motion([_medium]);
      final t = _drag(motion, 200);
      motion.dragEnd(t, 0);
      final caught = t + 0.1;
      motion.advance(caught);
      final before = motion.at(caught).height;
      expect(before, greaterThan(_medium));
      motion.dragStart(caught, 500);
      motion.dragUpdate(caught + 0.01, 500);
      expect(motion.at(caught + 0.01).height, closeTo(before, 1e-6));
    });
  });

  group('refused dismissal', () {
    test('the pull below the smallest detent rubber-bands with 200', () {
      // A 200 point custom detent presented modally (simulator).
      const capture = [(41.0, 17.1), (83.7, 34.8), (130.0, 50.2)];
      for (final (travel, below) in capture) {
        final motion = MorphSheetMotion(
          heights: [200 + _bottom],
          width: _w,
          initial: 0,
          fullHeight: _full,
          dismissible: false,
        );
        motion.present(0);
        motion.advance(3);
        motion.dragStart(3, 300);
        for (var i = 1; i <= 40; i++) {
          motion.dragUpdate(3 + i / 120, 300 + (travel - _slop) * i / 40);
        }
        expect(motion.at(3 + 40 / 120).offset, closeTo(below, 2.5));
      }
    });
  });

  group('docking during a drag', () {
    test('progress ends 10 points below the large detent', () {
      final motion = _motion([_medium, _full], docked: 1);
      // Value 608.3 above the bottom safe area: progress 0.5196 measured.
      final t = _drag(motion, 608.3 + _bottom - _medium);
      expect(motion.at(t).dock, closeTo(0.5196, 1e-3));
    });

    test('the bottom corners turn as one minus the square of the gap', () {
      final motion = _motion([_medium, _full], docked: 1);
      final t = _drag(motion, 546.3 + _bottom - _medium);
      final p = motion.at(t).dock;
      // Simulator: 58.44 of 54 -> 62 at progress 0.333.
      final radius = 54 + 8 * motion.at(t).cornerBlend;
      expect(p, closeTo(0.333, 2e-3));
      expect(radius, closeTo(58.44, 0.25));
    });

    test('a settle carries the corners on from where the drag left them', () {
      final motion = _motion([_medium, _full], docked: 1);
      final t = _drag(motion, 546.3 + _bottom - _medium);
      final dragged = motion.at(t).cornerBlend;
      motion.dragEnd(t, -1500);
      final settle = t + MorphSheetTuning.releaseDelay;
      motion.advance(settle);
      expect(motion.at(settle).cornerBlend, closeTo(dragged, 1e-6));
      motion.advance(settle + 2);
      expect(motion.at(settle + 2).cornerBlend, 1);
    });
  });

  group('background', () {
    test('a drag switches the fill where the docking passes one half', () {
      final motion = _motion([_medium, _full], docked: 1);
      // Up to value 600.0: still glass; the simulator kept it.
      var t = _drag(motion, 600.0 + _bottom - _medium);
      motion.advance(t + 0.5);
      expect(motion.at(t + 0.5).fill, 0);
      // On to 602.7: the background turned, the fill rides the sheet
      // spring from there while the finger holds still.
      motion.dragUpdate(t + 0.5, 600 - (602.7 + _bottom - _medium));
      final flip = t + 0.5;
      // Simulator alpha 1/60 s apart after the flip, one frame late:
      // 0.146, 0.256, 0.364, 0.468, 0.574.
      const measured = [0.146, 0.256, 0.364, 0.468, 0.574];
      for (var i = 0; i < measured.length; i++) {
        final at = flip + (i + 2) / 60;
        motion.advance(at);
        expect(motion.at(at).fill, closeTo(measured[i], 0.035));
      }
      // Back down below the switch: the fill heads out again.
      t = flip + 0.2;
      motion.dragUpdate(t, 600 - (601.0 + _bottom - _medium));
      motion.advance(t + 1);
      expect(motion.at(t + 1).fill, closeTo(0, 1e-3));
    });

    test('a programmatic change fills in step with the docking', () {
      final motion = _motion([_medium, _full], docked: 1);
      motion.animateTo(3, 1);
      for (final dt in [0.05, 0.1, 0.2, 0.3]) {
        motion.advance(3 + dt);
        expect(motion.at(3 + dt).fill, closeTo(motion.at(3 + dt).dock, 1e-9));
      }
    });

    test('a sheet without a docked detent never fills', () {
      final motion = _motion([_medium]);
      final t = _drag(motion, 300);
      expect(motion.at(t).fill, 0);
    });
  });
}
