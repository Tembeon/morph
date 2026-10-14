import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/foundation.dart';

/// The page's text style: shorter lines than the Material body style the
/// flight's shuttle sets for its content.
const _page = TextStyle(fontSize: 13, height: 1.3, color: Color(0xFF000000));

/// One line of [_page] text, rounded up.
const double _line = 17;

void main() {
  testWidgets('a button label morphing into a dialog keeps the page text '
      'style and never overflows', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: DefaultTextStyle(
          style: _page,
          child: Center(
            child: MorphTag(
              id: 'button',
              child: Builder(
                builder: (BuildContext context) => GestureDetector(
                  onTap: () => flight = showMorphDialogFlight(
                    context,
                    from: 'button',
                    width: 400,
                    height: 300,
                    builder: (BuildContext context, MorphFlight flight) =>
                        const Center(
                          child: MorphSharedElement(
                            id: 'title',
                            child: Text('Title'),
                          ),
                        ),
                  ),
                  // Every column fills its box exactly in the page style:
                  // a copy drawn in a taller style overflows.
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MorphSharedElement(
                          id: 'title',
                          child: SizedBox(
                            width: 120,
                            height: _line,
                            child: Column(children: [Text('Title')]),
                          ),
                        ),
                        Text('Label'),
                        Text('Second line'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Label'));
    var copies = 0;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull, reason: 'open, frame $i');
      for (final element in find.text('Label').evaluate()) {
        copies++;
        expect(
          DefaultTextStyle.of(element).style,
          _page,
          reason: 'open, frame $i: the source copy keeps the page style',
        );
      }
    }
    expect(copies, greaterThan(120), reason: 'the source flew as a copy');
    flight!.close();
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 8));
      expect(tester.takeException(), isNull, reason: 'close, frame $i');
      for (final element in find.text('Label').evaluate()) {
        expect(DefaultTextStyle.of(element).style, _page);
      }
    }
  });

  testWidgets('source copies follow a text style change and keep it after '
      'the source leaves the tree', (WidgetTester tester) async {
    final stage = ValueNotifier<int>(0);
    addTearDown(stage.dispose);
    const changed = TextStyle(fontSize: 12, color: Color(0xFF008800));
    MorphFlight? flight;
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: ValueListenableBuilder<int>(
          valueListenable: stage,
          builder: (BuildContext context, int value, Widget? child) =>
              value == 2
              ? const SizedBox.shrink()
              : DefaultTextStyle(
                  style: value == 0 ? _page : changed,
                  child: Center(
                    child: MorphTag(
                      id: 'button',
                      child: Builder(
                        builder: (BuildContext context) => GestureDetector(
                          onTap: () => flight = showMorphDialogFlight(
                            context,
                            from: 'button',
                            width: 300,
                            height: 200,
                            builder:
                                (BuildContext context, MorphFlight flight) =>
                                    const Text('Target'),
                          ),
                          child: const SizedBox(
                            width: 120,
                            height: 40,
                            child: Text('Source'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
    await tester.tap(find.text('Source'));
    await tester.pumpAndSettle();
    stage.value = 1;
    await tester.pump();
    await tester.pump();
    for (final element in find.text('Source').evaluate()) {
      expect(DefaultTextStyle.of(element).style, changed);
    }
    expect(
      DefaultTextStyle.of(tester.element(find.text('Target'))).style,
      isNot(changed),
      reason: 'the target still uses its own Material text style',
    );
    stage.value = 2;
    await tester.pump();
    flight!.markNeedsBuild();
    await tester.pump();
    expect(flight!.isSourceLost, isTrue);
    expect(find.text('Source'), findsOneWidget);
    expect(
      DefaultTextStyle.of(tester.element(find.text('Source'))).style,
      changed,
    );
    flight!.close();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
