import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/liquid_field.dart';

/// Implementation-independent correctness net for the tracing pipeline.
///
/// The strongest invariant: away from the surface (farther than ~1.5
/// grid cells, which covers both sampling error and Chaikin shrink) the
/// traced path and the field sign MUST agree at every probe point. Any
/// optimization of the sampler, the grid, or clustering that breaks
/// geometry trips this net regardless of how the internals changed.
void expectContourMatchesField(
  LiquidField field, {
  double cell = 4,
  double probeStep = 7,
  double? margin,
  int? evalBudget = liquidDefaultEvalBudget,
}) {
  final Path path = liquidPath(field, cell: cell, evalBudget: evalBudget);
  final Rect b = field.bounds(pad: cell * 2);
  final double effectiveMargin = margin ?? cell * 1.5;
  int checked = 0;
  for (double y = b.top; y <= b.bottom; y += probeStep) {
    for (double x = b.left; x <= b.right; x += probeStep) {
      final double d = field.eval(Offset(x, y));
      if (d.abs() < effectiveMargin) {
        continue;
      }
      checked++;
      expect(
        path.contains(Offset(x, y)),
        d < 0,
        reason: 'field/contour sign mismatch at ($x, $y), distance $d',
      );
    }
  }
  expect(checked, greaterThan(50), reason: 'probe net too sparse to trust');
}

/// Shoelace area of a loop: a grid-alignment-tolerant shape measure
/// (bounds shift by sub-cell amounts when the grid origin moves; area
/// is far more stable).
double loopArea(List<Offset> loop) {
  double sum = 0;
  for (int i = 0; i < loop.length; i++) {
    final Offset a = loop[i];
    final Offset b = loop[(i + 1) % loop.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum.abs() / 2;
}

void main() {
  group('contour/field sign consistency', () {
    test('fused pair (goo k)', () {
      const LiquidField field = LiquidField(<MorphMass>[
        .box(.fromLTWH(0, 0, 120, 70), radius: 16),
        .box(.fromLTWH(136, 20, 90, 50), radius: 20),
      ], k: 40);
      expectContourMatchesField(field);
    });

    test('separate islands (gap > k)', () {
      const LiquidField field = LiquidField(<MorphMass>[
        .box(.fromLTWH(0, 0, 100, 60), radius: 12),
        .box(.fromLTWH(180, 10, 80, 40), radius: 10),
      ], k: 20);
      expect(liquidContours(field, cell: 4), hasLength(2));
      expectContourMatchesField(field);
    });

    test('chain of three with mixed gaps', () {
      const LiquidField field = LiquidField(<MorphMass>[
        .box(.fromLTWH(0, 0, 90, 50), radius: 12),
        .box(.fromLTWH(100, 6, 90, 50), radius: 12),
        .box(.fromLTWH(320, 0, 90, 50), radius: 12),
      ], k: 26);
      expectContourMatchesField(field);
    });

    test('distant pair connected by a bridge', () {
      const LiquidField field = LiquidField(<MorphMass>[
        .box(.fromLTWH(0, 0, 80, 50), radius: 10),
        .box(.fromLTWH(220, 0, 80, 50), radius: 10),
        .bridge(Offset(40, 25), Offset(260, 25), radius: 9),
      ], k: 8);
      expect(liquidContours(field, cell: 4), hasLength(1));
      expectContourMatchesField(field);
    });

    test('stadium via radius clamp', () {
      const LiquidField field = LiquidField(<MorphMass>[
        .box(.fromLTWH(0, 0, 140, 48), radius: 500),
      ], k: 12);
      expectContourMatchesField(field);
    });

    // A triangle of bridge pipes must stay hollow inside. This is the
    // fill-rule regression: the stitcher walks loops in arbitrary
    // directions, so with the default nonZero rule the interior hole
    // filled or not by winding accident (and popped on topology
    // changes). evenOdd makes holes independent of winding.
    test('a triangle of bridges is hollow inside', () {
      const Offset a = Offset(20, 20);
      const Offset b = Offset(220, 20);
      const Offset c = Offset(120, 180);
      final LiquidField field = LiquidField(<MorphMass>[
        .box(.fromCenter(center: a, width: 44, height: 44), radius: 14),
        .box(.fromCenter(center: b, width: 44, height: 44), radius: 14),
        .box(.fromCenter(center: c, width: 44, height: 44), radius: 14),
        const MorphMass.bridge(a, b, radius: 10),
        const MorphMass.bridge(b, c, radius: 10),
        const MorphMass.bridge(a, c, radius: 10),
      ], k: 10);

      final Offset centroid = Offset(
        (a.dx + b.dx + c.dx) / 3,
        (a.dy + b.dy + c.dy) / 3,
      );
      expect(
        field.eval(centroid),
        greaterThan(0),
        reason: 'the probe must genuinely lie in the field hole',
      );
      final Path path = liquidPath(field, cell: 4);
      expect(
        path.contains(centroid),
        isFalse,
        reason: 'the ring interior must stay hollow',
      );
      expect(
        path.contains(const Offset(120, 20)),
        isTrue,
        reason: 'the pipe itself must stay filled',
      );
      expectContourMatchesField(field);
    });
  });

  group('eval budget (graceful degradation)', () {
    // A screen-wide blob of many fused shapes exceeds the budget; the
    // grid coarsens but geometry must stay sign-correct within the
    // coarser margin, and the result must stay deterministic.
    test('over-budget scene keeps sign-correct geometry', () {
      final List<Rect> rects = <Rect>[
        for (int i = 0; i < 40; i++)
          .fromLTWH((i % 8) * 110.0, (i ~/ 8) * 110.0, 100, 100),
      ];
      final LiquidField field = LiquidField(<MorphMass>[
        for (final Rect rect in rects) .box(rect, radius: 16),
      ], k: 20);
      const int budget = 30000;
      // The overshoot factor here coarsens the grid ~6x; deep interiors
      // (50px from the surface) and far exteriors must survive that.
      final Path path = liquidPath(field, cell: 4, evalBudget: budget);
      for (final Rect rect in rects) {
        expect(
          path.contains(rect.center),
          isTrue,
          reason: 'piece center at ${rect.center} must stay inside',
        );
      }
      final Rect far = field.bounds(pad: 60);
      expect(path.contains(far.topLeft), isFalse);
      expect(path.contains(far.bottomRight), isFalse);
    });

    test('budgeted tracing is deterministic', () {
      final LiquidField field = LiquidField(<MorphMass>[
        for (int i = 0; i < 24; i++)
          .box(
            .fromLTWH((i % 6) * 120.0, (i ~/ 6) * 120.0, 100, 80),
            radius: 14,
          ),
      ], k: 18);
      final Rect first = liquidPath(field, evalBudget: 20000).getBounds();
      final Rect second = liquidPath(field, evalBudget: 20000).getBounds();
      expect(first, second);
    });
  });

  group('LiquidTracer (per-cluster cache)', () {
    List<MorphMass> scene({double movedX = 0}) {
      return <MorphMass>[
        .box(.fromLTWH(0 + movedX, 0, 100, 60), radius: 12),
        const MorphMass.box(.fromLTWH(90, 20, 80, 50), radius: 12),
        const MorphMass.box(.fromLTWH(400, 0, 100, 60), radius: 14),
        const MorphMass.box(.fromLTWH(0, 300, 90, 55), radius: 10),
      ];
    }

    test('matches the pure liquidPath exactly', () {
      final LiquidField field = LiquidField(scene(), k: 18);
      final LiquidTracer tracer = LiquidTracer();
      expect(tracer.trace(field).getBounds(), liquidPath(field).getBounds());
      expect(tracer.lastClusterCount, 3);
      expect(tracer.lastMissCount, 3);
    });

    test('re-traces only the cluster that changed', () {
      final LiquidTracer tracer = LiquidTracer();
      tracer.trace(LiquidField(scene(), k: 18));
      tracer.trace(LiquidField(scene(), k: 18));
      expect(tracer.lastMissCount, 0, reason: 'identical scene: all cached');

      final LiquidField moved = LiquidField(scene(movedX: 4), k: 18);
      final Path cached = tracer.trace(moved);
      expect(
        tracer.lastMissCount,
        1,
        reason: 'only the moved piece\'s cluster re-traces',
      );
      // The cached composite must be identical to a fresh trace.
      expect(cached.getBounds(), liquidPath(moved).getBounds());
    });

    test('a global knob change invalidates everything', () {
      final LiquidTracer tracer = LiquidTracer();
      tracer.trace(LiquidField(scene(), k: 18));
      tracer.trace(LiquidField(scene(), k: 30));
      expect(tracer.lastMissCount, tracer.lastClusterCount);
    });
  });

  group('near-range interaction (no over-eager culling)', () {
    // Two shapes with a gap in (k/2, k) do NOT merge but DO bulge
    // toward each other: facing surfaces (opposite normals) blend over
    // the full k, so the field bends wherever the distance difference
    // is below k. An optimization that culls the neighbor too
    // aggressively (e.g. clustering with a threshold below k) loses the
    // bulge and fails here.
    test('gap of 0.75k keeps islands apart but bulging', () {
      const double k = 24;
      const Rect left = .fromLTWH(0, 0, 100, 60);
      const Rect right = .fromLTWH(118, 0, 100, 60);

      const LiquidField pair = LiquidField(<MorphMass>[
        .box(left, radius: 12),
        .box(right, radius: 12),
      ], k: k);
      const LiquidField solo = LiquidField(<MorphMass>[
        .box(left, radius: 12),
      ], k: k);

      final List<List<Offset>> loops = liquidContours(pair, cell: 3);
      expect(loops, hasLength(2));

      final List<Offset> leftLoop = loops.firstWhere(
        (List<Offset> loop) =>
            loop.map((Offset p) => p.dx).reduce((a, b) => a < b ? a : b) < 50,
      );
      final double pairRight = leftLoop
          .map((Offset p) => p.dx)
          .reduce((a, b) => a > b ? a : b);
      final double soloRight = liquidContours(
        solo,
        cell: 3,
      ).single.map((Offset p) => p.dx).reduce((a, b) => a > b ? a : b);
      expect(
        pairRight,
        greaterThan(soloRight + 0.3),
        reason: 'the facing edge must bulge toward the neighbor',
      );
      expectContourMatchesField(pair, cell: 3);
    });

    // The Liquid Glass law: the blend width shrinks with the angle
    // between the two normals, to nothing where edges run side by side.
    // Two fused boxes keep their aligned tops and bottoms straight; an
    // unmodulated smooth minimum would lift them by up to ~1.6 px here
    // next to the joint.
    test('fused pair keeps its aligned edges straight', () {
      const double k = 40;
      const LiquidField pair = LiquidField(<MorphMass>[
        .box(.fromLTWH(0, 0, 100, 60), radius: 12),
        .box(.fromLTWH(110, 0, 100, 60), radius: 12),
      ], k: k);
      final List<List<Offset>> loops = liquidContours(pair, cell: 2);
      expect(loops, hasLength(1), reason: 'a gap below k/2 fuses');
      final List<Offset> loop = loops.single;
      final double top = loop
          .map((Offset p) => p.dy)
          .reduce((a, b) => a < b ? a : b);
      final double bottom = loop
          .map((Offset p) => p.dy)
          .reduce((a, b) => a > b ? a : b);
      expect(top, greaterThan(-0.3));
      expect(bottom, lessThan(60.3));
      expect(
        pair.eval(const Offset(88, -0.5)),
        greaterThan(0.4),
        reason: 'the top edge next to the joint is not lifted',
      );
      expectContourMatchesField(pair, cell: 2);
    });

    // Beyond a gap of k the mix-form smin is EXACTLY min, so a distant
    // neighbor must not change the shape at all (up to sub-cell grid
    // alignment). Guards cluster splitting from the opposite side:
    // splitting is allowed to change nothing.
    test('gap of 2k leaves shapes bit-identical in area', () {
      const double k = 20;
      const Rect left = .fromLTWH(0, 0, 100, 60);
      const Rect right = .fromLTWH(140 + 20, 0, 100, 60);

      const LiquidField pair = LiquidField(<MorphMass>[
        .box(left, radius: 12),
        .box(right, radius: 12),
      ], k: k);
      const LiquidField solo = LiquidField(<MorphMass>[
        .box(left, radius: 12),
      ], k: k);

      final List<List<Offset>> loops = liquidContours(pair, cell: 4);
      expect(loops, hasLength(2));
      final double pairArea = loops
          .map(loopArea)
          .reduce((a, b) => a < b ? a : b);
      final double soloArea = loopArea(liquidContours(solo, cell: 4).single);
      expect(
        (pairArea - soloArea).abs() / soloArea,
        lessThan(0.015),
        reason: 'a neighbor beyond k must not deform the shape',
      );
    });
  });
}
