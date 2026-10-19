import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/liquid_glass_settings.dart';

/// The final pass folds the light direction, the highlight color and the
/// rim parameters the layer always writes the same; these must stay what the
/// layer writes.
void main() {
  final core = File(
    'lib/src/glass/renderer/shaders/liquid_glass_final_render_core.glsl',
  ).readAsStringSync();
  final layer = File(
    'lib/src/glass/renderer/rendering/liquid_glass_layer.dart',
  ).readAsStringSync();

  double shaderConstant(String name) {
    final match = RegExp('const float $name = ([0-9.]+);').firstMatch(core);
    expect(match, isNotNull, reason: name);
    return double.parse(match!.group(1)!);
  }

  test('the light falls along +y on a white highlight', () {
    expect(core, contains('float lightFacing = -normalXY.y;'));
    expect(core, contains('return abs(surfaceNormal.x);'));
    expect(RegExp(r'\buLightDirection\b').allMatches(core), hasLength(1));
    expect(RegExp(r'\buHighlightColor\b').allMatches(core), hasLength(1));
    expect(layer, contains('..setOffset(const Offset(0, 1))'));
    expect(
      layer,
      contains('..setColor(const Color.fromARGB(255, 255, 255, 255))'),
    );
  });

  test('the rim values the pass folds are the ones the layer writes', () {
    expect(
      shaderConstant('kBevelShadowDirectionality'),
      GlassRim.bevelShadowDirectionality,
    );
    // The glint lobe is linear (wrap 0.5, an exponent of 1) and as strong
    // on the wall opposite the light.
    expect(GlassRim.highlightWrap, 0.5);
    expect(GlassRim.highlightOppositeStrength, 1);
    for (final literal in [
      '0, // bevel shadow size response',
      '0, // contour transmittance',
      '0, // contour offset',
    ]) {
      expect(layer, contains(literal));
    }
    for (final folded in [
      'uSpecularWrap',
      'uHighlightOppositeStrength',
      'uBevelShadowSizeResponse',
      'uContourTransmittance',
      'uContourOffset',
    ]) {
      expect(core, isNot(contains(folded)), reason: folded);
    }
  });
}
