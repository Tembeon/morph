import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';

const _contentKey = Key('content');

Widget _app(void Function(BuildContext context) onPresent) => MaterialApp(
  home: Builder(
    builder: (BuildContext context) => Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 80),
          TextButton(
            onPressed: () => onPresent(context),
            child: const Text('present'),
          ),
        ],
      ),
    ),
  ),
);

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
  testWidgets('reports detent changes', (tester) async {
    final changes = <MorphSheetDetent>[];
    await tester.pumpWidget(
      _app(
        (context) => showMorphSheet<void>(
          context,
          detents: const [MorphSheetDetent.medium, MorphSheetDetent.large],
          onDetentChanged: changes.add,
          builder: _content,
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    expect(changes, isEmpty);
    MorphSheet.of(
      tester.element(find.byKey(_contentKey)),
    ).animateTo(MorphSheetDetent.large);
    await _settle(tester);
    expect(changes, [MorphSheetDetent.large]);
    await tester.drag(find.text('sheet'), const Offset(0, 250));
    await _settle(tester);
    expect(changes, [MorphSheetDetent.large, MorphSheetDetent.medium]);
  });

  testWidgets('a sheet that may not leave reports the attempt', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      _app(
        (context) => showMorphSheet<void>(
          context,
          detents: const [MorphSheetDetent.medium],
          dismissible: false,
          onDismissAttempt: () => attempts++,
          builder: _content,
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    await tester.fling(find.text('sheet'), const Offset(0, 400), 3000);
    await _settle(tester);
    expect(attempts, 1);
    await tester.tapAt(const Offset(400, 40));
    await _settle(tester);
    expect(attempts, 2);
    expect(find.byKey(_contentKey), findsOneWidget);
  });

  testWidgets('a short refused pull is not an attempt', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      _app(
        (context) => showMorphSheet<void>(
          context,
          detents: const [MorphSheetDetent.medium],
          dismissible: false,
          onDismissAttempt: () => attempts++,
          builder: _content,
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    await tester.timedDrag(
      find.text('sheet'),
      const Offset(0, 12),
      const Duration(milliseconds: 600),
    );
    await _settle(tester);
    expect(attempts, 0);
    await tester.timedDrag(
      find.text('sheet'),
      const Offset(0, 200),
      const Duration(milliseconds: 1500),
    );
    await _settle(tester);
    expect(attempts, 1);
  });

  testWidgets('a pop scope that cannot pop also holds the drag', (
    tester,
  ) async {
    var attempts = 0;
    var invoked = 0;
    await tester.pumpWidget(
      _app(
        (context) => showMorphSheet<void>(
          context,
          detents: const [MorphSheetDetent.medium],
          onDismissAttempt: () => attempts++,
          builder: (context) => PopScope<Object?>(
            canPop: false,
            onPopInvokedWithResult: (bool didPop, Object? _) {
              if (!didPop) invoked++;
            },
            child: _content(context),
          ),
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    final rest = tester.getRect(find.byKey(_contentKey));
    await tester.fling(find.text('sheet'), const Offset(0, 400), 3000);
    await _settle(tester);
    expect(find.byKey(_contentKey), findsOneWidget);
    expect(
      tester.getRect(find.byKey(_contentKey)).top,
      moreOrLessEquals(rest.top, epsilon: 0.05),
    );
    expect(attempts, 1);
    expect(invoked, 1);
  });

  testWidgets('custom and fitted detents', (tester) async {
    await tester.pumpWidget(
      _app(
        (context) => showMorphSheet<void>(
          context,
          detents: [
            MorphSheetDetent.custom(
              (double maximum) => maximum * 0.25,
              identifier: 'quarter',
            ),
          ],
          builder: _content,
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    final quarter = tester.getRect(find.byKey(_contentKey)).height;
    Navigator.of(tester.element(find.byKey(_contentKey))).pop();
    await _settle(tester);
    await _settle(tester);
    expect(find.byKey(_contentKey), findsNothing);

    await tester.pumpWidget(
      _app(
        (context) => showMorphSheet<void>(
          context,
          detents: const [MorphSheetDetent.fitted],
          builder: (context) => const SizedBox(
            key: _contentKey,
            height: 200,
            child: Text('fitted'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('present'));
    await _settle(tester);
    final fitted = tester.getRect(find.byKey(_contentKey)).height;
    expect(quarter, greaterThan(0));
    expect(fitted, lessThan(260));
    expect(MorphSheetDetent.fitted.resolve(500, fittedHeight: 200), 200);
    expect(MorphSheetDetent.fitted.resolve(500), 500);
  });

  test('custom detents compare by identifier', () {
    double half(double m) => m / 2;
    expect(
      MorphSheetDetent.custom(half, identifier: 'a'),
      MorphSheetDetent.custom((m) => m, identifier: 'a'),
    );
    expect(
      MorphSheetDetent.custom(half, identifier: 'a'),
      isNot(MorphSheetDetent.custom(half, identifier: 'b')),
    );
    expect(MorphSheetDetent.custom(half).resolve(400), 200);
  });
}
