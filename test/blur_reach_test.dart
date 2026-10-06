// The test reads the renderer's internal blur arithmetic.
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/blur_reach.dart';

void main() {
  test('a 2 pt blur at 2.625 rises to the half resolution threshold', () {
    final raised = morphHalfResolutionSigma(2, 2.625);
    expect(raised, closeTo(2.173, 0.002));
    expect(morphImpellerBlurSigma(raised, 2.625), greaterThan(5.657));
    expect(morphImpellerBlurSigma(2, 2.625), lessThan(5.657));
  });

  test('sigmas already at half resolution or too far below keep', () {
    expect(morphHalfResolutionSigma(2, 3), 2);
    expect(morphHalfResolutionSigma(2, 2), 2);
    expect(morphHalfResolutionSigma(1.5, 2.625), 1.5);
    expect(morphHalfResolutionSigma(0, 2.625), 0);
  });

  test('the reach covers the kernel at full and half resolution', () {
    expect(morphBlurReach(2, 2.625) * 2.625, 14);
    expect(morphBlurReach(2, 3) * 3, 17);
  });
}
