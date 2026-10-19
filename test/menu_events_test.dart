import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/menu_host.dart';
import 'package:morph/src/widgets/menu_motion.dart';

Future<void> _frames(WidgetTester tester, int milliseconds) async {
  for (var i = 0; i < milliseconds; i += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

MorphMenuController _host(WidgetTester tester) =>
    tester.widget<MorphMenuLayer>(find.byType(MorphMenuLayer)).host
        as MorphMenuController;

/// A page holding [child] where a menu opens, under [canPop] and with
/// [refused] counting the pops it refuses.
Widget _page(
  Widget child, {
  required void Function(BuildContext context) page,
  bool canPop = true,
  VoidCallback? refused,
}) => MaterialApp(
  builder: (BuildContext context, Widget? child) => MorphScope(child: child!),
  home: Builder(
    builder: (BuildContext context) {
      page(context);
      return PopScope<Object?>(
        canPop: canPop,
        onPopInvokedWithResult: (bool didPop, Object? _) {
          if (!didPop) refused?.call();
        },
        child: Scaffold(
          body: Align(alignment: const Alignment(0, -0.6), child: child),
        ),
      );
    },
  ),
);

void main() {
  test('each command and each step raises its events once, in order', () {
    final motion = MorphMenuMotion(
      button: const Rect.fromLTWH(179, 300, 44, 44),
      itemCount: 4,
      bounds: const Size(402, 874),
    );
    final tuning = motion.tuning;
    motion.open(0);
    motion.advance(1);
    motion.drainEvents();
    final menu = motion.menuRect;
    final rows = [
      for (var i = 0; i < 4; i++)
        Offset(menu.center.dx, menu.top + menu.height * (i + 0.5) / 4),
    ];
    final targets = motion.layout.targets;
    expect(motion.rowAt(rows[0]), 0);

    motion.pointerDown(1.01, rows[0]);
    final down = motion.drainEvents().single as MorphMenuHighlightChanged;
    expect(down.time, 1.01);
    expect(down.from, isNull);
    expect(down.to, same(targets[0]));
    expect(down.tracked, isTrue);
    expect(motion.drainEvents(), isEmpty);

    motion.pointerMove(1.05, rows[1]);
    final move = motion.drainEvents().single as MorphMenuHighlightChanged;
    expect(move.from, same(targets[0]));
    expect(move.to, same(targets[1]));
    expect(move.tracked, isTrue);

    motion.pointerUp(1.1, rows[1]);
    expect(motion.drainEvents(), isEmpty);
    expect(motion.advanceToRequest(1.1 + tuning.actionDelay - 1e-6), isTrue);
    expect(motion.drainEvents(), isEmpty);
    expect(motion.advanceToRequest(2), isFalse);
    final step = motion.drainEvents();
    expect(step, hasLength(2));
    final action = step.first as MorphMenuActivated;
    expect(action.time, closeTo(1.1 + tuning.actionDelay, 1e-12));
    expect((action.card, action.index), (0, 1));
    expect(action.target, same(targets[1]));
    final request = step.last as MorphMenuCloseRequested;
    expect(request.time, closeTo(1.1 + tuning.dismissDelay, 1e-12));
    expect(motion.admitClose(request), isTrue);
    expect(motion.advanceToRequest(3), isTrue);
    expect(motion.drainEvents(), isEmpty);
    expect(motion.isPresented, isFalse);

    motion.open(3);
    motion.advance(4);
    motion.highlight(4, 2);
    final key = motion.drainEvents().single as MorphMenuHighlightChanged;
    expect((key.from, key.to, key.tracked), (null, targets[2], false));
  });

  for (final early in [false, true]) {
    final how = early ? 'released before the menu appears' : 'tapped';
    testWidgets('a row $how runs its action once, before the menu starts '
        'closing', (tester) async {
      final seen = <({bool open, bool flying})>[];
      late MorphMenuController host;
      await tester.pumpWidget(
        _page(
          MorphMenuButton(
            menu: [
              const MorphMenuItem(title: 'One'),
              MorphMenuItem(
                title: 'Two',
                onSelected: () => seen.add((
                  open: host.menuMotion!.isOpen,
                  flying: host.flight!.isOpenOrOpening,
                )),
              ),
            ],
          ),
          page: (_) {},
        ),
      );
      await tester.tap(find.byType(MorphMenuButton));
      await tester.pumpAndSettle();
      host = _host(tester);
      final row = tester.getCenter(find.text('Two'));
      if (early) {
        await tester.tapAt(const Offset(8, 590));
        await tester.pumpAndSettle();
        expect(find.text('Two'), findsNothing);
        await tester.tap(find.byType(MorphMenuButton));
      }
      await tester.tapAt(row);
      expect(seen, isEmpty);
      await tester.pumpAndSettle();
      expect(seen, [(open: true, flying: true)]);
      expect(find.text('Two'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an action that pops when $how closes the menu once and '
        'leaves the page', (tester) async {
      late BuildContext page;
      var chosen = 0;
      await tester.pumpWidget(
        _page(
          MorphMenuButton(
            menu: [
              const MorphMenuItem(title: 'One'),
              MorphMenuItem(
                title: 'Two',
                onSelected: () {
                  chosen++;
                  Navigator.of(page).pop();
                },
              ),
            ],
          ),
          page: (context) => page = context,
        ),
      );
      await tester.tap(find.byType(MorphMenuButton));
      await tester.pumpAndSettle();
      final row = tester.getCenter(find.text('Two'));
      if (early) {
        await tester.tapAt(const Offset(8, 590));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(MorphMenuButton));
      }
      await tester.tapAt(row);
      await tester.pumpAndSettle();
      expect(chosen, 1);
      expect(find.text('Two'), findsNothing);
      expect(find.byType(MorphMenuButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a close request a command from the action passes by still '
      'closes the menu', (tester) async {
    late MorphMenuController host;
    final highlights = <bool>[];
    await tester.pumpWidget(
      _page(
        MorphMenuButton(
          menu: [
            MorphMenuItem(title: 'One', onHighlightChanged: highlights.add),
            MorphMenuItem(
              title: 'Two',
              onSelected: () {
                host.menuCommand(
                  (motion, t) => motion.highlight(t, 0),
                  at: host.menuClock,
                );
              },
            ),
          ],
        ),
        page: (_) {},
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    await tester.pumpAndSettle();
    host = _host(tester);
    final row = tester.getCenter(find.text('Two'));
    await tester.tapAt(const Offset(8, 590));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MorphMenuButton));
    await tester.tapAt(row);
    await tester.pumpAndSettle();
    final motion = host.menuMotion!;
    expect(highlights, [true]);
    expect(motion.isPresented, isFalse);
    expect(find.text('Two'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an action that removes its source closes the menu and '
      'reaches nothing after', (tester) async {
    var visible = true;
    late StateSetter rebuild;
    final calls = <String>[];
    await tester.pumpWidget(
      _page(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            rebuild = setState;
            if (!visible) return const SizedBox.shrink();
            return MorphMenuButton(
              menu: [
                MorphMenuItem(
                  title: 'Gone',
                  onHighlightChanged: (bool on) => calls.add('highlight $on'),
                  onSelected: () {
                    calls.add('selected');
                    rebuild(() => visible = false);
                  },
                ),
              ],
            );
          },
        ),
        page: (_) {},
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    await tester.pumpAndSettle();
    final host = _host(tester);
    await tester.tapAt(tester.getCenter(find.text('Gone')));
    await tester.pumpAndSettle();
    expect(calls, ['highlight true', 'selected']);
    expect(find.byType(MorphMenuButton), findsNothing);
    expect(host.menuMotion!.isPresented, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap on a held source calls onTap before the next frame', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _page(
        MorphMenuSource(
          trigger: MorphMenuTrigger.hold,
          onTap: () => taps++,
          menu: const [MorphMenuItem(title: 'Copy')],
          child: const SizedBox.square(dimension: 44),
        ),
        page: (_) {},
      ),
    );
    await tester.tap(find.byType(MorphMenuSource));
    expect(taps, 1);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('Back the page refuses keeps the menu open; the pop it '
      'approves later closes it from where it stands', (tester) async {
    late BuildContext page;
    var refusals = 0;
    await tester.pumpWidget(
      _page(
        const MorphMenuButton(menu: [MorphMenuItem(title: 'Copy')]),
        page: (context) => page = context,
        canPop: false,
        refused: () => refusals++,
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    await _frames(tester, 160);
    final motion = _host(tester).menuMotion!;
    expect(motion.isOpen, isTrue);
    await tester.binding.handlePopRoute();
    expect(refusals, 1);
    expect(motion.isOpen, isTrue);
    await _frames(tester, 400);
    expect(motion.isOpen, isTrue);
    expect(motion.progress, closeTo(1, 0.01));
    final time = motion.time;
    final progress = motion.progress;
    Navigator.of(page).pop();
    expect(motion.isClosing, isTrue);
    expect(motion.time, time);
    expect(motion.progress, closeTo(progress, 1e-12));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    expect(find.byType(MorphMenuButton), findsOneWidget);
    expect(refusals, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back the page allows closes the menu, not the page', (
    tester,
  ) async {
    await tester.pumpWidget(
      _page(
        const MorphMenuButton(menu: [MorphMenuItem(title: 'Copy')]),
        page: (_) {},
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    await tester.pumpAndSettle();
    final motion = _host(tester).menuMotion!;
    await tester.binding.handlePopRoute();
    expect(motion.isClosing, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsNothing);
    expect(find.byType(MorphMenuButton), findsOneWidget);
  });
}
