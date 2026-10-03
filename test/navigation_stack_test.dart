import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

const _screen = Size(402, 874);

Future<void> _setScreen(WidgetTester tester) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

MorphBarButton _icon(String id) => MorphBarButton(
  id: id,
  icon: const SizedBox.square(dimension: 24),
  semanticLabel: id,
  onPressed: () {},
);

Widget _inbox(void Function(BuildContext) onContext) => Builder(
  builder: (context) {
    onContext(context);
    return MorphNavigationScaffold(
      title: 'Inbox',
      largeTitle: true,
      leading: MorphBarButtonGroup([
        MorphBarButton(id: 'close', label: 'Close', onPressed: () {}),
      ]),
      trailing: [
        MorphBarButtonGroup([_icon('add'), _icon('search'), _icon('more')]),
      ],
      toolbarLeading: [
        MorphBarButtonGroup([_icon('filter')], id: 'tbL'),
      ],
      slivers: const [SliverToBoxAdapter(child: SizedBox(height: 2000))],
    );
  },
);

Widget _detail() => MorphNavigationScaffold(
  title: 'Message',
  trailing: [
    MorphBarButtonGroup([_icon('like'), _icon('share')]),
    MorphBarButtonGroup([
      MorphBarButton(id: 'done', label: 'Done', onPressed: () {}),
    ], prominent: true),
  ],
  toolbarLeading: [
    MorphBarButtonGroup([_icon('up'), _icon('down')], id: 'tbL'),
  ],
  slivers: const [SliverToBoxAdapter(child: SizedBox(height: 2000))],
);

/// A gallery-like app: a home screen that pushes the stack as an ordinary
/// iOS page, whose own Cupertino edge swipe pops it.
Future<BuildContext> _pumpNested(WidgetTester tester) async {
  await _setScreen(tester);
  late BuildContext inbox;
  final home = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: home,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(platform: TargetPlatform.iOS),
      home: const Scaffold(body: Center(child: Text('Library'))),
    ),
  );
  home.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => MorphNavigationStack(home: _inbox((c) => inbox = c)),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Library'), findsNothing);
  return inbox;
}

Future<void> _pushDetail(WidgetTester tester, BuildContext inbox) async {
  Navigator.of(
    inbox,
  ).push(MorphNavigationRoute<void>(builder: (_) => _detail()));
  await tester.pumpAndSettle();
  expect(find.text('Message'), findsOneWidget);
}

Future<void> _edgeSwipe(WidgetTester tester) async {
  final gesture = await tester.startGesture(const Offset(4, 500));
  for (var i = 0; i < 20; i++) {
    await gesture.moveBy(const Offset(14, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

Finder _key(String id) => find.byKey(ValueKey<Object>(id));

Offset _item(WidgetTester tester, String id) => tester.getCenter(_key(id));

double _opacity(WidgetTester tester, String id) => tester
    .widget<Opacity>(
      find.descendant(of: _key(id), matching: find.byType(Opacity)).first,
    )
    .opacity;

/// How far the detail page is out, as a share of the width.
double _pageOut(WidgetTester tester) =>
    tester
        .getTopLeft(
          find.byWidgetPredicate(
            (w) => w is MorphNavigationScaffold && w.title == 'Message',
          ),
        )
        .dx /
    _screen.width;

void main() {
  group('a stack inside an iOS page route', () {
    testWidgets('an edge swipe on a pushed screen returns to the stack root', (
      tester,
    ) async {
      final inbox = await _pumpNested(tester);
      await _pushDetail(tester, inbox);
      await _edgeSwipe(tester);
      expect(find.text('Message'), findsNothing);
      expect(find.text('Inbox'), findsWidgets);
      expect(find.text('Library'), findsNothing);
    });

    testWidgets('the back button returns to the stack root', (tester) async {
      final inbox = await _pumpNested(tester);
      await _pushDetail(tester, inbox);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Message'), findsNothing);
      expect(find.text('Inbox'), findsWidgets);
      expect(find.text('Library'), findsNothing);
    });

    testWidgets('the system back pops the stack first, then the page', (
      tester,
    ) async {
      final inbox = await _pumpNested(tester);
      await _pushDetail(tester, inbox);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Message'), findsNothing);
      expect(find.text('Inbox'), findsWidgets);
      expect(find.text('Library'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Library'), findsOneWidget);
    });

    testWidgets('maybePop from inside the stack pops its screen first', (
      tester,
    ) async {
      final inbox = await _pumpNested(tester);
      await _pushDetail(tester, inbox);
      await Navigator.of(inbox, rootNavigator: true).maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Message'), findsNothing);
      expect(find.text('Inbox'), findsWidgets);
      expect(find.text('Library'), findsNothing);
    });

    testWidgets('at the stack root the edge swipe pops the enclosing page', (
      tester,
    ) async {
      await _pumpNested(tester);
      await _edgeSwipe(tester);
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Inbox'), findsNothing);
    });

    testWidgets(
      'after a pop inside the stack the enclosing swipe works again',
      (tester) async {
        final inbox = await _pumpNested(tester);
        await _pushDetail(tester, inbox);
        await _edgeSwipe(tester);
        expect(find.text('Library'), findsNothing);
        await _edgeSwipe(tester);
        expect(find.text('Library'), findsOneWidget);
      },
    );
  });

  group('the shared bar morphs', () {
    testWidgets('on a push as on a pop', (tester) async {
      final inbox = await _pumpNested(tester);
      final add = _item(tester, 'add');
      final outer = _item(tester, 'search');
      Navigator.of(
        inbox,
      ).push(MorphNavigationRoute<void>(builder: (_) => _detail()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_item(tester, 'done').dx, closeTo(outer.dx, 0.5));
      expect(_opacity(tester, 'done'), lessThan(0.05));
      expect(_opacity(tester, 'add'), greaterThan(0.95));
      expect(_opacity(tester, 'up'), lessThan(0.05));
      expect(_opacity(tester, 'filter'), greaterThan(0.95));
      await tester.pump(const Duration(milliseconds: 150));
      final mid = _item(tester, 'done').dx;
      expect(_opacity(tester, 'done'), inExclusiveRange(0.05, 0.95));
      expect(_opacity(tester, 'add'), inExclusiveRange(0.05, 0.95));
      expect(_opacity(tester, 'up'), inExclusiveRange(0.05, 0.95));
      expect(_opacity(tester, 'filter'), inExclusiveRange(0.05, 0.95));
      await tester.pumpAndSettle();
      final done = _item(tester, 'done').dx;
      expect(_key('add'), findsNothing);
      expect(_key('filter'), findsNothing);
      expect(mid, inExclusiveRange(outer.dx, done));

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_item(tester, 'add').dx, closeTo(done, 0.5));
      expect(_opacity(tester, 'add'), lessThan(0.05));
      await tester.pump(const Duration(milliseconds: 150));
      expect(_opacity(tester, 'add'), inExclusiveRange(0.05, 0.95));
      expect(_opacity(tester, 'filter'), inExclusiveRange(0.05, 0.95));
      await tester.pumpAndSettle();
      expect(_item(tester, 'add').dx, closeTo(add.dx, 0.01));
    });

    testWidgets('an edge swipe leans the capsules toward the screen below, '
        'and a cancelled one leans them back', (tester) async {
      final inbox = await _pumpNested(tester);
      final outer = _item(tester, 'search');
      final close = _item(tester, 'close');
      await _pushDetail(tester, inbox);
      final done = _item(tester, 'done');
      final back = _item(tester, 'morph.back');
      final like = _item(tester, 'like');
      void expectLean() {
        final lean = MorphNavigationTransition.barDrift * _pageOut(tester);
        expect(
          _item(tester, 'done').dx,
          closeTo(done.dx + lean * (outer.dx - done.dx), 0.01),
        );
        expect(
          _item(tester, 'morph.back').dx,
          closeTo(back.dx + lean * (close.dx - back.dx), 0.01),
        );
        expect(_item(tester, 'like'), like);
      }

      final gesture = await tester.startGesture(const Offset(4, 500));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(14, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expectLean();
      }
      expect(_pageOut(tester), inExclusiveRange(0.2, 0.5));
      expect(_item(tester, 'done').dx, lessThan(done.dx - 2));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-14, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expectLean();
      }
      await tester.pumpAndSettle();
      expect(find.text('Message'), findsOneWidget);
      expect(_item(tester, 'done'), done);
      expect(_item(tester, 'morph.back'), back);
    });

    testWidgets('a committed swipe hands the leaning capsules to the item '
        'transition without a jump', (tester) async {
      final inbox = await _pumpNested(tester);
      final add = _item(tester, 'add');
      final outer = _item(tester, 'search');
      await _pushDetail(tester, inbox);
      final done = _item(tester, 'done');
      final gesture = await tester.startGesture(const Offset(4, 500));
      for (var i = 0; i < 18; i++) {
        await gesture.moveBy(const Offset(14, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 16));
      final leaning = _item(tester, 'done').dx;
      expect(leaning, inExclusiveRange(outer.dx, done.dx - 5));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_item(tester, 'done').dx, closeTo(leaning, 0.01));
      expect(_item(tester, 'add').dx, closeTo(leaning, 0.01));
      await tester.pumpAndSettle();
      expect(find.text('Message'), findsNothing);
      expect(_item(tester, 'add').dx, closeTo(add.dx, 0.01));
    });
  });

  group('the stack keeps its bookkeeping honest', () {
    Widget page(
      String title, {
      List<MorphBarButtonGroup> trailing = const [],
    }) => MorphNavigationScaffold(
      title: title,
      trailing: trailing,
      slivers: const [SliverToBoxAdapter(child: SizedBox(height: 2000))],
    );

    Future<NavigatorState> pumpStack(WidgetTester tester, Widget home) async {
      await _setScreen(tester);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: MorphNavigationStack(
            home: Builder(
              builder: (BuildContext c) {
                context = c;
                return home;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return Navigator.of(context);
    }

    testWidgets('a new callback reaches the shared bar', (tester) async {
      final pressed = <int>[];
      late StateSetter set;
      var count = 0;
      await pumpStack(
        tester,
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            set = setState;
            final seen = count;
            return page(
              'Inbox',
              trailing: [
                MorphBarButtonGroup([
                  MorphBarButton(
                    id: 'add',
                    icon: const SizedBox.square(dimension: 24),
                    semanticLabel: 'add',
                    onPressed: () => pressed.add(seen),
                  ),
                ]),
              ],
            );
          },
        ),
      );
      set(() => count = 7);
      await tester.pumpAndSettle();
      await tester.tap(_key('add'));
      await tester.pumpAndSettle();
      expect(pressed, [7]);
    });

    testWidgets('a swipe pops its own page, not one pushed during it', (
      tester,
    ) async {
      final navigator = await pumpStack(tester, page('Inbox'));
      navigator.push(
        MorphNavigationRoute<void>(builder: (_) => page('Message')),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(4, 500));
      for (var i = 0; i < 16; i++) {
        await gesture.moveBy(const Offset(14, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      navigator.push(MorphNavigationRoute<void>(builder: (_) => page('Third')));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Third'), findsWidgets);
      expect(find.text('Message', skipOffstage: false), findsNothing);
      expect(navigator.userGestureInProgress, isFalse);
    });

    testWidgets('a page removed during its swipe ends the user gesture', (
      tester,
    ) async {
      final navigator = await pumpStack(tester, page('Inbox'));
      late Route<Object?> message;
      navigator.push(
        MorphNavigationRoute<void>(
          builder: (BuildContext context) {
            message = ModalRoute.of(context)!;
            return page('Message');
          },
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(4, 500));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(14, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(navigator.userGestureInProgress, isTrue);
      navigator.removeRoute(message);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(navigator.userGestureInProgress, isFalse);
      expect(find.text('Inbox'), findsWidgets);
    });

    testWidgets('a back menu row whose screen is gone does nothing', (
      tester,
    ) async {
      final navigator = await pumpStack(tester, page('Mailboxes'));
      late Route<Object?> inbox;
      navigator.push(
        MorphNavigationRoute<void>(
          builder: (BuildContext context) {
            inbox = ModalRoute.of(context)!;
            return page('Inbox');
          },
        ),
      );
      await tester.pumpAndSettle();
      navigator.push(
        MorphNavigationRoute<void>(builder: (_) => page('Message')),
      );
      await tester.pumpAndSettle();
      final bar = tester.widget<MorphNavigationBar>(
        find.byType(MorphNavigationBar),
      );
      final row = bar.leading!.buttons.single.menu!.first as MorphMenuItem;
      expect(row.title, 'Inbox');
      navigator.removeRoute(inbox);
      await tester.pumpAndSettle();
      row.onSelected!();
      await tester.pumpAndSettle();
      expect(find.text('Message'), findsWidgets);
    });

    testWidgets('the open back menu follows a renamed screen', (tester) async {
      final title = ValueNotifier<String>('Inbox');
      addTearDown(title.dispose);
      final navigator = await pumpStack(tester, page('Mailboxes'));
      navigator.push(
        MorphNavigationRoute<void>(
          builder: (_) => ValueListenableBuilder<String>(
            valueListenable: title,
            builder: (BuildContext context, String value, Widget? _) =>
                page(value),
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.push(
        MorphNavigationRoute<void>(builder: (_) => page('Message')),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(_key('morph.back')),
      );
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Mailboxes'), findsOneWidget);
      await gesture.moveTo(const Offset(300, 700));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      title.value = 'Topics';
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Topics'), findsWidgets);
      await tester.tapAt(const Offset(300, 700));
      await tester.pumpAndSettle();
    });

    testWidgets('a scaffold of a navigator inside a page keeps its own bars', (
      tester,
    ) async {
      await pumpStack(
        tester,
        Navigator(
          onGenerateRoute: (RouteSettings settings) =>
              MorphNavigationRoute<void>(builder: (_) => page('Nested')),
        ),
      );
      expect(find.byType(MorphNavigationBar), findsNWidgets(2));
      expect(find.text('Nested'), findsOneWidget);
    });

    testWidgets('reduced motion fades a pushed page in place', (tester) async {
      await _setScreen(tester);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: _screen, disableAnimations: true),
            child: MorphNavigationStack(
              home: Builder(
                builder: (BuildContext c) {
                  context = c;
                  return page('Inbox');
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Navigator.of(
        context,
      ).push(MorphNavigationRoute<void>(builder: (_) => page('Message')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final message = find.byWidgetPredicate(
        (w) => w is MorphNavigationScaffold && w.title == 'Message',
      );
      expect(tester.getTopLeft(message).dx, 0);
      final fade = tester.widget<FadeTransition>(
        find.ancestor(of: message, matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, inExclusiveRange(0.05, 0.95));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(message).dx, 0);
    });
  });
}
