import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/menu_host.dart';
import 'package:morph/widgets.dart';

Widget _app(Widget child) => MaterialApp(
  builder: (BuildContext context, Widget? child) => MorphScope(child: child!),
  home: Scaffold(
    body: Align(alignment: const Alignment(0, -0.6), child: child),
  ),
);

Future<void> _frames(WidgetTester tester, int milliseconds) async {
  for (var i = 0; i < milliseconds; i += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

MorphMenuController _host(WidgetTester tester) =>
    tester.widget<MorphMenuLayer>(find.byType(MorphMenuLayer)).host
        as MorphMenuController;

Widget _source({
  required bool bar,
  required List<MorphMenuEntry> entries,
  bool enabled = true,
}) => bar
    ? MorphToolbar(
        trailing: [
          MorphBarButtonGroup([
            MorphBarButton(
              id: 'door',
              label: 'Door',
              semanticLabel: 'Opcije',
              onPressed: enabled ? () {} : null,
              menu: entries,
            ),
          ]),
        ],
      )
    : MorphMenuButton(
        items: entries,
        enabled: enabled,
        semanticLabel: 'Opcije',
      );

Future<void> _open(WidgetTester tester, {required bool bar}) async {
  if (bar) {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Door')),
    );
    await _frames(tester, 900);
    await gesture.cancel();
  } else {
    await tester.tap(find.byType(MorphMenuButton));
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final bar in [false, true]) {
    final name = bar ? 'bar' : 'button';
    testWidgets('$name removal closes and advances the shared motion', (
      tester,
    ) async {
      var visible = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return visible
                  ? _source(
                      bar: bar,
                      entries: const [MorphMenuItem(title: 'Copy')],
                    )
                  : const SizedBox.shrink();
            },
          ),
        ),
      );
      await _open(tester, bar: bar);
      final host = _host(tester);
      final motion = host.menuMotion!;
      final flight = host.flight!;
      final height = motion.menuBlob.rect.height;
      final progress = motion.progress;
      rebuild(() => visible = false);
      await tester.pump();
      expect(motion.isOpen, isFalse);
      await _frames(tester, 112);
      expect(motion.progress, lessThan(progress));
      await _frames(tester, 112);
      expect(motion.menuBlob.rect.height, lessThan(height));
      await tester.pumpAndSettle();
      expect(flight.isFinished, isTrue);
      expect(tester.takeException(), isNull);
      expect(() => host.menuRepaint.addListener(() {}), throwsAssertionError);
    });

    testWidgets('$name disable during a hold cancels its menu opening', (
      tester,
    ) async {
      var enabled = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return _source(
                bar: bar,
                enabled: enabled,
                entries: const [MorphMenuItem(title: 'Copy')],
              );
            },
          ),
        ),
      );
      final door = bar ? find.text('Door') : find.byType(MorphMenuButton);
      final gesture = await tester.startGesture(tester.getCenter(door));
      await _frames(tester, 160);
      rebuild(() => enabled = false);
      await tester.pump();
      await _frames(tester, 1000);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(find.byType(MorphMenuLayer), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name entries and disabled state update the shared host', (
      tester,
    ) async {
      var enabled = true;
      var entries = const <MorphMenuEntry>[MorphMenuItem(title: 'Copy')];
      late StateSetter rebuild;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return _source(bar: bar, enabled: enabled, entries: entries);
            },
          ),
        ),
      );
      await _open(tester, bar: bar);
      final host = _host(tester);
      rebuild(
        () => entries = const [
          MorphMenuItem(title: 'Paste'),
          MorphMenuItem(title: 'Cut'),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      expect(_host(tester), same(host));
      rebuild(() => enabled = false);
      await tester.pumpAndSettle();
      expect(find.byType(MorphMenuLayer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('disabling during a pending tap opening cancels it', (
    tester,
  ) async {
    var enabled = true;
    late StateSetter rebuild;
    var launches = 0;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return MorphMenuButton(
              enabled: enabled,
              items: const [MorphMenuItem(title: 'Copy')],
              onOpen: (_) => launches++,
            );
          },
        ),
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    rebuild(() => enabled = false);
    await tester.pumpAndSettle();
    expect(launches, 0);
    expect(find.byType(MorphMenuLayer), findsNothing);
  });

  testWidgets('caller label and menu roles reach semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(_source(bar: false, entries: const [MorphMenuItem(title: 'Copy')])),
    );
    final door = find.bySemanticsLabel('Opcije');
    expect(
      tester.getSemantics(door).flagsCollection.isExpanded,
      ui.Tristate.isFalse,
    );
    tester.semantics.tap(find.semantics.byLabel('Opcije'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.text('Copy')).role, SemanticsRole.menuItem);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.role == SemanticsRole.menu,
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  test('a close cancels pending opening in the pure motion', () {
    final motion = MorphMenuMotion(
      button: const Rect.fromLTWH(100, 100, 48, 48),
      itemCount: 3,
      bounds: const Size(400, 800),
    );
    motion.pointerDown(0, motion.button.center);
    motion.pointerUp(0.01, motion.button.center);
    expect(motion.isOpenPending, isTrue);
    motion.close(0.02);
    motion.advance(1);
    expect(motion.isOpenPending, isFalse);
    expect(motion.isPresented, isFalse);
  });

  test('a long idle open preserves the close kick', () {
    MorphMenuMotion motion() => MorphMenuMotion(
      button: const Rect.fromLTWH(100, 100, 48, 48),
      itemCount: 3,
      bounds: const Size(400, 800),
    );
    final short = motion();
    final long = motion();
    short.open(0);
    long.open(0);
    short.advance(2);
    long.advance(3600);
    short.close(2);
    long.close(3600);
    for (var i = 1; i <= 120; i++) {
      final dt = i / 120;
      short.advance(2 + dt);
      long.advance(3600 + dt);
      expect(long.menuKick, closeTo(short.menuKick, 0.01));
      expect(long.buttonKick, closeTo(short.buttonKick, 0.01));
      expect(
        long.menuBlob.rect.height,
        closeTo(short.menuBlob.rect.height, 0.01),
      );
    }
  });

  testWidgets('context hold recognition and opening use motion time', (
    tester,
  ) async {
    timeDilation = 4;
    addTearDown(() => timeDilation = 1);
    var held = 0;
    await tester.pumpWidget(
      _app(
        MorphContextMenuRegion(
          onHold: () => held++,
          below: MorphSatellite(
            height: 40,
            builder: (_, _) => const Text('Actions'),
          ),
          child: const SizedBox(width: 160, height: 48, child: Text('Hero')),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Hero')),
    );
    await _frames(tester, 1200);
    await gesture.up();
    await tester.pump();
    expect(held, 0, reason: '300 ms motion time precedes commitment');
    await tester.pumpAndSettle();
    final second = await tester.startGesture(
      tester.getCenter(find.text('Hero')),
    );
    await _frames(tester, 1800);
    expect(held, 0, reason: '450 ms commits without opening');
    await second.up();
    await tester.pump();
    expect(held, 1);
    await tester.pumpAndSettle();
    timeDilation = 1;
  });

  testWidgets('disabling a context region cancels its held press', (
    tester,
  ) async {
    var enabled = true;
    var held = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return MorphContextMenuRegion(
              enabled: enabled,
              onHold: () => held++,
              child: const SizedBox(
                width: 160,
                height: 48,
                child: Text('Hero'),
              ),
            );
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Hero')),
    );
    await _frames(tester, 480);
    rebuild(() => enabled = false);
    await tester.pump();
    await _frames(tester, 1000);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(held, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a context tag change closes the old flight and adopts the new tag',
    (tester) async {
      var tag = 'old';
      late StateSetter rebuild;
      final flights = <MorphFlight>[];
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return MorphContextMenuRegion(
                tagId: tag,
                onOpen: flights.add,
                child: Builder(
                  builder: (context) => GestureDetector(
                    onTap: () => MorphContextMenuRegion.open(context),
                    child: const SizedBox(
                      width: 160,
                      height: 48,
                      child: Text('Hero'),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Hero'));
      await tester.pumpAndSettle();
      rebuild(() => tag = 'new');
      await tester.pumpAndSettle();
      expect(flights.single.isFinished, isTrue);
      await tester.tap(find.text('Hero'));
      await tester.pumpAndSettle();
      expect(flights, hasLength(2));
      expect(flights.last.isFinished, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
