import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/foundation.dart';

class _SubscriptionCounter extends ChangeNotifier {
  int subscriptions = 0;

  @override
  void addListener(VoidCallback listener) {
    subscriptions++;
    super.addListener(listener);
  }
}

void main() {
  testWidgets(
    'MediaQuery updates preserve frame subscriptions and content state',
    (WidgetTester tester) async {
      final ValueNotifier<MediaQueryData> mediaQuery =
          ValueNotifier<MediaQueryData>(
            const MediaQueryData(size: Size(800, 600)),
          );
      final _SubscriptionCounter repaint = _SubscriptionCounter();
      addTearDown(mediaQuery.dispose);
      addTearDown(repaint.dispose);
      late BuildContext sourceContext;
      final GlobalKey fieldKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          builder: (BuildContext context, Widget? child) =>
              ValueListenableBuilder<MediaQueryData>(
                valueListenable: mediaQuery,
                builder:
                    (
                      BuildContext context,
                      MediaQueryData data,
                      Widget? child,
                    ) => MediaQuery(data: data, child: child!),
                child: MorphScope(child: child!),
              ),
          home: Scaffold(
            body: MorphTag(
              id: 'source',
              replica: const Text('replica'),
              child: Builder(
                builder: (BuildContext context) {
                  sourceContext = context;
                  return const Text('source');
                },
              ),
            ),
          ),
        ),
      );
      final MorphFlight flight = showMorph(
        sourceContext,
        target: MorphTargetSpec(
          rectFor: (Size size, EdgeInsets padding) =>
              const Rect.fromLTWH(100, 100, 300, 200),
          repaint: repaint,
        ),
        builder: (BuildContext context, MorphFlight flight) =>
            TextField(key: fieldKey),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(fieldKey), 'preserved');
      final State<StatefulWidget> state = tester.state(find.byKey(fieldKey));
      final int subscriptions = repaint.subscriptions;
      for (int i = 1; i <= 5; i++) {
        mediaQuery.value = mediaQuery.value.copyWith(
          viewInsets: EdgeInsets.only(bottom: i * 10),
          textScaler: TextScaler.linear(1 + i * 0.1),
        );
        await tester.pump();
        expect(repaint.subscriptions, subscriptions);
        expect(
          tester.state<State<StatefulWidget>>(find.byKey(fieldKey)),
          same(state),
        );
        expect(find.text('preserved'), findsOneWidget);
      }
      flight.close();
      await tester.pumpAndSettle();
    },
  );
}
