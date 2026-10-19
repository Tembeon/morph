import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

/// How far from its leading side a navigation card of [size], clipped to a
/// rounded superellipse with corner [radius], can leave anything of the
/// page under it visible, in logical pixels, on a device with
/// [devicePixelRatio].
///
/// Impeller's rounded superellipse has no straight edges: its top and
/// bottom edges are superellipse arcs from the middle of each edge,
/// flattened into chords. Under a pixel-aligned edge the first 4x MSAA
/// sample sits 1/8 pixel deep, so a column of the card hides what is under
/// it fully once the chord there is less deep than that. This walks the
/// top edge's chords as Impeller tessellates them (round_superellipse_param
/// and round_superellipse_geometry, Flutter 3.47) and returns the distance
/// from the side at which they first reach 0.1 pixel deep (the 1/8 less
/// the float rounding between the engine and this walk), plus one device
/// pixel; never less than the corner itself.
@internal
double navigationCardEdgeReach(
  Size size,
  double radius,
  double devicePixelRatio,
) {
  final a = size.width / 2;
  final r = math.min(radius, math.min(a, size.height / 2));
  final margin = 1 / devicePixelRatio;
  if (r <= 1e-3) return margin;
  final (n, xJ) = _degree(2 * a / r);
  final maxTheta = math.asin(math.pow(xJ, n / 2).toDouble());
  final span = a - a * math.pow(math.cos(maxTheta).abs(), 2 / n);
  final step = math.min(math.pi / 80, maxTheta / math.max(1, span.ceil()));
  final depth = 0.1 / devicePixelRatio;
  var x0 = 0.0;
  var d0 = 0.0;
  for (var k = 1; ; k++) {
    final theta = math.min(k * step, maxTheta);
    final x1 = a * math.pow(math.sin(theta).abs(), 2 / n);
    final d1 = a - a * math.pow(math.cos(theta).abs(), 2 / n);
    if (d1 >= depth) {
      final x = d0 >= depth ? x0 : x0 + (x1 - x0) * (depth - d0) / (d1 - d0);
      return math.max(a - x, r) + margin;
    }
    if (theta >= maxTheta) break;
    x0 = x1;
    d0 = d1;
  }
  // Past J the corner is a circular arc that only goes deeper.
  return math.max(a - xJ * a, r) + margin;
}

// Impeller's precomputed degree n and k = 1 / (1 - xJ / a) by ratio
// 2a / r, linearly interpolated, and extrapolated on a line past 5.
const _table = <(double, double)>[
  (2.00000000, 1.13276676),
  (2.18349805, 1.20311921),
  (2.33888662, 1.28698796),
  (2.48660575, 1.36351941),
  (2.62226596, 1.44717976),
  (2.75148990, 1.53385819),
  (3.36298265, 1.98288283),
  (4.08649929, 2.23811846),
  (4.85481134, 2.47563463),
  (5.62945551, 2.72948597),
  (6.43023796, 2.98020421),
];

(double, double) _degree(double ratio) {
  if (ratio > 5) {
    final n = 1.559599389 * (ratio - 5) + _table.last.$1;
    final k = 0.522807185 * (ratio - 5) + _table.last.$2;
    return (n, 1 - 1 / k);
  }
  final clamped = ratio.clamp(2.0, 5.0);
  final steps = clamped < 2.5 ? (clamped - 2) * 10 : (clamped - 2.5) * 2 + 5;
  final left = steps.floor().clamp(0, _table.length - 2);
  final frac = steps - left;
  final n = (1 - frac) * _table[left].$1 + frac * _table[left + 1].$1;
  final k = (1 - frac) * _table[left].$2 + frac * _table[left + 1].$2;
  return (n, 1 - 1 / k);
}
