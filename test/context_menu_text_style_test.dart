import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

/// The page's text style, shorter than the default body style.
const _page = TextStyle(fontSize: 13, height: 1.3, color: Color(0xFF000000));

void main() {
  testWidgets('a tightly fitting hero keeps its text style and never '
      'overflows while its menu opens and closes', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: DefaultTextStyle(
          style: _page,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 200),
              MorphContextMenuRegion(
                onOpen: (MorphFlight f) => flight = f,
                menu: <MorphMenuEntry>[
                  MorphMenuWidget(
                    height: 100,
                    builder: (BuildContext context) =>
                        const SizedBox(height: 100),
                  ),
                ],
                // The column fills the row's height exactly: any copy
                // drawn in a taller text style overflows.
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      SizedBox(width: 36, height: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [Text('Anna'), Text('Lunch tomorrow?')],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Anna')),
    );
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull, reason: 'open, frame $i');
      for (final element in find.text('Anna').evaluate()) {
        expect(
          DefaultTextStyle.of(element).style,
          _page,
          reason: 'open, frame $i: every copy reads the page style',
        );
      }
    }
    await gesture.up();
    expect(flight, isNotNull);
    flight!.close();
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull, reason: 'close, frame $i');
    }
    expect(flight!.isFinished, isTrue);
  });
}
