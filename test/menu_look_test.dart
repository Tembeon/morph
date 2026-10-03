import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

const _items = [
  MorphMenuItem(title: 'Copy', icon: Icons.copy),
  MorphMenuItem(title: 'Delete', icon: Icons.delete, destructive: true),
];

Widget _app({Brightness brightness = Brightness.light, bool rtl = false}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: const Scaffold(
        body: Center(child: MorphMenuButton(items: _items)),
      ),
    );

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byType(MorphMenuButton));
  await tester.pumpAndSettle();
}

TextStyle _titleStyle(WidgetTester tester, String title) => tester
    .widget<RichText>(
      find.descendant(
        of: find.text(title).last,
        matching: find.byType(RichText),
      ),
    )
    .text
    .style!;

void main() {
  testWidgets('menu titles do not inherit the app overlay text style', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _open(tester);
    final style = _titleStyle(tester, 'Copy');
    expect(style.decoration, isNot(TextDecoration.underline));
    expect(style.fontWeight ?? FontWeight.w400, FontWeight.w400);
    expect(style.fontSize, 17);
    expect(style.fontFamily, isNot('monospace'));
  });

  testWidgets('row glyphs lead their titles', (tester) async {
    await tester.pumpWidget(_app());
    await _open(tester);
    final icon = tester.getRect(find.byIcon(Icons.copy).last);
    final title = tester.getRect(find.text('Copy').last);
    expect(icon.right, lessThan(title.left));
    expect(title.left - icon.center.dx, moreOrLessEquals(24, epsilon: 0.5));
  });

  testWidgets('row glyphs lead their titles in RTL too', (tester) async {
    await tester.pumpWidget(_app(rtl: true));
    await _open(tester);
    final icon = tester.getRect(find.byIcon(Icons.copy).last);
    final title = tester.getRect(find.text('Copy').last);
    expect(icon.left, greaterThan(title.right));
  });

  testWidgets('a dark theme resolves the dark menu', (tester) async {
    await tester.pumpWidget(_app(brightness: Brightness.dark));
    await _open(tester);
    expect(_titleStyle(tester, 'Copy').color, const Color(0xFFFFFFFF));
    expect(
      _titleStyle(tester, 'Delete').color,
      MorphMenuStyle.dark.destructiveColor,
    );
  });

  testWidgets('the theme extension styles every menu', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            MorphWidgetsTheme(
              menu: MorphMenuStyle.light.copyWith(
                textStyle: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF123456),
                ),
              ),
            ),
          ],
        ),
        home: const Scaffold(
          body: Center(child: MorphMenuButton(items: _items)),
        ),
      ),
    );
    await _open(tester);
    expect(_titleStyle(tester, 'Copy').color, const Color(0xFF123456));
    expect(_titleStyle(tester, 'Copy').fontSize, 15);
  });
}
