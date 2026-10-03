import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/liquid_field.dart';

import 'liquid_geometry_scenes.dart';

/// Geometry snapshots ("goldens without pixels"): per-loop area,
/// centroid, and bounds for fixed scenes, captured from a reviewed
/// state of the tracer. The sign-consistency net catches broken
/// geometry; these snapshots additionally catch silent DRIFT - a
/// contour that is still valid but no longer the same shape.
///
/// When geometry changes INTENTIONALLY, regenerate with
/// `flutter test test/golden_dump_helper.dart` and review the diff.
class LoopSnapshot {
  const LoopSnapshot({
    required this.area,
    required this.centroid,
    required this.bounds,
  });

  final double area;
  final Offset centroid;
  final Rect bounds;
}

const double _areaTolerance = 0.015;
const double _pointTolerance = 1.0;
const double _boundsTolerance = 1.5;

final Map<String, List<LoopSnapshot>> goldenSnapshots =
    <String, List<LoopSnapshot>>{
      'fusedPair': <LoopSnapshot>[
        const LoopSnapshot(
          area: 15650.6,
          centroid: Offset(136.7, 74.6),
          bounds: .fromLTRB(20.0, 30.0, 260.0, 110.0),
        ),
      ],
      'neckAtRipDistance': <LoopSnapshot>[
        const LoopSnapshot(
          area: 5887.7,
          centroid: Offset(51.4, 29.3),
          bounds: .fromLTRB(0.0, 0.0, 100.6, 60.0),
        ),
        const LoopSnapshot(
          area: 5894.8,
          centroid: Offset(167.9, 30.0),
          bounds: .fromLTRB(117.3, 0.0, 218.0, 60.0),
        ),
      ],
      'ringWithHole': <LoopSnapshot>[
        const LoopSnapshot(
          area: 24803.0,
          centroid: Offset(122.2, 73.1),
          bounds: .fromLTRB(-2.0, -2.0, 242.0, 202.0),
        ),
        const LoopSnapshot(
          area: 10696.2,
          centroid: Offset(121.4, 76.0),
          bounds: .fromLTRB(42.0, 30.0, 198.0, 157.1),
        ),
      ],
      // 24 separate islands on a budget-coarsened grid (gap 15 < k 22:
      // one cluster with bulges, no merges). Column stats from a
      // reviewed dump, repeated per row with a 95px pitch; the small
      // per-cell variation sits well inside the tolerances.
      'budgetedGrid': <LoopSnapshot>[
        for (int row = 0; row < 4; row++)
          for (final (double area, double cx, double left, double right)
              in const <(double, double, double, double)>[
                (6817.1, 50.7, 0.0, 101.1),
                (6865.7, 166.2, 114.1, 216.2),
                (6871.3, 280.0, 228.9, 331.1),
                (6865.7, 394.9, 343.8, 445.9),
                (6868.8, 510.6, 458.9, 561.1),
                (6810.8, 626.0, 574.1, 675.0),
              ])
            LoopSnapshot(
              area: area,
              centroid: Offset(cx, 34.0 + row * 95.0),
              bounds: .fromLTRB(left, row * 95.0, right, 70.0 + row * 95.0),
            ),
      ],
    };

void main() {
  for (final String name in goldenScenes.keys) {
    test('geometry snapshot: $name', () {
      final List<List<Offset>> loops = liquidContours(
        goldenScenes[name]!,
        cell: 4,
      );
      final List<LoopSnapshot> expected = goldenSnapshots[name]!;
      expect(
        loops,
        hasLength(expected.length),
        reason: 'loop count drifted for $name',
      );
      for (final LoopSnapshot snapshot in expected) {
        final List<Offset>? match = _findMatch(loops, snapshot);
        expect(
          match,
          isNotNull,
          reason:
              'no traced loop near expected centroid '
              '${snapshot.centroid} in $name',
        );
        final _LoopStats stats = _LoopStats.of(match!);
        expect(
          (stats.area - snapshot.area).abs() / snapshot.area,
          lessThan(_areaTolerance),
          reason: 'area drifted for a loop of $name',
        );
        expect(
          (stats.bounds.left - snapshot.bounds.left).abs(),
          lessThan(_boundsTolerance),
          reason: 'bounds.left drifted for a loop of $name',
        );
        expect(
          (stats.bounds.top - snapshot.bounds.top).abs(),
          lessThan(_boundsTolerance),
          reason: 'bounds.top drifted for a loop of $name',
        );
        expect(
          (stats.bounds.right - snapshot.bounds.right).abs(),
          lessThan(_boundsTolerance),
          reason: 'bounds.right drifted for a loop of $name',
        );
        expect(
          (stats.bounds.bottom - snapshot.bounds.bottom).abs(),
          lessThan(_boundsTolerance),
          reason: 'bounds.bottom drifted for a loop of $name',
        );
      }
    });
  }
}

/// Candidates by centroid proximity, disambiguated by area: a ring's
/// outer loop and its hole share nearly the same centroid.
List<Offset>? _findMatch(List<List<Offset>> loops, LoopSnapshot snapshot) {
  List<Offset>? best;
  double bestAreaDelta = .infinity;
  for (final List<Offset> loop in loops) {
    final _LoopStats stats = _LoopStats.of(loop);
    if ((stats.centroid - snapshot.centroid).distance > _pointTolerance + 2) {
      continue;
    }
    final double areaDelta = (stats.area - snapshot.area).abs();
    if (areaDelta < bestAreaDelta) {
      bestAreaDelta = areaDelta;
      best = loop;
    }
  }
  return best;
}

class _LoopStats {
  const _LoopStats(this.area, this.centroid, this.bounds);

  factory _LoopStats.of(List<Offset> loop) {
    double area = 0;
    double cx = 0;
    double cy = 0;
    Rect bounds = const .fromLTRB(
      .infinity,
      .infinity,
      .negativeInfinity,
      .negativeInfinity,
    );
    for (int i = 0; i < loop.length; i++) {
      final Offset a = loop[i];
      final Offset b = loop[(i + 1) % loop.length];
      area += a.dx * b.dy - b.dx * a.dy;
      cx += a.dx;
      cy += a.dy;
      bounds = .fromLTRB(
        a.dx < bounds.left ? a.dx : bounds.left,
        a.dy < bounds.top ? a.dy : bounds.top,
        a.dx > bounds.right ? a.dx : bounds.right,
        a.dy > bounds.bottom ? a.dy : bounds.bottom,
      );
    }
    return _LoopStats(
      (area / 2).abs(),
      Offset(cx / loop.length, cy / loop.length),
      bounds,
    );
  }

  final double area;
  final Offset centroid;
  final Rect bounds;
}
