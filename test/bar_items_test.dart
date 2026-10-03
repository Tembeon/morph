import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

MorphBarButton _icon(Object id) => MorphBarButton(
  id: id,
  icon: const SizedBox.square(dimension: 24),
  semanticLabel: '$id',
  onPressed: () {},
);

Future<StateSetter> _toolbar(
  WidgetTester tester,
  List<MorphBarButtonGroup> Function() groups,
) async {
  late StateSetter set;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            set = setState;
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MorphToolbar(trailing: groups()),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return set;
}

MorphBarItemLayout _item(Object id, double cx) => MorphBarItemLayout(
  id,
  Rect.fromCenter(center: Offset(cx, 24), width: 24, height: 24),
);

MorphBarCapsuleLayout _capsule(Object id, double cx, List<Object> items) =>
    MorphBarCapsuleLayout(
      id,
      Rect.fromCenter(center: Offset(cx, 24), width: 48, height: 48),
      [for (final i in items) _item(i, cx)],
    );

void main() {
  group('an id that comes back while it still fades out', () {
    test('revives the leaving capsule and item instead of a twin', () {
      final motion = MorphBarMotion();
      final both = [
        _capsule('L', 50, ['a']),
        _capsule('R', 300, ['b']),
      ];
      motion.setLayout(0, both);
      motion.setLayout(1, [
        _capsule('L', 50, ['a']),
      ]);
      motion.advance(1.15);
      motion.setLayout(1.2, both);
      for (var t = 1.2; t < 4; t += 1 / 60) {
        motion.advance(t);
        expect(motion.capsules.where((c) => c.id == 'R'), hasLength(1));
        expect(motion.items.where((i) => i.id == 'b'), hasLength(1));
      }
      expect(motion.isSettled, isTrue);
      final r = motion.capsuleFrame('R')!;
      expect(r.leaving, isFalse);
      expect(r.rect.center.dx, closeTo(300, 0.01));
      expect(r.rect.width, closeTo(48, 0.01));
      final b = motion.itemFrame('b')!;
      expect(b.leaving, isFalse);
      expect(b.presence, closeTo(1, 1e-3));
      expect(b.center.dx, closeTo(300, 0.01));
    });

    testWidgets('builds one button, no duplicate keys', (tester) async {
      var shown = true;
      final set = await _toolbar(
        tester,
        () => [
          MorphBarButtonGroup([_icon('a')], id: 'A'),
          if (shown) MorphBarButtonGroup([_icon('b')], id: 'B'),
        ],
      );
      set(() => shown = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      set(() => shown = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey<Object>('b')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<Object>('b')), findsOneWidget);
    });
  });

  testWidgets('ids are compared as values, not by their text', (tester) async {
    Object id = 1;
    final set = await _toolbar(
      tester,
      () => [
        MorphBarButtonGroup([_icon(id)], id: 'G'),
      ],
    );
    expect(find.byKey(const ValueKey<Object>(1)), findsOneWidget);
    set(() => id = '1');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<Object>('1')), findsOneWidget);
    expect(find.byKey(const ValueKey<Object>(1)), findsNothing);
  });

  testWidgets('a toolbar flip-flop leaves no stale buttons behind', (
    tester,
  ) async {
    var page = 0;
    final set = await _toolbar(
      tester,
      () => [
        MorphBarButtonGroup([_icon('p$page')], id: 'G'),
      ],
    );
    for (var i = 1; i < 6; i++) {
      set(() => page = i);
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey<Object>('p5')), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(ValueKey<Object>('p$i')), findsNothing);
    }
  });
}
