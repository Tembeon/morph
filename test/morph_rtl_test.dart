import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

/// RTL coverage: the engine resolves corner geometry with a fixed .ltr
/// (uniformMorphRadius), which is direction-proof only while the four
/// corners are equal. These tests pin that contract - the uniform
/// directional radius keeps the concentric path, mixed corners fall
/// back - and fly a whole morph under Directionality.rtl.

Future<void> settle(WidgetTester tester, {int frames = 600}) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    if (!tester.binding.hasScheduledFrame) {
      break;
    }
  }
}

void main() {
  group('uniformMorphRadius', () {
    test('circle and stadium sit on the half-side cap', () {
      expect(uniformMorphRadius(const CircleBorder(), const Size(100, 60)), 30);
      expect(
        uniformMorphRadius(const StadiumBorder(), const Size(100, 60)),
        30,
      );
    });

    test('a uniform rounded rect reports its corner, capped', () {
      final RoundedRectangleBorder shape = RoundedRectangleBorder(
        borderRadius: .circular(16),
      );
      expect(uniformMorphRadius(shape, const Size(100, 60)), 16);
      expect(uniformMorphRadius(shape, const Size(20, 20)), 10);
    });

    test('a uniform directional radius is direction-proof', () {
      final RoundedRectangleBorder shape = RoundedRectangleBorder(
        borderRadius: BorderRadiusDirectional.circular(16),
      );
      expect(uniformMorphRadius(shape, const Size(100, 60)), 16);
    });

    test('mixed corners fall back to the exotic-shape path', () {
      const RoundedRectangleBorder mixed = RoundedRectangleBorder(
        borderRadius: BorderRadiusDirectional.only(
          topStart: Radius.circular(16),
        ),
      );
      expect(uniformMorphRadius(mixed, const Size(100, 60)), isNull);
      const RoundedRectangleBorder elliptical = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.elliptical(16, 8)),
      );
      expect(uniformMorphRadius(elliptical, const Size(100, 60)), isNull);
    });
  });

  testWidgets('a flight under RTL derives its radius concentrically', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) => Directionality(
          textDirection: TextDirection.rtl,
          child: MorphScope(child: child!),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MorphTag(
              id: 'rtl',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadiusDirectional.circular(24),
              ),
              child: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => showMorphDialog(
                    context,
                    from: 'rtl',
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadiusDirectional.circular(8),
                    ),
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Text('content'),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull);
    }

    // Mid-flight the concentric path emits a plain uniform BorderRadius
    // between the endpoint radii; the shape-lerp fallback would have
    // kept the directional geometry, so the casts distinguish the two.
    final Material material = tester.widget<Material>(
      find.byWidgetPredicate(
        (Widget w) => w is Material && w.animationDuration == .zero,
      ),
    );
    final RoundedRectangleBorder shape =
        material.shape! as RoundedRectangleBorder;
    final BorderRadius radius = shape.borderRadius as BorderRadius;
    expect(radius.topLeft.x, inInclusiveRange(8, 24));

    final MorphScopeState scope = tester.state<MorphScopeState>(
      find.byType(MorphScope),
    );
    final MorphFlight flight = scope.flightOf('rtl')!;
    await settle(tester);
    flight.close();
    await settle(tester);
    expect(flight.isFinished, isTrue);
  });
}
