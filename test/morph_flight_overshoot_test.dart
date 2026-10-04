import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/foundation.dart';
import 'package:morph/src/skin.dart';

void main() {
  testWidgets(
    'shuttle, skin and shared element overshoot before route settle',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const Rect source = Rect.fromLTWH(40, 60, 100, 50);
      const Rect target = Rect.fromLTWH(90, 90, 250, 180);
      late BuildContext sourceContext;
      await tester.pumpWidget(
        MaterialApp(
          builder: (BuildContext context, Widget? child) =>
              MorphScope(child: child!),
          home: Scaffold(
            body: MorphSkin(
              blend: 60,
              color: Colors.blue,
              pieces: <MorphPiece>[
                const MorphPiece(
                  id: 'fellow',
                  rect: Rect.fromLTWH(20, 40, 35, 40),
                ),
                MorphPiece.morphable(
                  id: 'hero',
                  rect: source,
                  radius: 20,
                  child: Builder(
                    builder: (BuildContext context) {
                      sourceContext = context;
                      return const MorphSharedElement(
                        id: 'detail',
                        fade: .none,
                        child: SizedBox.expand(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final NavigatorState navigator = Navigator.of(sourceContext);
      final MorphPageRoute<void> route = MorphPageRoute<void>(
        from: 'hero',
        motion: MorphMotion.liquid,
        target: MorphTargetSpec(
          rectFor: (Size size, EdgeInsets padding) => target,
          shape: const RoundedRectangleBorder(
            borderRadius: .all(.circular(32)),
          ),
          surfaceColor: Colors.blue,
          elevation: 0,
        ),
        builder: (BuildContext context, MorphFlight flight) =>
            const MorphSharedElement(
              id: 'detail',
              fade: .none,
              child: SizedBox.expand(),
            ),
      );
      unawaited(navigator.push(route));
      await tester.pump();
      final MorphFlight flight = route.flight!;
      for (int i = 0; i < 50 && flight.controller.value <= 1; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      expect(flight.controller.value, greaterThan(1));
      expect(flight.routeOwnsContent.value, isFalse);
      final Rect expected = Rect.lerp(source, target, flight.controller.value)!;
      final Finder material = find.byWidgetPredicate(
        (Widget widget) =>
            widget is Material && widget.animationDuration == .zero,
      );
      expect(material, findsOneWidget);
      expect(tester.getRect(material), rectMoreOrLessEquals(expected));
      final RoundedRectangleBorder shape =
          tester.widget<Material>(material).shape! as RoundedRectangleBorder;
      expect(
        shape.borderRadius.resolve(.ltr).topLeft.x,
        closeTo(20 + 12 * flight.controller.value, 1e-9),
      );
      final RenderMorphSkin skin = tester.renderObject(find.byType(MorphSkin));
      expect(skin.lastFlightBlobRects, hasLength(1));
      expect(
        skin.lastFlightBlobRects.single.shift(skin.localToGlobal(Offset.zero)),
        rectMoreOrLessEquals(expected),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey<Object>('detail'))),
        rectMoreOrLessEquals(expected),
      );
      await tester.pumpAndSettle();
      expect(flight.routeOwnsContent.value, isTrue);
      expect(tester.getRect(material), rectMoreOrLessEquals(target));
      navigator.pop();
      await tester.pump();
      for (int i = 0; i < 100 && !flight.controller.hasHandedOff; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      expect(flight.controller.hasHandedOff, isTrue);
      expect(flight.controller.value, lessThan(0));
      expect(flight.isLanding, isTrue);
      expect(skin.lastFlightBlobCount, 0);
      await tester.pumpAndSettle();
      expect(flight.isFinished, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
