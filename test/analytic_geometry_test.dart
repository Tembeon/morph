// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

String? _ineligibility({
  bool enabled = true,
  bool hasField = false,
  int fusedBoxes = 0,
  bool shadersReady = true,
  required List<(double, List<LiquidGlassAppearance>)> geometries,
}) => RenderLiquidGlassLayer.analyticIneligibility(
  enabled: enabled,
  hasField: hasField,
  fusedBoxes: fusedBoxes,
  shadersReady: () => shadersReady,
  geometries: geometries,
  fallback: const LiquidGlassAppearance.ios27RegularDark(),
);

void main() {
  group('analytic eligibility', () {
    const dark = LiquidGlassAppearance.ios27RegularDark();
    const green = LiquidGlassAppearance.ios27RegularDark(
      tint: Color(0x9934C759),
    );
    const light = LiquidGlassAppearance.ios27RegularLight();

    test('separate shapes with one appearance are eligible', () {
      expect(
        _ineligibility(
          geometries: [
            (0, [dark, dark]),
            (0, [dark]),
          ],
        ),
        isNull,
      );
    });

    test('the toggle', () {
      expect(
        _ineligibility(
          enabled: false,
          geometries: [
            (0, [dark]),
          ],
        ),
        'disabled',
      );
    });

    test('a sampled fused field', () {
      expect(
        _ineligibility(
          hasField: true,
          geometries: [
            (0, [dark, dark]),
          ],
        ),
        'fused field',
      );
    });

    test('a body of merged boxes, up to four', () {
      for (final boxes in [2, 3, 4]) {
        expect(
          _ineligibility(
            hasField: true,
            fusedBoxes: boxes,
            geometries: [(0, List.filled(boxes, dark))],
          ),
          isNull,
        );
      }
      expect(
        _ineligibility(
          hasField: true,
          fusedBoxes: 5,
          geometries: [(0, List.filled(5, dark))],
        ),
        'more than 4 fused boxes',
      );
      expect(
        _ineligibility(
          hasField: true,
          fusedBoxes: 2,
          geometries: [
            (0, [dark, light]),
          ],
        ),
        'mixed appearances',
      );
    });

    test('a blend with one shape never blends; with two it does', () {
      expect(
        _ineligibility(
          geometries: [
            (12, [dark]),
            (0, [dark]),
          ],
        ),
        isNull,
      );
      expect(
        _ineligibility(
          geometries: [
            (12, [dark, dark]),
          ],
        ),
        'blend group',
      );
    });

    test('eight shapes are eligible, nine are not', () {
      expect(_ineligibility(geometries: [(0, List.filled(8, dark))]), isNull);
      expect(
        _ineligibility(
          geometries: [(0, List.filled(5, dark)), (0, List.filled(4, dark))],
        ),
        'more than 8 shapes',
      );
    });

    test('appearances that differ only by tint are eligible', () {
      expect(
        _ineligibility(
          geometries: [
            (0, [dark, green]),
          ],
        ),
        isNull,
      );
    });

    test('mixed appearances are not', () {
      expect(
        _ineligibility(
          geometries: [
            (0, [dark, light]),
          ],
        ),
        'mixed appearances',
      );
    });

    test('shaders that have not loaded', () {
      expect(
        _ineligibility(
          shadersReady: false,
          geometries: [
            (0, [dark]),
          ],
        ),
        'shaders not loaded',
      );
    });
  });

  test('the analytic shaders stay out of the liquid program list', () {
    expect(ShaderKeys.liquidGlassRenders, hasLength(9));
    for (final key in ShaderKeys.liquidGlassAnalyticRenders) {
      expect(ShaderKeys.liquidGlassRenders, isNot(contains(key)));
    }
  });
}
