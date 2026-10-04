import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  TextDirection direction = TextDirection.ltr,
  MorphWidgetsTheme? theme,
}) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness, extensions: [?theme]),
      home: Directionality(
        textDirection: direction,
        child: Align(alignment: Alignment.topCenter, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('rows and the card sit at the measured UIKit insets', (
    tester,
  ) async {
    await _pump(
      tester,
      MorphListSection(
        header: 'Controls',
        footer: 'A footer.',
        children: [
          MorphListRow(
            key: const Key('plain'),
            title: const Text('Segmented control'),
            chevron: true,
            onTap: () {},
          ),
          const MorphListRow(
            key: Key('subtitle'),
            title: Text('Tab bar'),
            subtitle: Text('Floating'),
          ),
          const MorphListRow(
            key: Key('value'),
            title: Text('Width'),
            detail: Text('94'),
          ),
          const MorphListRow(
            key: Key('icon'),
            title: Text('Settings'),
            leading: Icon(Icons.settings),
            chevron: true,
          ),
          MorphListRow(
            key: const Key('switch'),
            title: const Text('Loupe'),
            trailing: MorphSwitch(value: true, onChanged: (_) {}),
          ),
        ],
      ),
    );
    final plain = tester.getRect(find.byKey(const Key('plain')));
    expect(plain.left, MorphListMetrics.sectionInset);
    expect(plain.right, 402 - MorphListMetrics.sectionInset);
    expect(plain.height, MorphListMetrics.minRowHeight);
    expect(tester.getRect(find.text('Segmented control')).left, 36);
    expect(
      tester.getRect(find.byKey(const Key('subtitle'))).height,
      moreOrLessEquals(17 + 15 + 2 * MorphListMetrics.rowPadding),
    );
    expect(tester.getRect(find.text('94')).right, 382 - 16);
    expect(tester.getRect(find.text('Settings')).left, 76);
    expect(tester.getCenter(find.byIcon(Icons.settings)).dx, 48);
    expect(tester.getRect(find.byType(MorphSwitch)).right, 362);
    final header = tester.getRect(find.text('Controls'));
    expect(header.left, 36);
    expect(plain.top - header.bottom, MorphListMetrics.headerBottom);
    final footer = tester.getRect(find.text('A footer.'));
    final last = tester.getRect(find.byKey(const Key('switch')));
    expect(
      footer.top - last.bottom,
      moreOrLessEquals(MorphListMetrics.footerTop),
    );
    final chevrons = find.descendant(
      of: find.byKey(const Key('plain')),
      matching: find.byType(CustomPaint),
    );
    expect(
      tester
          .renderObjectList<RenderBox>(chevrons)
          .any(
            (RenderBox box) =>
                box.size == MorphListMetrics.chevronSize &&
                box.localToGlobal(box.size.bottomRight(Offset.zero)).dx == 362,
          ),
      isTrue,
    );
  });

  testWidgets('a tapped row highlights while pressed and calls back', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      MorphListSection(
        children: [
          MorphListRow(title: const Text('Row'), onTap: () => taps++),
          const MorphListRow(title: Text('Inert')),
        ],
      ),
    );
    Color? fill(String text) {
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(of: find.text(text), matching: find.byType(DecoratedBox))
            .first,
      );
      return (box.decoration as BoxDecoration).color;
    }

    expect(fill('Row'), isNull);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Row')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(fill('Row'), MorphListStyle.light.highlightColor);
    await gesture.up();
    await tester.pump();
    expect(fill('Row'), isNull);
    expect(taps, 1);
    await tester.tap(find.text('Inert'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(fill('Inert'), isNull);
  });

  testWidgets('a disabled row ignores taps; Enter taps a focused row', (
    tester,
  ) async {
    var taps = 0;
    await _pump(
      tester,
      MorphListSection(
        children: [
          MorphListRow(
            title: const Text('Off'),
            enabled: false,
            onTap: () => taps++,
          ),
          MorphListRow(title: const Text('On'), onTap: () => taps++),
        ],
      ),
    );
    await tester.tap(find.text('Off'));
    expect(taps, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
    final semantics = tester.getSemantics(find.text('On'));
    expect(semantics.flagsCollection.isButton, isTrue);
  });

  testWidgets('right to left mirrors the row', (tester) async {
    await _pump(
      tester,
      const MorphListSection(
        children: [
          MorphListRow(
            title: Text('Title'),
            detail: Text('Value'),
            chevron: true,
          ),
        ],
      ),
      direction: TextDirection.rtl,
    );
    expect(tester.getRect(find.text('Title')).right, 402 - 36);
    expect(tester.getRect(find.text('Value')).left, 20 + 20 + 10.33 + 8);
  });

  testWidgets('the separator runs under every row but the last', (
    tester,
  ) async {
    await _pump(
      tester,
      const MorphListSection(
        children: [
          MorphListRow(title: Text('A')),
          MorphListRow(title: Text('B')),
          MorphListRow(title: Text('C')),
        ],
      ),
    );
    final painted = find.descendant(
      of: find.byType(MorphListSection),
      matching: find.byWidgetPredicate(
        (Widget w) => w is CustomPaint && w.foregroundPainter != null,
      ),
    );
    expect(painted, findsNWidgets(2));
  });

  testWidgets('dark and themed looks resolve', (tester) async {
    await _pump(
      tester,
      const MorphListSection(children: [MorphListRow(title: Text('A'))]),
      brightness: Brightness.dark,
    );
    expect(
      tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byType(MorphListSection),
              matching: find.byType(ColoredBox),
            ),
          )
          .color,
      MorphListStyle.dark.cellColor,
    );
    expect(
      tester
          .widget<RichText>(
            find.descendant(
              of: find.text('A'),
              matching: find.byType(RichText),
            ),
          )
          .text
          .style
          ?.color,
      MorphListStyle.dark.titleColor,
    );
    const custom = MorphListStyle(cellColor: Color(0xFF123456));
    await _pump(
      tester,
      const MorphListSection(children: [MorphListRow(title: Text('A'))]),
      theme: const MorphWidgetsTheme(list: custom),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byType(MorphListSection),
              matching: find.byType(ColoredBox),
            ),
          )
          .color,
      const Color(0xFF123456),
    );
  });

  testWidgets('a scaffold gives its content the body text style', (
    tester,
  ) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (BuildContext context, Widget? _) => const MediaQuery(
          data: MediaQueryData(size: Size(402, 874)),
          child: MorphNavigationScaffold(
            title: 'Page',
            slivers: [SliverToBoxAdapter(child: Text('Body'))],
          ),
        ),
      ),
    );
    final style = tester
        .widget<RichText>(
          find.descendant(
            of: find.text('Body'),
            matching: find.byType(RichText),
          ),
        )
        .text
        .style!;
    expect(style.fontSize, 17);
    expect(style.decoration, isNot(TextDecoration.underline));
    expect(style.color, MorphBarStyle.light.titleColor);
  });
}
