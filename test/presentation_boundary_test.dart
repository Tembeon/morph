import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

const _screen = Size(402, 874);

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

class _App extends StatelessWidget {
  const _App({required this.root, required this.page});

  final GlobalKey<NavigatorState> root;
  final Widget page;

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: root,
    debugShowCheckedModeBanner: false,
    builder: (BuildContext context, Widget? child) => MorphScope(child: child!),
    home: MorphNavigationStack(
      home: MorphNavigationScaffold(
        title: 'Page',
        trailing: [
          MorphBarButtonGroup([
            MorphBarButton(id: 'bar', label: 'Bar', onPressed: () {}),
          ]),
        ],
        slivers: [SliverToBoxAdapter(child: page)],
      ),
    ),
  );
}

Future<GlobalKey<NavigatorState>> _pump(
  WidgetTester tester,
  Widget page,
) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final root = GlobalKey<NavigatorState>();
  await tester.pumpWidget(_App(root: root, page: page));
  await _settle(tester);
  return root;
}

OverlayState _overlayAround(WidgetTester tester, Finder finder) =>
    tester.state<OverlayState>(
      find.ancestor(of: finder, matching: find.byType(Overlay)).first,
    );

Finder get _barButton => find.text('Bar');

void main() {
  testWidgets('a menu button on a stack page opens above the stack bars', (
    WidgetTester tester,
  ) async {
    final root = await _pump(
      tester,
      const Center(
        child: MorphMenuButton(items: [MorphMenuItem(title: 'Copy')]),
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    expect(
      _overlayAround(tester, find.text('Copy')),
      same(root.currentState!.overlay),
    );
    expect(
      _overlayAround(tester, _barButton),
      same(root.currentState!.overlay),
    );
  });

  testWidgets('an explicit overlay still wins over the stack default', (
    WidgetTester tester,
  ) async {
    final root = await _pump(
      tester,
      Center(
        child: Builder(
          builder: (BuildContext context) => MorphMenuButton(
            overlay: Overlay.of(context),
            items: const [MorphMenuItem(title: 'Copy')],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(MorphMenuButton));
    await _settle(tester);
    final overlay = _overlayAround(tester, find.text('Copy'));
    expect(overlay, isNot(same(root.currentState!.overlay)));
    expect(overlay, same(_overlayAround(tester, find.byType(MorphMenuButton))));
  });

  testWidgets('a context menu on a stack page opens above the stack bars', (
    WidgetTester tester,
  ) async {
    final root = await _pump(
      tester,
      Center(
        child: MorphContextMenuRegion(
          below: MorphSatellite(
            height: 40,
            builder: (BuildContext context, MorphFlight flight) =>
                const Text('below'),
          ),
          child: const SizedBox(
            width: 120,
            height: 80,
            child: ColoredBox(color: Color(0xFF0088FF)),
          ),
        ),
      ),
    );
    final hero = tester.getCenter(find.byType(MorphContextMenuRegion));
    final gesture = await tester.startGesture(hero);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await _settle(tester);
    expect(find.text('below'), findsOneWidget);
    expect(
      _overlayAround(tester, find.text('below')),
      same(root.currentState!.overlay),
    );
  });

  testWidgets('a sheet from a stack page is pushed above the stack bars', (
    WidgetTester tester,
  ) async {
    late BuildContext page;
    final root = await _pump(
      tester,
      Builder(
        builder: (BuildContext context) {
          page = context;
          return const SizedBox(height: 100);
        },
      ),
    );
    late BuildContext sheet;
    unawaited(
      presentMorphSheet<void>(
        page,
        builder: (BuildContext context) {
          sheet = context;
          return const Text('sheet');
        },
      ),
    );
    await _settle(tester);
    expect(find.text('sheet'), findsOneWidget);
    expect(Navigator.of(sheet), same(root.currentState));
    Navigator.of(sheet).pop();
    await _settle(tester);

    unawaited(
      presentMorphSheet<void>(
        page,
        useRootNavigator: false,
        builder: (BuildContext context) {
          sheet = context;
          return const Text('inner sheet');
        },
      ),
    );
    await _settle(tester);
    expect(Navigator.of(sheet), same(Navigator.of(page)));
    expect(Navigator.of(page), isNot(same(root.currentState)));
  });

  testWidgets('an engine dialog from a stack page flies above the bars and '
      'measures its anchor in the same overlay', (WidgetTester tester) async {
    late BuildContext page;
    final root = await _pump(
      tester,
      MorphTag(
        id: 'card',
        child: Builder(
          builder: (BuildContext context) {
            page = context;
            return const SizedBox(height: 100);
          },
        ),
      ),
    );
    final overlayBox =
        root.currentState!.overlay!.context.findRenderObject()! as RenderBox;
    final box = page.findRenderObject()! as RenderBox;
    expect(
      morphAnchorRect(page),
      box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size,
    );
    showMorphDialog(
      page,
      from: 'card',
      width: 200,
      height: 120,
      builder: (BuildContext context, MorphFlight flight) =>
          const Text('dialog'),
    );
    await _settle(tester);
    expect(
      _overlayAround(tester, find.text('dialog')),
      same(root.currentState!.overlay),
    );
  });

  testWidgets('nested stacks present outside the outermost one', (
    WidgetTester tester,
  ) async {
    late BuildContext inner;
    final root = await _pump(
      tester,
      SizedBox(
        height: 400,
        child: MorphNavigationStack(
          home: MorphNavigationScaffold(
            title: 'Inner',
            slivers: [
              SliverToBoxAdapter(
                child: Builder(
                  builder: (BuildContext context) {
                    inner = context;
                    return const SizedBox(height: 10);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(morphPresentationOverlayOf(inner), same(root.currentState!.overlay));
    expect(morphPresentationNavigatorOf(inner), same(root.currentState));
  });

  testWidgets('without a boundary a nested navigator keeps its own world', (
    WidgetTester tester,
  ) async {
    late BuildContext page;
    final nested = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          key: nested,
          onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
            builder: (BuildContext context) {
              page = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(
      morphPresentationOverlayOf(page),
      same(nested.currentState!.overlay),
    );
    expect(morphPresentationNavigatorOf(page), same(nested.currentState));
  });
}
