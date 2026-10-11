import 'dart:ui' show Brightness;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/renderer.dart';

void expectValue(Object a, Object same, List<Object> different) {
  expect(identical(a, same), isFalse);
  expect(a, same);
  expect(a.hashCode, same.hashCode);
  for (final other in different) {
    expect(a, isNot(other));
  }
}

void main() {
  test('settings compare by every field', () {
    double radius() => 20;
    final a = LiquidGlassSettings(refractionHeight: radius());
    expectValue(a, LiquidGlassSettings(refractionHeight: radius()), [
      a.copyWith(refractionAmount: 61),
      a.copyWith(refractionFitsShape: false),
      a.copyWith(backdropShrink: 0.1),
      a.copyWith(frost: 3),
      a.copyWith(dispersion: 0.2),
      a.copyWith(highlight: 0.5),
      a.copyWith(tintAmount: 0.4),
    ]);
  });

  test('appearances compare by every field', () {
    double one() => 1;
    final a = LiquidGlassAppearance(saturation: one());
    expectValue(a, LiquidGlassAppearance(saturation: one()), [
      a.copyWith(tint: const Color(0x11223344)),
      a.copyWith(saturation: 1.2),
      a.copyWith(transmissionGamma: 1.1),
      a.copyWith(vibrancy: 0.3),
      a.copyWith(visibility: 0.5),
      a.copyWith(colorModel: const LiquidGlassColorModel.ios27Clear()),
    ]);
  });

  test('color models compare by kind and brightness', () {
    expect(
      const LiquidGlassColorModel.direct(),
      const LiquidGlassColorModel.direct(),
    );
    expect(
      const LiquidGlassColorModel.direct(),
      isNot(const LiquidGlassColorModel.ios27Clear()),
    );
    const light = Ios27LiquidGlassColorModel(brightness: Brightness.light);
    const dark = Ios27LiquidGlassColorModel(brightness: Brightness.dark);
    expect(light, isNot(dark));
    expect(
      light.hashCode,
      const Ios27LiquidGlassColorModel(brightness: Brightness.light).hashCode,
    );
  });

  test('shapes compare by kind, side and radius', () {
    double radius() => 12;
    final a = LiquidRoundedSuperellipse(borderRadius: radius());
    expectValue(a, LiquidRoundedSuperellipse(borderRadius: radius()), [
      LiquidRoundedRectangle(borderRadius: radius()),
      const LiquidRoundedSuperellipse(borderRadius: 13),
      LiquidRoundedSuperellipse(
        borderRadius: radius(),
        side: const BorderSide(),
      ),
      const LiquidOval(),
    ]);
    expect(const LiquidOval(), const LiquidOval());
  });
}
