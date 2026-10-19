import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';

void main() {
  testWidgets('a context menu opens with no scope installed by the app', (
    tester,
  ) async {
    var picked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MorphContextMenuRegion(
            menu: [MorphMenuItem(title: 'Copy', onSelected: () => picked++)],
            child: const SizedBox(width: 120, height: 60, child: Text('row')),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('row')),
    );
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(picked, 1);
    expect(find.text('Copy'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
