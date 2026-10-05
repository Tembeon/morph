import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/rendering/consolidated_fake_glass_layer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_liquid_native.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/glass_tier.dart';
import 'package:morph/src/widgets/menu_fusion.dart';
import 'package:morph/widgets.dart';

void main() {
  setUpAll(() => isLocalTest = true);

  testWidgets('the frosted tier keeps the surface color as its tint', (
    tester,
  ) async {
    const surface = MorphGlassSurface(
      kind: MorphGlassKind.track,
      shape: RRect.fromLTRBXY(0, 0, 60, 30, 15, 15),
      color: Color(0xFF34C759),
      brightness: Brightness.light,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 60,
            height: 30,
            child: Builder(
              builder: (BuildContext context) => const MorphGlassRenderer(
                tier: MorphGlassTier.frosted,
              ).buildSurface(context, surface),
            ),
          ),
        ),
      ),
    );
    final painted = [
      for (final box in tester.widgetList<DecoratedBox>(
        find.bySubtype<DecoratedBox>(),
      ))
        if (box.decoration case final BoxDecoration d
            when d.color == surface.color && d.gradient == null)
          d,
    ];
    expect(painted, isNotEmpty);
  });

  test('the liquid tier bends a lens by its lift like UIKit', () {
    const painter = MorphGlassRenderer(refraction: 2, blur: 0.5);
    MorphGlassSurface lens(MorphGlassOptics optics, double lift) =>
        MorphGlassSurface(
          kind: MorphGlassKind.lens,
          shape: const RRect.fromLTRBXY(0, 0, 80, 28, 14, 14),
          color: const Color(0xFFFFFFFF),
          brightness: Brightness.light,
          lift: lift,
          optics: optics,
        );
    final resting = morphLiquidSettings(
      painter,
      lens(MorphGlassOptics.large, 0),
    );
    final lifted = morphLiquidSettings(
      painter,
      lens(MorphGlassOptics.large, 1),
    );
    expect(resting.refractionAmount, 0);
    expect(lifted.refractionAmount, 36);
    expect(lifted.dispersion, MorphGlassRenderer.lensDispersion);
    expect(lifted.highlight, greaterThan(resting.highlight));
    final frosted = morphLiquidSettings(
      painter,
      lens(MorphGlassOptics.small, 0),
    );
    final clear = morphLiquidSettings(painter, lens(MorphGlassOptics.small, 1));
    expect(frosted.frost, 3);
    expect(clear.frost, 0);
  });

  testWidgets('a lifted segmented lens shows its label at its own size', (
    tester,
  ) async {
    const surfaces = [
      MorphGlassSurface(
        kind: MorphGlassKind.track,
        shape: RRect.fromLTRBXY(0, 0, 300, 36, 18, 18),
        color: Color(0x14787880),
        brightness: Brightness.light,
        glass: false,
      ),
      MorphGlassSurface(
        kind: MorphGlassKind.lens,
        shape: RRect.fromLTRBXY(10, 2, 110, 34, 16, 16),
        color: Color(0x00FFFFFF),
        brightness: Brightness.light,
        lift: 1,
        optics: MorphGlassOptics.large,
      ),
    ];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 36,
            child: Builder(
              builder: (BuildContext context) => const MorphGlassRenderer()
                  .buildLayer(context, surfaces, content: const Text('Label')),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(LiquidGlassLayer), findsOneWidget);
    expect(find.text('Label'), findsOneWidget);
    expect(_lensShrink(tester, 0), MorphGlassRenderer.segmentedShrink);
    expect(_lensShrinkRim(tester, 0), MorphGlassRenderer.lensShrinkRim);
    final base = tester.getRect(find.text('Label').first);
    final seen = _seenThroughLens(tester, 0, null, 'Label');
    expect(seen.center.dx, moreOrLessEquals(base.center.dx, epsilon: 0.01));
    expect(seen.center.dy, moreOrLessEquals(base.center.dy, epsilon: 0.01));
    expect(seen.width, moreOrLessEquals(base.width, epsilon: 0.01));
    expect(
      find.descendant(
        of: find.byType(MorphGlassContentCopy),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the liquid tier draws a plain surface flat', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 36,
            child: Builder(
              builder: (BuildContext context) =>
                  const MorphGlassRenderer().buildLayer(context, const [
                    MorphGlassSurface(
                      kind: MorphGlassKind.track,
                      shape: RRect.fromLTRBXY(0, 0, 300, 36, 18, 18),
                      color: Color(0x14787880),
                      brightness: Brightness.light,
                      glass: false,
                    ),
                    MorphGlassSurface(
                      kind: MorphGlassKind.lens,
                      shape: RRect.fromLTRBXY(2, 2, 100, 34, 16, 16),
                      color: Color(0xFFFFFFFF),
                      brightness: Brightness.light,
                      optics: MorphGlassOptics.large,
                    ),
                  ]),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(LiquidGlassLayer), findsNothing);
  });

  testWidgets('a label seen through a dragged lens stays on its slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 360,
            child: MorphGlass(
              painter: const MorphGlassRenderer(),
              child: MorphSegmentedControl(
                segments: const ['Day', 'Night'],
                selected: 1,
                onChanged: (int _) {},
              ),
            ),
          ),
        ),
      ),
    );
    final base = tester.getRect(find.text('Night').first);
    final gesture = await tester.startGesture(base.center);
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final lens = find.descendant(
      of: find.byKey(const ValueKey<(String, int)>(('glass', 0))),
      matching: find.byType(LiquidGlass),
    );
    expect(_lensShrink(tester, 0), greaterThan(0.1));
    final start = tester.getRect(lens).center;
    final seen = <Rect>[];
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(-2, 0));
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(_seenThroughLens(tester, 0, 1, 'Night'));
    }
    expect((tester.getRect(lens).center - start).dx, lessThan(-10));
    for (final label in seen) {
      expect(label.center.dx, moreOrLessEquals(base.center.dx, epsilon: 0.01));
      expect(label.center.dy, moreOrLessEquals(base.center.dy, epsilon: 0.01));
      expect(
        label.width,
        moreOrLessEquals(
          base.width * (1 + MorphGlassRenderer.segmentedMagnification),
          epsilon: 0.01,
        ),
      );
    }
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a lifted lens on a bar refracts the bar glass beneath it', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 62,
            child: Builder(
              builder: (BuildContext context) =>
                  const MorphGlassRenderer().buildLayer(context, const [
                    MorphGlassSurface(
                      kind: MorphGlassKind.bar,
                      shape: RRect.fromLTRBXY(0, 0, 300, 62, 31, 31),
                      color: Color(0xB81C1C1E),
                      brightness: Brightness.dark,
                    ),
                    MorphGlassSurface(
                      kind: MorphGlassKind.lens,
                      shape: RRect.fromLTRBXY(10, -6, 120, 68, 37, 37),
                      color: Color(0x1FFFFFFF),
                      brightness: Brightness.dark,
                      lift: 1,
                      optics: MorphGlassOptics.large,
                    ),
                  ], content: const Text('Home')),
            ),
          ),
        ),
      ),
    );
    final layers = tester
        .widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
        .toList();
    expect(layers, hasLength(2));
    expect(layers.map((LiquidGlassLayer l) => l.useBackdropGroup), [
      false,
      false,
    ]);
    final stack = tester.widget<Stack>(
      find
          .ancestor(
            of: find.byKey(const ValueKey<(String, int)>(('glass', 0))),
            matching: find.bySubtype<Stack>(),
          )
          .first,
    );
    final keys = [for (final child in stack.children) child.key];
    expect(
      keys.indexOf(const ValueKey<(String, int)>(('copy', 0))),
      lessThan(keys.indexOf(const ValueKey<(String, int)>(('glass', 0)))),
    );
    expect(
      keys.indexOf(const ValueKey<String>('body')),
      lessThan(keys.indexOf(const ValueKey<(String, int)>(('glass', 0)))),
    );
  });

  testWidgets('a lifted lens on a bar minifies the bar, not the label', (
    tester,
  ) async {
    const lens = RRect.fromLTRBXY(10, -6, 120, 68, 37, 37);
    const slot = Rect.fromLTWH(0, 0, 100, 62);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 62,
            child: Builder(
              builder: (BuildContext context) =>
                  const MorphGlassRenderer().buildLayer(
                    context,
                    const [
                      MorphGlassSurface(
                        kind: MorphGlassKind.bar,
                        shape: RRect.fromLTRBXY(0, 0, 300, 62, 31, 31),
                        color: Color(0xB81C1C1E),
                        brightness: Brightness.dark,
                      ),
                      MorphGlassSurface(
                        kind: MorphGlassKind.lens,
                        shape: lens,
                        color: Color(0x1FFFFFFF),
                        brightness: Brightness.dark,
                        lift: 1,
                        optics: MorphGlassOptics.large,
                      ),
                    ],
                    content: const Row(
                      children: [
                        SizedBox(width: 100, child: Center(child: Text('A'))),
                      ],
                    ),
                    contentSlots: const [slot],
                  ),
            ),
          ),
        ),
      ),
    );
    final layers = tester
        .widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
        .toList();
    expect(layers.first.settings.backdropShrink, 0);
    expect(_lensShrink(tester, 0), MorphGlassRenderer.tabBarShrink);
    final base = tester.getRect(find.text('A').first);
    final seen = _seenThroughLens(tester, 0, 0, 'A');
    expect(seen.center.dx, moreOrLessEquals(base.center.dx, epsilon: 0.01));
    expect(seen.center.dy, moreOrLessEquals(base.center.dy, epsilon: 0.01));
    expect(
      seen.width,
      moreOrLessEquals(
        base.width * (1 + MorphGlassRenderer.tabBarMagnification),
        epsilon: 0.01,
      ),
    );
  });

  Widget host(Widget Function(BuildContext context) build) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 300, height: 120, child: Builder(builder: build)),
    ),
  );

  MorphGlassSurface capsule(double left, double width) => MorphGlassSurface(
    kind: MorphGlassKind.bar,
    shape: RRect.fromLTRBXY(left, 10, left + width, 54, 22, 22),
    color: const Color(0xB81C1C1E),
    brightness: Brightness.dark,
  );

  group('tiers shade the same shapes', () {
    for (final tier in MorphGlassTier.values) {
      testWidgets('${tier.name} draws the fused capsules as one body', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            (context) => MorphGlassRenderer(tier: tier).buildLayer(context, [
              capsule(0, 100),
              capsule(106, 60),
            ], spacing: 12),
          ),
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget.runtimeType.toString() == 'LiquidGlassBlendGroup',
          ),
          findsNothing,
        );
        final layers = tester.widgetList<LiquidGlassLayer>(
          find.byType(LiquidGlassLayer),
        );
        final blurs = find.bySubtype<BackdropFilter>().evaluate().length;
        switch (tier) {
          case MorphGlassTier.flat:
            expect(layers, isEmpty);
            expect(blurs, 0);
          case MorphGlassTier.frosted:
            expect(layers, isEmpty);
            expect(blurs, 1);
          case MorphGlassTier.fake || MorphGlassTier.liquid:
            expect(layers, hasLength(1));
            expect(layers.single.field, isNotNull);
        }
      });
    }

    testWidgets('capsules the spacing apart stay their own shapes', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          (context) => const MorphGlassRenderer().buildLayer(context, [
            capsule(0, 100),
            capsule(112, 60),
          ], spacing: 12),
        ),
      );
      final layer = tester.widget<LiquidGlassLayer>(
        find.byType(LiquidGlassLayer),
      );
      expect(layer.field, isNull);
      expect(find.byType(LiquidGlass), findsNWidgets(2));
    });

    testWidgets('a menu outline is shaded from its distance field', (
      tester,
    ) async {
      const menu = RRect.fromLTRBXY(20, 0, 220, 80, 32, 32);
      const button = RRect.fromLTRBXY(100, 90, 144, 134, 22, 22);
      final outline = morphMenuSilhouette(menu, button, 12);
      expect(morphGlassOutlineField(outline), isNotNull);
      await tester.pumpWidget(
        host(
          (context) => const MorphGlassRenderer().buildLayer(context, [
            const MorphGlassSurface(
              kind: MorphGlassKind.button,
              shape: button,
              color: Color(0xF2222222),
              brightness: Brightness.dark,
            ),
            const MorphGlassSurface(
              kind: MorphGlassKind.menu,
              shape: menu,
              color: Color(0xF2222222),
              brightness: Brightness.dark,
            ),
          ], outline: outline),
        ),
      );
      final layer = tester.widget<LiquidGlassLayer>(
        find.byType(LiquidGlassLayer),
      );
      expect(layer.field, same(morphGlassOutlineField(outline)));
      expect(find.byType(ClipPath), findsNothing);
      final fake = tester.renderObject<RenderConsolidatedFakeGlassLayer>(
        find.byType(ConsolidatedFakeGlassLayer),
      );
      expect(fake.outline, same(outline.path));
      expect(fake.debugClipPath, same(outline.path));
    });
  });

  group('a fused outline carries its own distance field', () {
    test(
      'the field is negative inside the path, its gradient unit near the edge',
      () {
        const menu = RRect.fromLTRBXY(0, 0, 200, 120, 30, 30);
        const button = RRect.fromLTRBXY(80, 128, 124, 172, 22, 22);
        final outline = morphMenuSilhouette(menu, button, 10);
        final field = morphGlassOutlineField(outline)!;
        var checked = 0;
        var near = 0;
        var unit = 0;
        for (var j = 2; j < field.rows - 2; j += 2) {
          for (var i = 2; i < field.cols - 2; i += 2) {
            final at = (j * field.cols + i) * 4;
            final d = field.samples[at];
            if (d.abs() < 2) continue;
            final p = field.origin + Offset(i * field.step, j * field.step);
            expect(outline.path.contains(p), d < 0, reason: '$p');
            if (d.abs() < 8 && p.dy < 100) {
              final length = Offset(
                field.samples[at + 1],
                field.samples[at + 2],
              ).distance;
              near++;
              if ((length - 1).abs() < 0.2) unit++;
            }
            checked++;
          }
        }
        expect(checked, greaterThan(50));
        expect(unit / near, greaterThan(0.85));
      },
    );

    test('fused corners turn their light where the shapes alone do', () {
      const menu = RRect.fromLTRBXY(0, 0, 200, 120, 30, 30);
      const button = RRect.fromLTRBXY(80, 128, 124, 172, 22, 22);
      Offset optical(Offset p) {
        const r = 30 * morphOpticalCornerScale;
        final qx = (p.dx - 100).abs() - 100 + r;
        final qy = (p.dy - 60).abs() - 60 + r;
        final sx = p.dx < 100 ? -1.0 : 1.0;
        final sy = p.dy < 60 ? -1.0 : 1.0;
        if (qx > 0 && qy > 0) {
          final n = Offset(qx, qy) / Offset(qx, qy).distance;
          return Offset(sx * n.dx, sy * n.dy);
        }
        return qx > qy ? Offset(sx, 0) : Offset(0, sy);
      }

      for (final outline in [
        morphMenuSilhouette(menu, button, 1.5),
        morphGlassContainerOutline([menu, button], 12),
      ]) {
        final field = morphGlassOutlineField(outline)!;
        var corner = 0;
        for (var j = 0; j < field.rows; j++) {
          for (var i = 0; i < field.cols; i++) {
            final at = (j * field.cols + i) * 4;
            final p = field.origin + Offset(i * field.step, j * field.step);
            if (field.samples[at].abs() > 3 || p.dy > 100) continue;
            final g = Offset(field.samples[at + 1], field.samples[at + 2]);
            final want = optical(p);
            final angle =
                (math.atan2(g.dy, g.dx) - math.atan2(want.dy, want.dx)).abs();
            expect(
              math.min(angle, 2 * math.pi - angle),
              lessThan(0.06),
              reason: '$p',
            );
            if (want.dx != 0 && want.dy != 0) corner++;
          }
        }
        expect(corner, greaterThan(8));
      }
    });

    test('a container fuses only what lies within its spacing', () {
      final shapes = [
        const RRect.fromLTRBXY(0, 0, 100, 44, 22, 22),
        const RRect.fromLTRBXY(105, 0, 150, 44, 22, 22),
        const RRect.fromLTRBXY(170, 0, 214, 44, 22, 22),
      ];
      expect(morphGlassContainerGroups(shapes, 12), [
        [0, 1],
        [2],
      ]);
      final outline = morphGlassContainerOutline(shapes.sublist(0, 2), 12);
      expect(outline.path.contains(const Offset(102.5, 22)), isTrue);
      expect(
        identical(
          morphGlassContainerOutline(shapes.sublist(0, 2), 12),
          outline,
        ),
        isTrue,
      );
    });
  });

  group('the adaptive tier', () {
    const budget = Duration(microseconds: 8333);
    const slow = Duration(milliseconds: 12);
    const fast = Duration(milliseconds: 2);
    Duration at(int frame) => Duration(microseconds: frame * 8333);

    test('steps down when a quarter of a window misses the budget', () {
      final governor = MorphGlassTierGovernor(
        ceiling: MorphGlassTier.liquid,
        policy: const MorphGlassTierPolicy(warmUp: Duration.zero),
      );
      var changed = false;
      for (var i = 0; i < 30; i++) {
        changed = governor.addFrame(
          build: fast,
          raster: i < 8 ? slow : fast,
          budget: budget,
          now: at(i),
          gesture: true,
        );
      }
      expect(changed, isTrue);
      expect(governor.tier, MorphGlassTier.flat);
    });

    test('skips frosted unless the policy lists it', () {
      MorphGlassTier stepDown(MorphGlassTierPolicy policy) {
        final governor = MorphGlassTierGovernor(
          ceiling: MorphGlassTier.liquid,
          policy: policy,
        );
        for (var i = 0; i < 30; i++) {
          governor.addFrame(
            build: fast,
            raster: slow,
            budget: budget,
            now: at(i),
            gesture: false,
          );
        }
        return governor.tier;
      }

      expect(
        stepDown(const MorphGlassTierPolicy(warmUp: Duration.zero)),
        MorphGlassTier.flat,
      );
      expect(
        stepDown(
          const MorphGlassTierPolicy(
            warmUp: Duration.zero,
            tiers: {MorphGlassTier.flat, MorphGlassTier.frosted},
          ),
        ),
        MorphGlassTier.frosted,
      );
      expect(
        stepDown(
          const MorphGlassTierPolicy(
            warmUp: Duration.zero,
            tiers: {MorphGlassTier.liquid},
          ),
        ),
        MorphGlassTier.liquid,
      );
    });

    test('holds when fewer frames miss', () {
      final governor = MorphGlassTierGovernor(
        ceiling: MorphGlassTier.liquid,
        policy: const MorphGlassTierPolicy(warmUp: Duration.zero),
      );
      for (var i = 0; i < 300; i++) {
        governor.addFrame(
          build: fast,
          raster: i % 30 < 7 ? slow : fast,
          budget: budget,
          now: at(i),
          gesture: false,
        );
      }
      expect(governor.tier, MorphGlassTier.liquid);
    });

    test('steps back up only after the wait and never under a finger', () {
      final governor = MorphGlassTierGovernor(
        ceiling: MorphGlassTier.liquid,
        policy: const MorphGlassTierPolicy(warmUp: Duration.zero),
      );
      var frame = 0;
      void feed(int frames, Duration raster, {bool gesture = false}) {
        for (var i = 0; i < frames; i++) {
          governor.addFrame(
            build: fast,
            raster: raster,
            budget: budget,
            now: at(frame++),
            gesture: gesture,
          );
        }
      }

      feed(30, slow);
      expect(governor.tier, MorphGlassTier.flat);
      feed(300, fast);
      expect(governor.tier, MorphGlassTier.flat);
      feed(600, fast, gesture: true);
      expect(governor.tier, MorphGlassTier.flat);
      feed(30, fast);
      expect(governor.tier, MorphGlassTier.liquid);
      feed(30, slow);
      expect(governor.tier, MorphGlassTier.flat);
      expect(governor.stepUpWait, const Duration(seconds: 10));
    });

    test('never goes above its ceiling or below flat', () {
      final governor = MorphGlassTierGovernor(
        ceiling: MorphGlassTier.frosted,
        policy: const MorphGlassTierPolicy(warmUp: Duration.zero),
      );
      for (var i = 0; i < 300; i++) {
        governor.addFrame(
          build: slow,
          raster: slow,
          budget: budget,
          now: at(i),
          gesture: false,
        );
      }
      expect(governor.tier, MorphGlassTier.flat);
      for (var i = 300; i < 6000; i++) {
        governor.addFrame(
          build: fast,
          raster: fast,
          budget: budget,
          now: at(i),
          gesture: false,
        );
      }
      expect(governor.tier, MorphGlassTier.frosted);
    });

    testWidgets('an explicit tier wins and the renderer reports it', (
      tester,
    ) async {
      late BuildContext inside;
      await tester.pumpWidget(
        MorphAdaptiveGlass(
          tier: MorphGlassTier.frosted,
          child: Builder(
            builder: (BuildContext context) {
              inside = context;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(MorphAdaptiveGlass.tierOf(inside), MorphGlassTier.frosted);
    });
  });
}

LiquidGlassSettings _lensSettings(WidgetTester tester, int lens) => tester
    .widget<LiquidGlassLayer>(
      find.descendant(
        of: find.byKey(ValueKey<(String, int)>(('glass', lens))),
        matching: find.byType(LiquidGlassLayer),
      ),
    )
    .settings;

/// The backdrop shrink the glass of floating surface [lens] renders with.
double _lensShrink(WidgetTester tester, int lens) =>
    _lensSettings(tester, lens).backdropShrink;

/// The rim weight of that shrink.
double _lensShrinkRim(WidgetTester tester, int lens) =>
    _lensSettings(tester, lens).backdropShrinkRim;

/// Where [text] in content slot [slot], or in the one slot when null,
/// shows through the glass of floating surface [lens]: its copy under the
/// glass, minified the way the renderer reads the backdrop - a point on
/// the face shows the backdrop `1 + (1 / (1 - shrink) - 1) * visibility`
/// times farther from the nearest point of the glass's center line, which
/// runs along its longer side over `rim` times the long side less the
/// short side.
///
/// The copy is cut into strips at the line's ends; the text is read in
/// the strip that holds its center.
Rect _seenThroughLens(WidgetTester tester, int lens, int? slot, String text) {
  final glass = find.descendant(
    of: find.byKey(ValueKey<(String, int)>(('glass', lens))),
    matching: find.byType(LiquidGlass),
  );
  final visibility =
      tester.widget<LiquidGlass>(glass).appearance?.visibility ?? 1;
  final scale = 1 + (1 / (1 - _lensShrink(tester, lens)) - 1) * visibility;
  final bounds = tester.getRect(glass);
  final center = bounds.center;
  final rim = _lensShrinkRim(tester, lens);
  final half = rim * (bounds.longestSide - bounds.shortestSide) / 2;
  final axis = bounds.width >= bounds.height
      ? Offset(half, 0)
      : Offset(0, half);
  final copy = find.byKey(ValueKey<(String, int)>(('copy', lens)));
  final copyWidget = tester.widget<MorphGlassContentCopy>(
    find.descendant(of: copy, matching: find.byType(MorphGlassContentCopy)),
  );
  final original = tester.getRect(find.text(text));
  final origin = tester.getTopLeft(
    find.byKey(const ValueKey<String>('content')),
  );
  final local = original.shift(-origin);
  final itemSlot = slot == null
      ? Offset.zero & tester.getSize(copy)
      : copyWidget.slots[slot];
  Rect? rect;
  var along = 0.0;
  if (half == 0) {
    rect = copyWidget.transformedRect(local, itemSlot, 0).shift(origin);
  } else {
    final length = axis.distanceSquared;
    for (var i = 0; i < 3; i++) {
      final candidate = copyWidget
          .transformedRect(local, itemSlot, i)
          .shift(origin);
      final t =
          ((candidate.center - center).dx * axis.dx +
              (candidate.center - center).dy * axis.dy) /
          length;
      if (i == 0 && t < -1 || i == 1 && t.abs() <= 1 || i == 2 && t > 1) {
        rect = candidate;
        along = t;
      }
    }
  }
  final seen = rect!;
  final anchor = center + axis * along.clamp(-1.0, 1.0);
  final inBand = half > 0 && along.abs() <= 1;
  return Rect.fromCenter(
    center: anchor + (seen.center - anchor) / scale,
    width: inBand && axis.dy == 0 ? seen.width : seen.width / scale,
    height: inBand && axis.dx == 0 ? seen.height : seen.height / scale,
  );
}
