import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/widgets.dart';

final _entries = <MorphMenuEntry>[
  for (var i = 0; i < 12; i++) MorphMenuItem(title: 'Row $i'),
  const MorphSubmenu(
    title: 'More',
    children: [
      MorphMenuItem(title: 'Child'),
      MorphSubmenu(
        title: 'Deeper',
        children: [MorphMenuItem(title: 'Last')],
      ),
    ],
  ),
  for (var i = 12; i < 32; i++) MorphMenuItem(title: 'Row $i'),
];

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 16),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

MorphMenuLayer _layer(WidgetTester tester) =>
    tester.widget<MorphMenuLayer>(find.byType(MorphMenuLayer));

ScrollController _scroll(WidgetTester tester) => tester
    .widget<CustomScrollView>(
      find.descendant(
        of: find.byType(MorphMenuLayer),
        matching: find.byType(CustomScrollView),
      ),
    )
    .controller!;

Future<void> _open(WidgetTester tester, {bool liquid = false}) async {
  isLocalTest = true;
  addTearDown(() => isLocalTest = false);
  final app = MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: const Alignment(0, -0.9),
        child: MorphMenuButton(items: _entries),
      ),
    ),
  );
  await tester.pumpWidget(
    liquid ? MorphGlass(painter: const MorphGlassRenderer(), child: app) : app,
  );
  await tester.tap(find.byType(MorphMenuButton));
  await _settle(tester);
  await tester.dragFrom(
    tester.getCenter(find.text('Row 5').last),
    const Offset(0, -180),
  );
  await _settle(tester);
  expect(_scroll(tester).offset, greaterThan(100));
}

Future<void> _tap(WidgetTester tester, String title) async {
  await tester.tapAt(tester.getCenter(find.text(title).last));
  await _settle(tester);
}

void main() {
  testWidgets('a scrolled parent retains its offset through submenu frames', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    final offset = _scroll(tester).offset;
    await tester.tapAt(tester.getCenter(find.text('More').last));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(microseconds: 8333));
      expect(
        _scroll(tester).offset,
        closeTo(offset, 0.001),
        reason: 'frame $i',
      );
      expect(
        _layer(tester).host.menuMotion!.scrollOffset,
        closeTo(offset, 0.001),
      );
    }
    await _tap(tester, 'Deeper');
    expect(_scroll(tester).offset, closeTo(offset, 0.001));
    await _tap(tester, 'Deeper');
    await tester.tapAt(tester.getCenter(find.text('More').last));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(microseconds: 8333));
      expect(_scroll(tester).offset, closeTo(offset, 0.001), reason: 'back $i');
    }
    expect(_layer(tester).host.menuMotion!.cards.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('parent scrolling is locked until the last submenu returns', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    await _tap(tester, 'More');
    Future<void> locked() async {
      final motion = _layer(tester).host.menuMotion!;
      final count = motion.cards.length;
      final offset = _scroll(tester).offset;
      final point = Offset(motion.menuRect.center.dx, motion.menuRect.top + 90);
      final gesture = await tester.startGesture(point);
      await gesture.moveBy(const Offset(0, -70));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_scroll(tester).offset, closeTo(offset, 0.001));
      await gesture.up();
      await _settle(tester);
      expect(motion.cards.length, count);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: point, scrollDelta: const Offset(0, 100)),
      );
      await _settle(tester);
      expect(_scroll(tester).offset, closeTo(offset, 0.001));
    }

    await locked();
    await _tap(tester, 'Deeper');
    await locked();
    await _tap(tester, 'Deeper');
    await locked();
    await _tap(tester, 'More');
    final offset = _scroll(tester).offset;
    final motion = _layer(tester).host.menuMotion!;
    await tester.dragFrom(
      Offset(motion.menuRect.center.dx, motion.menuRect.top + 90),
      const Offset(0, -70),
    );
    await _settle(tester);
    expect(_scroll(tester).offset, greaterThan(offset + 30));
    expect(tester.takeException(), isNull);
  });

  for (final liquid in [false, true]) {
    final material = liquid ? 'liquid' : 'painted';
    testWidgets('$material parent taps return one submenu at a time', (
      WidgetTester tester,
    ) async {
      await _open(tester, liquid: liquid);
      final offset = _scroll(tester).offset;
      await _tap(tester, 'More');
      await _tap(tester, 'Deeper');
      for (var count = 2; count >= 1; count--) {
        final motion = _layer(tester).host.menuMotion!;
        final point = Offset(
          motion.menuRect.center.dx,
          motion.menuRect.top + 40,
        );
        await tester.tapAt(point);
        await _settle(tester);
        expect(motion.cards.length, count);
        expect(_scroll(tester).offset, closeTo(offset, 0.001));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('$material outside taps dismiss after a blocked parent drag', (
      WidgetTester tester,
    ) async {
      await _open(tester, liquid: liquid);
      await _tap(tester, 'More');
      await _tap(tester, 'Deeper');
      final motion = _layer(tester).host.menuMotion!;
      final offset = _scroll(tester).offset;
      await tester.dragFrom(
        Offset(motion.menuRect.center.dx, motion.menuRect.top + 90),
        const Offset(0, -70),
      );
      await _settle(tester);
      expect(motion.cards.length, 3);
      expect(_scroll(tester).offset, closeTo(offset, 0.001));
      await tester.tapAt(
        Offset(motion.menuRect.right + 10, motion.menuRect.center.dy),
      );
      await _settle(tester);
      expect(find.byType(MorphMenuLayer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('opening a submenu stops an existing parent scroll activity', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    final scroll = _scroll(tester);
    (scroll.position as ScrollPositionWithSingleContext).goBallistic(900);
    final host = _layer(tester).host;
    host.menuMotion!.select(host.menuClock, 12);
    host.menuWake();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(host.menuMotion!.hasSubmenu, isTrue);
    final offset = scroll.offset;
    await tester.pump(const Duration(milliseconds: 100));
    expect(scroll.offset, closeTo(offset, 0.001));
    expect(scroll.position.isScrollingNotifier.value, isFalse);
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}
