/// Liquid geometry: a scalar signed-distance field (SDF) and its vector
/// tracing. The whole surface "fusion" is one idea: shapes are not drawn
/// individually but united by a smooth minimum of their fields; the
/// blend zone at a joint IS the concave fillet. A small [LiquidField.k]
/// gives a crisp geometric joint, a large one - a gooey neck. The zero
/// iso-contour is traced by marching squares into an ordinary [Path] -
/// no shaders and no blur+threshold, hence no halos.
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

/// A named bundle of fusion knobs - in the spirit of MorphMotion
/// presets. k and cell are distances in pixels: the presets are
/// calibrated for button-scale UI (pieces of 40-150px); scenes at other
/// scales should scale k along via an explicit [MorphSkin.blend].
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

  /// The fusion width in px: how far apart two masses may sit and
  /// still pour into one skin (the smooth-min k of the field).
  final double blend;

  /// Outline grid step in px.
  final double cell;

  /// Chaikin smoothing passes over the traced contour.
  final int smoothPasses;

  /// A crisp concave joint - "a tab poured into a panel".
  static const MorphSkinStyle geometric = MorphSkinStyle(
    name: 'geometric',
    blend: 14,
  );

  /// An organic gooey neck.
  static const MorphSkinStyle goo = MorphSkinStyle(
    name: 'goo',
    blend: 42,
    cell: 7,
  );

  /// A barely-there fillet: the fusion reads without announcing itself.
  static const MorphSkinStyle subtle = MorphSkinStyle(name: 'subtle', blend: 8);

  /// The built-in presets.
  static const List<MorphSkinStyle> values = <MorphSkinStyle>[
    subtle,
    geometric,
    goo,
  ];

  @override
  String toString() => 'MorphSkinStyle.$name';
}

/// Polynomial smooth minimum in the mix form (no derivative kink at the
/// seam). k = 0 degenerates to a plain min.
double liquidSmin(double a, double b, double k) {
  if (k <= 0) {
    return math.min(a, b);
  }
  final double h = (0.5 + 0.5 * (b - a) / k).clamp(0.0, 1.0);
  return b * (1 - h) + a * h - k * h * (1 - h);
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

/// Distance to a capsule (the segment [a]-[b] with radius [radius]).
double liquidCapsuleDistance(Offset p, Offset a, Offset b, double radius) {
  final Offset pa = p - a;
  final Offset ba = b - a;
  final double denom = ba.dx * ba.dx + ba.dy * ba.dy;
  final double h = denom < 1e-9
      ? 0
      : ((pa.dx * ba.dx + pa.dy * ba.dy) / denom).clamp(0.0, 1.0);
  final Offset d = pa - ba * h;
  return d.distance - radius;
}

/// Gap between two rects (0 when they intersect). The "no neck for
/// sure" gate: blend depth at the middle of a gap is ~k/4, so with a gap
/// larger than k the smooth union has provably split into islands and a
/// distant shape can be left out of the field.
double liquidRectGap(Rect a, Rect b) {
  final double dx = math.max(0, math.max(a.left - b.right, b.left - a.right));
  final double dy = math.max(0, math.max(a.top - b.bottom, b.top - a.bottom));
  return math.sqrt(dx * dx + dy * dy);
}

/// A raw SDF mass poured into a skin. Sealed: [LiquidBox] and
/// [LiquidBridge] are the whole vocabulary.
sealed class LiquidShape {
  const LiquidShape();

  /// Signed distance from [p] to the shape surface (negative inside).
  double distance(Offset p);

  /// The shape's own bounds, blend excluded: padding by k is added by
  /// [LiquidField.bounds].
  Rect get outerRect;
}

/// A rounded-box mass (a stadium when the radius reaches the shorter
/// half-extent).
class LiquidBox extends LiquidShape {
  /// Creates a rounded-box mass.
  const LiquidBox(this.rect, {this.radius = 0})
    : assert(radius >= 0, 'radius cannot be negative.');

  /// The box geometry.
  final Rect rect;

  /// Corner radius; clamped to the half-extents, so a large radius
  /// yields a stadium.
  final double radius;

  @override
  double distance(Offset p) => liquidBoxDistance(p, rect, radius);

  @override
  Rect get outerRect => rect;
}

/// An explicit "bridge": a pipe between two distant shapes when
/// proximity fusion is not enough.
class LiquidBridge extends LiquidShape {
  /// Creates a capsule mass between [a] and [b].
  const LiquidBridge(this.a, this.b, {required this.radius})
    : assert(radius > 0, 'a bridge with no radius has no mass.');

  /// One capsule endpoint.
  final Offset a;

  /// The other capsule endpoint.
  final Offset b;

  /// Half the capsule width.
  final double radius;

  @override
  double distance(Offset p) => liquidCapsuleDistance(p, a, b, radius);

  @override
  Rect get outerRect => Rect.fromPoints(a, b).inflate(radius);
}

/// A group of shapes as one field: the smooth union of all [shapes] with
/// blend [k]. Two shapes whose k-zones overlap fuse on their own - no
/// explicit connection needed.
class LiquidField {
  /// Creates a field over [shapes] with fusion width [k].
  const LiquidField(this.shapes, {this.k = 24})
    : assert(k >= 0, 'k (blend) is a distance in px and cannot be negative.');

  /// The masses of the field.
  final List<LiquidShape> shapes;

  /// Blend width in field pixels. It is a distance: when the scene is
  /// scaled, k scales along with it.
  final double k;

  /// The smooth-min distance of the whole field at [p].
  double eval(Offset p) {
    if (shapes.isEmpty) {
      return double.infinity;
    }
    double d = shapes.first.distance(p);
    for (int i = 1; i < shapes.length; i++) {
      d = liquidSmin(d, shapes[i].distance(p), k);
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
class _FieldSampler {
  factory _FieldSampler(List<LiquidShape> shapes, double k) {
    int boxCount = 0;
    for (final LiquidShape shape in shapes) {
      if (shape is LiquidBox) {
        boxCount++;
      }
    }
    // Boxes: cx, cy, hw, hh, r (pre-clamped). Bridges: ax, ay, bax,
    // bay, len2 (guarded against zero), r.
    final Float64List boxes = Float64List(boxCount * 5);
    final Float64List bridges = Float64List((shapes.length - boxCount) * 6);
    int bi = 0;
    int gi = 0;
    for (final LiquidShape shape in shapes) {
      switch (shape) {
        case LiquidBox(:final Rect rect, :final double radius):
          final double hw = rect.width / 2;
          final double hh = rect.height / 2;
          boxes[bi++] = rect.center.dx;
          boxes[bi++] = rect.center.dy;
          boxes[bi++] = hw;
          boxes[bi++] = hh;
          boxes[bi++] = math.min(radius, math.min(hw, hh));
        case LiquidBridge(
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
    return _FieldSampler._(boxes, bridges, k);
  }

  _FieldSampler._(this._boxes, this._bridges, this._k);

  final Float64List _boxes;
  final Float64List _bridges;
  final double _k;

  double eval(double x, double y) {
    // Seeded by the first shape's distance, exactly like the reference
    // LiquidField.eval: folding infinity through smin would produce
    // infinity * 0 = NaN.
    double d = .infinity;
    bool first = true;
    final Float64List boxes = _boxes;
    for (int i = 0; i < boxes.length; i += 5) {
      final double r = boxes[i + 4];
      final double qx = (x - boxes[i]).abs() - boxes[i + 2] + r;
      final double qy = (y - boxes[i + 1]).abs() - boxes[i + 3] + r;
      final double ax = qx > 0 ? qx : 0.0;
      final double ay = qy > 0 ? qy : 0.0;
      double di = math.sqrt(ax * ax + ay * ay) - r;
      final double inner = qx > qy ? qx : qy;
      if (inner < 0) {
        di += inner;
      }
      if (first) {
        d = di;
        first = false;
      } else {
        d = _smin(d, di);
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
      final double di = math.sqrt(dx * dx + dy * dy) - bridges[i + 5];
      if (first) {
        d = di;
        first = false;
      } else {
        d = _smin(d, di);
      }
    }
    return d;
  }

  double _smin(double a, double b) {
    final double k = _k;
    if (k <= 0) {
      return a < b ? a : b;
    }
    double h = 0.5 + 0.5 * (b - a) / k;
    if (h < 0) {
      h = 0;
    } else if (h > 1) {
      h = 1;
    }
    return b * (1 - h) + a * h - k * h * (1 - h);
  }
}

/// Splits shapes into connectivity clusters: shapes whose bounds gap is
/// <= k belong together (transitively). Each cluster is traced on its
/// own tight grid instead of one grid over the union bounds - for
/// spread-out scenes this shrinks the sampled area by orders of
/// magnitude.
///
/// Exactness proof sketch: the mix-form smin equals the plain min
/// exactly once the distance difference reaches k. On and near cluster
/// A's zero contour, every point lies on A's surface, so its distance
/// to any shape of another cluster is at least the inter-cluster gap
/// (> k) - the neighbor's contribution vanishes identically there.
/// Mutual bulging exists only below a gap of k, which keeps such shapes
/// in one cluster by construction; and no phantom mass can appear
/// between clusters because at a midpoint both distances exceed k/2
/// while smin dips at most k/4 below the plain min. The split is
/// therefore not an approximation.
List<List<LiquidShape>> _clusterShapes(List<LiquidShape> shapes, double k) {
  final int n = shapes.length;
  if (n <= 1) {
    return <List<LiquidShape>>[shapes];
  }
  final List<Rect> rects = <Rect>[
    for (final LiquidShape shape in shapes) shape.outerRect,
  ];
  final List<int> cluster = .filled(n, -1);
  int clusterCount = 0;
  final List<int> queue = <int>[];
  for (int seed = 0; seed < n; seed++) {
    if (cluster[seed] != -1) {
      continue;
    }
    final int id = clusterCount++;
    cluster[seed] = id;
    queue.add(seed);
    while (queue.isNotEmpty) {
      final int current = queue.removeLast();
      for (int other = 0; other < n; other++) {
        if (cluster[other] == -1 &&
            liquidRectGap(rects[current], rects[other]) <= k) {
          cluster[other] = id;
          queue.add(other);
        }
      }
    }
  }
  if (clusterCount == 1) {
    return <List<LiquidShape>>[shapes];
  }
  final List<List<LiquidShape>> result = <List<LiquidShape>>[
    for (int i = 0; i < clusterCount; i++) <LiquidShape>[],
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
/// traces identically.
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
  for (final List<LiquidShape> cluster in _clusterShapes(
    field.shapes,
    field.k,
  )) {
    loops.addAll(
      _tracedAndSmoothed(cluster, field.k, step, smoothPasses, evalBudget),
    );
  }
  return loops;
}

List<List<Offset>> _tracedAndSmoothed(
  List<LiquidShape> cluster,
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
    final List<List<LiquidShape>> clusters = _clusterShapes(
      field.shapes,
      field.k,
    );
    lastClusterCount = clusters.length;
    int misses = 0;
    for (final List<LiquidShape> cluster in clusters) {
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
    List<LiquidShape> cluster,
    double k,
    double cell,
    int smoothPasses,
    int? evalBudget,
  ) {
    final Float64List sig = Float64List(4 + cluster.length * 6);
    int i = 0;
    sig[i++] = k;
    sig[i++] = cell;
    sig[i++] = smoothPasses.toDouble();
    sig[i++] = (evalBudget ?? -1).toDouble();
    for (final LiquidShape shape in cluster) {
      switch (shape) {
        case LiquidBox(:final Rect rect, :final double radius):
          sig[i++] = 0;
          sig[i++] = rect.left;
          sig[i++] = rect.top;
          sig[i++] = rect.width;
          sig[i++] = rect.height;
          sig[i++] = radius;
        case LiquidBridge(
          :final Offset a,
          :final Offset b,
          :final double radius,
        ):
          sig[i++] = 1;
          sig[i++] = a.dx;
          sig[i++] = a.dy;
          sig[i++] = b.dx;
          sig[i++] = b.dy;
          sig[i++] = radius;
      }
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
  List<LiquidShape> shapes,
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

      final double x0 = b.left + i * step;
      final double y0 = b.top + j * step;
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
        final double center = sampler.eval((x0 + x1) / 2, (y0 + y1) / 2);
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

  return _ClusterTrace(_stitch(segments, step), extraSmoothPasses);
}

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
