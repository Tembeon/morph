import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/widgets/bar_motion.dart';
import 'package:morph/src/widgets/glass_button.dart';
import 'package:morph/src/widgets/navigation_bar.dart';
import 'package:morph/src/widgets/navigation_motion.dart';

List<Map<String, Object?>> _rows(String path) => [
  for (final line in File(path).readAsLinesSync())
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

double _d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();

double _rms(List<double> e) =>
    math.sqrt(e.fold<double>(0, (a, v) => a + v * v) / e.length);

/// The 60 Hz simulator frame between the tick that sees an offset and the
/// commit that starts the animation it causes.
const _commit = 1 / 60;

/// The times the recorded content offset crosses the large title's
/// height, upward (true) and back (false); [commit] is one display frame.
List<(double, bool)> _crossings(
  List<Map<String, Object?>> rows, {
  double commit = _commit,
}) {
  final out = <(double, bool)>[];
  bool? under;
  for (final r in rows) {
    if (r['k'] != 'so') continue;
    final scrolled = _d(r, 'oy') + 168;
    final now = scrolled >= MorphNavigationBarMetrics.largeTitleHeight;
    if (under != null && now != under) out.add((_d(r, 't') + commit, now));
    under = now;
  }
  return out;
}

void _replayTitle(
  List<Map<String, Object?>> rows, {
  double commit = _commit,
  double titleRms = 0.06,
  double edgeRms = 0.12,
}) {
  final crossings = _crossings(rows, commit: commit);
  expect(crossings, isNotEmpty);
  final motion = MorphNavigationTitleMotion(titleVisible: false);
  var next = 0;
  final title = <double>[];
  final edge = <double>[];
  final changes = [
    for (final r in rows)
      if (r['k'] == 'B') r,
  ];
  for (final r in changes) {
    final t = _d(r, 't');
    while (next < crossings.length && crossings[next].$1 <= t) {
      final (at, under) = crossings[next];
      motion.setTitleVisible(at, visible: under);
      motion.setScrolledUnder(at, scrolledUnder: under);
      next++;
    }
    if (next == 0) continue;
    motion.advance(t);
    if (r['cls'] == 'title') title.add(motion.titleOpacity - _d(r, 'a'));
    if (r['cls'] == 'edge') edge.add(motion.edgeOpacity - _d(r, 'a'));
  }
  expect(title.length, greaterThan(20));
  expect(_rms(title), lessThan(titleRms), reason: 'title opacity rms');
  if (edge.isNotEmpty) {
    expect(_rms(edge), lessThan(edgeRms), reason: 'edge opacity rms');
  }
}

/// One edge swipe of a device recording: where the page stood and how fast
/// the finger left at the release, how the swipe ended, and the page's
/// offset from its rest place after the release.
class _Swipe {
  _Swipe(List<Map<String, Object?>> rows) {
    width = _d(rows.first, 'w');
    final touches = [
      for (final r in rows)
        if (r['k'] == 'touch') r,
    ];
    final down = touches.first;
    lift = _d(touches.last, 't');
    final reference = touches.lastWhere(
      (r) => _d(r, 't') <= lift - 0.05,
      orElse: () => down,
    );
    velocity =
        (_d(touches.last, 'x') - _d(reference, 'x')) /
        (lift - _d(reference, 't')) /
        width;
    final byLid = <Object?, List<Map<String, Object?>>>{};
    for (final r in rows) {
      if (r['cls'] == 'page') byLid.putIfAbsent(r['lid'], () => []).add(r);
    }
    final center = width / 2;
    final top = byLid.values.firstWhere((s) {
      final before = s.where((r) => _d(r, 't') <= _d(down, 't'));
      return before.isNotEmpty &&
          (_d(before.last, 'x') - center).abs() < 1 &&
          s.any((r) => _d(r, 'x') > center + 5);
    });
    offset = _d(top.lastWhere((r) => _d(r, 't') <= lift), 'x') - center;
    popped = _d(top.last, 'x') - center > width / 2;
    after = [
      for (final r in top)
        if (_d(r, 't') > lift) (_d(r, 't') - lift, _d(r, 'x') - center),
    ];
  }

  late final double width;
  late final double lift;
  late final double velocity;
  late final double offset;
  late final bool popped;
  late final List<(double, double)> after;
}

/// Whether a swipe released with the page [out] of the width out at
/// [velocity] widths per second pops, as MorphNavigationRoute decides.
bool _pops(double out, double velocity) {
  const flick = MorphNavigationTransition.popVelocity;
  return velocity > flick ||
      (velocity > -flick && out > MorphNavigationTransition.popDistance);
}

void main() {
  group('inline title and edge effect replay (iOS 27.0 simulator)', () {
    for (final name in ['drag-collapse', 'fling', 'drag-partial45']) {
      test(name, () {
        _replayTitle(_rows('test/fixtures/ios27/bars/title-$name.jsonl'));
      });
    }

    test('the hidden title sits 15 points low and 4 points blurred', () {
      final motion = MorphNavigationTitleMotion(titleVisible: false);
      expect(motion.titleOffset, 15);
      expect(motion.titleBlur, 4);
      motion.setTitleVisible(0, visible: true);
      motion.advance(2);
      expect(motion.titleOffset, moreOrLessEquals(0, epsilon: 1e-3));
      expect(motion.titleBlur, moreOrLessEquals(0, epsilon: 1e-3));
      expect(motion.isSettled, isTrue);
    });

    test('a change without a finger switches at once', () {
      final motion = MorphNavigationTitleMotion(titleVisible: false);
      motion.setTitleVisible(0, visible: true, animated: false);
      motion.setScrolledUnder(0, scrolledUnder: true, animated: false);
      expect(motion.titleOpacity, 1);
      expect(motion.edgeOpacity, 1);
    });
  });

  group('page transition replay', () {
    test('push and pop move the page underneath like UIKit (device)', () {
      final rows = _rows('test/fixtures/ios27-device/bars/push-pop.jsonl');
      final events = [
        for (final r in rows)
          if (r['k'] == 'evt' && (r['e'] == 'push' || r['e'] == 'pop')) r,
      ];
      expect(events.length, 2);
      final errors = <double>[];
      for (final e in events) {
        final t0 = _d(e, 't');
        final push = e['e'] == 'push';
        final page = [
          for (final r in rows)
            if (r['cls'] == 'page' &&
                r['lid'] == 1 &&
                _d(r, 't') >= t0 &&
                _d(r, 't') < t0 + 1)
              r,
        ];
        final start = _d(page.first, 't');
        final from = _d(page.first, 'x');
        final to = _d(page.last, 'x');
        final sim = SpringSimulation(
          MorphNavigationTransition.pushSpring.description,
          0,
          1,
          MorphNavigationTransition.pushVelocity,
        );
        for (final r in page) {
          final p = sim.x(_d(r, 't') - start);
          errors.add(from + (to - from) * p - _d(r, 'x'));
        }
        expect(push ? from > to : from < to, isTrue);
      }
      expect(_rms(errors), lessThan(1.5));
    });

    test('a page released mid-swipe settles on the interactive spring', () {
      final errors = <double>[];
      for (final name in ['commit', 'cancel']) {
        final rows = _rows('test/fixtures/ios27/bars/pop-edge-$name.jsonl');
        final touches = [
          for (final r in rows)
            if (r['k'] == 'touch') r,
        ];
        final lift = _d(touches.last, 't');
        final page = [
          for (final r in rows)
            if (r['cls'] == 'page' && _d(r, 'y') < 100 && _d(r, 't') >= lift) r,
        ];
        final byLid = <Object?, List<Map<String, Object?>>>{};
        for (final r in page) {
          byLid.putIfAbsent(r['lid'], () => []).add(r);
        }
        final series = byLid.values.reduce(
          (a, b) =>
              (_d(a.last, 'x') - _d(a.first, 'x')).abs() >
                  (_d(b.last, 'x') - _d(b.first, 'x')).abs()
              ? a
              : b,
        );
        var k = 0;
        while (k + 1 < series.length &&
            (_d(series[k + 1], 'x') - _d(series[k], 'x')).abs() < 0.5) {
          k++;
        }
        final start = _d(series[k], 't');
        final from = _d(series[k], 'x');
        final to = _d(series.last, 'x');
        final sim = SpringSimulation(
          MorphNavigationTransition.interactiveSpring.description,
          0,
          1,
          0,
        );
        for (final r in series.skip(k)) {
          final t = _d(r, 't') - start;
          if (t > 0.6) break;
          errors.add(from + (to - from) * sim.x(t) - _d(r, 'x'));
        }
      }
      expect(errors.length, greaterThan(20));
      expect(_rms(errors), lessThan(6));
    });
  });

  group('device replays (iPhone 16 Pro, iOS 27.0.1, 120 Hz)', () {
    for (final name in ['drag-collapse', 'fling', 'drag-partial45']) {
      test('inline title and edge effect: $name', () {
        _replayTitle(
          _rows('test/fixtures/ios27-device/bars/title-$name.jsonl'),
          commit: 1 / 120,
        );
      });
    }

    test('a half-scrolled large title snaps to the nearer end', () {
      for (final d in [20, 24, 28, 31, 35, 40, 45]) {
        final rows = _rows(
          'test/fixtures/ios27-device/bars/title-drag-partial$d.jsonl',
        );
        final lift = _d(rows.lastWhere((r) => r['k'] == 'touch'), 't');
        final offsets = [
          for (final r in rows)
            if (r['k'] == 'so') (_d(r, 't'), _d(r, 'oy') + 168),
        ];
        final atLift = offsets.lastWhere((o) => o.$1 <= lift).$2;
        final rest = offsets.last.$2;
        const half = MorphNavigationBarMetrics.largeTitleHeight / 2;
        expect(
          rest,
          atLift < half ? 0 : MorphNavigationBarMetrics.largeTitleHeight,
          reason: 'released at $atLift',
        );
      }
    });

    test('an edge swipe pops by distance or by flick like UIKit', () {
      for (final name in [
        'commit',
        'cancel',
        'slow25',
        'slow30',
        'slow35',
        'flick-v400',
        'flick-v450',
        'flickback',
        'flickback3',
      ]) {
        final swipe = _Swipe(
          _rows('test/fixtures/ios27-device/bars/pop-edge-$name.jsonl'),
        );
        expect(
          _pops(swipe.offset / swipe.width, swipe.velocity),
          swipe.popped,
          reason:
              '$name: ${(swipe.offset / swipe.width).toStringAsFixed(2)} W '
              'at ${swipe.velocity.toStringAsFixed(2)} W/s',
        );
      }
    });

    test('the released page settles on the interactive spring', () {
      final errors = <double>[];
      for (final name in [
        'commit',
        'cancel',
        'slow25',
        'slow35',
        'flick-v400',
      ]) {
        final swipe = _Swipe(
          _rows('test/fixtures/ios27-device/bars/pop-edge-$name.jsonl'),
        );
        final to = swipe.popped ? swipe.width : 0.0;
        final v = swipe.popped
            ? 0.0
            : swipe.velocity *
                  MorphNavigationTransition.cancelVelocityScale *
                  swipe.width;
        List<double> errorsWith(double lag) {
          final sim = SpringSimulation(
            MorphNavigationTransition.interactiveSpring.description,
            swipe.offset,
            to,
            v,
          );
          return [
            for (final (t, x) in swipe.after)
              if (t < 0.65) (t < lag ? swipe.offset : sim.x(t - lag)) - x,
          ];
        }

        var best = errorsWith(0);
        for (var lag = 0.002; lag <= 0.06; lag += 0.002) {
          final e = errorsWith(lag);
          if (_rms(e) < _rms(best)) best = e;
        }
        expect(_rms(best), lessThan(1), reason: name);
        errors.addAll(best);
      }
      expect(errors.length, greaterThan(100));
      expect(_rms(errors), lessThan(0.8));
    });

    test('the bar capsules drift toward the screen below during a swipe', () {
      MorphBarCapsuleLayout capsule(Object id, double left, double width) =>
          MorphBarCapsuleLayout(id, Rect.fromLTWH(left, 62, width, 44), [
            MorphBarItemLayout((
              id,
              'item',
            ), Rect.fromLTWH(left + 4, 66, width - 8, 36)),
          ]);
      const leading = ('leading', 0);
      const outer = ('trailing', 0);
      const inner = ('trailing', 1);
      final detail = [
        capsule(leading, 16, 94),
        capsule(outer, 386 - 73.67, 73.67),
        capsule(inner, 248.5 - 103.67 / 2, 103.67),
      ];
      final list = [
        capsule(leading, 16, 62.33),
        capsule(outer, 386 - 99.33, 99.33),
      ];
      final errors = <double>[];
      for (final name in ['commit', 'cancel', 'slow25', 'slow40']) {
        final rows = _rows(
          'test/fixtures/ios27-device/bars/pop-edge-drift-$name.jsonl',
        );
        final width = _d(rows.first, 'w');
        final touches = [
          for (final r in rows)
            if (r['k'] == 'touch') r,
        ];
        final down = _d(touches.first, 't');
        final lift = _d(touches.last, 't');
        final popped = _Swipe(rows).popped;
        final motion = MorphBarMotion();
        motion.setLayout(0, detail, animated: false);
        double? progress;
        final own = <double>[];
        for (final r in rows) {
          if (r['k'] != 'B') continue;
          final t = _d(r, 't');
          if (r['cls'] == 'page' && r['lid'] == 88) {
            progress = (_d(r, 'x') - width / 2) / width;
            continue;
          }
          final p = progress;
          if (r['cls'] != 'capsule' || p == null || t <= down) continue;
          if (popped && t > lift) continue;
          final x = _d(r, 'x');
          final w = _d(r, 'w');
          final Object? id = switch ((x - w / 2, x + w / 2)) {
            (final l, _) when (l - 16).abs() < 1.5 => leading,
            (_, final r) when (r - 386).abs() < 1.5 => outer,
            _ when (x - 248.5).abs() < 1.5 => inner,
            _ => null,
          };
          if (id == null) continue;
          motion.setDrift(list, MorphNavigationTransition.barDrift * p);
          final frame = motion.capsuleFrame(id)!.rect;
          own.add(frame.width - w);
          own.add(frame.center.dx - x);
        }
        expect(own.length, greaterThan(80), reason: name);
        expect(_rms(own), lessThan(0.4), reason: name);
        errors.addAll(own);
      }
      expect(_rms(errors), lessThan(0.3));
    });

    test('a held bar button group lifts on the glass button model', () {
      final rows = _rows('test/fixtures/ios27-device/bars/item-hold.jsonl');
      final touches = [
        for (final r in rows)
          if (r['k'] == 'touch') r,
      ];
      final capsule = [
        for (final r in rows)
          if (r['cls'] == 'capsule') r,
      ];
      final rest = _d(capsule.first, 'w');
      final down = _d(touches.first, 't');
      final up = _d(touches.last, 't');
      final at = Offset(rest - 25, 22);
      List<double> errorsWith(double lag) {
        final motion = MorphGlassButtonMotion(
          size: Size(rest, _d(capsule.first, 'h')),
        );
        var pressed = false;
        var released = false;
        final out = <double>[];
        for (final r in capsule) {
          final t = _d(r, 't') + 1 / 120;
          if (t < down) continue;
          if (!pressed && t >= down + lag) {
            motion.pointerDown(down + lag, at);
            pressed = true;
          }
          if (!released && t >= up + lag) {
            motion.pointerUp(up + lag, at);
            released = true;
          }
          motion.advance(t);
          out.add(motion.scale * rest - _d(r, 'w'));
        }
        return out;
      }

      var errors = errorsWith(0);
      for (var lag = 0.005; lag <= 0.06; lag += 0.005) {
        final e = errorsWith(lag);
        if (_rms(e) < _rms(errors)) errors = e;
      }
      expect(errors.length, greaterThan(40));
      expect(_rms(errors), lessThan(0.6));
    });
  });
}
