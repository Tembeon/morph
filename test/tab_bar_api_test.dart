import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

const _home = IconData(0xe318);
const _homeFilled = IconData(0xe319);

Widget _bar(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

void main() {
  testWidgets('a tap on the selected tab is reported as a reselection', (
    tester,
  ) async {
    final reselected = <int>[];
    final changed = <int>[];
    await tester.pumpWidget(
      _bar(
        MorphTabBar(
          items: const [
            MorphTabItem(icon: _home, label: 'One'),
            MorphTabItem(icon: _home, label: 'Two'),
          ],
          selected: 0,
          onChanged: changed.add,
          onReselected: reselected.add,
        ),
      ),
    );
    await tester.tap(find.text('One').first);
    await tester.pumpAndSettle();
    expect(reselected, [0]);
    expect(changed, isEmpty);
    await tester.tap(find.text('Two').first);
    await tester.pumpAndSettle();
    expect(reselected, [0]);
    expect(changed, [1]);
  });

  testWidgets('the selected icon shows inside the lens, with one crisp badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _bar(
        MorphTabBar(
          items: const [
            MorphTabItem(
              icon: _home,
              selectedIcon: _homeFilled,
              label: 'One',
              badge: MorphBadge.count(4),
            ),
            MorphTabItem(icon: _home, label: 'Two'),
          ],
          selected: 0,
          onChanged: (_) {},
        ),
      ),
    );
    final selectedGlyph = find.byWidgetPredicate(
      (w) =>
          w is RichText &&
          w.text.toPlainText() == String.fromCharCode(_homeFilled.codePoint),
    );
    expect(selectedGlyph, findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    final badge = find.text('4');
    final restSize = tester.getSize(badge);
    final held = await tester.startGesture(tester.getCenter(find.text('One')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('4'), findsOneWidget);
    expect(tester.getSize(badge), restSize);
    expect(tester.takeException(), isNull);
    await held.up();
    await tester.pumpAndSettle();
  });
}
