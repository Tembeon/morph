import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/glass_tier.dart';
import 'package:morph/widgets.dart';

void main() {
  test(
    'G5 startup and tier changes ignore warm-up jank and failure counts',
    () {
      final governor = MorphGlassTierGovernor(ceiling: MorphGlassTier.liquid);
      const slow = Duration(milliseconds: 20);
      void frame(int milliseconds) => governor.addFrame(
        build: slow,
        raster: slow,
        budget: const Duration(milliseconds: 8),
        now: Duration(milliseconds: milliseconds),
        gesture: false,
      );
      for (var i = 0; i < 1000; i += 8) {
        frame(i);
      }
      expect(governor.tier, MorphGlassTier.liquid);
      for (var i = 1000; i < 1240; i += 8) {
        frame(i);
      }
      expect(governor.tier, MorphGlassTier.frosted);
      expect(governor.stepUpWait, const Duration(seconds: 5));
      for (var i = 1240; i < 2200; i += 8) {
        frame(i);
      }
      expect(governor.tier, MorphGlassTier.frosted);
    },
  );
}
