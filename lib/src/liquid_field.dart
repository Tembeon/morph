/// Liquid geometry: a scalar signed-distance field (SDF) and its vector
/// tracing. The whole surface "fusion" is one idea: shapes are not drawn
/// individually but united by a smooth minimum of their fields; the
/// blend zone at a joint IS the concave fillet. The smooth minimum is
/// the one iOS 27 Liquid Glass draws, measured on a device: its width
/// at each point is [LiquidField.k] scaled by `(1 - dot(na, nb)) / 2`,
/// where `na` and `nb` are the unit gradients of the two operands - full
/// width where surfaces face each other, none where their edges run
/// side by side, so aligned edges stay straight. The zero iso-contour is
/// traced by marching squares into an ordinary [Path] - no shaders and
/// no blur+threshold, hence no halos.
///
/// Sign convention is standard SDF: negative inside a shape, zero on the
/// surface, positive outside.
///
/// This layer is pure: only numbers and [Path], no widgets and no time.
/// Animation is the consumer's job: every input (rect, radius, k) can be
/// driven from a single spring value, keeping the system invariant
/// intact.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:meta/meta.dart';

/// A named bundle of fusion knobs - in the spirit of MorphMotion
/// presets. blend and cell are distances in pixels.
class MorphSkinStyle {
  /// Creates a named knob bundle.
  const MorphSkinStyle({
    required this.name,
    required this.blend,
    this.cell = 6,
    this.smoothPasses = 2,
  });

  /// Preset name, for debugging and toString.
  final String name;

  /// The fusion width in px: Liquid Glass's container spacing, 1:1.
  /// Two facing surfaces start to lean toward each other below a gap
  /// of blend and touch at a gap of blend / 2.
  final double blend;

  /// Outline grid step in px.
  final double cell;

  /// Chaikin smoothing passes over the traced contour.
  final int smoothPasses;

  /// SwiftUI's default: a `GlassEffectContainer` without a spacing
  /// merges with a spacing of 8 pt on iOS 27.
  static const MorphSkinStyle subtle = MorphSkinStyle(name: 'subtle', blend: 8);

  /// The built-in presets.
  static const List<MorphSkinStyle> values = <MorphSkinStyle>[subtle];

  // Value equality: MorphTheme compares by ==, and an identity-compared
  // custom style would make every theme rebuild read as a change.
  @override
  bool operator ==(Object other) {
    return other is MorphSkinStyle &&
        other.name == name &&
        other.blend == blend &&
        other.cell == cell &&
        other.smoothPasses == smoothPasses;
  }

  @override
  int get hashCode => Object.hash(name, blend, cell, smoothPasses);

  @override
  String toString() => 'MorphSkinStyle.$name';
}

/// Polynomial smooth minimum in the mix form (no derivative kink at the
/// seam): `min(a, b) - max(k - |a - b|, 0)^2 / (4 k)`. k = 0 degenerates
/// to a plain min.
double liquidSmin(double a, double b, double k) {
  if (k <= 0) {
    return math.min(a, b);
  }
  final double h = (0.5 + 0.5 * (b - a) / k).clamp(0.0, 1.0);
  return b * (1 - h) + a * h - k * h * (1 - h);
}

/// The blend width below which [LiquidField] merges by a plain min, in
/// px: the smooth minimum dips at most a quarter of its width below the
/// min, so a width this small is indistinguishable from it.
@internal
const double liquidMinMergeWidth = 1e-4;

/// The local blend width of the Liquid Glass merge: [k] scaled by
/// `(1 - dot(na, nb)) / 2`, the squared sine of half the angle between
/// the unit normals [na] and [nb]. Facing surfaces (opposite normals)
/// blend over the full [k], surfaces running side by side (equal
/// normals) not at all.
double liquidMergeWidth(double k, Offset na, Offset nb) {
  return k * (1 - (na.dx * nb.dx + na.dy * nb.dy)) * 0.5;
}

/// Exact distance to a rounded rectangle. The radius is clamped by the
/// half-extents, so radius >= min(w, h) / 2 yields a true stadium.
double liquidBoxDistance(Offset p, Rect rect, double radius) {
  final double hw = rect.width / 2;
  final double hh = rect.height / 2;
  final double r = math.min(radius, math.min(hw, hh));
  final double qx = (p.dx - rect.center.dx).abs() - hw + r;
  final double qy = (p.dy - rect.center.dy).abs() - hh + r;
  final double ax = math.max(qx, 0);
  final double ay = math.max(qy, 0);
  final double outside = math.sqrt(ax * ax + ay * ay);
  final double inside = math.min(math.max(qx, qy), 0);
  return outside + inside - r;
}

/// The unit gradient of [liquidBoxDistance] at [p]: the outward normal
/// of the nearest surface point. Deep inside, past the corner radius,
/// it points along the axis of the nearest straight edge.
Offset liquidBoxNormal(Offset p, Rect rect, double radius) {
  final double hw = rect.width / 2;
  final double hh = rect.height / 2;
  final double r = math.min(radius, math.min(hw, hh));
  final double px = p.dx - rect.center.dx;
  final double py = p.dy - rect.center.dy;
  final double qx = px.abs() - hw + r;
  final double qy = py.abs() - hh + r;
  final double ax = math.max(qx, 0);
  final double ay = math.max(qy, 0);
  final double length = math.sqrt(ax * ax + ay * ay);
  if (length > 0) {
    return Offset(
      px < 0 ? -ax / length : ax / length,
      py < 0 ? -ay / length : ay / length,
    );
  }
  if (qx > qy) {
    return Offset(px < 0 ? -1 : 1, 0);
  }
  return Offset(0, py < 0 ? -1 : 1);
}

/// Distance to a capsule (the segment [a]-[b] with radius [radius]).
double liquidCapsuleDistance(Offset p, Offset a, Offset b, double radius) {
  return (p - _capsuleAxisPoint(p, a, b)).distance - radius;
}

/// The unit gradient of [liquidCapsuleDistance] at [p]: the direction
/// away from the nearest point of the segment [a]-[b]. Zero on the
/// segment itself, where the distance has no gradient.
Offset liquidCapsuleNormal(Offset p, Offset a, Offset b) {
  final Offset d = p - _capsuleAxisPoint(p, a, b);
  final double length = d.distance;
  return length > 0 ? d / length : Offset.zero;
}

Offset _capsuleAxisPoint(Offset p, Offset a, Offset b) {
  final Offset pa = p - a;
  final Offset ba = b - a;
  final double denom = ba.dx * ba.dx + ba.dy * ba.dy;
  final double h = denom < 1e-9
      ? 0
      : ((pa.dx * ba.dx + pa.dy * ba.dy) / denom).clamp(0.0, 1.0);
  return a + ba * h;
}

/// Gap between two rects (0 when they intersect). The "no neck for
/// sure" gate: the local blend width never exceeds k and the smooth
/// minimum equals the plain min wherever the two distances differ by
/// at least it, so with a gap larger than k the smooth union has
/// provably split into islands and a distant shape can be left out of
/// the field.
double liquidRectGap(Rect a, Rect b) {
  final double dx = math.max(0, math.max(a.left - b.right, b.left - a.right));
  final double dy = math.max(0, math.max(a.top - b.bottom, b.top - a.bottom));
  return math.sqrt(dx * dx + dy * dy);
}

/// A raw SDF mass poured into a skin - contentless geometry fused into
/// the contour alongside the pieces ([MorphSkin.extraMasses]). A mass
/// has no morph identity: it cannot fly, it only adds to the shape.
/// Sealed: [MorphMass.box] and [MorphMass.bridge] are the whole
/// vocabulary.
sealed class MorphMass {
  const MorphMass();

  /// A rounded-box mass over [rect]. [radius] is the corner radius,
  /// clamped to the half-extents - a large radius yields a stadium.
  const factory MorphMass.box(Rect rect, {double radius}) = _BoxMass;

  /// An explicit bridge: a capsule pipe of half-width [radius] between
  /// [a] and [b], for fusing two distant masses when proximity fusion
  /// is not enough.
  const factory MorphMass.bridge(Offset a, Offset b, {required double radius}) =
      _BridgeMass;

  /// Signed distance from [p] to the mass surface (negative inside).
  double distance(Offset p);

  Offset _normal(Offset p);

  /// The mass's own bounds, blend excluded: padding by k is added by
  /// [LiquidField.bounds].
  Rect get outerRect;
}

class _BoxMass extends MorphMass {
  const _BoxMass(this.rect, {this.radius = 0})
    : assert(radius >= 0, 'radius cannot be negative.');

  final Rect rect;

  final double radius;

  @override
  double distance(Offset p) => liquidBoxDistance(p, rect, radius);

  @override
  Offset _normal(Offset p) => liquidBoxNormal(p, rect, radius);

  @override
  Rect get outerRect => rect;
}

class _BridgeMass extends MorphMass {
  const _BridgeMass(this.a, this.b, {required this.radius})
    : assert(radius > 0, 'a bridge with no radius has no mass.');

  final Offset a;

  final Offset b;

  final double radius;

  @override
  double distance(Offset p) => liquidCapsuleDistance(p, a, b, radius);

  @override
  Offset _normal(Offset p) => liquidCapsuleNormal(p, a, b);

  @override
  Rect get outerRect => Rect.fromPoints(a, b).inflate(radius);
}

/// Doubles per mass in the canonical flat encoding
/// ([liquidMassSignature]): the kind tag plus five scalar parameters.
@internal
const int liquidMassSignatureStride = 6;

/// Writes [mass]'s canonical flat encoding into [out] at [i] and
/// returns the index past it ([liquidMassSignatureStride] doubles).
/// The ONE flattening of a mass into numbers: the tracer's cluster
/// keys and the skin's input signature both write through here. Full
/// parameters, not the outer rect: two bridges along opposite
/// diagonals share an outer rect and a radius yet trace different
/// capsules.
@internal
int liquidMassSignature(MorphMass mass, Float64List out, int i) {
  switch (mass) {
    case _BoxMass(:final Rect rect, :final double radius):
      out[i] = 0;
      out[i + 1] = rect.left;
      out[i + 2] = rect.top;
      out[i + 3] = rect.width;
      out[i + 4] = rect.height;
      out[i + 5] = radius;
    case _BridgeMass(:final Offset a, :final Offset b, :final double radius):
      out[i] = 1;
      out[i + 1] = a.dx;
      out[i + 2] = a.dy;
      out[i + 3] = b.dx;
      out[i + 4] = b.dy;
      out[i + 5] = radius;
  }
  return i + liquidMassSignatureStride;
}

/// A group of shapes as one field: the Liquid Glass smooth union of all
/// [shapes] with blend [k]. Two shapes whose k-zones overlap fuse on
/// their own - no explicit connection needed.
///
/// The fold runs left to right over the boxes, then over the bridges,
/// each in list order. It carries the field's unit gradient along: each
/// step blends the next mass in over the local width
/// [liquidMergeWidth] of the two normals and mixes the normals by the
/// smooth minimum's own weight. For two masses this is exactly the
/// merge measured on iOS 27; for more it is the natural fold of it.
class LiquidField {
  /// Creates a field over [shapes] with fusion width [k].
  const LiquidField(this.shapes, {this.k = 24})
    : assert(k >= 0, 'k (blend) is a distance in px and cannot be negative.');

  /// The masses of the field.
  final List<MorphMass> shapes;

  /// Blend width in field pixels - Liquid Glass's container spacing,
  /// 1:1. It is a distance: when the scene is scaled, k scales along
  /// with it.
  final double k;

  /// The smooth-union distance of the whole field at [p].
  ///
  /// The reference implementation of the fold, over plain [Offset]
  /// math; the tracer samples the same field through an
  /// allocation-free twin.
  double eval(Offset p) {
    double d = .infinity;
    Offset n = .zero;
    bool first = true;
    for (final bool boxes in const <bool>[true, false]) {
      for (final MorphMass shape in shapes) {
        if ((shape is _BoxMass) != boxes) {
          continue;
        }
        final double di = shape.distance(p);
        final Offset ni = shape._normal(p);
        if (first) {
          d = di;
          n = ni;
          first = false;
          continue;
        }
        final double width = liquidMergeWidth(k, n, ni);
        if (width < liquidMinMergeWidth) {
          if (di < d) {
            d = di;
            n = ni;
          }
          continue;
        }
        final double h = (0.5 + 0.5 * (di - d) / width).clamp(0.0, 1.0);
        d = liquidSmin(d, di, width);
        final Offset mixed = ni * (1 - h) + n * h;
        final double length = mixed.distance;
        n = length > 1e-12 ? mixed / length : Offset.zero;
      }
    }
    return d;
  }

  /// The group bounds with headroom for the fusion bulge: at the
  /// fillets the skin protrudes outward by up to ~k past a shape's
  /// edge; without the padding the marching-squares grid would clip the
  /// blend.
  Rect bounds({double pad = 0}) {
    if (shapes.isEmpty) {
      return Rect.zero;
    }
    Rect r = shapes.first.outerRect;
    for (int i = 1; i < shapes.length; i++) {
      r = r.expandToInclude(shapes[i].outerRect);
    }
    return r.inflate(pad + k);
  }
}

/// The allocation-free evaluator for the sampling hot loop. Shape
/// parameters are flattened into typed arrays once per trace; the
/// per-vertex work is pure double arithmetic - no Offset objects, no
/// virtual dispatch. At ~10^4..10^5 vertices per recompute (every frame
/// during a morph) this is the difference between a silent GC hum and
/// none at all.
///
/// The fold is [LiquidField.eval]'s, step for step. The accumulated
/// distance and normal live in fields, so a step allocates nothing. A
/// mass whose distance differs from the accumulated one by at least k
/// merges by a plain min whatever the normals (the local width never
/// exceeds k), so it skips the dot product, and when it loses, its
/// normal as well - most of a cluster's grid is decided there.
class _FieldSampler {
  factory _FieldSampler(List<MorphMass> shapes, double k) {
    int boxCount = 0;
    for (final MorphMass shape in shapes) {
      if (shape is _BoxMass) {
        boxCount++;
      }
    }
    // Boxes: cx, cy, hw, hh, r (pre-clamped). Bridges: ax, ay, bax,
    // bay, len2 (guarded against zero), r.
    final Float64List boxes = Float64List(boxCount * 5);
    final Float64List bridges = Float64List((shapes.length - boxCount) * 6);
    int bi = 0;
    int gi = 0;
    for (final MorphMass shape in shapes) {
      switch (shape) {
        case _BoxMass(:final Rect rect, :final double radius):
          final double hw = rect.width / 2;
          final double hh = rect.height / 2;
          boxes[bi++] = rect.center.dx;
          boxes[bi++] = rect.center.dy;
          boxes[bi++] = hw;
          boxes[bi++] = hh;
          boxes[bi++] = math.min(radius, math.min(hw, hh));
        case _BridgeMass(
          :final Offset a,
          :final Offset b,
          :final double radius,
        ):
          final double bax = b.dx - a.dx;
          final double bay = b.dy - a.dy;
          bridges[gi++] = a.dx;
          bridges[gi++] = a.dy;
          bridges[gi++] = bax;
          bridges[gi++] = bay;
          bridges[gi++] = math.max(1e-9, bax * bax + bay * bay);
          bridges[gi++] = radius;
      }
    }
    return _FieldSampler._(boxes, bridges, k, shapes.length == 1);
  }

  _FieldSampler._(this._boxes, this._bridges, this._k, this._single);

  final Float64List _boxes;
  final Float64List _bridges;
  final double _k;

  /// One mass alone: its distance is the field, its normal is never
  /// read.
  final bool _single;

  double _d = 0;
  double _nx = 0;
  double _ny = 0;

  double eval(double x, double y) {
    final double k = _k;
    // Seeded by the first shape, exactly like the reference
    // LiquidField.eval: folding infinity through smin would produce
    // infinity * 0 = NaN.
    bool first = true;
    final Float64List boxes = _boxes;
    for (int i = 0; i < boxes.length; i += 5) {
      final double px = x - boxes[i];
      final double py = y - boxes[i + 1];
      final double r = boxes[i + 4];
      final double qx = px.abs() - boxes[i + 2] + r;
      final double qy = py.abs() - boxes[i + 3] + r;
      final double ax = qx > 0 ? qx : 0.0;
      final double ay = qy > 0 ? qy : 0.0;
      final double length = math.sqrt(ax * ax + ay * ay);
      double di = length - r;
      final double inner = qx > qy ? qx : qy;
      if (inner < 0) {
        di += inner;
      }
      final bool seed = first;
      if (seed) {
        if (_single) {
          return di;
        }
        first = false;
      } else if (di - _d >= k) {
        continue;
      }
      double nx;
      double ny;
      if (length > 0) {
        nx = ax / length;
        ny = ay / length;
      } else if (qx > qy) {
        nx = 1;
        ny = 0;
      } else {
        nx = 0;
        ny = 1;
      }
      if (px < 0) {
        nx = -nx;
      }
      if (py < 0) {
        ny = -ny;
      }
      if (seed) {
        _d = di;
        _nx = nx;
        _ny = ny;
      } else {
        _merge(di, nx, ny);
      }
    }
    final Float64List bridges = _bridges;
    for (int i = 0; i < bridges.length; i += 6) {
      final double pax = x - bridges[i];
      final double pay = y - bridges[i + 1];
      final double bax = bridges[i + 2];
      final double bay = bridges[i + 3];
      double h = (pax * bax + pay * bay) / bridges[i + 4];
      if (h < 0) {
        h = 0;
      } else if (h > 1) {
        h = 1;
      }
      final double dx = pax - bax * h;
      final double dy = pay - bay * h;
      final double length = math.sqrt(dx * dx + dy * dy);
      final double di = length - bridges[i + 5];
      final bool seed = first;
      if (seed) {
        if (_single) {
          return di;
        }
        first = false;
      } else if (di - _d >= k) {
        continue;
      }
      final double nx = length > 0 ? dx / length : 0.0;
      final double ny = length > 0 ? dy / length : 0.0;
      if (seed) {
        _d = di;
        _nx = nx;
        _ny = ny;
      } else {
        _merge(di, nx, ny);
      }
    }
    return first ? .infinity : _d;
  }

  /// Folds a mass at distance [b] with unit normal ([bx], [by]) into
  /// the accumulator; the caller has already let the accumulator win
  /// every step it wins by k or more.
  void _merge(double b, double bx, double by) {
    final double a = _d;
    if (a - b >= _k) {
      _d = b;
      _nx = bx;
      _ny = by;
      return;
    }
    final double width = _k * (1 - (_nx * bx + _ny * by)) * 0.5;
    if (width < liquidMinMergeWidth) {
      if (b < a) {
        _d = b;
        _nx = bx;
        _ny = by;
      }
      return;
    }
    double h = 0.5 + 0.5 * (b - a) / width;
    if (h < 0) {
      h = 0;
    } else if (h > 1) {
      h = 1;
    }
    _d = b * (1 - h) + a * h - width * h * (1 - h);
    final double mx = bx * (1 - h) + _nx * h;
    final double my = by * (1 - h) + _ny * h;
    final double length = math.sqrt(mx * mx + my * my);
    if (length > 1e-12) {
      _nx = mx / length;
      _ny = my / length;
    } else {
      _nx = 0;
      _ny = 0;
    }
  }
}

/// Connectivity labels over [rects]: rects whose gap is at most [k]
/// share a label (transitively), labels are dense from zero. The ONE
/// implementation of the body predicate - the tracer's cluster split
/// and the skin's launch fellowship both delegate here, so the two
/// notions of "one body" cannot drift apart.
@internal
List<int> liquidConnectivityLabels(List<Rect> rects, double k) {
  final int n = rects.length;
  final List<int> labels = .filled(n, -1);
  int count = 0;
  final List<int> queue = <int>[];
  for (int seed = 0; seed < n; seed++) {
    if (labels[seed] != -1) {
      continue;
    }
    final int id = count++;
    labels[seed] = id;
    queue.add(seed);
    while (queue.isNotEmpty) {
      final int current = queue.removeLast();
      for (int other = 0; other < n; other++) {
        if (labels[other] == -1 &&
            liquidRectGap(rects[current], rects[other]) <= k) {
          labels[other] = id;
          queue.add(other);
        }
      }
    }
  }
  return labels;
}

/// Splits shapes into connectivity clusters: shapes whose bounds gap is
/// <= k belong together (transitively). Each cluster is traced on its
/// own tight grid instead of one grid over the union bounds - for
/// spread-out scenes this shrinks the sampled area by orders of
/// magnitude.
///
/// Exactness proof sketch: the local blend width k' = k (1 - na.nb) / 2
/// never exceeds k, and the mix-form smin with any width k' <= k equals
/// the plain min exactly - distance AND carried normal, the winner's -
/// once the distance difference reaches k. On and near cluster A's zero
/// contour, every point lies on A's surface, so its distance to any
/// shape of another cluster is at least the inter-cluster gap (> k) -
/// the neighbor's contribution vanishes identically there. Mutual
/// bulging exists only below a gap of k, which keeps such shapes in one
/// cluster by construction; and no phantom mass can appear between
/// clusters because at a midpoint both distances exceed k/2 while smin
/// dips at most k'/4 <= k/4 below the plain min. The split is therefore
/// not an approximation.
List<List<MorphMass>> _clusterShapes(List<MorphMass> shapes, double k) {
  final int n = shapes.length;
  if (n <= 1) {
    return <List<MorphMass>>[shapes];
  }
  final List<int> cluster = liquidConnectivityLabels(<Rect>[
    for (final MorphMass shape in shapes) shape.outerRect,
  ], k);
  int clusterCount = 0;
  for (final int id in cluster) {
    if (id >= clusterCount) {
      clusterCount = id + 1;
    }
  }
  if (clusterCount == 1) {
    return <List<MorphMass>>[shapes];
  }
  final List<List<MorphMass>> result = <List<MorphMass>>[
    for (int i = 0; i < clusterCount; i++) <MorphMass>[],
  ];
  for (int i = 0; i < n; i++) {
    result[cluster[i]].add(shapes[i]);
  }
  return result;
}

// Marching-squares table: for each of the 16 corner masks, the pairs of
// cell edges the contour crosses. Edges: 0 top, 1 right, 2 bottom,
// 3 left. Corner bits: 8 TL, 4 TR, 2 BR, 1 BL (bit set = inside, field
// < 0). Saddles (masks 5 and 10) are resolved by the cell-center sign.
const List<List<List<int>>> _kEdgeTable = <List<List<int>>>[
  <List<int>>[],
  <List<int>>[
    <int>[3, 2],
  ],
  <List<int>>[
    <int>[2, 1],
  ],
  <List<int>>[
    <int>[3, 1],
  ],
  <List<int>>[
    <int>[0, 1],
  ],
  <List<int>>[
    <int>[3, 2],
    <int>[0, 1],
  ],
  <List<int>>[
    <int>[0, 2],
  ],
  <List<int>>[
    <int>[3, 0],
  ],
  <List<int>>[
    <int>[3, 0],
  ],
  <List<int>>[
    <int>[0, 2],
  ],
  <List<int>>[
    <int>[3, 0],
    <int>[2, 1],
  ],
  <List<int>>[
    <int>[0, 1],
  ],
  <List<int>>[
    <int>[3, 1],
  ],
  <List<int>>[
    <int>[2, 1],
  ],
  <List<int>>[
    <int>[3, 2],
  ],
  <List<int>>[],
];

Offset _zeroCrossing(
  double x0,
  double y0,
  double v0,
  double x1,
  double y1,
  double v1,
) {
  final double denom = v0 - v1;
  final double t = denom.abs() < 1e-6 ? 0.5 : (v0 / denom).clamp(0.0, 1.0);
  return Offset(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t);
}

/// The default cap on field evaluations (grid vertices x shapes) per
/// cluster per trace. Typical scenes stay far below it; extreme ones (a
/// screen-wide blob of dozens of fused pieces) coarsen their grid just
/// enough to fit, so the worst frame cost is bounded. A deterministic
/// function of geometry - no time, no hysteresis; the same scene always
/// traces identically. Surfaced publicly as `MorphSkin.defaultEvalBudget`.
@internal
const int liquidDefaultEvalBudget = 200000;

/// Traces the zero iso-contour: closed point loops in field coordinates.
/// Contour points are placed by linearly interpolating the zero crossing
/// along a cell edge (not at the midpoint) - this is what turns the grid
/// staircase into a curve. [cell] is the grid step in field pixels,
/// [smoothPasses] the number of Chaikin smoothing passes.
///
/// Shapes are first split into connectivity clusters (see
/// [_clusterShapes]); each cluster is sampled on its own tight grid.
/// [evalBudget] caps the per-cluster field evaluations by coarsening the
/// grid when exceeded (quality degrades before the frame rate does);
/// null disables the cap.
List<List<Offset>> liquidContours(
  LiquidField field, {
  double cell = 6,
  int smoothPasses = 2,
  int? evalBudget = liquidDefaultEvalBudget,
}) {
  assert(cell > 0, 'cell is the sampling grid step in px, must be > 0.');
  assert(smoothPasses >= 0, 'smoothPasses cannot be negative.');
  assert(
    evalBudget == null || evalBudget > 0,
    'evalBudget must be positive; null disables the budget.',
  );
  final double step = math.max(2, cell);
  final List<List<Offset>> loops = <List<Offset>>[];
  for (final List<MorphMass> cluster in _clusterShapes(field.shapes, field.k)) {
    loops.addAll(
      _tracedAndSmoothed(cluster, field.k, step, smoothPasses, evalBudget),
    );
  }
  return loops;
}

List<List<Offset>> _tracedAndSmoothed(
  List<MorphMass> cluster,
  double k,
  double step,
  int smoothPasses,
  int? evalBudget,
) {
  final _ClusterTrace trace = _traceCluster(cluster, k, step, evalBudget);
  if (smoothPasses <= 0) {
    return trace.loops;
  }
  // A budget-coarsened grid produces fewer, more faceted points; extra
  // Chaikin passes buy the roundness back almost for free (the point
  // count the passes double is small precisely because the grid is
  // coarse).
  final int passes = smoothPasses + trace.extraSmoothPasses;
  return <List<Offset>>[
    for (final List<Offset> loop in trace.loops) _chaikin(loop, passes),
  ];
}

/// A stateful tracer with a per-cluster cache: only clusters whose
/// geometry actually changed are re-traced; the rest reuse their loops
/// from the previous call. This is what keeps a mostly-static group
/// cheap while one piece animates (a flight blob crossing the canvas
/// re-traces its own cluster, not the whole scene).
///
/// Cache keys are full per-cluster signatures (fold order, every shape
/// parameter, k/cell/smoothing/budget) compared element-wise on hash
/// collision - a changed cluster can never reuse a stale contour. The
/// cache is swapped wholesale on every [trace], so it never grows past
/// the current scene.
///
/// The pure [liquidPath]/[liquidContours] remain for one-shot use;
/// MorphSkin holds one tracer per State.
class LiquidTracer {
  Map<int, List<_ClusterCacheEntry>> _cache = <int, List<_ClusterCacheEntry>>{};

  /// Clusters re-traced by the last [trace] call - instrumentation for
  /// tests and performance work.
  int lastMissCount = 0;

  /// Total clusters seen by the last [trace] call.
  int lastClusterCount = 0;

  /// Traces [field] into a contour path, re-tracing only the clusters
  /// whose geometry changed since the previous call.
  Path trace(
    LiquidField field, {
    double cell = 6,
    int smoothPasses = 2,
    int? evalBudget = liquidDefaultEvalBudget,
  }) {
    final double step = math.max(2, cell);
    final Path path = Path()..fillType = .evenOdd;
    final Map<int, List<_ClusterCacheEntry>> next =
        <int, List<_ClusterCacheEntry>>{};
    final List<List<MorphMass>> clusters = _clusterShapes(
      field.shapes,
      field.k,
    );
    lastClusterCount = clusters.length;
    int misses = 0;
    for (final List<MorphMass> cluster in clusters) {
      final Float64List signature = _clusterSignature(
        cluster,
        field.k,
        cell,
        smoothPasses,
        evalBudget,
      );
      final int hash = Object.hashAll(signature);
      List<List<Offset>>? loops = _lookup(_cache[hash], signature);
      if (loops == null) {
        misses++;
        loops = _tracedAndSmoothed(
          cluster,
          field.k,
          step,
          smoothPasses,
          evalBudget,
        );
      }
      (next[hash] ??= <_ClusterCacheEntry>[]).add(
        _ClusterCacheEntry(signature, loops),
      );
      for (final List<Offset> loop in loops) {
        path.moveTo(loop.first.dx, loop.first.dy);
        for (int i = 1; i < loop.length; i++) {
          path.lineTo(loop[i].dx, loop[i].dy);
        }
        path.close();
      }
    }
    lastMissCount = misses;
    _cache = next;
    return path;
  }

  static List<List<Offset>>? _lookup(
    List<_ClusterCacheEntry>? entries,
    Float64List signature,
  ) {
    if (entries == null) {
      return null;
    }
    for (final _ClusterCacheEntry entry in entries) {
      if (_signaturesEqual(entry.signature, signature)) {
        return entry.loops;
      }
    }
    return null;
  }

  static bool _signaturesEqual(Float64List a, Float64List b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  /// Fold order matters (chained smin is order-dependent), so the
  /// signature captures shapes in their cluster order, kind-tagged.
  static Float64List _clusterSignature(
    List<MorphMass> cluster,
    double k,
    double cell,
    int smoothPasses,
    int? evalBudget,
  ) {
    final Float64List sig = Float64List(
      4 + cluster.length * liquidMassSignatureStride,
    );
    int i = 0;
    sig[i++] = k;
    sig[i++] = cell;
    sig[i++] = smoothPasses.toDouble();
    sig[i++] = (evalBudget ?? -1).toDouble();
    for (final MorphMass shape in cluster) {
      i = liquidMassSignature(shape, sig, i);
    }
    return sig;
  }
}

class _ClusterCacheEntry {
  const _ClusterCacheEntry(this.signature, this.loops);

  final Float64List signature;
  final List<List<Offset>> loops;
}

class _ClusterTrace {
  const _ClusterTrace(this.loops, this.extraSmoothPasses);

  static const _ClusterTrace empty = _ClusterTrace(<List<Offset>>[], 0);

  final List<List<Offset>> loops;
  final int extraSmoothPasses;
}

_ClusterTrace _traceCluster(
  List<MorphMass> shapes,
  double k,
  double baseStep,
  int? evalBudget,
) {
  if (shapes.isEmpty) {
    return .empty;
  }
  Rect b = shapes.first.outerRect;
  for (int i = 1; i < shapes.length; i++) {
    b = b.expandToInclude(shapes[i].outerRect);
  }
  // The fusion bulge reaches up to ~k past a shape edge; without the
  // padding the grid would clip the blend.
  b = b.inflate(k);
  if (b.width <= 0 || b.height <= 0) {
    return .empty;
  }

  double step = baseStep;
  int cols = (b.width / step).ceil() + 1;
  int rows = (b.height / step).ceil() + 1;
  int extraSmoothPasses = 0;
  if (evalBudget != null) {
    // Cost driver is vertices x shapes. When over budget, coarsen the
    // step by exactly the overshoot factor (area scales inversely with
    // step squared, hence the square root). The coarser polyline gets
    // extra smoothing passes to compensate the faceting.
    final double evals = cols.toDouble() * rows * shapes.length;
    if (evals > evalBudget) {
      final double factor = math.sqrt(evals / evalBudget);
      step *= factor;
      cols = (b.width / step).ceil() + 1;
      rows = (b.height / step).ceil() + 1;
      extraSmoothPasses = factor >= 4 ? 2 : 1;
    }
  }
  // A guard against the pathological combination of a huge cluster and
  // a tiny cell: an empty contour beats a frozen frame. Loud in debug -
  // a silently vanishing skin is a miserable thing to diagnose.
  if (cols * rows > 400000) {
    assert(() {
      debugPrint(
        'morph/liquid: cluster grid ${cols}x$rows exceeds the safety cap; '
        'its contour is skipped. Increase cell (grid step) or reduce the '
        'cluster extent (${b.width.round()}x${b.height.round()}px).',
      );
      return true;
    }());
    return .empty;
  }

  final _FieldSampler sampler = _FieldSampler(shapes, k);
  final Float64List values = Float64List(cols * rows);
  for (int j = 0; j < rows; j++) {
    final double y = b.top + j * step;
    final int rowBase = j * cols;
    for (int i = 0; i < cols; i++) {
      values[rowBase + i] = sampler.eval(b.left + i * step, y);
    }
  }

  final List<(Offset, Offset)> segments = _marchGrid(
    values,
    cols,
    rows,
    b.left,
    b.top,
    step,
    sampler.eval,
  );

  return _ClusterTrace(_stitch(segments, step), extraSmoothPasses);
}

/// Marching squares over a sampled grid: the segments of the zero
/// iso-contour of [values] ([cols] x [rows], row-major, vertex (i, j) at
/// ([left] + i [step], [top] + j [step])). [centerAt] resolves the two
/// saddle cases by the field at a cell's center.
List<(Offset, Offset)> _marchGrid(
  Float64List values,
  int cols,
  int rows,
  double left,
  double top,
  double step,
  double Function(double x, double y) centerAt,
) {
  final List<(Offset, Offset)> segments = <(Offset, Offset)>[];
  for (int j = 0; j < rows - 1; j++) {
    for (int i = 0; i < cols - 1; i++) {
      final double vTL = values[j * cols + i];
      final double vTR = values[j * cols + i + 1];
      final double vBR = values[(j + 1) * cols + i + 1];
      final double vBL = values[(j + 1) * cols + i];
      int mask = 0;
      if (vTL < 0) {
        mask |= 8;
      }
      if (vTR < 0) {
        mask |= 4;
      }
      if (vBR < 0) {
        mask |= 2;
      }
      if (vBL < 0) {
        mask |= 1;
      }
      if (mask == 0 || mask == 15) {
        continue;
      }

      final double x0 = left + i * step;
      final double y0 = top + j * step;
      final double x1 = x0 + step;
      final double y1 = y0 + step;

      Offset edgePoint(int edge) => switch (edge) {
        0 => _zeroCrossing(x0, y0, vTL, x1, y0, vTR),
        1 => _zeroCrossing(x1, y0, vTR, x1, y1, vBR),
        2 => _zeroCrossing(x0, y1, vBL, x1, y1, vBR),
        _ => _zeroCrossing(x0, y0, vTL, x0, y1, vBL),
      };

      List<List<int>> cases = _kEdgeTable[mask];
      if (mask == 5 || mask == 10) {
        final double center = centerAt((x0 + x1) / 2, (y0 + y1) / 2);
        final bool insideCenter = center < 0;
        final List<List<int>> joined = <List<int>>[
          <int>[3, 0],
          <int>[2, 1],
        ];
        final List<List<int>> split = <List<int>>[
          <int>[3, 2],
          <int>[0, 1],
        ];
        if (mask == 5) {
          cases = insideCenter ? joined : split;
        } else {
          cases = insideCenter ? split : joined;
        }
      }
      for (final List<int> pair in cases) {
        segments.add((edgePoint(pair[0]), edgePoint(pair[1])));
      }
    }
  }

  return segments;
}

/// The evaluator of [field] for a sampling loop: the merge law at (x, y)
/// without an [Offset] or a normal allocated per call, the same values as
/// [LiquidField.eval].
@internal
double Function(double x, double y) liquidFieldSampler(LiquidField field) =>
    _FieldSampler(field.shapes, field.k).eval;

/// Stitches loose segments into closed loops: endpoints snap together
/// with half-grid-step precision - on thin necks numerically identical
/// points drift slightly apart.
List<List<Offset>> _stitch(List<(Offset, Offset)> segments, double cell) {
  final double eps = cell * 0.5;
  (int, int) key(Offset p) => ((p.dx / eps).round(), (p.dy / eps).round());

  final Map<(int, int), List<(int, int)>> byEndpoint =
      <(int, int), List<(int, int)>>{};
  for (int i = 0; i < segments.length; i++) {
    byEndpoint.putIfAbsent(key(segments[i].$1), () => <(int, int)>[]).add((
      i,
      0,
    ));
    byEndpoint.putIfAbsent(key(segments[i].$2), () => <(int, int)>[]).add((
      i,
      1,
    ));
  }

  final List<bool> used = .filled(segments.length, false);
  final List<List<Offset>> loops = <List<Offset>>[];

  for (int start = 0; start < segments.length; start++) {
    if (used[start]) {
      continue;
    }
    final List<Offset> loop = <Offset>[];
    int current = start;
    int end = 0;
    int guard = 0;
    while (!used[current] && guard++ < segments.length + 2) {
      used[current] = true;
      final (Offset, Offset) seg = segments[current];
      final Offset a = end == 0 ? seg.$1 : seg.$2;
      final Offset b = end == 0 ? seg.$2 : seg.$1;
      loop.add(a);
      final List<(int, int)> candidates = byEndpoint[key(b)] ?? <(int, int)>[];
      int next = -1;
      int nextEnd = 0;
      for (final (int seg, int segEnd) in candidates) {
        if (!used[seg]) {
          next = seg;
          nextEnd = segEnd;
          break;
        }
      }
      if (next == -1) {
        break;
      }
      current = next;
      end = nextEnd;
    }
    if (loop.length >= 3) {
      loops.add(loop);
    }
  }
  return loops;
}

/// Chaikin corner cutting: each pass replaces a point with a pair at 1/4
/// and 3/4 of its edges. Damps the contour jitter between morph frames.
List<Offset> _chaikin(List<Offset> points, int passes) {
  List<Offset> out = points;
  for (int pass = 0; pass < passes; pass++) {
    final List<Offset> next = <Offset>[];
    final int n = out.length;
    for (int i = 0; i < n; i++) {
      final Offset a = out[i];
      final Offset b = out[(i + 1) % n];
      next
        ..add(Offset(a.dx * 0.75 + b.dx * 0.25, a.dy * 0.75 + b.dy * 0.25))
        ..add(Offset(a.dx * 0.25 + b.dx * 0.75, a.dy * 0.25 + b.dy * 0.75));
    }
    out = next;
  }
  return out;
}

/// The full pipeline: field -> loops -> one [Path] in field coordinates
/// (multiple subpaths when the group splits into islands).
///
/// Fill type is evenOdd on purpose: interior holes (e.g. the middle of
/// a triangle of bridges) must stay hollow. The stitcher walks loops in
/// an arbitrary direction, so with the default nonZero rule a hole
/// would fill or not depending on accidental winding - and pop when the
/// topology changes.
Path liquidPath(
  LiquidField field, {
  double cell = 6,
  int smoothPasses = 2,
  int? evalBudget = liquidDefaultEvalBudget,
}) {
  final Path path = Path()..fillType = .evenOdd;
  for (final List<Offset> loop in liquidContours(
    field,
    cell: cell,
    smoothPasses: smoothPasses,
    evalBudget: evalBudget,
  )) {
    path.moveTo(loop.first.dx, loop.first.dy);
    for (int i = 1; i < loop.length; i++) {
      path.lineTo(loop[i].dx, loop[i].dy);
    }
    path.close();
  }
  return path;
}
