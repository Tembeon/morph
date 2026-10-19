import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/glass_painter.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/glass_tier.dart';

import 'support/liquid_capability.dart';

/// Glass asked for liquid draws flat until the liquid tier is ready and
/// turns liquid when it is, however the renderer was installed.
void main() {
  setUpAll(() => isLocalTest = true);
  tearDownAll(() => isLocalTest = false);

  Widget tiers(List<MorphGlassTier?> seen) => Builder(
    builder: (BuildContext context) {
      seen.add(GlassAdaptiveScope.tierOf(context));
      return const SizedBox();
    },
  );

  Widget button() => const Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: MorphGlassEffect(child: SizedBox(width: 120, height: 44)),
    ),
  );

  testWidgets('an adaptive scope given liquid installs flat until ready', (
    tester,
  ) async {
    final capability = pendingLiquidGlass();
    final seen = <MorphGlassTier?>[];
    await tester.pumpWidget(
      GlassAdaptiveScope(tier: MorphGlassTier.liquid, child: tiers(seen)),
    );
    final painter = MorphGlassScope.maybeOf(
      tester.element(find.byType(SizedBox)),
    );
    expect((painter! as GlassBuiltInPainter).tier, MorphGlassTier.flat);
    expect(seen, [MorphGlassTier.flat]);
    capability.value = true;
    await tester.pump();
    expect(seen, [MorphGlassTier.flat, MorphGlassTier.liquid]);
    final ready = MorphGlassScope.maybeOf(
      tester.element(find.byType(SizedBox)),
    );
    expect((ready! as GlassBuiltInPainter).tier, MorphGlassTier.liquid);
  });

  testWidgets('a glass effect under an adaptive scope turns liquid', (
    tester,
  ) async {
    final capability = pendingLiquidGlass();
    await tester.pumpWidget(
      GlassAdaptiveScope(tier: MorphGlassTier.liquid, child: button()),
    );
    expect(find.byType(LiquidGlassLayer), findsNothing);
    capability.value = true;
    await tester.pump();
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
  });

  testWidgets('a liquid renderer installed directly tells its dependents', (
    tester,
  ) async {
    final capability = pendingLiquidGlass();
    final seen = <MorphGlassTier?>[];
    await tester.pumpWidget(
      MorphGlassScope(painter: const GlassBuiltInPainter(), child: tiers(seen)),
    );
    expect(seen, [MorphGlassTier.flat]);
    capability.value = true;
    await tester.pump();
    expect(seen, [MorphGlassTier.flat, MorphGlassTier.liquid]);
  });

  testWidgets('a glass effect under a direct liquid renderer turns liquid', (
    tester,
  ) async {
    final capability = pendingLiquidGlass();
    await tester.pumpWidget(
      MorphGlassScope(painter: const GlassBuiltInPainter(), child: button()),
    );
    expect(find.byType(LiquidGlassLayer), findsNothing);
    capability.value = true;
    await tester.pump();
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
  });

  testWidgets('a flat renderer installed directly does not follow', (
    tester,
  ) async {
    final capability = pendingLiquidGlass();
    final seen = <MorphGlassTier?>[];
    await tester.pumpWidget(
      MorphGlassScope(
        painter: const GlassBuiltInPainter(tier: MorphGlassTier.flat),
        child: tiers(seen),
      ),
    );
    capability.value = true;
    await tester.pump();
    expect(seen, [MorphGlassTier.flat]);
  });
}
