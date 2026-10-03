import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/bar_motion.dart';

List<Map<String, Object?>> _rows(String path) => [
  for (final line in File(path).readAsLinesSync())
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

double _d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();

Rect _box(double cx, double w, double h, double cy) =>
    Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);

/// The three item sets of the probe's toolbar script on a bar whose
/// capsules sit at [cy], with the trailing positions of a screen [right]
/// points wide minus the 28 point inset.
Map<String, List<MorphBarCapsuleLayout>> _sets(double cy, double right) {
  MorphBarItemLayout item(String id, double cx, double w, double h) =>
      MorphBarItemLayout(id, _box(cx, w, h, cy));
  final r = right - 28;
  return {
    'A': [
      MorphBarCapsuleLayout('L', _box(63.83, 71.67, 48, cy), [
        item('filter', 63.8, 39.7, 20.3),
      ]),
      MorphBarCapsuleLayout('R', _box(r - 24, 48, 48, cy), [
        item('compose', r - 24.3, 26.7, 27),
      ]),
    ],
    'B': [
      MorphBarCapsuleLayout('L', _box(83.17, 110.33, 48, cy), [
        item('trash', 53.2, 24.3, 28),
        item('folder', 110.3, 30, 24),
      ]),
      MorphBarCapsuleLayout('R', _box(r - 54.83, 109.67, 48, cy), [
        item('reply', r - 83.2, 27, 24),
        item('compose', r - 26.3, 26.7, 27),
      ]),
    ],
    'C': [
      MorphBarCapsuleLayout('L', _box(52, 48, 48, cy), [
        item('trash', 51.8, 24.3, 28),
      ]),
      MorphBarCapsuleLayout('M', _box(112, 48, 48, cy), [
        item('folder', 112, 30, 24),
      ]),
      MorphBarCapsuleLayout('R', _box(r - 24, 48, 48, cy), [
        item('compose', r - 24.3, 26.7, 27),
      ]),
    ],
  };
}

double _rms(List<double> e) =>
    math.sqrt(e.fold<double>(0, (a, v) => a + v * v) / e.length);

/// Replays the recorded item changes and returns the capsule errors
/// (x, w, h) against the presentation frames.
(List<double>, List<double>, List<double>) _replayCapsules(
  String path, {
  MorphBarTransitionSpec spec = MorphBarTransitionSpec.standard,
}) {
  final rows = _rows(path);
  final start = rows.firstWhere((r) => r['k'] == 'start');
  final cy = _d(start, 'h') - 28 - 24;
  final sets = _sets(cy, _d(start, 'w'));
  final changes = [
    for (final r in rows)
      if (r['k'] == 'evt' && r['e'] == 'setToolbarItems') r,
  ];
  final glass = [
    for (final r in rows)
      if (r['k'] == 'B' && r['cls'] == 'SDFElement') r,
  ];
  final motion = MorphBarMotion(spec: spec);
  motion.setLayout(_d(changes.first, 't') - 1, sets['A']!);
  final dx = <double>[];
  final dw = <double>[];
  final dh = <double>[];
  for (var k = 0; k < changes.length; k++) {
    final t0 = _d(changes[k], 't');
    final t1 = k + 1 < changes.length ? _d(changes[k + 1], 't') : t0 + 1;
    motion.setLayout(t0, sets[changes[k]['set']]!);
    for (final r in glass) {
      final t = _d(r, 't');
      if (t <= t0 || t >= math.min(t1, t0 + 0.8)) continue;
      motion.advance(t);
      MorphBarCapsuleFrame? best;
      var bestD = double.infinity;
      for (final f in motion.capsules) {
        final d =
            (f.rect.center.dx - _d(r, 'x')).abs() +
            (f.rect.width - _d(r, 'w')).abs();
        if (d < bestD) {
          bestD = d;
          best = f;
        }
      }
      dx.add(best!.rect.center.dx - _d(r, 'x'));
      dw.add(best.rect.width - _d(r, 'w'));
      dh.add(best.rect.height - _d(r, 'h'));
    }
  }
  return (dx, dw, dh);
}

final _sim = _sets(904, 440);
final _layoutA = _sim['A']!;
final _layoutB = _sim['B']!;
final _layoutC = _sim['C']!;

void main() {
  group('toolbar item replacement replay (iPhone 16 Pro, iOS 27.0.1)', () {
    test('capsules move, resize and swell like UIKit', () {
      final (dx, dw, dh) = _replayCapsules(
        'test/fixtures/ios27-device/bars/toolbar-swap.jsonl',
      );
      expect(dx.length, greaterThan(300));
      expect(_rms(dx), lessThan(1.2), reason: 'center x rms');
      expect(_rms(dw), lessThan(2.0), reason: 'width rms');
      expect(_rms(dh), lessThan(1.0), reason: 'height rms');
    });
  });

  group('toolbar item replacement replay (iOS 27.0 simulator)', () {
    final rows = _rows('test/fixtures/ios27/bars/toolbar-swap.jsonl');
    final changes = [
      for (final r in rows)
        if (r['k'] == 'evt' && r['e'] == 'setToolbarItems') r,
    ];

    test('capsules move, resize and swell like UIKit', () {
      final (dx, dw, dh) = _replayCapsules(
        'test/fixtures/ios27/bars/toolbar-swap.jsonl',
      );
      expect(dx.length, greaterThan(200));
      expect(_rms(dx), lessThan(1.2), reason: 'center x rms');
      expect(_rms(dw), lessThan(2.5), reason: 'width rms');
      expect(_rms(dh), lessThan(1.5), reason: 'height rms');
    });

    test('a capsule is born at a fifth of its size on its neighbour', () {
      final motion = MorphBarMotion();
      motion.setLayout(0, _layoutA);
      motion.setLayout(1, _layoutC);
      motion.advance(1.0001);
      final born = motion.capsuleFrame('M')!;
      expect(born.rect.width, moreOrLessEquals(48 * 0.2, epsilon: 0.01));
      expect(born.rect.center.dx, moreOrLessEquals(76, epsilon: 0.01));
      motion.advance(3);
      final settled = motion.capsuleFrame('M')!.rect;
      expect(settled.center.dx, moreOrLessEquals(112, epsilon: 0.01));
      expect(settled.width, moreOrLessEquals(48, epsilon: 0.01));
      expect(motion.isSettled, isTrue);
    });

    test('new items grow out of the old capsule center, old ones leave', () {
      final motion = MorphBarMotion();
      motion.setLayout(0, _layoutA);
      motion.setLayout(1, _layoutB);
      motion.advance(1.001);
      final folder = motion.itemFrame('folder')!;
      expect(folder.scale, moreOrLessEquals(0.2, epsilon: 1e-6));
      expect(folder.presence, 0);
      expect(folder.blur, moreOrLessEquals(10, epsilon: 1e-6));
      expect(folder.center.dx, moreOrLessEquals(63.8, epsilon: 0.5));
      expect(motion.itemFrame('filter')!.leaving, isTrue);
      motion.advance(3);
      expect(motion.itemFrame('filter'), isNull);
      expect(
        motion.itemFrame('folder')!.scale,
        moreOrLessEquals(1, epsilon: 1e-6),
      );
      expect(motion.isSettled, isTrue);
    });

    test('items appear on the transition spring within the recording', () {
      final images = [
        for (final r in rows)
          if (r['k'] == 'B' && r['cls'] == 'UIImageView') r,
      ];
      final motion = MorphBarMotion();
      final t0 = _d(changes.first, 't');
      motion.setLayout(t0 - 1, _layoutA);
      motion.setLayout(t0, _layoutB);
      final errors = <double>[];
      for (final r in images) {
        final t = _d(r, 't');
        if (t <= t0 + 0.02 || t > t0 + 0.7) continue;
        final w = _d(r, 'w');
        final x = _d(r, 'x');
        if (x < 40 || x > 140) continue;
        motion.advance(t);
        final id = w / _d(r, 'h') < 1 ? 'trash' : 'folder';
        final f = motion.itemFrame(id);
        if (f == null) continue;
        final finalW = id == 'trash' ? 24.3 : 30.0;
        errors.add(f.scale - w / finalW);
      }
      expect(errors, isNotEmpty);
      final rms = math.sqrt(
        errors.fold<double>(0, (a, v) => a + v * v) / errors.length,
      );
      expect(rms, lessThan(0.12));
    });
  });
}
