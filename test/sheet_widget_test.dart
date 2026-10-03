import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

const _contentKey = Key('content');

Widget _app({
  required void Function(BuildContext context) onPresent,
  ThemeData? theme,
  TextDirection direction = TextDirection.ltr,
  VoidCallback? onPageTap,
}) {
  return MaterialApp(
    theme: theme,
    home: Directionality(
      textDirection: direction,
      child: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 80),
              TextButton(
                onPressed: () => onPresent(context),
                child: const Text('present'),
              ),
              TextButton(onPressed: onPageTap, child: const Text('page')),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _content(BuildContext context) => const Material(
  type: MaterialType.transparency,
  child: SizedBox.expand(key: _contentKey, child: Text('sheet')),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('presents at the medium detent, floating, and docks at large', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        onPresent: (BuildContext context) => presentMorphSheet<void>(
          context,
          detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
          grabberVisible: true,
          builder: _content,
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    final medium = tester.getRect(find.byKey(_contentKey));
    expect(medium.left, moreOrLessEquals(8, epsilon: 0.05));
    expect(medium.right, moreOrLessEquals(394, epsilon: 0.05));
    expect(medium.bottom, moreOrLessEquals(866, epsilon: 0.05));
    expect(medium.height, moreOrLessEquals(469.68 * 386 / 402, epsilon: 0.1));
    final sheet = MorphSheet.of(tester.element(find.byKey(_contentKey)));
    expect(sheet.detent, MorphSheetDetent.medium);
    sheet.animateTo(MorphSheetDetent.large);
    await _settle(tester);
    final large = tester.getRect(find.byKey(_contentKey));
    expect(large.top, moreOrLessEquals(62, epsilon: 0.05));
    expect(large.width, moreOrLessEquals(402, epsilon: 0.05));
    expect(sheet.detent, MorphSheetDetent.large);
  });

  testWidgets('a drag up docks it, a drag down dismisses it with no result', (
    WidgetTester tester,
  ) async {
    Object? result = 'pending';
    await tester.pumpWidget(
      _app(
        onPresent: (BuildContext context) async {
          result = await presentMorphSheet<String>(
            context,
            detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
            builder: _content,
          );
        },
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    final before = tester.getRect(find.byKey(_contentKey)).top;
    await tester.drag(find.text('sheet'), const Offset(0, -300));
    await _settle(tester);
    final docked = tester.getRect(find.byKey(_contentKey));
    expect(docked.top, lessThan(before - 100));
    expect(docked.width, moreOrLessEquals(800, epsilon: 0.05));
    await tester.fling(find.text('sheet'), const Offset(0, 500), 3000);
    await _settle(tester);
    await _settle(tester);
    expect(find.byKey(_contentKey), findsNothing);
    expect(result, isNull);
  });

  testWidgets('a tap on the dimming dismisses; Navigator.pop returns', (
    WidgetTester tester,
  ) async {
    Object? result = 'pending';
    await tester.pumpWidget(
      _app(
        onPresent: (BuildContext context) async {
          result = await presentMorphSheet<String>(
            context,
            detents: const [MorphSheetDetent.medium],
            builder: _content,
          );
        },
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    await tester.tapAt(const Offset(400, 40));
    await _settle(tester);
    expect(find.byKey(_contentKey), findsNothing);
    expect(result, isNull);
    await tester.tap(find.text('present'));
    await _settle(tester);
    Navigator.of(tester.element(find.byKey(_contentKey))).pop('done');
    await _settle(tester);
    expect(result, 'done');
    expect(find.byKey(_contentKey), findsNothing);
  });

  testWidgets('an undimmed detent leaves the page behind interactive', (
    WidgetTester tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        onPageTap: () => taps++,
        onPresent: (BuildContext context) => presentMorphSheet<void>(
          context,
          detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
          largestUndimmedDetent: MorphSheetDetent.medium,
          builder: _content,
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    await tester.tap(find.text('page'));
    expect(taps, 1);
    expect(find.byKey(_contentKey), findsOneWidget);
  });

  testWidgets('a sheet that is not dismissible stays on a drag down', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        onPresent: (BuildContext context) => presentMorphSheet<void>(
          context,
          detents: const [MorphSheetDetent.medium],
          dismissible: false,
          builder: _content,
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    final rest = tester.getRect(find.byKey(_contentKey));
    await tester.fling(find.text('sheet'), const Offset(0, 400), 3000);
    await _settle(tester);
    expect(
      tester.getRect(find.byKey(_contentKey)).top,
      moreOrLessEquals(rest.top, epsilon: 0.05),
    );
    await tester.tapAt(const Offset(400, 40));
    await _settle(tester);
    expect(find.byKey(_contentKey), findsOneWidget);
  });

  testWidgets('a scrollable hands its drags to the sheet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        onPresent: (BuildContext context) => presentMorphSheet<void>(
          context,
          detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
          builder: (BuildContext context) => Material(
            type: MaterialType.transparency,
            child: ListView.builder(
              key: _contentKey,
              controller: MorphSheet.scrollControllerOf(context),
              itemCount: 50,
              itemBuilder: (BuildContext context, int i) =>
                  SizedBox(height: 50, child: Text('row $i')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    final medium = tester.getRect(find.byKey(_contentKey)).top;
    await tester.drag(find.text('row 2'), const Offset(0, -250));
    await _settle(tester);
    final expanded = tester.getRect(find.byKey(_contentKey)).top;
    expect(expanded, lessThan(medium - 100));
    expect(find.text('row 0'), findsOneWidget);
    await tester.drag(find.text('row 2'), const Offset(0, -200));
    await _settle(tester);
    expect(tester.getRect(find.byKey(_contentKey)).top, expanded);
    expect(find.text('row 0'), findsNothing);
  });

  testWidgets('one drag up expands the sheet, then scrolls the list', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        onPresent: (BuildContext context) => presentMorphSheet<void>(
          context,
          detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
          builder: (BuildContext context) => Material(
            type: MaterialType.transparency,
            child: ListView.builder(
              key: _contentKey,
              controller: MorphSheet.scrollControllerOf(context),
              itemCount: 50,
              itemBuilder: (BuildContext context, int i) =>
                  SizedBox(height: 50, child: Text('row $i')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    await tester.timedDrag(
      find.text('row 2'),
      const Offset(0, -600),
      const Duration(milliseconds: 900),
    );
    await _settle(tester);
    expect(
      tester.getRect(find.byKey(_contentKey)).top,
      moreOrLessEquals(0, epsilon: 0.1),
    );
    expect(find.text('row 0'), findsNothing);
  });

  testWidgets('the sheet is a named route for screen readers', (
    WidgetTester tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        onPresent: (BuildContext context) => presentMorphSheet<void>(
          context,
          semanticLabel: 'Options',
          builder: _content,
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    expect(tester.getSemantics(find.text('sheet')), isNotNull);
    expect(find.bySemanticsLabel('Options'), findsOneWidget);
    expect(
      tester.semantics
          .find(find.bySemanticsLabel('Options'))
          .getSemanticsData()
          .flagsCollection
          .scopesRoute,
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('dark theme docks on the dark fill; RTL lays out the same', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _app(
        theme: ThemeData(brightness: Brightness.dark),
        direction: TextDirection.rtl,
        onPresent: (BuildContext context) =>
            presentMorphSheet<void>(context, builder: _content),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    final boxes = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
    expect(
      boxes.any((ColoredBox b) => b.color == MorphSheetStyle.dark.dockedColor),
      isTrue,
    );
    expect(tester.getRect(find.byKey(_contentKey)).width, 800);
  });
  testWidgets('with the keyboard up the content pads above it', (
    WidgetTester tester,
  ) async {
    late EdgeInsets padding;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        onPresent: (BuildContext context) => presentMorphSheet<void>(
          context,
          builder: (BuildContext context) {
            padding = MediaQuery.paddingOf(context);
            return _content(context);
          },
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    expect(padding.bottom, 100);
    expect(padding.top, 0);
    expect(
      MediaQuery.viewInsetsOf(tester.element(find.byKey(_contentKey))),
      EdgeInsets.zero,
    );
  });
}
