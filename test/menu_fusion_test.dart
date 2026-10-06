import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/menu_entries.dart';
import 'package:morph/src/widgets/menu_fusion.dart';
import 'package:morph/src/widgets/menu_fusion_worker.dart';
import 'package:morph/src/widgets/menu_motion.dart';

const _fixture = 'test/fixtures/ios27-device/menu/fusion.json';
const _tuning = MorphMenuTuning.standard;

Map<String, Object?> _load() =>
    (jsonDecode(File(_fixture).readAsStringSync()) as Map)
        .cast<String, Object?>();

List<(double, double)> _series(Object? rows) => [
  for (final row in (rows! as List<Object?>).cast<List<Object?>>())
    ((row[0]! as num).toDouble(), (row[1]! as num).toDouble()),
];

/// The rms error of the envelope against [rows] at the best start time
/// within 30 ms before the first logged nonzero radius.
double _envelopeRms(List<(double, double)> rows, {required bool opening}) {
  var best = double.infinity;
  for (var lead = 0.0; lead <= 0.03; lead += 0.0005) {
    var sum = 0.0;
    for (final (t, radius) in rows) {
      final model = math.min(
        _tuning.fusionEnvelope(t + lead, opening: opening),
        _tuning.fusionRadius,
      );
      sum += (model - radius) * (model - radius);
    }
    best = math.min(best, math.sqrt(sum / rows.length));
  }
  return best;
}

/// The extent of [path] along the row at [y]: from its leftmost to its
/// rightmost point inside, sampled every quarter point.
double _rowWidth(Path path, double y) {
  final bounds = path.getBounds();
  double? first;
  double? last;
  for (var x = bounds.left - 1; x <= bounds.right + 1; x += 0.25) {
    if (path.contains(Offset(x, y))) {
      first ??= x;
      last = x;
    }
  }
  return first == null ? 0 : last! - first + 0.25;
}

void main() {
  group('the fusion radius replays the device', () {
    final doc = _load();
    for (final (name, opening) in [('opens', true), ('closes', false)]) {
      for (final (i, rows) in (doc[name]! as List<Object?>).indexed) {
        test('$name ${i + 1}', () {
          expect(
            _envelopeRms(_series(rows), opening: opening),
            lessThan(opening ? 0.5 : 0.2),
          );
        });
      }
    }

    test('it never passes the measured radius and ends at the cutoff', () {
      for (final opening in [true, false]) {
        var last = 0.0;
        for (var t = 0.0; t < 1.5; t += 1 / 120) {
          last = _tuning.fusionEnvelope(t, opening: opening);
          expect(math.min(last, _tuning.fusionRadius), lessThanOrEqualTo(20));
        }
        expect(last, lessThan(_tuning.fusionCutoff));
        expect(_tuning.fusionEnded(1.5, opening: opening), isTrue);
      }
    });
  });

  group('the silhouette replays the filmed close', () {
    final frames = _load()['frames']! as List<Object?>;
    for (final frame in frames.cast<Map<String, Object?>>()) {
      test('frame at ${frame['film_t']}', () {
        final menu = (frame['menu']! as Map).cast<String, Object?>();
        final source = (frame['source']! as Map).cast<String, Object?>();
        double n(Map<String, Object?> m, String key) =>
            (m[key]! as num).toDouble();
        final g = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(n(menu, 'cx'), n(menu, 'cy')),
            width: n(menu, 'w'),
            height: n(menu, 'h'),
          ),
          Radius.circular(n(menu, 'r')),
        );
        final d = n(source, 'd');
        final s = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(n(source, 'cx'), n(source, 'cy')),
            width: d,
            height: d,
          ),
          Radius.circular(d / 2),
        );
        final path = morphMenuSilhouette(
          g,
          s,
          (frame['gaussianRadius']! as num).toDouble(),
        ).path;
        var sum = 0.0;
        var count = 0;
        var filmNeck = double.infinity;
        var ourNeck = double.infinity;
        final rows = (frame['rows']! as List<Object?>).cast<List<Object?>>();
        for (final row in rows) {
          final y = (row[0]! as num).toDouble();
          final width = (row[1]! as num).toDouble();
          final ours = _rowWidth(path, y);
          sum += (ours - width) * (ours - width);
          count++;
          if (y > g.bottom - 2 && y < s.center.dy) {
            filmNeck = math.min(filmNeck, width);
            ourNeck = math.min(ourNeck, ours);
          }
        }
        // The first frame is the one the neck forms in: the film shows a
        // thread a few milliseconds before the logged geometry does.
        final forming = frame == frames.first;
        expect(
          math.sqrt(sum / count),
          lessThan(forming ? 4.5 : 2.6),
          reason: 'the film reads the outer rim, about a point wider',
        );
        if (!forming) {
          expect(
            filmNeck - ourNeck,
            inInclusiveRange(0, 5),
            reason: 'the neck, read on the outer rim by the film',
          );
        }
        expect(
          path.computeMetrics().length,
          forming ? lessThanOrEqualTo(2) : 1,
          reason: 'one body once the neck has formed',
        );
      });
    }
  });

  test('a tall menu closing into a bottom button keeps no separate ball', () {
    final motion = MorphMenuMotion(
      button: Rect.fromCenter(
        center: const Offset(201, 796),
        width: 48,
        height: 48,
      ),
      itemCount: 10,
      bounds: const Size(402, 874),
      padding: const EdgeInsets.only(top: 62, bottom: 34),
    );
    motion.open(0, sourceScale: 1);
    motion.advance(1.2);
    motion.close(1.2);
    var widestGap = 0.0;
    var apart = 0;
    var necked = 0;
    for (var t = 1.2; t < 2.2; t += 1 / 120) {
      motion.advance(t);
      final g = motion.menuBlob.rect;
      final s = motion.buttonBlob.rect;
      final gap = s.top - g.bottom;
      widestGap = math.max(widestGap, gap);
      final path = motion.silhouette?.path;
      if (gap <= 0) continue;
      expect(path, isNotNull, reason: 'a gap opens only while fused');
      final loops = path!.computeMetrics().toList();
      for (final loop in loops.skip(1)) {
        apart++;
        expect(
          loop.extractPath(0, loop.length).getBounds().width,
          lessThan(0.6 * s.width),
          reason: 'only a drop of the button stands apart',
        );
      }
      if (loops.length == 1 &&
          path.contains(Offset(s.center.dx, (g.bottom + s.top) / 2))) {
        necked++;
      }
    }
    expect(widestGap, greaterThan(15), reason: 'the shapes do part');
    expect(apart, lessThanOrEqualTo(3), reason: 'apart for 25 ms at most');
    expect(necked, greaterThan(10), reason: 'a neck spans the gap');
  });

  test('the fusion rises again on a reversal without a jump', () {
    final motion = MorphMenuMotion(
      button: Rect.fromCenter(
        center: const Offset(201, 437),
        width: 48,
        height: 48,
      ),
      itemCount: 3,
      bounds: const Size(402, 874),
    );
    motion.open(0, sourceScale: 1);
    var last = 0.0;
    for (var frame = 0; frame < 180; frame++) {
      final t = frame / 120;
      if (frame == 36) motion.close(t);
      if (frame == 48) motion.open(t);
      motion.advance(t);
      final radius = motion.fusionRadius;
      expect((radius - last).abs(), lessThan(11), reason: 'at $t');
      if (frame == 36 || frame == 48) {
        expect(radius, greaterThanOrEqualTo(last - 1), reason: 'at $t');
      }
      last = radius;
    }
    motion.close(1.5);
    for (var t = 1.5; t < 3.5; t += 1 / 60) {
      motion.advance(t);
    }
    expect(motion.fusionRadius, 0);
    expect(motion.silhouette, isNull);
    expect(motion.isPresented, isFalse);
  });

  test('the sparse field is the blurred union, its path the zero contour', () {
    double box(RRect s, double x, double y) {
      final r = math.min(s.tlRadiusX, math.min(s.width, s.height) / 2);
      final qx = (x - s.center.dx).abs() - (s.width / 2 - r);
      final qy = (y - s.center.dy).abs() - (s.height / 2 - r);
      final ox = math.max(qx, 0.0);
      final oy = math.max(qy, 0.0);
      return math.sqrt(ox * ox + oy * oy) + math.min(math.max(qx, qy), 0.0) - r;
    }

    final random = math.Random(3);
    for (var n = 0; n < 12; n++) {
      final radius = 1 + random.nextDouble() * 19;
      final step = MorphMenuFusion.stepOf(radius);
      final reach = MorphMenuFusion.reachOf(radius);
      final top = 100 + random.nextDouble() * 50;
      final width = 120 + random.nextDouble() * 160;
      final height = 60 + random.nextDouble() * 300;
      final corner = random.nextDouble() * 60;
      final g = RRect.fromLTRBXY(
        70,
        top,
        70 + width,
        top + height,
        corner,
        corner,
      );
      final d = 6 + random.nextDouble() * 40;
      final cx = 70 + random.nextDouble() * width;
      final cy = top + height + random.nextDouble() * 30 - 10;
      final s = RRect.fromLTRBXY(
        cx - d / 2,
        cy,
        cx + d / 2,
        cy + d,
        d / 2,
        d / 2,
      );
      final outline = morphMenuSilhouette(g, s, radius);
      final field = morphGlassOutlineField(outline)!;
      final band = 1.26 * radius + 1.5 * step;
      for (var j = 0; j < field.rows; j += 3) {
        for (var i = 0; i < field.cols; i += 3) {
          final x = field.origin.dx + i * field.step;
          final y = field.origin.dy + j * field.step;
          var sum = 0.0;
          var blurred = 0.0;
          for (var a = -reach; a <= reach; a++) {
            for (var b = -reach; b <= reach; b++) {
              final w = math.exp(
                -0.5 * (a * a + b * b) * step * step / (radius * radius),
              );
              sum += w;
              blurred +=
                  w *
                  math.min(
                    box(g, x + a * step, y + b * step),
                    box(s, x + a * step, y + b * step),
                  );
            }
          }
          blurred /= sum;
          final raw = math.min(box(g, x, y), box(s, x, y));
          final want = raw > band || raw < -math.max(band, 24) ? raw : blurred;
          expect(
            field.samples[(j * field.cols + i) * 4],
            closeTo(want, 0.01),
            reason: '($x, $y) at radius $radius',
          );
          if (blurred.abs() > 0.5) {
            expect(outline.path.contains(Offset(x, y)), blurred < 0);
          }
        }
      }
    }
  });

  test('a small radius leaves the plain union', () {
    final fusion = MorphMenuFusion();
    final g = RRect.fromLTRBR(0, 0, 100, 100, const Radius.circular(20));
    final s = RRect.fromLTRBR(40, 110, 60, 130, const Radius.circular(10));
    expect(fusion.outline(g, s, 0.5), isNull);
    final fused = fusion.outline(g, s, 10)!;
    expect(identical(fusion.outline(g, s, 10), fused), isTrue);
    expect(fused.path.contains(const Offset(50, 105)), isTrue);
  });

  test('the kernel reaches three radii, nine steps where a step is a third '
      'of the radius', () {
    for (var radius = 6.0; radius <= 18; radius += 0.001) {
      expect(MorphMenuFusion.reachOf(radius), 9, reason: '$radius');
    }
    expect(MorphMenuFusion.reachOf(20), 10);
    expect(MorphMenuFusion.reachOf(2), 3);
    expect(MorphMenuFusion.reachOf(2.01), 4);
  });

  testWidgets('the flat glass of a tall menu closing into a bottom button '
      'stays one body', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF007AFF),
        pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
            PageRouteBuilder<T>(
              settings: settings,
              pageBuilder: (BuildContext context, _, _) => builder(context),
            ),
        home: Align(
          alignment: .bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 54),
            child: MorphMenuButton(
              items: [
                for (var i = 0; i < 10; i++) MorphMenuItem(title: 'Row $i'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 100));
    var apart = 0;
    var tallest = 0.0;
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(microseconds: 8333));
      for (final paint in tester.widgetList<CustomPaint>(
        find.byType(CustomPaint),
      )) {
        final painter = paint.painter;
        if (painter == null ||
            painter.runtimeType.toString() != '_GlassPainter') {
          continue;
        }
        final canvas = TestRecordingCanvas();
        painter.paint(canvas, const Size(402, 874));
        final paths = [
          for (final call in canvas.invocations)
            if (call.invocation.memberName == #drawPath)
              call.invocation.positionalArguments.first as Path,
        ];
        final loops = paths.last.computeMetrics().toList();
        loops.sort(
          (a, b) => b
              .extractPath(0, b.length)
              .getBounds()
              .height
              .compareTo(a.extractPath(0, a.length).getBounds().height),
        );
        tallest = math.max(
          tallest,
          loops.first.extractPath(0, loops.first.length).getBounds().height,
        );
        for (final loop in loops.skip(1)) {
          final bounds = loop.extractPath(0, loop.length).getBounds();
          final inside = loops.first
              .extractPath(0, loops.first.length)
              .getBounds()
              .contains(bounds.center);
          if (inside) continue;
          apart++;
          expect(bounds.width, lessThan(24), reason: 'a drop, not the button');
        }
      }
    }
    expect(apart, lessThanOrEqualTo(3));
    expect(tallest, greaterThan(300));
  });

  group('the fusion computed ahead', () {
    setUp(() => MorphMenuFusion.debugPrefetch = true);
    tearDown(() {
      MorphMenuFusion.debugPrefetch = null;
      MorphFusionWorker.reset();
    });

    Future<void> ready() async {
      for (var i = 0; i < 500 && !MorphFusionWorker.debugHasReady; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(MorphFusionWorker.debugHasReady, isTrue);
    }

    final menu = RRect.fromLTRBR(70, 200, 330, 640, const Radius.circular(32));
    final button = RRect.fromLTRBR(
      177,
      612,
      225,
      660,
      const Radius.circular(24),
    );

    test('is the fusion of its inputs, bit for bit', () async {
      MorphMenuFusion().prefetch(menu, button, 6.5);
      await ready();
      final ahead = MorphFusionWorker.take(
        MorphMenuFusion.encode(menu, button, 6.5, Float64List(11)),
        0,
      )!;
      final here = morphMenuSilhouetteParts(menu, button, 6.5);
      expect(ahead.samples, here.samples);
      expect(ahead.points, here.points);
      expect(ahead.loops, here.loops);
      expect(
        [ahead.cols, ahead.rows, ahead.left, ahead.top, ahead.step],
        [here.cols, here.rows, here.left, here.top, here.step],
      );
    });

    test('serves a frame within the tolerance and no other', () async {
      final fusion = MorphMenuFusion();
      fusion.prefetch(menu, button, 6.5);
      await ready();
      final far = menu.shift(const Offset(0, 0.05));
      final fused = fusion.outline(far, button, 6.5)!;
      expect(MorphFusionWorker.debugHasReady, isTrue);
      expect(
        morphGlassOutlineField(fused)!.samples,
        morphMenuSilhouetteParts(far, button, 6.5).samples,
      );
      final near = menu.shift(const Offset(0, 0.01));
      final served = fusion.outline(near, button, 6.5)!;
      expect(MorphFusionWorker.debugHasReady, isFalse);
      expect(
        morphGlassOutlineField(served)!.samples,
        morphMenuSilhouetteParts(menu, button, 6.5).samples,
      );
    });
  });
}
