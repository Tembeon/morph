import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// The signed distance from [p] to the stadium of [rect].
double _stadium(Offset p, Rect rect) {
  final radius = math.min(rect.width, rect.height) / 2;
  final qx = (p.dx - rect.center.dx).abs() - rect.width / 2 + radius;
  final qy = (p.dy - rect.center.dy).abs() - rect.height / 2 + radius;
  final ox = math.max(qx, 0.0);
  final oy = math.max(qy, 0.0);
  return math.sqrt(ox * ox + oy * oy) +
      math.min(math.max(qx, qy), 0.0) -
      radius;
}

/// The largest distance from Flutter's rounded superellipse outline of a
/// [width] x 44 pt box with 22 pt corners to the stadium of the same box,
/// in device pixels at [dpr].
double _deviation(double width, double dpr) {
  final rect = Rect.fromLTWH(0, 0, width * dpr, 44 * dpr);
  final path = Path();
  path.addRSuperellipse(
    RSuperellipse.fromRectAndRadius(rect, Radius.circular(22 * dpr)),
  );
  var worst = 0.0;
  for (final metric in path.computeMetrics()) {
    for (var d = 0.0; d < metric.length; d += 0.05) {
      final p = metric.getTangentForOffset(d)!.position;
      worst = math.max(worst, _stadium(p, rect).abs());
    }
  }
  return worst;
}

/// A full-radius rounded superellipse is not a stadium in Flutter's
/// definition (impeller/geometry/round_superellipse_param.cc: a
/// superellipse of degree 2 joined to a circular arc, its octants fitted
/// to the ratio of the half size to the radius): only the square one, a
/// circle, coincides. ShaderKeys.analyticCapsule shades it as the stadium
/// anyway; this pins how far apart the two are for 44 pt capsules at a
/// 3.14 pixel ratio.
void main() {
  test('a full-radius rounded superellipse lies inside its stadium', () {
    const dpr = 3.14;
    final deviations = {
      for (final width in [44.0, 60.0, 96.0, 120.0, 200.0, 379.0])
        width: _deviation(width, dpr),
    };
    // The deviation per width is the test's output.
    // ignore: avoid_print
    print('max |superellipse - stadium| device px at $dpr: $deviations');
    expect(deviations[44]!, lessThan(0.05));
    for (final width in [60.0, 96.0, 120.0, 200.0, 379.0]) {
      expect(deviations[width]!, inInclusiveRange(0.5, 1.5));
    }
  });
}
