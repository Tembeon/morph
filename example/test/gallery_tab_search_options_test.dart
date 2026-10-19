import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/knobs.dart';

import 'support/gallery_text.dart';

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

Future<void> _open(WidgetTester tester, String title) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const GalleryApp());
  await _settle(tester);
  final entry = find.widgetWithText(MorphListRow, title);
  await Scrollable.ensureVisible(tester.element(entry), alignment: 0.5);
  await _settle(tester);
  await tester.tap(entry);
  await _settle(tester);
}

/// The options sheet's list.
Finder get _sheet => find.byType(ListView).last;

/// Scrolls the options sheet to [finder] and taps it.
Future<void> _knob(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find
        .descendant(of: _sheet, matching: find.byType(Scrollable))
        .first,
  );
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

/// The switch of the knob [label].
Finder _switch(String label) => find.descendant(
  of: find.widgetWithText(GalleryToggle, label),
  matching: find.byType(MorphSwitch),
);

/// The segment [segment] of the choice [label].
Finder _segment(String label, String segment) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(MorphListRow)),
  matching: find.text(segment),
);

Future<void> _openOptions(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Page options'));
  await _settle(tester);
}

Future<void> _closeOptions(WidgetTester tester) async {
  Navigator.of(tester.element(_sheet)).pop();
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final previous = FlutterError.onError;
    FlutterError.onError = (_) {};
    try {
      await MorphTheme.precacheGlass();
    } finally {
      FlutterError.onError = previous;
    }
  });

  testWidgets('tab bar options: badges, icons, a disabled tab, tint, '
      'reselection', (tester) async {
    await _open(tester, 'Tab bar');
    MorphTabBar bar() => tester.widget<MorphTabBar>(find.byType(MorphTabBar));
    expect(bar().items[1].badge, const MorphBadge.count(3));
    expect(bar().items[2].badge, const MorphBadge.indicator());
    expect(bar().appearance, isNull);

    await _openOptions(tester);
    await _knob(tester, _segment('Library', 'Text'));
    await _knob(tester, _segment('Radio', 'None'));
    await _knob(tester, _switch('Selected icons'));
    await _knob(tester, _switch('Disable Profile'));
    await _knob(tester, find.bySemanticsLabel('Purple').last);
    await _closeOptions(tester);
    expect(bar().items[1].badge, const MorphBadge.string('New'));
    expect(bar().items[2].badge, isNull);
    expect(find.text('New'), findsWidgets);
    expect(bar().items[0].selectedIcon, Icons.home_rounded);
    expect(bar().items[3].enabled, isFalse);
    expect(bar().appearance?.selectedColor, const Color(0xFFAF52DE));

    final tabs = find.byType(MorphTabBar);
    await tester.tapAt(
      tester.getCenter(
        find.descendant(of: tabs, matching: find.text('Profile')),
      ),
    );
    await _settle(tester);
    expect(bar().selected, 0);
    await tester.tapAt(
      tester.getCenter(find.descendant(of: tabs, matching: find.text('Home'))),
    );
    await _settle(tester);
    await tester.tapAt(
      tester.getCenter(find.descendant(of: tabs, matching: find.text('Home'))),
    );
    await _settle(tester);
    await _openOptions(tester);
    await tester.scrollUntilVisible(
      find.text('Reselected'),
      120,
      scrollable: find
          .descendant(of: _sheet, matching: find.byType(Scrollable))
          .first,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(MorphListRow, 'Reselected'),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(unstyledTexts(), isEmpty);
  });

  testWidgets('minimize options: automatic and a direct content scroll', (
    tester,
  ) async {
    await _open(tester, 'Tab bar minimize');
    MorphTabBar bar() => tester.widget<MorphTabBar>(find.byType(MorphTabBar));
    expect(bar().minimizeBehavior, MorphTabBarMinimizeBehavior.onScrollDown);
    expect(bar().contentScroll, isNull);
    await _openOptions(tester);
    await _knob(tester, _segment('Behavior', 'Auto'));
    await _knob(tester, _segment('Scroll', 'Direct'));
    await _closeOptions(tester);
    expect(bar().minimizeBehavior, MorphTabBarMinimizeBehavior.automatic);
    expect(bar().contentScroll, isNotNull);
    expect(
      tester
          .widget<MorphSegmentedControl>(
            find.byType(MorphSegmentedControl).first,
          )
          .selectedIndex,
      isNull,
    );
    await tester.tap(find.text('Scroll down'));
    await _settle(tester);
    expect(bar().minimizeBehavior, MorphTabBarMinimizeBehavior.onScrollDown);
    await tester.fling(
      find.byType(CustomScrollView).last,
      const Offset(0, -400),
      1500,
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimize page: a search tab with a stacked search field', (
    tester,
  ) async {
    await _open(tester, 'Tab bar minimize');
    await tester.tap(find.text('Search tab'));
    await _settle(tester);
    final bar = tester.widget<MorphTabBar>(find.byType(MorphTabBar));
    expect(bar.items.last.role, MorphTabRole.search);
    bar.onChanged!(3);
    await _settle(tester);
    expect(find.text('Item 0'), findsOneWidget);
    final field = find.byType(MorphSearchField);
    await tester.tap(field.first);
    await _settle(tester);
    await tester.enterText(find.byType(EditableText).last, 'Item 1');
    await _settle(tester);
    expect(find.text('Item 0'), findsNothing);
    expect(find.text('Item 12'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close'));
    await _settle(tester);
    expect(find.text('Item 0'), findsOneWidget);
    expect(unstyledTexts(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search options: the page controller, focus, submit, labels', (
    tester,
  ) async {
    await _open(tester, 'Search');
    expect(find.text('Banana'), findsOneWidget);
    await _openOptions(tester);
    await _knob(tester, _switch('Page controller'));
    await _knob(tester, find.text('Type "berry"'));
    expect(find.text('Blueberry'), findsOneWidget);
    expect(find.text('Banana'), findsNothing);
    await _knob(tester, find.text('Clear the field'));
    expect(find.text('Banana'), findsOneWidget);
    await _knob(tester, _switch('Custom labels'));
    await _knob(tester, _switch('Autofocus inline field'));
    await _closeOptions(tester);

    await tester.tap(find.byType(MorphSearchField));
    await _settle(tester);
    await tester.enterText(find.byType(EditableText), 'ap');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settle(tester);
    expect(find.text('Submitted "ap"'), findsOneWidget);
    expect(find.text('Apple'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await _settle(tester);

    await tester.tap(find.text('Inline'));
    await _settle(tester);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    expect(find.bySemanticsLabel('Fruit search'), findsWidgets);
    expect(unstyledTexts(), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
