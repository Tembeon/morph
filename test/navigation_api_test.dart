import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/badge.dart';
import 'package:morph/morph.dart';

const _screen = Size(402, 874);

Future<void> _setScreen(WidgetTester tester) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

const _filler = [SliverToBoxAdapter(child: SizedBox(height: 2000))];

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 16),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);

Widget _app(Widget stack) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(platform: TargetPlatform.iOS),
  home: stack,
);

void main() {
  testWidgets('a pages stack pushes, pops and reports the removed page', (
    tester,
  ) async {
    await _setScreen(tester);
    var pages = <Page<Object?>>[
      const MorphNavigationPage<void>(
        key: ValueKey('inbox'),
        child: MorphNavigationScaffold(title: 'Inbox', slivers: _filler),
      ),
    ];
    final removed = <Page<Object?>>[];
    late StateSetter update;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MorphNavigationStack.pages(
              pages: pages,
              onDidRemovePage: (page) {
                removed.add(page);
                setState(
                  () => pages = [
                    for (final p in pages)
                      if (p != page) p,
                  ],
                );
              },
            );
          },
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('Inbox'), findsOneWidget);
    update(
      () => pages = [
        ...pages,
        const MorphNavigationPage<void>(
          key: ValueKey('message'),
          child: MorphNavigationScaffold(title: 'Message', slivers: _filler),
        ),
      ],
    );
    await _settle(tester);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget, reason: 'the back button');
    await tester.tap(find.text('Inbox'));
    await _settle(tester);
    expect(removed.single.key, const ValueKey('message'));
    expect(pages, hasLength(1));
    expect(find.text('Message'), findsNothing);
  });

  Future<void> pushOver(
    WidgetTester tester,
    MorphNavigationScaffold below,
    MorphNavigationScaffold above,
  ) async {
    await _setScreen(tester);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(MorphNavigationStack(navigatorKey: key, home: below)),
    );
    await _settle(tester);
    key.currentState!.push(MorphNavigationRoute<void>(builder: (_) => above));
    await _settle(tester);
  }

  testWidgets('back button display modes', (tester) async {
    await pushOver(
      tester,
      const MorphNavigationScaffold(
        title: 'Settings',
        backButtonDisplayMode: .minimal,
        slivers: _filler,
      ),
      const MorphNavigationScaffold(title: 'General', slivers: _filler),
    );
    expect(find.text('Settings'), findsNothing);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
  });

  testWidgets('a generic back button says Back', (tester) async {
    await pushOver(
      tester,
      const MorphNavigationScaffold(
        title: 'Settings',
        backButtonDisplayMode: .generic,
        slivers: _filler,
      ),
      const MorphNavigationScaffold(title: 'General', slivers: _filler),
    );
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('hidesBackButton leaves the leading edge empty', (tester) async {
    await pushOver(
      tester,
      const MorphNavigationScaffold(title: 'Settings', slivers: _filler),
      const MorphNavigationScaffold(
        title: 'General',
        hidesBackButton: true,
        slivers: _filler,
      ),
    );
    expect(find.text('Settings'), findsNothing);
    expect(find.bySemanticsLabel('Back'), findsNothing);
  });

  testWidgets('the subtitle shows under the inline and the large title', (
    tester,
  ) async {
    await _setScreen(tester);
    await tester.pumpWidget(
      _app(
        const MorphNavigationStack(
          home: MorphNavigationScaffold(
            title: 'Inbox',
            subtitle: '3 unread',
            largeTitleDisplayMode: .always,
            slivers: _filler,
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('3 unread'), findsOneWidget);
    final large = tester.getRect(find.byType(MorphLargeTitle));
    expect(large.height, MorphLargeTitle.extentFor(subtitle: true));
  });

  testWidgets('automatic large titles follow the stack and the page below', (
    tester,
  ) async {
    await _setScreen(tester);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(
        MorphNavigationStack(
          navigatorKey: key,
          prefersLargeTitles: true,
          home: const MorphNavigationScaffold(
            title: 'Inbox',
            largeTitleDisplayMode: .automatic,
            slivers: _filler,
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(find.byType(MorphLargeTitle), findsOneWidget);
    key.currentState!.push(
      MorphNavigationRoute<void>(
        builder: (_) => const MorphNavigationScaffold(
          title: 'Message',
          largeTitleDisplayMode: .automatic,
          slivers: _filler,
        ),
      ),
    );
    await _settle(tester);
    expect(
      find.descendant(
        of: find.byType(MorphLargeTitle),
        matching: find.text('Message'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('automatic without prefersLargeTitles stays inline', (
    tester,
  ) async {
    await _setScreen(tester);
    await tester.pumpWidget(
      _app(
        const MorphNavigationStack(
          home: MorphNavigationScaffold(
            title: 'Inbox',
            largeTitleDisplayMode: .automatic,
            slivers: _filler,
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(find.byType(MorphLargeTitle), findsNothing);
  });

  testWidgets('a bar button shows its badge', (tester) async {
    await _setScreen(tester);
    await tester.pumpWidget(
      _app(
        MorphNavigationStack(
          home: MorphNavigationScaffold(
            title: 'Inbox',
            trailing: [
              MorphBarButtonGroup([
                MorphBarButton(
                  id: 'cart',
                  icon: const SizedBox.square(dimension: 24),
                  badge: const MorphBadge.count(3),
                  onPressed: () {},
                ),
              ]),
            ],
            slivers: _filler,
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('3'), findsOneWidget);
    final item = tester.getRect(find.byType(MorphBadged));
    final badge = tester.getRect(
      find.ancestor(of: find.text('3'), matching: find.byType(Container)),
    );
    expect((badge.center - item.topRight).distance, lessThan(10));
    expect(badge.width, greaterThanOrEqualTo(badge.height));
  });

  test('a bar badge stays within 10 points past its corner', () {
    const item = Size(44, 44);
    final capsule = Offset.zero & item;
    const wide = Size(40, 18);
    final ltr = MorphBadged.cornerOrigin(
      size: wide,
      itemSize: item,
      capsule: capsule,
      radius: 22,
      rtl: false,
    );
    final inset = 22 * (1 - 0.7071067811865476);
    expect(ltr.dx + wide.width, moreOrLessEquals(44 - inset + 10));
    final rtl = MorphBadged.cornerOrigin(
      size: wide,
      itemSize: item,
      capsule: capsule,
      radius: 22,
      rtl: true,
    );
    expect(rtl.dx, moreOrLessEquals(inset - 10));
    expect(MorphBadgeMetrics.sizeOf(null), const Size.square(18));
  });

  test('badges hide when empty', () {
    expect(const MorphBadge.count(0).visible, isFalse);
    expect(const MorphBadge.string('').visible, isFalse);
    expect(const MorphBadge.indicator().visible, isTrue);
    expect(const MorphBadge.count(12).label, '12');
  });
}
