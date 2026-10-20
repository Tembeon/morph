// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The test drives the renderer's own layer.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/pass/final_pass.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/glass_field.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show RenderLiquidGlassLayer;
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_outline.dart';

import '../integration_test/support/shader_harness.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

/// The analytic geometry modes on the host's Impeller: `changes` rests on
/// one matte encode and shades analytically only while the geometry
/// changes; the capsule option shades full-radius superellipses as
/// stadiums.
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/analytic_mode_host_test.dart
///
/// Without Impeller the test does nothing.
void main() {
  late WidgetTester tester;
  late ShaderHarness harness;
  late ui.Image backdrop;
  final boundary = GlobalKey();

  Widget scene(int count, {bool ticking = false}) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: boundary,
        child: SizedBox.fromSize(
          size: harnessRegion,
          child: Stack(
            children: [
              Positioned.fill(
                child: RawImage(
                  image: backdrop,
                  scale: harness.devicePixelRatio,
                  filterQuality: FilterQuality.none,
                  fit: BoxFit.none,
                  alignment: Alignment.topLeft,
                ),
              ),
              if (ticking) const _Ticking(),
              Positioned.fill(
                child: LiquidGlassLayer(
                  settings: const LiquidGlassSettings(frost: 0),
                  child: Stack(
                    children: [
                      for (var i = 0; i < count; i++)
                        Positioned(
                          left: 20.0 + (i % 3) * 110,
                          top: 40.0 + (i ~/ 3) * 180,
                          width: 96,
                          height: 44,
                          child: const LiquidGlass(
                            shape: LiquidRoundedSuperellipse(borderRadius: 22),
                            appearance:
                                LiquidGlassAppearance.ios27RegularDark(),
                            child: SizedBox.expand(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> frames(int count) async {
    for (var i = 0; i < count; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<HarnessShot> shoot() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = (await tester.runAsync(
      () => render.toImage(pixelRatio: harness.devicePixelRatio),
    ))!;
    final data = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    image.dispose();
    return HarnessShot(image.width, image.height, data.buffer.asUint8List());
  }

  RenderLiquidGlassLayer layer() => tester.allRenderObjects
      .whereType<RenderLiquidGlassLayer>()
      .toSet()
      .single;

  Future<HarnessShot> fresh(int count) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(scene(count));
    await frames(6);
    return shoot();
  }

  Future<void> setUp(WidgetTester t) async {
    tester = t;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    addTearDown(() {
      GlassGeometryFlags.debugAnalyticGeometry = null;
      GlassGeometryFlags.debugAnalyticMode = null;
      GlassGeometryFlags.debugAnalyticCapsule = null;
    });
    await tester.runAsync(GlassBuiltInPainter.precache);
    await tester.runAsync(GlassFinalPass.precacheAnalyticShaders);
    harness = ShaderHarness(tester);
    backdrop = await harness.backdrop();
    GlassGeometryFlags.debugAnalyticGeometry = true;
  }

  testWidgets('changes: a resting layer shades from one matte encode', (
    WidgetTester t,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await setUp(t);

    GlassGeometryFlags.debugAnalyticMode = AnalyticGeometryMode.always;
    final always = await fresh(2);
    expect(layer().debugAnalytic, isTrue);
    GlassGeometryFlags.debugAnalyticMode = AnalyticGeometryMode.changes;
    final resting = await fresh(2);
    expect(layer().debugAnalytic, isFalse);
    expect(layer().debugResting, isTrue);
    expect(layer().debugAnalyticIneligibility, 'resting');
    final restVsAlways = HarnessDiff.of(resting, always);
    // ignore: avoid_print
    print(
      'changes at rest (matte) vs always (analytic) '
      '${restVsAlways.toJson()}',
    );
    final renderer = layer().gpuGeometryRenderer!;

    // A change shades analytically in its own frame, with no encode.
    final encodes = renderer.debugRenderCount;
    await tester.pumpWidget(scene(3));
    expect(layer().debugAnalytic, isTrue);
    expect(layer().debugResting, isFalse);
    expect(renderer.debugRenderCount, encodes);
    // At rest again: one encode.
    await frames(6);
    expect(layer().debugResting, isTrue);
    expect(renderer.debugRenderCount, encodes + 1);
    // Resting asks for nothing more: no encode and no paint of the layer
    // (other frames in this scene come from the host, both modes alike).
    final paints = layer().debugPaintCount;
    await frames(6);
    expect(renderer.debugRenderCount, encodes + 1);
    expect(layer().debugPaintCount, paints);
    final restedThree = await shoot();
    GlassGeometryFlags.debugAnalyticMode = AnalyticGeometryMode.always;
    await frames(3);
    expect(layer().debugAnalytic, isTrue);
    GlassGeometryFlags.debugAnalyticGeometry = false;
    final matteThree = await fresh(3);
    // The rest encode is the matte path's own frame.
    expect(HarnessDiff.of(restedThree, matteThree).max, 0);
  });

  testWidgets('changes: a geometry changing every other frame stays '
      'analytic', (WidgetTester t) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await setUp(t);
    GlassGeometryFlags.debugAnalyticMode = AnalyticGeometryMode.changes;
    await tester.pumpWidget(scene(2, ticking: true));
    await frames(3);
    final renderer = layer().gpuGeometryRenderer!;
    final encodes = renderer.debugRenderCount;
    for (var i = 0; i < 12; i++) {
      if (i.isEven) {
        await tester.pumpWidget(scene(i % 4 == 0 ? 3 : 2, ticking: true));
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(layer().debugAnalytic, isTrue, reason: 'frame $i');
    }
    expect(renderer.debugRenderCount, encodes);
  });

  testWidgets('changes: a resting merged body encodes the merge law', (
    WidgetTester t,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await setUp(t);
    debugClearMorphGlassOutlines();
    // A neck of two bar capsules, and a navigation bar's Done capsule
    // dragged down and toward its neighbor and stretched by its tether,
    // gray like its neighbor and blue (prominent) beside a gray one.
    final stretchedDone = [
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(230, 400, 44, 44),
        const ui.Radius.circular(22),
      ),
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(279, 410, 82, 38),
        const ui.Radius.circular(19),
      ),
    ];
    const doneNeck = ui.Rect.fromLTRB(264, 396, 289, 452);
    const gray = LiquidGlassAppearance.ios27RegularDark();
    final bodies =
        <String, (List<ui.RRect>, ui.Rect, List<LiquidGlassAppearance>)>{
          'neck-s12': (
            [
              for (final rect in const [
                ui.Rect.fromLTWH(40, 240, 120, 44),
                ui.Rect.fromLTWH(165, 240, 120, 44),
              ])
                ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(22)),
            ],
            const ui.Rect.fromLTRB(150, 236, 175, 288),
            const [gray, gray],
          ),
          'stretched-done': (stretchedDone, doneNeck, const [gray, gray]),
          // Two points from its neighbor, so the tint seam runs the
          // neck's height.
          'stretched-done-prominent': (
            [
              stretchedDone.first,
              stretchedDone.last.shift(const Offset(-3, 0)),
            ],
            const ui.Rect.fromLTRB(261, 396, 286, 452),
            const [
              gray,
              LiquidGlassAppearance.ios27RegularDark(tint: Color(0xFF0A84FF)),
            ],
          ),
        };
    for (final MapEntry(key: name, value: (boxes, neck, appearances))
        in bodies.entries) {
      final body = HarnessCase(
        name,
        const LiquidGlassSettings(frost: 0),
        [
          for (final (i, box) in boxes.indexed)
            HarnessShape(
              box.outerRect,
              LiquidRoundedSuperellipse(borderRadius: box.tlRadiusX),
              appearances[i],
            ),
        ],
        field: morphGlassOutlineField(morphGlassContainerBoxOutline(boxes, 12)),
      );
      GlassGeometryFlags.debugAnalyticMode = AnalyticGeometryMode.changes;
      final traces = morphGlassOutlineDebugTraces;
      await harness.show(body, ShaderVariant.candidate);
      expect(layer().debugResting, isTrue, reason: name);
      expect(layer().field, isA<GlassBoxField>(), reason: name);
      // A fused body's resting tints come from its boxes, not a map.
      expect(layer().debugMaterialImage, isNull, reason: name);
      final rest = await harness.shoot();
      await frames(4);
      // The geometry pass merges the boxes itself: the CPU never fuses.
      expect(morphGlassOutlineDebugTraces - traces, 0, reason: name);
      GlassGeometryFlags.debugAnalyticMode = AnalyticGeometryMode.always;
      await frames(3);
      expect(layer().debugAnalytic, isTrue, reason: name);
      final moving = await harness.shoot();
      var area = boxes.first.outerRect;
      for (final box in boxes.skip(1)) {
        area = area.expandToInclude(box.outerRect);
      }
      final dpr = harness.devicePixelRatio;
      final whole = _regionDiff(rest, moving, area.inflate(3), dpr);
      final inNeck = _regionDiff(rest, moving, neck, dpr);
      // ignore: avoid_print
      print(
        '$name rest vs moving: body max ${whole.max} '
        'mean ${whole.mean.toStringAsFixed(4)}, neck max ${inNeck.max} '
        'mean ${inNeck.mean.toStringAsFixed(4)}',
      );
      // NEAR: the matte's 12-bit and companded quantization, as for
      // separate shapes (host run 2026-10-19: neck max 9 and 15, mean
      // 0.10 and 0.24; a field sampled every 4 pt bent the neck into
      // straight steps, up to 125 channel steps from the moving frame).
      // The prominent Done's tint seam takes its boxes' tints in both
      // frames (2026-10-20: max 14, mean 0.15); a coarse tint map drew it
      // in blurred 8-pixel steps (max 208, mean 1.26).
      expect(inNeck.max, lessThanOrEqualTo(24), reason: name);
      expect(inNeck.mean, lessThan(0.5), reason: name);
      expect(whole.mean, lessThan(0.5), reason: name);
    }
  });

  testWidgets('capsules as stadiums against the superellipse', (
    WidgetTester t,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await setUp(t);
    GlassGeometryFlags.debugAnalyticMode = AnalyticGeometryMode.always;
    GlassGeometryFlags.debugAnalyticCapsule = false;
    final superellipse = await fresh(3);
    GlassGeometryFlags.debugAnalyticCapsule = true;
    final stadium = await fresh(3);
    expect(layer().debugAnalytic, isTrue);
    final diff = HarnessDiff.of(superellipse, stadium);
    // ignore: avoid_print
    print('capsule stadium vs superellipse ${diff.toJson()}');
    expect(diff.pixels, greaterThan(0));
  });
}

/// Keeps frames coming, as a running animation does.
class _Ticking extends StatefulWidget {
  const _Ticking();

  @override
  State<_Ticking> createState() => _TickingState();
}

class _TickingState extends State<_Ticking>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) {});

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// The largest channel difference and the mean RGB difference of [a] and
/// [b] over [region] (logical pixels at [dpr]).
({int max, double mean}) _regionDiff(
  HarnessShot a,
  HarnessShot b,
  ui.Rect region,
  double dpr,
) {
  var max = 0;
  var sum = 0;
  var count = 0;
  final left = (region.left * dpr).floor().clamp(0, a.width);
  final right = (region.right * dpr).ceil().clamp(0, a.width);
  final top = (region.top * dpr).floor().clamp(0, a.height);
  final bottom = (region.bottom * dpr).ceil().clamp(0, a.height);
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final p = (y * a.width + x) * 4;
      for (var c = 0; c < 3; c++) {
        final d = (a.bytes[p + c] - b.bytes[p + c]).abs();
        if (d > max) max = d;
        sum += d;
      }
      count++;
    }
  }
  return (max: max, mean: count == 0 ? 0.0 : sum / (count * 3));
}
