// The test reads the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

const String _shaders = 'lib/src/glass/renderer/shaders/';

final RegExp _uniform = RegExp(
  r'^uniform (float|vec2|vec3|vec4) (\w+)(?:\[([^\]]+)\])?;',
);

const Map<String, int> _floats = {'float': 1, 'vec2': 2, 'vec3': 3, 'vec4': 4};

/// The float index of every non-sampler uniform declared in [lines], in
/// declaration order from [start], array sizes evaluated with [defines].
Map<String, (int, int)> _layout(
  Iterable<String> lines,
  int start,
  Map<String, int> defines,
) {
  final layout = <String, (int, int)>{};
  var index = start;
  for (final line in lines) {
    final match = _uniform.firstMatch(line.trim());
    if (match == null) continue;
    var count = 1;
    if (match.group(3) case final size?) {
      // Left to right over * and /, as the declarations write them.
      final terms = size.split(' ').where((t) => t.isNotEmpty).toList();
      int value(String term) => defines[term] ?? int.parse(term);
      count = value(terms.first);
      for (var t = 1; t + 1 < terms.length; t += 2) {
        count = terms[t] == '*'
            ? count * value(terms[t + 1])
            : count ~/ value(terms[t + 1]);
      }
    }
    final floats = _floats[match.group(1)]! * count;
    layout[match.group(2)!] = (index, floats);
    index += floats;
  }
  return layout;
}

/// The core's floats before the analytic include.
int _coreFloats() {
  final core = File(
    '${_shaders}liquid_glass_final_render_core.glsl',
  ).readAsLinesSync();
  final include = core.indexWhere(
    (line) => line.contains('#include "analytic_geometry.glsl"'),
  );
  expect(include, greaterThan(0));
  final layout = _layout(core.take(include), 0, const {});
  final (last, size) = layout.values.last;
  return last + size;
}

/// The analytic file's lines a variant compiles: its `#if SHAPE_TINT` and
/// `#if ANALYTIC_FUSED` blocks (with their `#else`) by [tint] and [fused],
/// every other conditional kept.
List<String> _analyticLines({required bool tint, required bool fused}) {
  final lines = File('${_shaders}analytic_geometry.glsl').readAsLinesSync();
  final kept = <String>[];
  final open = <bool>[];
  bool active() => open.every((on) => on);
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#if')) {
      open.add(switch (trimmed) {
        '#if SHAPE_TINT' => tint,
        '#if ANALYTIC_FUSED' => fused,
        _ => true,
      });
      continue;
    }
    if (trimmed == '#else') {
      open.add(!open.removeLast());
      continue;
    }
    if (trimmed == '#endif') {
      open.removeLast();
      continue;
    }
    if (active()) kept.add(line);
  }
  return kept;
}

int _maxShapes() => _define('ANALYTIC_MAX_SHAPES');

int _define(String name) {
  final define = RegExp('^#define $name (\\d+)');
  for (final line in File(
    '${_shaders}analytic_geometry.glsl',
  ).readAsLinesSync()) {
    if (define.firstMatch(line) case final match?) {
      return int.parse(match.group(1)!);
    }
  }
  throw StateError('$name not defined');
}

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
  group('analytic uniform layout', () {
    test('the core ends its float uniforms at 65', () {
      expect(_coreFloats(), RenderLiquidGlassLayer.analyticUniformIndex);
      expect(RenderLiquidGlassLayer.analyticUniformIndex, 65);
    });

    test('the shape cap matches the shader', () {
      expect(_maxShapes(), RenderLiquidGlassLayer.analyticMaxShapes);
      expect(RenderLiquidGlassLayer.analyticMaxShapes, 8);
    });

    for (final fused in [false, true]) {
      for (final tint in [false, true]) {
        test('the analytic uniforms sit where the layer writes them: '
            '${fused ? 'fused ' : ''}${tint ? 'tint' : 'one appearance'}', () {
          final max = _maxShapes();
          final boxes = _define('ANALYTIC_MAX_BOXES');
          expect(boxes, GlassBoxField.maxBoxes);
          final layout =
              _layout(_analyticLines(tint: tint, fused: fused), _coreFloats(), {
                'MAX_SHAPES': max,
                'ANALYTIC_MAX_SHAPES': max,
                'ANALYTIC_MAX_BOXES': boxes,
              });
          expect(layout['uAnalyticOptics'], (
            RenderLiquidGlassLayer.analyticUniformIndex,
            4,
          ));
          expect(layout['uAnalyticRanges'], (69, 4));
          expect(layout['uShapeData'], (
            RenderLiquidGlassLayer.analyticShapeDataIndex,
            max * 12,
          ));
          expect(RenderLiquidGlassLayer.analyticShapeDataIndex, 73);
          expect(layout['uRseData'], (
            RenderLiquidGlassLayer.analyticRseDataIndex,
            max * 12,
          ));
          expect(RenderLiquidGlassLayer.analyticRseDataIndex, 169);
          expect(layout['uShapeBounds'], (
            RenderLiquidGlassLayer.analyticBoundsIndex,
            max * 4,
          ));
          expect(RenderLiquidGlassLayer.analyticBoundsIndex, 265);
          expect(layout['uShapeCull'], (
            RenderLiquidGlassLayer.analyticCullIndex,
            max,
          ));
          expect(RenderLiquidGlassLayer.analyticCullIndex, 297);
          if (fused) {
            expect(layout['uFusedBoxes'], (
              RenderLiquidGlassLayer.analyticFusedBoxesIndex,
              boxes * 8,
            ));
            expect(RenderLiquidGlassLayer.analyticFusedBoxesIndex, 305);
          } else {
            expect(layout.containsKey('uFusedBoxes'), isFalse);
          }
          if (tint) {
            final at = fused
                ? RenderLiquidGlassLayer.analyticFusedTintsIndex
                : RenderLiquidGlassLayer.analyticTintsIndex;
            expect(layout['uShapeTints'], (at, max * 4));
            expect(at, fused ? 337 : 305);
          } else {
            expect(layout.containsKey('uShapeTints'), isFalse);
          }
          expect(layout.keys, [
            'uAnalyticOptics',
            'uAnalyticRanges',
            'uShapeData',
            'uRseData',
            'uShapeBounds',
            'uShapeCull',
            if (fused) 'uFusedBoxes',
            if (tint) 'uShapeTints',
          ]);
        });
      }
    }

    test('the separate-shape variants carry no merge law', () {
      final separate = _analyticLines(tint: true, fused: false).join('\n');
      for (final name in ['fusedDistance', 'fusedOptics', 'fusedBox(']) {
        expect(separate, isNot(contains(name)));
      }
      final fused = _analyticLines(tint: true, fused: true).join('\n');
      expect(fused, contains('fusedDistance'));
      for (final variant in ['', '_ios27', '_tint', '_tint_ios27']) {
        final plain = File(
          '${_shaders}liquid_glass_final_render_analytic$variant.frag',
        ).readAsStringSync();
        expect(plain, isNot(contains('ANALYTIC_FUSED')));
        final merged = File(
          '${_shaders}liquid_glass_final_render_analytic_fused$variant.frag',
        ).readAsStringSync();
        expect(merged, contains('#define ANALYTIC_FUSED 1'));
      }
    });
  });

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
    expect(ShaderKeys.liquidGlassRenders, hasLength(5));
    for (final key in ShaderKeys.liquidGlassAnalyticRenders) {
      expect(ShaderKeys.liquidGlassRenders, isNot(contains(key)));
    }
  });
}
