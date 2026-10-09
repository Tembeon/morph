// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The test drives the renderer's own layer.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/glass_field.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show AnalyticGeometryMode, RenderLiquidGlassLayer;
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/widgets.dart';

import '../integration_test/support/shader_harness.dart';

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
      RenderLiquidGlassLayer.debugAnalyticGeometry = null;
      RenderLiquidGlassLayer.debugAnalyticMode = null;
      RenderLiquidGlassLayer.debugAnalyticCapsule = null;
    });
    await tester.runAsync(MorphGlassRenderer.precache);
    await tester.runAsync(RenderLiquidGlassLayer.precacheAnalyticShaders);
    harness = ShaderHarness(tester);
    backdrop = await harness.backdrop();
    RenderLiquidGlassLayer.debugAnalyticGeometry = true;
  }

  testWidgets('changes: a resting layer shades from one matte encode', (
    WidgetTester t,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await setUp(t);

    RenderLiquidGlassLayer.debugAnalyticMode = AnalyticGeometryMode.always;
    final always = await fresh(2);
    expect(layer().debugAnalytic, isTrue);
    RenderLiquidGlassLayer.debugAnalyticMode = AnalyticGeometryMode.changes;
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
    RenderLiquidGlassLayer.debugAnalyticMode = AnalyticGeometryMode.always;
    await frames(3);
    expect(layer().debugAnalytic, isTrue);
    RenderLiquidGlassLayer.debugAnalyticGeometry = false;
    final matteThree = await fresh(3);
    // The rest encode is the matte path's own frame.
    expect(HarnessDiff.of(restedThree, matteThree).max, 0);
  });

  testWidgets('changes: a geometry changing every other frame stays '
      'analytic', (WidgetTester t) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await setUp(t);
    RenderLiquidGlassLayer.debugAnalyticMode = AnalyticGeometryMode.changes;
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

  testWidgets('changes: a resting merged body fuses its field once', (
    WidgetTester t,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await setUp(t);
    RenderLiquidGlassLayer.debugAnalyticMode = AnalyticGeometryMode.changes;
    debugClearMorphGlassOutlines();
    const rects = [
      ui.Rect.fromLTWH(40, 240, 120, 44),
      ui.Rect.fromLTWH(165, 240, 120, 44),
    ];
    final merged = HarnessCase(
      'rest-merged',
      const LiquidGlassSettings(frost: 0),
      [
        for (final rect in rects)
          HarnessShape(
            rect,
            const LiquidRoundedSuperellipse(borderRadius: 22),
            const LiquidGlassAppearance.ios27RegularDark(),
          ),
      ],
      field: morphGlassOutlineField(
        morphGlassContainerBoxOutline([
          for (final rect in rects)
            ui.RRect.fromRectAndRadius(rect, const ui.Radius.circular(22)),
        ], 12),
      ),
    );
    final traces = morphGlassOutlineDebugTraces;
    await harness.show(merged, ShaderVariant.candidate);
    expect(layer().debugResting, isTrue);
    expect(layer().field, isA<GlassBoxField>());
    expect(morphGlassOutlineDebugTraces - traces, 1);
    await frames(10);
    expect(morphGlassOutlineDebugTraces - traces, 1);
  });

  testWidgets('capsules as stadiums against the superellipse', (
    WidgetTester t,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    await setUp(t);
    RenderLiquidGlassLayer.debugAnalyticMode = AnalyticGeometryMode.always;
    RenderLiquidGlassLayer.debugAnalyticCapsule = false;
    final superellipse = await fresh(3);
    RenderLiquidGlassLayer.debugAnalyticCapsule = true;
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
