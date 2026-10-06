/// The small-blur harness: backdrop blurs of the edge effect and of the
/// frosted glass rendered offscreen over the shader harness's backdrop,
/// once as the package draws them (the edge effect blurring a copy of the
/// backdrop around its band, a frost just below Impeller's half
/// resolution blur raised to it) and once as before (the blur over the
/// whole pass, the frost as given), compared pixel by pixel on the same
/// device.
library;

// The harness flips the package's own A/B switches.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart'
    show RenderLiquidGlassLayer;
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/internal/blur_reach.dart'
    show debugMorphHalfResolutionBlur;
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/widgets/scroll_edge_effect.dart'
    show debugMorphEdgeEffectBoundsBlur;
import 'package:morph/widgets.dart';

import 'shader_harness.dart';

/// One blur case: what is drawn over the backdrop.
class BlurCase {
  /// Creates a case named [name] drawing [build].
  const BlurCase(this.name, this.build, {this.bound = 2});

  /// The case's name in the report.
  final String name;

  /// The layer over the backdrop for a variant, in the harness region's
  /// coordinates.
  final Widget Function(BlurVariant variant) build;

  /// The largest channel difference from the whole-pass blur the case
  /// accepts: the bounded edge effect is the same blur, a raised frost
  /// is not.
  final int bound;
}

Widget _glass(HarnessCase glassCase) => LiquidGlassLayer(
  settings: glassCase.settings,
  fake: glassCase.fake,
  blursOwnBackdrop: glassCase.ownBackdrop,
  defaultAppearance: const LiquidGlassAppearance.ios27RegularDark(),
  child: Stack(
    children: [
      for (final s in glassCase.shapes)
        Positioned.fromRect(
          rect: s.rect,
          child: LiquidGlass(
            shape: s.shape,
            appearance: s.appearance,
            child: const SizedBox.expand(),
          ),
        ),
    ],
  ),
);

HarnessCase _fake(HarnessCase glassCase) => HarnessCase(
  'fake-${glassCase.name}',
  glassCase.settings,
  glassCase.shapes,
  fake: true,
);

/// The frosted cases of the shader harness: 2 pt frost under toolbar
/// glass, a frosted menu, half visible frosted glass, and the same on the
/// fake tier.
List<HarnessCase> get _frosted {
  final cases = harnessCasesNamed(
    'toolbar-dark-blur,menu-frosted,visibility-half-frosted',
  );
  return [...cases, for (final c in cases) _fake(c)];
}

/// The cases: a tab bar, the frosted glass of [_frosted], and the hard and
/// soft edge effects at the top and the bottom of the region, faded and
/// not.
final List<BlurCase> blurCases = [
  BlurCase(
    'tab-bar',
    (BlurVariant variant) => MorphGlass(
      painter: const MorphGlassRenderer(tier: MorphGlassTier.liquid),
      child: Align(
        alignment: const Alignment(0, 0.6),
        child: MorphTabBar(
          items: const [
            MorphTabItem(icon: IconData(0xe318), label: 'Home'),
            MorphTabItem(icon: IconData(0xe318), label: 'Search'),
            MorphTabItem(icon: IconData(0xe318), label: 'Radio'),
          ],
          selected: 0,
          onChanged: (int i) {},
        ),
      ),
    ),
    bound: 8,
  ),
  for (final glassCase in _frosted)
    BlurCase(
      glassCase.name,
      (BlurVariant variant) => _glass(glassCase),
      bound: 24,
    ),
  for (final (name, style, edge, opacity) in const [
    ('edge-hard-top', MorphScrollEdgeEffectStyle.hard, AxisDirection.up, 1.0),
    ('edge-soft-top', MorphScrollEdgeEffectStyle.soft, AxisDirection.up, 1.0),
    (
      'edge-hard-bottom',
      MorphScrollEdgeEffectStyle.hard,
      AxisDirection.down,
      1.0,
    ),
    (
      'edge-hard-top-faded',
      MorphScrollEdgeEffectStyle.hard,
      AxisDirection.up,
      0.45,
    ),
    (
      'edge-soft-bottom-faded',
      MorphScrollEdgeEffectStyle.soft,
      AxisDirection.down,
      0.7,
    ),
  ])
    BlurCase(
      name,
      (BlurVariant variant) => MorphScrollEdgeEffect(
        extent: 100,
        edge: edge,
        style: style,
        opacity: opacity,
        theme: MorphScrollEdgeEffectThemeData.dark,
      ),
    ),
];

/// Which blurs a render uses.
enum BlurVariant {
  /// The package's: the seeded edge effect, the raised frost.
  bounded,

  /// The blur over the whole pass, the frost as given.
  whole,
}

/// Switches the package between [variant]'s blur inputs.
void useBlurVariant(BlurVariant variant) {
  debugMorphEdgeEffectBoundsBlur = variant == BlurVariant.bounded;
  debugMorphHalfResolutionBlur = variant == BlurVariant.bounded;
  RenderLiquidGlassLayer.debugSeedsBlur = true;
  useShaderVariant(ShaderVariant.candidate);
}

/// Renders every case of [cases] on both variants with [harness]'s
/// backdrop and compares them: the bounded variant twice (`repeat`, must
/// be 0) and its difference from the whole-pass blur (`diff`).
Future<Map<String, Object>> runBlurParity(
  ShaderHarness harness, {
  required List<BlurCase> cases,
  String? outDir,
}) async {
  final image = await harness.backdrop();
  final boundary = GlobalKey();
  final dpr = harness.devicePixelRatio;
  final size = Size(image.width / dpr, image.height / dpr);
  Future<HarnessShot> shoot(BlurCase blurCase, BlurVariant variant) async {
    useBlurVariant(variant);
    await harness.tester.pumpWidget(const SizedBox.shrink());
    await harness.tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: size, devicePixelRatio: dpr),
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox.fromSize(
                size: size,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RawImage(
                        image: image,
                        scale: dpr,
                        filterQuality: FilterQuality.none,
                        fit: BoxFit.none,
                        alignment: Alignment.topLeft,
                      ),
                    ),
                    Positioned.fill(
                      key: ValueKey('${blurCase.name}-${variant.name}'),
                      child: blurCase.build(variant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await harness.tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await harness.tester.pump(const Duration(milliseconds: 16));
    }
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final shot = (await harness.tester.runAsync(() async {
      final picture = await render.toImage(pixelRatio: dpr);
      final data = await picture.toByteData();
      final out = HarnessShot(
        picture.width,
        picture.height,
        data!.buffer.asUint8List(),
      );
      picture.dispose();
      return out;
    }))!;
    return shot;
  }

  final results = <String, Object>{};
  for (final blurCase in cases) {
    final first = await shoot(blurCase, BlurVariant.bounded);
    final repeat = await shoot(blurCase, BlurVariant.bounded);
    final whole = await shoot(blurCase, BlurVariant.whole);
    if (outDir != null) {
      File(
        '$outDir/${blurCase.name}.bounded.png',
      ).writeAsBytesSync(await harness.png(first));
      File(
        '$outDir/${blurCase.name}.whole.png',
      ).writeAsBytesSync(await harness.png(whole));
    }
    results[blurCase.name] = {
      'bound': blurCase.bound,
      'bounded': first.hash,
      'whole': whole.hash,
      'repeat': HarnessDiff.of(first, repeat).max,
      'diff': HarnessDiff.of(first, whole).toJson(),
    };
  }
  useBlurVariant(BlurVariant.bounded);
  return {
    'device_pixel_ratio': dpr,
    'region': [size.width, size.height],
    'cases': results,
  };
}

/// Checks a [runBlurParity] report: every repeat is 0 and no case differs
/// from the whole-pass blur by more than its bound.
void expectBlurParity(Map<String, Object> report) {
  final cases = report['cases']! as Map<String, Object>;
  for (final MapEntry(:key, :value) in cases.entries) {
    final entry = value as Map<String, Object>;
    expect(entry['repeat'], 0, reason: '$key: repeat capture differs');
    final diff = entry['diff']! as Map<String, Object>;
    expect(
      diff['max']! as int,
      lessThanOrEqualTo(entry['bound']! as int),
      reason: '$key: $diff',
    );
  }
}
