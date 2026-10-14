import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// An iPhone 17 Pro's screen, 402 x 874 points, status bar 62.
Future<void> _pump(
  WidgetTester tester, {
  ValueChanged<bool>? onActive,
  ValueChanged<String>? onChanged,
  bool? active,
}) async {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MorphNavigationScaffold(
        title: 'Search',
        largeTitleDisplayMode: MorphLargeTitleDisplayMode.always,
        search: MorphNavigationSearch(
          onActiveChanged: onActive,
          onChanged: onChanged,
          active: active,
        ),
        slivers: [
          SliverList.builder(
            itemCount: 40,
            itemBuilder: (BuildContext context, int i) =>
                SizedBox(height: 52, child: Text('Item $i')),
          ),
        ],
      ),
    ),
  );
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

Rect _field(WidgetTester tester) =>
    tester.getRect(find.byType(MorphSearchField).last);

void main() {
  testWidgets('the stacked field sits under the large title at rest', (
    tester,
  ) async {
    await _pump(tester);
    // iOS 27 simulator: 16 - 386 wide, 168 - 212 tall, under a 52 point
    // large title below the 54 point bar; the content starts 10 below.
    expect(
      tester.getRect(find.byType(MorphSearchField).first),
      const Rect.fromLTRB(16, 168, 386, 212),
    );
    expect(tester.getTopLeft(find.text('Item 0')).dy, 222);
  });

  testWidgets('a tap presents the search, the close button ends it', (
    tester,
  ) async {
    final active = <bool>[];
    final changes = <String>[];
    await _pump(tester, onActive: active.add, onChanged: changes.add);
    await tester.tapAt(const Offset(201, 190));
    await tester.pump();
    expect(active, [true]);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    await _settle(tester);
    // Pinned under the status bar, narrowed for the close button.
    expect(
      _field(tester),
      rectMoreOrLessEquals(
        const Rect.fromLTRB(16, 62, 402 - 16 - 44 - 10, 106),
        epsilon: 0.01,
      ),
    );
    expect(
      tester.getRect(find.bySemanticsLabel('Close')),
      rectMoreOrLessEquals(
        const Rect.fromLTWH(402 - 16 - 44, 62, 44, 44),
        epsilon: 0.01,
      ),
    );
    // The page moved up with the field: the first row is 10 below it.
    expect(
      tester.getTopLeft(find.text('Item 0')).dy,
      moreOrLessEquals(116, epsilon: 0.01),
    );
    await tester.enterText(find.byType(EditableText).last, 'abc');
    await tester.tap(find.bySemanticsLabel('Close'));
    await _settle(tester);
    expect(active, [true, false]);
    expect(changes.last, '');
    expect(find.text('abc'), findsNothing);
    expect(find.bySemanticsLabel('Close'), findsNothing);
    expect(tester.getTopLeft(find.text('Item 0')).dy, 222);
  });

  testWidgets('the motion follows the stacked spring', (tester) async {
    await _pump(tester);
    await tester.tapAt(const Offset(201, 190));
    await tester.pump();
    final tops = <double>[];
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      tops.add(_field(tester).top);
    }
    // Monotone toward the top with a slight overshoot (damping 0.9).
    expect(tops.first, lessThan(168));
    expect(tops.reduce((a, b) => a < b ? a : b), lessThan(62));
    expect(tops.last, moreOrLessEquals(62, epsilon: 1));
    await _settle(tester);
  });

  testWidgets('active presents and ends the search from code', (tester) async {
    final active = <bool>[];
    await _pump(tester, onActive: active.add, active: false);
    await _pump(tester, onActive: active.add, active: true);
    await _settle(tester);
    expect(_field(tester).top, moreOrLessEquals(62, epsilon: 0.01));
    await _pump(tester, onActive: active.add, active: false);
    await _settle(tester);
    expect(find.bySemanticsLabel('Close'), findsNothing);
    expect(active, isEmpty);
  });

  testWidgets('inside a navigation stack the shared bar steps aside', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 62 * 3);
    addTearDown(tester.view.reset);
    final active = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MorphNavigationStack(
          prefersLargeTitles: true,
          home: MorphNavigationScaffold(
            title: 'Search',
            largeTitleDisplayMode: MorphLargeTitleDisplayMode.always,
            trailing: [
              MorphBarButtonGroup([
                MorphBarButton(
                  id: 'more',
                  icon: const Icon(Icons.more_horiz),
                  semanticLabel: 'More',
                  onPressed: () {},
                ),
              ]),
            ],
            search: MorphNavigationSearch(onActiveChanged: active.add),
            slivers: [
              SliverList.builder(
                itemCount: 40,
                itemBuilder: (BuildContext context, int i) =>
                    SizedBox(height: 52, child: Text('Item $i')),
              ),
            ],
          ),
        ),
      ),
    );
    await _settle(tester);
    await tester.tapAt(const Offset(201, 190));
    await _settle(tester);
    expect(_field(tester).top, moreOrLessEquals(62, epsilon: 0.01));
    expect(find.bySemanticsLabel('More'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Close'));
    await _settle(tester);
    expect(active, [true, false]);
    expect(find.bySemanticsLabel('More'), findsOneWidget);
  });

  testWidgets('Escape ends the search', (tester) async {
    final active = <bool>[];
    await _pump(tester, onActive: active.add);
    await tester.tapAt(const Offset(201, 190));
    await _settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(active, [true, false]);
  });
}
