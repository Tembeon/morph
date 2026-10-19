import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/list.dart';

Widget _scene(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);

void main() {
  testWidgets('the detail button calls its own callback', (tester) async {
    final semantics = tester.ensureSemantics();
    var rowTaps = 0;
    var infoTaps = 0;
    await tester.pumpWidget(
      _scene(
        ListView(
          children: [
            MorphListSection(
              children: [
                MorphListRow(
                  title: const Text('Wi-Fi'),
                  accessory: MorphListAccessory.detailDisclosureButton,
                  onTap: () => rowTaps++,
                  onAccessoryTap: () => infoTaps++,
                ),
                const MorphListRow(
                  title: Text('Chosen'),
                  accessory: MorphListAccessory.checkmark,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final info = find.bySemanticsLabel('More info');
    expect(info, findsOneWidget);
    await tester.tap(info);
    await tester.pump();
    expect(infoTaps, 1);
    expect(rowTaps, 0);
    await tester.tap(find.text('Wi-Fi'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(rowTaps, 1);
    expect(
      tester.getSemantics(find.text('Chosen')),
      matchesSemantics(
        isSelected: true,
        hasSelectedState: true,
        label: 'Chosen',
      ),
    );
    semantics.dispose();
  });

  testWidgets('a sliver section builds only the rows in view', (tester) async {
    final built = <int>{};
    await tester.pumpWidget(
      _scene(
        CustomScrollView(
          slivers: [
            MorphSliverListSection(
              header: const Text('Contacts'),
              itemCount: 1000,
              itemBuilder: (BuildContext context, int i) {
                built.add(i);
                return MorphListRow(title: Text('Row $i'));
              },
            ),
          ],
        ),
      ),
    );
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Row 0'), findsOneWidget);
    expect(built.length, lessThan(40));
    final first = tester.getRect(find.text('Row 0'));
    final second = tester.getRect(find.text('Row 1'));
    expect(second.top - first.top, closeTo(MorphListMetrics.minRowHeight, 1));
  });
}
