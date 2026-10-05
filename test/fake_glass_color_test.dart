import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/fake_glass_color.dart';

void main() {
  List<double> apply(List<double> m, List<double> rgb) => [
    for (var row = 0; row < 3; row++)
      ((m[row * 5] * rgb[0] +
                      m[row * 5 + 1] * rgb[1] +
                      m[row * 5 + 2] * rgb[2]) *
                  255 +
              m[row * 5 + 4]) /
          255,
  ];

  test('the fake face over black is the emission alone', () {
    final m = fakeGlassFaceMatrix(
      emission: const Color.from(
        alpha: 1,
        red: 32 / 255,
        green: 32 / 255,
        blue: 32 / 255,
      ),
      transmittance: 0.6,
      lift: 1,
      chromaGain: 1,
    );
    for (final c in apply(m, [0, 0, 0])) {
      expect(c, closeTo(32 / 255, 1e-9));
    }
  });

  test('the fake face over white reaches white once clamped', () {
    final m = fakeGlassFaceMatrix(
      emission: const Color.from(alpha: 1, red: 0, green: 0, blue: 0),
      transmittance: 1,
      lift: 1,
      chromaGain: 1,
    );
    for (final c in apply(m, [1, 1, 1])) {
      expect(c.clamp(0.0, 1.0), 1);
    }
  });
}
