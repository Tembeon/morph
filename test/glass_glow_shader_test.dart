// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/glass_painter.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/glass/renderer/liquid_glass_glow.dart';
import 'package:morph/src/glass/renderer/liquid_shader_variants.dart';
import 'package:morph/src/glass/renderer/pass/final_pass_layout.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/menu_fusion.dart';

const String _shaders = 'lib/src/glass/renderer/shaders/';

final RegExp _uniform = RegExp(
  r'^uniform (float|vec2|vec3|vec4) (\w+)(?:\[(\d+)\])?;',
);

const Map<String, int> _floats = {'float': 1, 'vec2': 2, 'vec3': 3, 'vec4': 4};

/// The float index and count of the core's uniform [name].
(int, int) _coreUniform(String name) {
  var index = 0;
  for (final line in File(
    '${_shaders}liquid_glass_final_render_core.glsl',
  ).readAsLinesSync()) {
    final match = _uniform.firstMatch(line.trim());
    if (match == null) continue;
    final floats = _floats[match.group(1)]! * int.parse(match.group(3) ?? '1');
    if (match.group(2) == name) return (index, floats);
    index += floats;
  }
  throw StateError('$name not declared');
}

const _button = RRect.fromLTRBXY(100, 90, 144, 134, 22, 22);
const _menu = RRect.fromLTRBXY(20, 0, 220, 80, 32, 32);

const _glow = MorphGlassGlow(
  wash: 0.04,
  center: Offset(60, 30),
  radius: 0.568 * 160,
  gain: 3 * 0.38 * 0.5,
);

MorphGlassSurface _surface(
  MorphGlassKind kind,
  RRect shape, {
  bool lit = false,
}) => MorphGlassSurface(
  kind: kind,
  shape: shape,
  color: const Color(0xF2222222),
  brightness: Brightness.dark,
  glow: lit ? _glow : null,
);

Widget _host(Widget Function(BuildContext context) build) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: RepaintBoundary(
      child: SizedBox(width: 300, height: 140, child: Builder(builder: build)),
    ),
  ),
);

/// The glows the liquid glass layers under the tree hand their final pass.
List<LiquidGlassGlow?> _layerGlows(WidgetTester tester) => [
  for (final layer in tester.widgetList<LiquidGlassLayer>(
    find.byType(LiquidGlassLayer),
  ))
    layer.glowOf?.call(),
];

void main() {
  setUpAll(() => isLocalTest = true);

  group('the glow uniforms', () {
    test('sit after uSolidBackdrop in every final shader', () {
      expect(_coreUniform('uSolidBackdropGlow'), (
        FinalPassLayout.solidBackdrop,
        16,
      ));
      expect(FinalPassLayout.glow, FinalPassLayout.solidBackdrop + 4);
      expect(
        FinalPassLayout.glow + LiquidGlassGlow.floatCount,
        FinalPassLayout.analytic,
      );
      final core = File(
        '${_shaders}liquid_glass_final_render_core.glsl',
      ).readAsStringSync();
      for (final (i, name) in [
        'uSolidBackdrop',
        'uGlowSpot',
        'uGlowBox',
        'uGlowShape',
      ].indexed) {
        expect(core, contains('#define $name uSolidBackdropGlow[$i]'));
      }
      expect(core, contains('#include "glass_glow.glsl"'));
      // Every variant lights the glow, the mixed-appearance one included.
      final gate = core.indexOf('if (uGlowSpot.w > 0.0 || uGlowShape.y > 0.0)');
      final call = core.indexOf('applyGlassGlow(');
      expect(gate, greaterThan(0));
      expect(call, greaterThan(gate));
      expect(core.lastIndexOf('#if', call), lessThan(gate));
      // Every variant compiles the one entry, which includes the core.
      expect(
        File('${_shaders}liquid_glass_final_render.frag').readAsStringSync(),
        contains('#include "liquid_glass_final_render_core.glsl"'),
      );
      expect(LiquidShaderVariant.values, hasLength(19));
    });

    test('carry a glow in the matte space of the layer', () {
      const dpr = 3.0;
      final glow = LiquidGlassGlow(
        clip: _menu,
        center: _glow.center,
        radius: _glow.radius,
        gain: _glow.gain,
        wash: _glow.wash,
      );
      final sigma = _glow.radius * dpr;
      expect(LiquidGlassGlow.uniformsOf(glow, dpr), [
        60 * dpr,
        30 * dpr,
        moreOrLessEquals(math.log2e / (2 * sigma * sigma), epsilon: 1e-15),
        _glow.gain,
        120 * dpr,
        40 * dpr,
        100 * dpr,
        40 * dpr,
        32 * dpr,
        _glow.wash,
        0,
        0,
      ]);
    });

    test('are all zero without a glow, which the shader skips', () {
      final none = LiquidGlassGlow.uniformsOf(null, 3);
      expect(none, List<double>.filled(LiquidGlassGlow.floatCount, 0));
      final dark = LiquidGlassGlow.uniformsOf(
        const LiquidGlassGlow(
          clip: _menu,
          center: Offset(60, 30),
          radius: 50,
          gain: 0,
          wash: 0,
        ),
        3,
      );
      expect(dark, none);
      expect(
        LiquidGlassGlow.shade(none, const Offset(90, 90), (0.25, 0.5, 1.25)),
        (0.25, 0.5, 1.25),
      );
    });
  });

  group('the shader reference', () {
    const dpr = 3.0;
    final glow = LiquidGlassGlow(
      clip: _menu,
      center: _glow.center,
      radius: _glow.radius,
      gain: _glow.gain,
      wash: _glow.wash,
    );
    final uniforms = LiquidGlassGlow.uniformsOf(glow, dpr);

    test('is the wash, then the dodge of the spot, clamped at white', () {
      for (final point in const [
        Offset(60, 30),
        Offset(100, 50),
        Offset(30, 70),
        Offset(200, 10),
      ]) {
        final factor = _glow.factorAt((point - _glow.center).distance);
        for (final c in const [0.0, 0.1, 0.35, 0.6, 0.9, 1.0]) {
          final (r, g, b) = LiquidGlassGlow.shade(uniforms, point * dpr, (
            c,
            c / 2,
            c / 4,
          ));
          double dodge(double channel) =>
              math.min(1.0, math.min(1.0, channel + _glow.wash) * factor);
          expect(r, moreOrLessEquals(dodge(c), epsilon: 1e-12));
          expect(g, moreOrLessEquals(dodge(c / 2), epsilon: 1e-12));
          expect(b, moreOrLessEquals(dodge(c / 4), epsilon: 1e-12));
        }
      }
    });

    test('lights nothing outside the lit surface', () {
      for (final point in const [
        Offset(10, 40),
        Offset(122, 112),
        Offset(230, 40),
        Offset(25, 5),
      ]) {
        expect(LiquidGlassGlow.shade(uniforms, point * dpr, (0.4, 0.4, 0.4)), (
          0.4,
          0.4,
          0.4,
        ), reason: '$point');
      }
    });

    test('blends the edge over one device pixel as the clip did', () {
      final edge = LiquidGlassGlow.shade(
        uniforms,
        const Offset(120 * dpr, 80 * dpr),
        (0.4, 0.4, 0.4),
      );
      final inside = LiquidGlassGlow.shade(
        uniforms,
        const Offset(120 * dpr, 80 * dpr - 1),
        (0.4, 0.4, 0.4),
      );
      expect(
        edge.$1,
        moreOrLessEquals(0.4 + (inside.$1 - 0.4) / 2, epsilon: 2e-3),
      );
    });

    test('stays within a level of the 16-stop gradient the dodge drew', () {
      // The gradient the color-dodge painter drew: white levels at 17
      // stops over three sigma, linear between, cut at that square.
      double drawn(double reach, double gain) {
        final p = math.min(reach, 1.0);
        const stops = 16;
        final i = math.min((p * stops).floor(), stops - 1);
        final t = p * stops - i;
        double white(int k) {
          final q = k / stops;
          return 1 - 1 / (1 + gain * math.exp(-4.5 * q * q));
        }

        return 1 / (1 - (white(i) + (white(i + 1) - white(i)) * t));
      }

      for (final gain in const [0.324, 0.57]) {
        var worst = 0.0;
        for (var n = 0; n <= 1000; n++) {
          final p = n / 1000;
          final exact = 1 + gain * math.exp(-4.5 * p * p);
          worst = math.max(worst, (exact - drawn(p, gain)).abs());
        }
        expect(worst * 255, lessThan(0.65), reason: 'gain $gain');
      }
    });
  });

  group('the liquid tier hands its final pass the lit surface', () {
    testWidgets('of separate shapes', (tester) async {
      await tester.pumpWidget(
        _host(
          (context) => const GlassBuiltInPainter().buildLayer(context, [
            _surface(MorphGlassKind.button, _button),
            _surface(MorphGlassKind.menu, _menu, lit: true),
          ]),
        ),
      );
      tester.takeException();
      expect(_layerGlows(tester), [
        LiquidGlassGlow(
          clip: _menu,
          center: _glow.center,
          radius: _glow.radius,
          gain: _glow.gain,
          wash: _glow.wash,
        ),
      ]);
    });

    testWidgets('of a fused body, clipped to the lit member', (tester) async {
      final outline = morphMenuSilhouette(_menu, _button, 12);
      await tester.pumpWidget(
        _host(
          (context) => const GlassBuiltInPainter().buildLayer(context, [
            _surface(MorphGlassKind.button, _button),
            _surface(MorphGlassKind.menu, _menu, lit: true),
          ], outline: outline),
        ),
      );
      tester.takeException();
      expect(_layerGlows(tester), [
        LiquidGlassGlow(
          clip: _menu,
          center: _glow.center,
          radius: _glow.radius,
          gain: _glow.gain,
          wash: _glow.wash,
        ),
      ]);
    });

    testWidgets('of one surface, in the surface box', (tester) async {
      await tester.pumpWidget(
        _host(
          (context) => const GlassBuiltInPainter().buildSurface(
            context,
            _surface(MorphGlassKind.menu, _menu, lit: true),
          ),
        ),
      );
      tester.takeException();
      expect(_layerGlows(tester), [
        LiquidGlassGlow(
          clip: _menu.shift(-_menu.outerRect.topLeft),
          center: _glow.center - _menu.outerRect.topLeft,
          radius: _glow.radius,
          gain: _glow.gain,
          wash: _glow.wash,
        ),
      ]);
    });

    testWidgets('and an unlit layer nothing', (tester) async {
      await tester.pumpWidget(
        _host(
          (context) => const GlassBuiltInPainter().buildLayer(context, [
            _surface(MorphGlassKind.button, _button),
            _surface(MorphGlassKind.menu, _menu),
          ]),
        ),
      );
      tester.takeException();
      expect(_layerGlows(tester), [null]);
    });
  });

  group('the flat tier draws no glow', () {
    Future<ui.Image> paint(
      WidgetTester tester,
      MorphGlassTier tier, {
      required bool lit,
    }) async {
      await tester.pumpWidget(
        _host(
          (context) => GlassBuiltInPainter(tier: tier).buildLayer(context, [
            _surface(MorphGlassKind.button, _button),
            _surface(MorphGlassKind.menu, _menu, lit: lit),
          ]),
        ),
      );
      tester.takeException();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      return tester.runAsync(boundary.toImage).then((i) => i!);
    }

    Future<List<int>> pixels(ui.Image image) async {
      final data = await image.toByteData();
      return data!.buffer.asUint8List();
    }

    testWidgets('flat', (tester) async {
      final dark = await paint(tester, MorphGlassTier.flat, lit: false);
      final lit = await paint(tester, MorphGlassTier.flat, lit: true);
      expect(find.byType(LiquidGlassLayer), findsNothing);
      final before = await tester.runAsync(() => pixels(dark));
      final after = await tester.runAsync(() => pixels(lit));
      expect(before!.any((byte) => byte != 0), isTrue);
      expect(after, before);
    });
  });
}
