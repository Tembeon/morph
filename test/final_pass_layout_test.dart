// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/glass/renderer/liquid_glass_glow.dart';
import 'package:morph/src/glass/renderer/liquid_shader_variants.dart';
import 'package:morph/src/glass/renderer/pass/final_pass_layout.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

import 'support/final_pass_glsl.dart';

void main() {
  group('the final pass layout matches the GLSL', () {
    test('the core block', () {
      final layout = coreLayout();
      expect(layout['uSize'], (FinalPassLayout.size, 2));
      expect(layout['uGeometryOffset'], (FinalPassLayout.geometryOffset, 2));
      expect(layout['uGeometrySize'], (FinalPassLayout.geometrySize, 2));
      expect(layout['uTint']!.$1, FinalPassLayout.tint);
      expect(layout['uProfileConfig']!.$1 + 1, FinalPassLayout.materialCenter);
      expect(layout['uFilterToMatteBasis'], (
        FinalPassLayout.filterToMatteBasis,
        4,
      ));
      expect(layout['uFilterToMatteOffset'], (
        FinalPassLayout.filterToMatteOffset,
        2,
      ));
      expect(layout['uBlurFade'], (FinalPassLayout.blurFade, 1));
      expect(layout['uSoften'], (FinalPassLayout.soften, 1));
      expect(layout['uBackdropBounds'], (FinalPassLayout.backdropBounds, 4));
      expect(layout['uGeometryUVScale'], (FinalPassLayout.geometryUVScale, 2));
      expect(layout['uMaterialTextureSize'], (
        FinalPassLayout.materialTextureSize,
        2,
      ));
      expect(layout['uBackdropShrinkAxis'], (
        FinalPassLayout.backdropShrinkAxis,
        2,
      ));
      expect(layout['uSolidBackdropGlow'], (FinalPassLayout.solidBackdrop, 16));
      expect(
        FinalPassLayout.glow + LiquidGlassGlow.floatCount,
        FinalPassLayout.solidBackdrop + 16,
      );
    });

    test('the core ends its float uniforms at 81', () {
      expect(coreFloats(), FinalPassLayout.analytic);
      expect(FinalPassLayout.analytic, 81);
    });

    test('the shape cap matches the shader', () {
      expect(
        analyticDefine('ANALYTIC_MAX_SHAPES'),
        FinalPassLayout.analyticMaxShapes,
      );
      expect(FinalPassLayout.analyticMaxShapes, 8);
    });

    for (final fused in [false, true]) {
      for (final tint in [false, true]) {
        test('the analytic block: '
            '${fused ? 'fused ' : ''}${tint ? 'tint' : 'one appearance'}', () {
          const max = FinalPassLayout.analyticMaxShapes;
          final boxes = analyticDefine('ANALYTIC_MAX_BOXES');
          expect(boxes, GlassBoxField.maxBoxes);
          final layout = glslLayout(
            analyticLines(tint: tint, fused: fused),
            coreFloats(),
            {
              'MAX_SHAPES': max,
              'ANALYTIC_MAX_SHAPES': max,
              'ANALYTIC_MAX_BOXES': boxes,
            },
          );
          expect(layout['uAnalyticHeader'], (FinalPassLayout.analytic, 8));
          expect(layout['uShapeData'], (FinalPassLayout.shapeData, max * 12));
          expect(FinalPassLayout.shapeData, 89);
          expect(layout['uRseData'], (FinalPassLayout.rseData, max * 12));
          expect(FinalPassLayout.rseData, 185);
          expect(layout['uShapeBounds'], (
            FinalPassLayout.shapeBounds,
            max * 5,
          ));
          expect(FinalPassLayout.shapeBounds, 281);
          expect(
            FinalPassLayout.shapeCull,
            FinalPassLayout.shapeBounds + max * 4,
          );
          expect(FinalPassLayout.shapeCull, 313);
          expect(layout['uAnalyticFlatFace'], (FinalPassLayout.flatFace, 1));
          expect(FinalPassLayout.flatFace, 321);
          if (fused) {
            expect(layout['uFusedBoxes'], (
              FinalPassLayout.fusedBoxes,
              boxes * 8,
            ));
            expect(FinalPassLayout.fusedBoxes, 322);
          } else {
            expect(layout.containsKey('uFusedBoxes'), isFalse);
          }
          if (tint) {
            final at = fused
                ? FinalPassLayout.fusedTints
                : FinalPassLayout.tints;
            expect(layout['uShapeTints'], (at, max * 4));
            expect(at, fused ? 354 : 322);
          } else {
            expect(layout.containsKey('uShapeTints'), isFalse);
          }
          expect(layout.keys, [
            'uAnalyticHeader',
            'uShapeData',
            'uRseData',
            'uShapeBounds',
            'uAnalyticFlatFace',
            if (fused) 'uFusedBoxes',
            if (tint) 'uShapeTints',
          ]);
        });
      }
    }

    // Metal gives each uniform declaration a buffer slot by declaration
    // order and has 31; a shader past that fails to compile on iOS and
    // macOS, and Impeller retries the compile on every frame it draws.
    for (final fused in [false, true]) {
      for (final tint in [false, true]) {
        test('the analytic shader fits Metal\'s 31 buffer slots: '
            '${fused ? 'fused ' : ''}${tint ? 'tint' : 'one appearance'}', () {
          final declarations = [
            ...coreLines(),
            ...analyticLines(tint: tint, fused: fused),
          ].where((line) => glslUniform.hasMatch(line.trim())).length;
          expect(declarations, lessThanOrEqualTo(31));
        });
      }
    }

    test('the separate-shape variants carry no merge law', () {
      final separate = analyticLines(tint: true, fused: false).join('\n');
      for (final name in ['fusedDistance', 'fusedOptics', 'fusedBox(']) {
        expect(separate, isNot(contains(name)));
      }
      final fused = analyticLines(tint: true, fused: true).join('\n');
      expect(fused, contains('fusedDistance'));
      for (final variant in LiquidShaderVariant.values) {
        expect(
          variant.defines.contains('WITH_ANALYTIC_FUSED'),
          ShaderKeys.liquidGlassAnalyticFusedRenders.contains(
            ShaderKeys.finalRender(variant),
          ),
          reason: variant.name,
        );
      }
    });
  });
}
