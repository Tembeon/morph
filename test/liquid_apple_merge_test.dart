import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/liquid_field.dart';

/// The skin against Liquid Glass merges measured on an iPhone 16 Pro,
/// iOS 27.0.1 (UIKit UIGlassContainerEffect and SwiftUI
/// GlassEffectContainer): pairs of 60x44 capsules and 44x44 circles at
/// gaps 40 .. -5 pt, container spacing 10/20/40/80 pt = blend 1:1.
///
/// The fixtures are silhouette heights H(x) every 1/3 pt between the
/// two shape centers. The measured silhouette sits 0.40 pt outside the
/// SDF zero (the tint fill's outward offset less antialiasing), so the
/// scenes are traced with every shape inflated by that much - the same
/// as tracing the field's 0.40 level, because the smooth union shifts
/// with its operands and inflation leaves the normals alone.
const String _fixtures = 'test/fixtures/ios27-device/merge';
const double _silhouetteOutset = 0.40;
const double _cell = 0.5;

Map<String, Object?> _json(String name) =>
    jsonDecode(File('$_fixtures/$name').readAsStringSync())
        as Map<String, Object?>;

double _number(Object? value) => (value! as num).toDouble();

/// The pair as the device laid it out: two equal shapes either side of
/// cx with [gap] between their facing edges.
LiquidField _pairField({
  required double w,
  required double h,
  required double cx,
  required double cy,
  required double gap,
  required double spacing,
}) {
  final double radius = h / 2 + _silhouetteOutset;
  MorphMass shape(double centerX) => .box(
    Rect.fromCenter(
      center: Offset(centerX, cy),
      width: w,
      height: h,
    ).inflate(_silhouetteOutset),
    radius: radius,
  );
  return LiquidField(<MorphMass>[
    shape(cx - gap / 2 - w / 2),
    shape(cx + gap / 2 + w / 2),
  ], k: spacing);
}

/// The traced silhouette's height at each of [xs]: the span between the
/// highest and the lowest crossing of the contour with that column, 0
/// where nothing crosses.
List<double> _heights(List<List<Offset>> loops, List<double> xs) {
  return <double>[
    for (final double x in xs)
      () {
        double top = double.infinity;
        double bottom = double.negativeInfinity;
        for (final List<Offset> loop in loops) {
          for (int i = 0; i < loop.length; i++) {
            final Offset a = loop[i];
            final Offset b = loop[(i + 1) % loop.length];
            if ((a.dx - x) * (b.dx - x) > 0 || a.dx == b.dx) {
              continue;
            }
            final double t = (x - a.dx) / (b.dx - a.dx);
            final double y = a.dy + (b.dy - a.dy) * t;
            top = math.min(top, y);
            bottom = math.max(bottom, y);
          }
        }
        return bottom > top ? bottom - top : 0.0;
      }(),
  ];
}

/// Whether [gap] sits at the touch threshold, where two facing caps
/// first meet: half the spacing plus the silhouette outset of both.
bool _nearTouch(double gap, double spacing) =>
    (gap - spacing / 2 - 2 * _silhouetteOutset).abs() < 1.5;

typedef _PairFit = ({double rms, double neck, double measuredNeck});

_PairFit _fitPair(Map<String, Object?> pair, double spacing) {
  final double w = _number(pair['w']);
  final double h = _number(pair['h']);
  final double cx = _number(pair['cx']);
  final double cy = _number(pair['cy']);
  final double gap = _number(pair['gap']);
  final double x0 = _number(pair['x0']);
  final double dx = _number(pair['dx']);
  final List<double> measured = <double>[
    for (final Object? v in pair['H']! as List<Object?>) _number(v),
  ];
  final LiquidField field = _pairField(
    w: w,
    h: h,
    cx: cx,
    cy: cy,
    gap: gap,
    spacing: spacing,
  );
  final List<List<Offset>> loops = liquidContours(
    field,
    cell: _cell,
    smoothPasses: 0,
    evalBudget: null,
  );
  final List<double> xs = <double>[
    for (int i = 0; i < measured.length; i++) x0 + i * dx,
  ];
  final List<double> traced = _heights(loops, xs);
  double sum = 0;
  for (int i = 0; i < measured.length; i++) {
    final double e = traced[i] - measured[i];
    sum += e * e;
  }
  final int mid = ((cx - x0) / dx).round();
  return (
    rms: math.sqrt(sum / measured.length),
    neck: _heights(loops, <double>[cx]).single,
    measuredNeck: measured[mid],
  );
}

void main() {
  for (final String api in <String>['uikit', 'swiftui']) {
    group('$api profiles', () {
      final Map<String, Object?> pages =
          _json('profiles-$api.json')['pages']! as Map<String, Object?>;
      for (final double spacing in <double>[10, 20, 40, 80]) {
        test(
          'spacing ${spacing.round()}: whole H(x) within the noise floor',
          () {
            final List<Object?> pairs =
                pages['${spacing.round()}']! as List<Object?>;
            double sum = 0;
            for (final Object? raw in pairs) {
              final Map<String, Object?> pair = raw! as Map<String, Object?>;
              final _PairFit fit = _fitPair(pair, spacing);
              sum += fit.rms * fit.rms;
              // The touch threshold (gap = spacing / 2) is a square root:
              // a 0.1 pt offset flips the neck between 0 and ~2.3 pt, and
              // the cap-tip columns carry the edge's own sub-point error.
              final bool threshold = _nearTouch(_number(pair['gap']), spacing);
              expect(
                fit.rms,
                lessThan(threshold ? 0.8 : 0.6),
                reason:
                    '${pair['kind']} gap ${pair['gap']}: profile rms '
                    '${fit.rms.toStringAsFixed(3)} pt',
              );
            }
            final double rms = math.sqrt(sum / pairs.length);
            // The law fits the device at 0.17 - 0.33 pt rms (the screenshot
            // noise floor is 0.21 - 0.23); a half-point grid adds a little.
            expect(
              rms,
              lessThan(0.4),
              reason: 'page rms ${rms.toStringAsFixed(3)} pt',
            );
          },
        );
      }
    });
  }

  test('neck heights at mid-gap match the device', () {
    final Map<String, Object?> necks = _json('necks.json');
    final Map<String, Object?> pages =
        _json('profiles-uikit.json')['pages']! as Map<String, Object?>;
    int checked = 0;
    for (final Object? raw in necks['rows']! as List<Object?>) {
      final List<Object?> row = raw! as List<Object?>;
      if (row[0] != 'uikit') {
        continue;
      }
      final double spacing = _number(row[1]);
      final String kind = row[2]! as String;
      final double gap = _number(row[3]);
      final double measured = _number(row[4]);
      final Map<String, Object?> pair =
          (pages['${spacing.round()}']! as List<Object?>)
              .cast<Map<String, Object?>>()
              .firstWhere(
                (Map<String, Object?> p) =>
                    p['kind'] == kind && _number(p['gap']) == gap,
              );
      final _PairFit fit = _fitPair(pair, spacing);
      final bool threshold = _nearTouch(gap, spacing);
      expect(
        (fit.neck - measured).abs(),
        lessThan(threshold ? 2.6 : 0.5),
        reason:
            'spacing $spacing $kind gap $gap: neck '
            '${fit.neck.toStringAsFixed(2)} vs ${measured.toStringAsFixed(2)}',
      );
      checked++;
    }
    expect(checked, greaterThan(30));
  });

  test('aligned edges stay straight: spacing 80 never lifts the tops', () {
    // Two 44 pt capsules overlapping at spacing 80 merge 47.1 pt tall on
    // the device; an unmodulated smooth minimum would lift the aligned
    // top and bottom edges by k/4 each and make it ~75.
    final LiquidField field = _pairField(
      w: 60,
      h: 44,
      cx: 110,
      cy: 150,
      gap: -5,
      spacing: 80,
    );
    final List<List<Offset>> loops = liquidContours(
      field,
      cell: _cell,
      smoothPasses: 0,
      evalBudget: null,
    );
    expect(loops, hasLength(1));
    final double tallest = <double>[
      for (double x = 60; x <= 160; x += 1) _heights(loops, <double>[x]).single,
    ].reduce(math.max);
    expect(tallest, closeTo(47.14, 0.5));
  });
}
