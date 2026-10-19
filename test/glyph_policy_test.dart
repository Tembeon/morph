import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glyph_scale.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/glass.dart';

/// Records the canvas transform each paint starts with.
class _Recorder extends CustomPainter {
  _Recorder(this.log);

  final List<Float64List> log;

  @override
  void paint(Canvas canvas, Size size) => log.add(canvas.getTransform());

  @override
  bool shouldRepaint(_Recorder oldDelegate) => true;
}

const Size _box = Size(100, 40);

Widget _tree(double scale, List<Float64List> log, {required bool glyphs}) {
  final Widget painted = CustomPaint(size: _box, painter: _Recorder(log));
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: glyphs ? MorphGlyphs(child: painted) : painted,
      ),
    ),
  );
}

/// The recorded transform's x scale and where it sends the box center.
({double scale, Offset center}) _read(Float64List m) {
  final matrix = Matrix4.fromFloat64List(m);
  final p = MatrixUtils.transformPoint(
    matrix,
    Offset(_box.width / 2, _box.height / 2),
  );
  return (scale: math.sqrt(m[0] * m[0] + m[1] * m[1]), center: p);
}

/// Pumps one frame at [scale] and reads the child's painted transform.
Future<({double scale, Offset center})> _paint(
  WidgetTester tester,
  double scale, {
  required bool glyphs,
}) async {
  final log = <Float64List>[];
  await tester.pumpWidget(_tree(scale, log, glyphs: glyphs));
  return _read(log.last);
}

RenderMorphGlyphs _only(WidgetTester tester) =>
    tester.renderObject<RenderMorphGlyphs>(find.byType(MorphGlyphs));

void main() {
  setUpAll(() async {
    isLocalTest = true;
    await MorphGlyphs.precache();
  });

  group('policy', () {
    MorphGlyphMode decide(
      double? steps, {
      MorphGlyphMode previous = MorphGlyphMode.live,
      bool stable = true,
      bool canRaster = true,
      double cover = 0,
    }) => MorphGlyphPolicy.decide(
      steps: steps,
      previous: previous,
      stable: stable,
      canRaster: canRaster,
      cover: cover,
    );

    test('a scale at rest is live, whatever covers it', () {
      expect(decide(0), MorphGlyphMode.live);
      expect(decide(0.01), MorphGlyphMode.live);
      expect(decide(0, cover: 5), MorphGlyphMode.live);
      expect(decide(0, previous: MorphGlyphMode.raster), MorphGlyphMode.live);
    });

    test('a card never snaps: it rasters at any motion, down to a drift', () {
      MorphGlyphMode card(double? steps, {bool stable = true}) =>
          MorphGlyphPolicy.decide(steps: steps, stable: stable, snaps: false);
      expect(card(null), MorphGlyphMode.live);
      expect(card(0), MorphGlyphMode.live);
      expect(card(0.001), MorphGlyphMode.raster);
      expect(card(0.2), MorphGlyphMode.raster);
      expect(card(3), MorphGlyphMode.raster);
      // Content that repaints on consecutive frames is drawn live.
      expect(card(0.2, stable: false), MorphGlyphMode.live);
    });

    test('an aligned drawing snaps a drift, and is live only when still', () {
      MorphGlyphMode aligned(double? steps) =>
          MorphGlyphPolicy.decide(steps: steps, aligned: true);
      expect(aligned(null), MorphGlyphMode.live);
      expect(aligned(0), MorphGlyphMode.live);
      expect(aligned(0.001), MorphGlyphMode.snapped);
      expect(aligned(0.2), MorphGlyphMode.snapped);
      expect(aligned(3), MorphGlyphMode.raster);
    });

    test('a slow scale snaps, a fast one rasters', () {
      expect(decide(0.2), MorphGlyphMode.snapped);
      expect(decide(0.5), MorphGlyphMode.raster);
      expect(decide(3), MorphGlyphMode.raster);
      // Rastering holds down to the hold speed, so a sweep slowing
      // through the fast speed does not flicker.
      expect(
        decide(0.2, previous: MorphGlyphMode.raster),
        MorphGlyphMode.raster,
      );
      expect(
        decide(0.05, previous: MorphGlyphMode.raster),
        MorphGlyphMode.snapped,
      );
    });

    test('a cover hides resampling at any motion and on the first frame', () {
      expect(decide(0.03, cover: 0.5), MorphGlyphMode.raster);
      expect(decide(null, cover: 0.5), MorphGlyphMode.raster);
      expect(decide(null, cover: 0.4), MorphGlyphMode.live);
      expect(decide(null), MorphGlyphMode.live);
    });

    test('content that will not hold a raster snaps on a coarser grid', () {
      expect(decide(3, stable: false), MorphGlyphMode.snapped);
      expect(decide(3, canRaster: false), MorphGlyphMode.snapped);
      expect(decide(3, cover: 2, stable: false), MorphGlyphMode.snapped);
      expect(MorphGlyphPolicy.gridFor(0.2), 64);
      expect(MorphGlyphPolicy.gridFor(0.3), 32);
      expect(MorphGlyphPolicy.gridFor(0.45), 32);
      expect(MorphGlyphPolicy.gridFor(0.6), 16);
      expect(MorphGlyphPolicy.gridFor(3), 16);
    });

    test('every grid is a subset of the finer ones and passes the ratio', () {
      for (final grid in MorphGlyphPolicy.grids) {
        expect(MorphGlyphScale.stepsPerOctave % grid, 0);
        expect(MorphGlyphScale.snap(2.625, 2.625, perOctave: grid), 2.625);
      }
    });

    test('a raster is magnified 9 percent at most, reduced 16 at most', () {
      const ratio = 2.625;
      expect(MorphGlyphScale.rasterRatio(0.3 * ratio, ratio), ratio);
      expect(MorphGlyphScale.rasterRatio(ratio, ratio), ratio);
      expect(MorphGlyphScale.rasterRatio(1.07 * ratio, ratio), ratio);
      for (var s = 1.001; s < 2; s += 0.013) {
        final r = MorphGlyphScale.rasterRatio(ratio * s, ratio);
        expect(r * MorphGlyphScale.rasterStretch, greaterThan(ratio * s));
        expect(r / (ratio * s), lessThan(math.pow(2, 1 / 4) + 1e-9));
      }
    });
  });

  testWidgets('a label at rest is untouched', (tester) async {
    final plain = await _paint(tester, 1.0123, glyphs: false);
    final first = await _paint(tester, 1.0123, glyphs: true);
    expect(first.scale, plain.scale);
    final rest = await _paint(tester, 1.0123, glyphs: true);
    final glyphs = _only(tester);
    expect(glyphs.debugMode, MorphGlyphMode.live);
    expect(glyphs.debugFactor, 1);
    expect(rest.scale, plain.scale);
    expect(rest.center, plain.center);
  });

  testWidgets('an aligned label moving slowly lands a sixteenth past a device '
      'pixel', (tester) async {
    final ratio = tester.view.devicePixelRatio;
    Future<Float64List> paint(double scale) async {
      final log = <Float64List>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 10.37),
              child: Transform.scale(
                scale: scale,
                child: MorphGlyphs(
                  aligned: true,
                  child: CustomPaint(size: _box, painter: _Recorder(log)),
                ),
              ),
            ),
          ),
        ),
      );
      return log.last;
    }

    final rest = await paint(1);
    expect(_only(tester).debugMode, MorphGlyphMode.live);
    expect((rest[12] * ratio) % 1, isNot(closeTo(0, 1e-3)));
    // A drift below MorphGlyphPolicy.restSteps snaps as a move does.
    for (final scale in [1.00015, 1.0003, 1.0303, 1.0305]) {
      final m = await paint(scale);
      final glyphs = _only(tester);
      expect(glyphs.debugMode, MorphGlyphMode.snapped);
      final x = m[12] * ratio - 1 / 16;
      expect(x, closeTo(x.roundToDouble(), 1e-4));
      final steps = math.log(m[0]) / math.ln2 * MorphGlyphScale.stepsPerOctave;
      expect(steps, closeTo(steps.roundToDouble(), 1e-4));
    }
  });

  testWidgets('a slowly moving label snaps about its center, then rests', (
    tester,
  ) async {
    // A quarter step of the finest grid since the last frame: slow.
    final scale = math.pow(2, 4.25 / MorphGlyphScale.stepsPerOctave).toDouble();
    final start = math.pow(2, 4 / MorphGlyphScale.stepsPerOctave).toDouble();
    final plain = await _paint(tester, scale, glyphs: false);
    await _paint(tester, start, glyphs: true);
    final snapped = await _paint(tester, scale, glyphs: true);
    final glyphs = _only(tester);
    expect(glyphs.debugMode, MorphGlyphMode.snapped);
    final factor = glyphs.debugFactor;
    expect(factor, isNot(1));
    expect((factor - 1).abs(), lessThan(0.0055));
    expect(snapped.scale, closeTo(plain.scale * factor, 1e-5));
    final steps =
        math.log(snapped.scale) / math.ln2 * MorphGlyphScale.stepsPerOctave;
    expect(steps, closeTo(steps.roundToDouble(), 1e-4));
    expect(snapped.center.dx, closeTo(plain.center.dx, 1e-4));
    expect(snapped.center.dy, closeTo(plain.center.dy, 1e-4));
    // The scale stops: the drawing paints itself once more, exact.
    await tester.pump();
    expect(glyphs.debugMode, MorphGlyphMode.live);
    expect(glyphs.debugFactor, 1);
  });

  testWidgets('a fast sweep of still content draws from one raster', (
    tester,
  ) async {
    Widget tree(double scale) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          child: const MorphGlyphs(
            child: SizedBox(
              width: 100,
              height: 40,
              child: Text('Inbox', textDirection: TextDirection.ltr),
            ),
          ),
        ),
      ),
    );
    MorphGlyphs.debugRasterCount = 0;
    await tester.pumpWidget(tree(0.5));
    final glyphs = _only(tester);
    for (var i = 1; i <= 10; i++) {
      await tester.pumpWidget(tree(0.5 + 0.05 * i));
      expect(glyphs.debugMode, MorphGlyphMode.raster);
    }
    // The whole sweep stays below the device pixel ratio: one raster.
    expect(MorphGlyphs.debugRasterCount, 1);
    await tester.pump();
    expect(glyphs.debugMode, MorphGlyphMode.live);
  });

  testWidgets('content that repaints every frame snaps instead', (
    tester,
  ) async {
    await _paint(tester, 0.5, glyphs: true);
    final glyphs = _only(tester);
    for (var i = 1; i <= 5; i++) {
      await _paint(tester, 0.5 + 0.05 * i, glyphs: true);
    }
    expect(glyphs.debugMode, MorphGlyphMode.snapped);
    expect(glyphs.tracker.perOctave, MorphGlyphPolicy.grids.last);
  });

  testWidgets('a composited label keeps its transform layer across paints', (
    tester,
  ) async {
    const key = ValueKey<String>('boundary');
    Widget tree(double scale) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          child: const MorphGlyphs(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      ),
    );
    double at(double steps) =>
        math.pow(2, steps / MorphGlyphScale.stepsPerOctave).toDouble();
    await tester.pumpWidget(tree(at(4)));
    await tester.pumpWidget(tree(at(4.25)));
    final glyphs = _only(tester);
    final boundary = tester.renderObject(find.byKey(key));
    Layer? transform() => boundary.debugLayer!.parent;
    expect(glyphs.debugMode, MorphGlyphMode.snapped);
    final first = transform();
    expect(first, isA<TransformLayer>());
    for (var frame = 0; frame < 3; frame++) {
      await tester.pumpWidget(tree(at(4.25 + 0.2 * (frame + 1))));
      expect(glyphs.debugMode, MorphGlyphMode.snapped);
      expect(transform(), same(first));
    }
  });

  testWidgets('exact drawing paints every scale as it is', (tester) async {
    MorphGlyphScale.debugExact = true;
    addTearDown(() => MorphGlyphScale.debugExact = false);
    await _paint(tester, 1, glyphs: true);
    final plain = await _paint(tester, 1.0123, glyphs: false);
    await _paint(tester, 1, glyphs: true);
    final drawn = await _paint(tester, 1.0123, glyphs: true);
    expect(drawn.scale, plain.scale);
    expect(_only(tester).debugMode, MorphGlyphMode.live);
  });

  testWidgets('a new pixel ratio repaints and layout is unchanged', (
    tester,
  ) async {
    await _paint(tester, 1.02, glyphs: true);
    final glyphs = _only(tester);
    expect(glyphs.size, _box);
    glyphs.devicePixelRatio = glyphs.devicePixelRatio;
    expect(glyphs.debugNeedsPaint, isFalse);
    glyphs.devicePixelRatio = glyphs.devicePixelRatio * 2;
    expect(glyphs.debugNeedsPaint, isTrue);
    expect(glyphs.size, _box);
  });

  testWidgets('a tab bar draws the labels of both rows through the policy', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Center(
            child: MorphTabBar(
              items: const [
                MorphTabItem(label: 'One', icon: IconData(0x41)),
                MorphTabItem(label: 'Two', icon: IconData(0x42)),
                MorphTabItem(label: 'Three', icon: IconData(0x43)),
              ],
              selected: 0,
              onChanged: (int i) {},
            ),
          ),
        ),
      ),
    );
    // A row outside the lens and one inside it, a drawing per tab.
    expect(find.byType(MorphGlyphs), findsNWidgets(6));
  });

  for (final tier in MorphGlassTier.values) {
    testWidgets('a released ${tier.name} tab bar returns its labels to live', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 3),
            child: MorphGlassScope(
              painter: GlassBuiltInPainter(tier: tier),
              child: Center(
                child: MorphTabBar(
                  items: const [
                    MorphTabItem(label: 'One', icon: IconData(0x41)),
                    MorphTabItem(label: 'Two', icon: IconData(0x42)),
                    MorphTabItem(label: 'Three', icon: IconData(0x43)),
                  ],
                  selected: 0,
                  onChanged: (int i) {},
                ),
              ),
            ),
          ),
        ),
      );
      List<RenderMorphGlyphs> all() => tester
          .renderObjectList<RenderMorphGlyphs>(find.byType(MorphGlyphs))
          .toList();
      expect(all(), hasLength(6));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('One').first),
      );
      var moved = false;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        moved = moved || all().any((g) => g.debugMode != MorphGlyphMode.live);
      }
      // The swell is real: some frame drew a label off the live drawing.
      expect(moved, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      for (final glyphs in all()) {
        expect(glyphs.debugMode, MorphGlyphMode.live);
        expect(glyphs.debugFactor, 1);
      }
    });
  }
}
