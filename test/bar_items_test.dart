import 'dart:ui' show SemanticsAction;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/bar_items.dart' show MorphBarItemId;
import 'package:morph/src/widgets/glyph_scale.dart';
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
  testWidgets('buttons that repeat an id are told apart by their order, '
      'and the n-th continues the n-th', (WidgetTester tester) async {
    MorphBarButton star(String label) =>
        MorphBarButton(id: 'star', label: label, onPressed: () {});
    var extra = false;
    final set = await _toolbar(
      tester,
      () => [
        MorphBarButtonGroup([
          if (extra) _icon('extra'),
          star('One'),
          star('Two'),
        ]),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    final second = find.byKey(
      const ValueKey<Object>(MorphBarItemId('star', 1)),
    );
    final before = tester.element(second);
    set(() => extra = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.element(second), same(before));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.element(second), same(before));
    expect(
      find.descendant(of: second, matching: find.text('Two')),
      findsOneWidget,
    );
    expect(find.text('One'), findsOneWidget);
  });

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

  test('a drift keeps its pairing until the layout changes', () {
    final motion = MorphBarMotion();
    final toward = [
      _capsule('A', 100, ['a']),
      _capsule('C', 400, ['c']),
    ];
    motion.setLayout(0, [
      _capsule('A', 50, ['a']),
    ]);
    motion.setDrift(toward, 0.5);
    expect(motion.capsuleFrame('A')!.rect.center.dx, closeTo(75, 1e-9));
    motion.setDrift(toward, 1);
    expect(motion.capsuleFrame('A')!.rect.center.dx, closeTo(100, 1e-9));
    motion.setLayout(1, [
      _capsule('A', 50, ['a']),
      _capsule('C', 300, ['c']),
    ]);
    motion.advance(4);
    expect(motion.isSettled, isTrue);
    motion.setDrift(toward, 0.5);
    expect(motion.capsuleFrame('A')!.rect.center.dx, closeTo(75, 1e-6));
    expect(motion.capsuleFrame('C')!.rect.center.dx, closeTo(350, 1e-6));
  });

  group('a second change inside the content delay', () {
    test('keeps a removed newborn item from growing', () {
      final motion = MorphBarMotion();
      final delay = motion.spec.contentDelay;
      motion.setLayout(0, [
        _capsule('L', 50, ['a']),
      ]);
      motion.setLayout(1, [
        _capsule('L', 50, ['a', 'b']),
      ]);
      motion.setLayout(1.01, [
        _capsule('L', 50, ['a']),
      ]);
      motion.advance(1 + delay + 0.008);
      expect(motion.itemFrame('b')?.presence ?? 0, closeTo(0, 1e-9));
    });

    test('keeps a moved item off its superseded target', () {
      final motion = MorphBarMotion();
      final delay = motion.spec.contentDelay;
      motion.setLayout(0, [
        _capsule('L', 50, ['a']),
      ]);
      motion.setLayout(1, [
        _capsule('L', 100, ['a']),
      ]);
      motion.setLayout(1.01, [
        _capsule('L', 50, ['a']),
      ]);
      motion.advance(1 + delay + 0.008);
      expect(motion.itemFrame('a')!.center.dx, closeTo(50, 1e-6));
    });
  });

  testWidgets('a held bar button swells without a build', (tester) async {
    await _toolbar(
      tester,
      () => [
        MorphBarButtonGroup([_icon('a'), _icon('b')], id: 'A'),
      ],
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<Object>('a'))),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final built = <Type>[];
    debugOnRebuildDirtyWidget = (Element element, bool _) {
      built.add(element.widget.runtimeType);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    final before = tester.getRect(find.byKey(const ValueKey<Object>('a')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugOnRebuildDirtyWidget = null;
    final after = tester.getRect(find.byKey(const ValueKey<Object>('a')));
    expect(after, isNot(before), reason: 'the press moves the item');
    expect(built, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a released bar item returns its content to exact scale', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _toolbar(
        tester,
        () => [
          MorphBarButtonGroup([_icon('a')], id: 'A'),
        ],
      );
      List<RenderMorphGlyphs> snaps() =>
          tester.allRenderObjects.whereType<RenderMorphGlyphs>().toList();
      expect(snaps(), isNotEmpty);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<Object>('a'))),
      );
      var swelled = false;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        swelled =
            swelled || snaps().any((s) => s.debugMode != MorphGlyphMode.live);
      }
      // The press scales the item: some frame left the live drawing.
      expect(swelled, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      for (final snap in snaps()) {
        expect(snap.debugMode, MorphGlyphMode.live);
        expect(snap.debugFactor, 1);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a press on a trailing button does not lean on a tiny move', (
    tester,
  ) async {
    await _toolbar(
      tester,
      () => [
        MorphBarButtonGroup([_icon('a')], id: 'A'),
        MorphBarButtonGroup([_icon('b')], id: 'B'),
      ],
    );
    final item = find.byKey(const ValueKey<Object>('b'));
    final rest = tester.getCenter(item);
    final gesture = await tester.startGesture(rest);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0.1, 0));
    var drift = 0.0;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final d = (tester.getCenter(item) - rest).distance;
      if (d > drift) drift = d;
    }
    expect(drift, lessThan(1));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a second finger neither steals the press nor strands it', (
    tester,
  ) async {
    final pressed = <String>[];
    MorphBarButton counted(String id) => MorphBarButton(
      id: id,
      icon: const SizedBox.square(dimension: 24),
      semanticLabel: id,
      onPressed: () => pressed.add(id),
    );
    await _toolbar(
      tester,
      () => [
        MorphBarButtonGroup([counted('x')], id: 'X'),
        MorphBarButtonGroup([counted('y')], id: 'Y'),
      ],
    );
    final a = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<Object>('x'))),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final b = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<Object>('y'))),
      pointer: 7,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await a.up();
    await tester.pump(const Duration(milliseconds: 16));
    await b.up();
    for (var i = 0; i < 180; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(pressed, ['x']);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a disabled bar button offers screen readers no tap', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var saved = 0;
    await _toolbar(
      tester,
      () => [
        MorphBarButtonGroup([
          MorphBarButton(
            id: 'save',
            label: 'Save',
            enabled: false,
            onPressed: () => saved++,
          ),
        ], id: 'G'),
      ],
    );
    final node = tester.getSemantics(find.bySemanticsLabel('Save'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(saved, 0);
    handle.dispose();
  });

  testWidgets('a parent rebuild with new callbacks keeps the bar as built', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final calls = <int>[];
    var round = 0;
    final set = await _toolbar(
      tester,
      () => [
        MorphBarButtonGroup([
          MorphBarButton(
            id: 'go',
            label: 'Go',
            onPressed: () => calls.add(round),
          ),
        ], id: 'G'),
      ],
    );
    Listener listener() => tester.widget<Listener>(
      find
          .descendant(
            of: find.byKey(const ValueKey<Object>('go')),
            matching: find.byType(Listener),
          )
          .first,
    );
    final before = listener();
    set(() => round = 1);
    await tester.pump();
    expect(identical(listener(), before), isTrue);
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('Go'));
    await tester.pumpAndSettle();
    expect(calls, [1, 1]);
    handle.dispose();
  });

  testWidgets('a keyboard inset moves the toolbar without rebuilding it', (
    tester,
  ) async {
    var inset = 0.0;
    late StateSetter set;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            set = setState;
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: MorphToolbar(
                      trailing: [
                        MorphBarButtonGroup([_icon('a')], id: 'A'),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    Listener listener() => tester.widget<Listener>(
      find
          .descendant(
            of: find.byKey(const ValueKey<Object>('a')),
            matching: find.byType(Listener),
          )
          .first,
    );
    final before = listener();
    final rest = tester.getCenter(find.byKey(const ValueKey<Object>('a')));
    set(() => inset = 300);
    await tester.pump();
    expect(identical(listener(), before), isTrue);
    expect(
      tester.getCenter(find.byKey(const ValueKey<Object>('a'))).dy,
      closeTo(
        rest.dy -
            300 -
            MorphToolbarMetrics.keyboardInset +
            MorphToolbarMetrics.bottomInset,
        0.01,
      ),
    );
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

  testWidgets('an item change does not rebuild the buttons that stay', (
    tester,
  ) async {
    var more = false;
    final set = await _toolbar(
      tester,
      () => [
        MorphBarButtonGroup([
          const MorphBarButton(id: 'edit', label: 'Edit', onPressed: _noop),
          if (more) _icon('b'),
        ], id: 'G'),
      ],
    );
    Widget content() => tester.widget(
      find.ancestor(
        of: find.text('Edit'),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_ButtonContent',
        ),
      ),
    );
    set(() => more = true);
    await tester.pump();
    final first = content();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(identical(content(), first), isTrue);
    }
    await tester.pumpAndSettle();
  });
}

void _noop() {}
