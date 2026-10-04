import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/page_control.dart';

Widget _scene(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

void main() {
  testWidgets('C8 empty page control has no adjustable value or actions', (
    tester,
  ) async {
    final changes = <int>[];
    await tester.pumpWidget(
      _scene(MorphPageControl(count: 0, page: 0, onChanged: changes.add)),
    );
    final semantics = tester.widgetList<Semantics>(find.byType(Semantics));
    expect(
      semantics.where((s) => s.properties.value == 'page 1 of 0'),
      isEmpty,
    );
    for (final s in semantics) {
      expect(s.properties.onIncrease, isNull);
      expect(s.properties.onDecrease, isNull);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.tap(find.byType(MorphPageControl));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(changes, isEmpty);
  });

  testWidgets('C8 out-of-range page is clamped for semantics and keyboard', (
    tester,
  ) async {
    final changes = <int>[];
    await tester.pumpWidget(
      _scene(MorphPageControl(count: 3, page: 99, onChanged: changes.add)),
    );
    expect(
      tester
          .widgetList<Semantics>(find.byType(Semantics))
          .any((s) => s.properties.value == 'page 3 of 3'),
      isTrue,
    );
    Focus.of(tester.element(find.byType(CustomPaint).last)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(changes, [1]);
    expect(tester.takeException(), isNull);
  });

  test('C8 empty motion accepts every interaction without invalid ranges', () {
    final motion = MorphPageControlMotion(
      count: 0,
      page: 50,
      showsProgress: true,
    );
    motion.pointerDown(0, 0);
    motion.pointerMove(0.1, 100);
    motion.pointerUp(0.2, 100, width: 28);
    motion.setPage(0.3, -4);
    expect(motion.count, 0);
    expect(motion.page, 0);
    expect(motion.contentWidth(0.3), 0);
    expect(motion.width(0, 0.3), 0);
    expect(motion.center(0, 0.3), 0);
  });
}
