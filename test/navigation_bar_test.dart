import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/bar_items.dart' show MorphBackChevronPainter;
import 'package:morph/widgets.dart';

const _screen = Size(402, 874);

Widget _app(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  ThemeData? theme,
  double textScale = 1,
  EdgeInsets padding = const EdgeInsets.only(top: 62, bottom: 34),
}) => MaterialApp(
  theme: theme,
  debugShowCheckedModeBanner: false,
  home: MediaQuery(
    data: MediaQueryData(
      size: _screen,
      padding: padding,
      textScaler: TextScaler.linear(textScale),
    ),
    child: Directionality(textDirection: direction, child: child),
  ),
);

Future<void> _setScreen(WidgetTester tester) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

MorphBarButton _icon(String id, {VoidCallback? onPressed}) => MorphBarButton(
  id: id,
  icon: const SizedBox.square(dimension: 24),
  semanticLabel: id,
  onPressed: onPressed ?? () {},
);

void main() {
  testWidgets('toolbar capsules sit 28 points from the screen edges', (
    tester,
  ) async {
    await _setScreen(tester);
    await tester.pumpWidget(
      _app(
        Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MorphToolbar(
                leading: [
                  MorphBarButtonGroup([_icon('a'), _icon('b')], id: 'L'),
                ],
                trailing: [
                  MorphBarButtonGroup([_icon('c')], id: 'R'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final c = tester.getRect(find.bySemanticsLabel('c'));
    expect(c.right, moreOrLessEquals(402 - 28 - 5, epsilon: 0.01));
    expect(c.bottom, moreOrLessEquals(874 - 28 - 5, epsilon: 0.01));
    final a = tester.getRect(find.bySemanticsLabel('a'));
    final b = tester.getRect(find.bySemanticsLabel('b'));
    expect(a.left, moreOrLessEquals(28 + 5, epsilon: 0.01));
    expect(a.width, 40);
    expect(b.left - a.right, 14);
  });

  testWidgets('a toolbar item change animates and settles', (tester) async {
    await _setScreen(tester);
    Widget bar(List<MorphBarButtonGroup> leading) => _app(
      Align(
        alignment: Alignment.bottomCenter,
        child: MorphToolbar(leading: leading),
      ),
    );
    await tester.pumpWidget(
      bar([
        MorphBarButtonGroup([_icon('a')], id: 'L'),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      bar([
        MorphBarButtonGroup([_icon('b'), _icon('c')], id: 'L'),
      ]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.bySemanticsLabel('a'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('b'), findsOneWidget);
    expect(find.bySemanticsLabel('c'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('bar buttons are buttons for screen readers; disabled ones '
      'do not tap', (tester) async {
    await _setScreen(tester);
    final handle = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Align(
          alignment: Alignment.topCenter,
          child: MorphNavigationBar(
            title: 'Inbox',
            leading: const MorphBarButtonGroup([
              MorphBarButton(id: 'edit', label: 'Edit'),
            ]),
            trailing: [
              MorphBarButtonGroup([_icon('add', onPressed: () => taps++)]),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel('add')),
      matchesSemantics(
        label: 'add',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Edit')),
      matchesSemantics(label: 'Edit', isButton: true, hasEnabledState: true),
    );
    await tester.tap(find.bySemanticsLabel('add'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    await tester.tap(find.bySemanticsLabel('Edit'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('right-to-left mirrors the bar and the back chevron', (
    tester,
  ) async {
    await _setScreen(tester);
    await tester.pumpWidget(
      _app(
        direction: TextDirection.rtl,
        Align(
          alignment: Alignment.topCenter,
          child: MorphNavigationBar(
            leading: MorphBarButtonGroup([
              MorphBarButton.back(label: 'Inbox', onPressed: () {}),
            ]),
            trailing: [
              MorphBarButtonGroup([_icon('add')]),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final back = tester.getRect(find.text('Inbox'));
    final add = tester.getRect(find.bySemanticsLabel('add'));
    expect(back.center.dx, greaterThan(201));
    expect(add.center.dx, lessThan(201));
    final chevron = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is MorphBackChevronPainter,
      ),
    );
    expect((chevron.painter! as MorphBackChevronPainter).mirrored, isTrue);
  });

  testWidgets('the bar resolves its look from MorphWidgetsTheme', (
    tester,
  ) async {
    await _setScreen(tester);
    const custom = MorphBarStyle(titleColor: Color(0xFFFF0000));
    await tester.pumpWidget(
      _app(
        theme: ThemeData(extensions: const [MorphWidgetsTheme(bar: custom)]),
        const Align(
          alignment: Alignment.topCenter,
          child: MorphNavigationBar(title: 'Red'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.text('Red'));
    expect(text.style?.color, const Color(0xFFFF0000));
    await tester.pumpWidget(
      _app(
        theme: ThemeData(brightness: Brightness.dark),
        const Align(
          alignment: Alignment.topCenter,
          child: MorphNavigationBar(title: 'Dark'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('Dark')).style?.color,
      MorphBarStyle.dark.titleColor,
    );
  });

  testWidgets('labels follow the text scale up to 1.25', (tester) async {
    await _setScreen(tester);
    double width(double scale) {
      return tester.getSize(find.bySemanticsLabel('Edit')).width;
    }

    Widget bar(double scale) => _app(
      textScale: scale,
      const Align(
        alignment: Alignment.topCenter,
        child: MorphNavigationBar(
          leading: MorphBarButtonGroup([
            MorphBarButton(id: 'edit', label: 'Edit', onPressed: _noop),
          ]),
        ),
      ),
    );
    await tester.pumpWidget(bar(1));
    await tester.pumpAndSettle();
    final w1 = width(1);
    await tester.pumpWidget(bar(1.25));
    await tester.pumpAndSettle();
    final w125 = width(1.25);
    await tester.pumpWidget(bar(2));
    await tester.pumpAndSettle();
    final w2 = width(2);
    expect(w125, greaterThan(w1));
    expect(w2, moreOrLessEquals(w125, epsilon: 0.01));
  });

  testWidgets('the inline title rises in when content scrolls under', (
    tester,
  ) async {
    await _setScreen(tester);
    Widget bar({required bool visible}) => _app(
      Align(
        alignment: Alignment.topCenter,
        child: MorphNavigationBar(
          title: 'Inbox',
          titleVisible: visible,
          scrolledUnder: visible,
        ),
      ),
    );
    await tester.pumpWidget(bar(visible: false));
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsNothing);
    await tester.pumpWidget(bar(visible: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final opacity = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('Inbox'), matching: find.byType(Opacity))
          .first,
    );
    expect(opacity.opacity, inExclusiveRange(0.05, 0.95));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('a stack pushes with a back button titled by the previous '
      'screen, and pops by the back button and by an edge swipe', (
    tester,
  ) async {
    await _setScreen(tester);
    late BuildContext homeContext;
    Widget detail() => const MorphNavigationScaffold(
      title: 'Detail',
      slivers: [SliverToBoxAdapter(child: SizedBox(height: 2000))],
    );
    await tester.pumpWidget(
      _app(
        MorphNavigationStack(
          home: Builder(
            builder: (context) {
              homeContext = context;
              return const MorphNavigationScaffold(
                title: 'Inbox',
                largeTitle: true,
                slivers: [SliverToBoxAdapter(child: SizedBox(height: 2000))],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsOneWidget);
    Navigator.of(
      homeContext,
    ).push(MorphNavigationRoute<void>(builder: (_) => detail()));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expect(find.text('Detail'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Back'), findsNothing);
    Navigator.of(
      homeContext,
    ).push(MorphNavigationRoute<void>(builder: (_) => detail()));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(4, 500));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(14, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Back'), findsNothing);
    expect(find.text('Detail'), findsNothing);
  });

  testWidgets('a large title released halfway snaps to the nearer end', (
    tester,
  ) async {
    await _setScreen(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        MorphNavigationScaffold(
          title: 'Inbox',
          largeTitle: true,
          controller: controller,
          slivers: const [SliverToBoxAdapter(child: SizedBox(height: 3000))],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(200, 500));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    final rest = controller.offset;
    expect(rest == 0 || (rest - 52).abs() < 0.5, isTrue, reason: '$rest');
  });

  testWidgets('with reduced motion an item change snaps', (tester) async {
    await _setScreen(tester);
    Widget bar(String id) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: _screen, disableAnimations: true),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: MorphToolbar(
            leading: [
              MorphBarButtonGroup([_icon(id)], id: 'L'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(bar('a'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(bar('b'));
    await tester.pump();
    expect(find.bySemanticsLabel('b'), findsOneWidget);
    expect(find.bySemanticsLabel('a'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

void _noop() {}
