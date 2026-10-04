import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/alert.dart';
import 'package:morph/src/widgets/alert_motion.dart';

void main() {
  test('fallback arrow stays within the content corners', () {
    for (final x in [-100.0, 0.0, 400.0, 600.0]) {
      final placement = morphPlacePopover(
        size: const Size(240, 300),
        source: Rect.fromLTWH(x, 100, 20, 20),
        screen: const Size(400, 400),
      );
      final vertical =
          placement.edge == MorphPopoverArrowEdge.top ||
          placement.edge == MorphPopoverArrowEdge.bottom;
      final low = vertical ? placement.content.left : placement.content.top;
      final high = vertical
          ? placement.content.right
          : placement.content.bottom;
      expect(placement.arrowCenter, greaterThanOrEqualTo(low + 48));
      expect(placement.arrowCenter, lessThanOrEqualTo(high - 48));
      expect(placement.content.top, greaterThanOrEqualTo(0));
    }
  });

  testWidgets(
    'popover placement uses the nested navigator origin on first paint',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: 500,
              height: 400,
              child: Navigator(
                key: nav,
                onGenerateRoute: (_) => PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => const SizedBox(),
                ),
              ),
            ),
          ),
        ),
      );
      final nested = tester.getRect(find.byKey(nav));
      nav.currentState!.push<MorphAlertAction>(
        MorphAlertRoute(
          actionSheet: true,
          source: Rect.fromLTWH(nested.left + 230, nested.top + 210, 40, 30),
          actions: const [MorphAlertAction(title: 'Choose')],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final first = tester.getCenter(find.text('Choose'));
      await tester.pumpAndSettle();
      final settled = tester.getCenter(find.text('Choose'));
      expect(first.dx, closeTo(settled.dx, 1));
      expect(settled.dx, closeTo(nested.left + 250, 1));
    },
  );

  testWidgets('an action sheet rejects an unlaid-out anchor descriptively', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(
              () => showMorphActionSheet(context, anchor: context),
              throwsA(
                isA<FlutterError>().having(
                  (error) => error.message,
                  'message',
                  contains('anchor must be laid out'),
                ),
              ),
            );
            return const SizedBox();
          },
        ),
      ),
    );
  });

  testWidgets('an action sheet rejects a disposed anchor descriptively', (
    tester,
  ) async {
    late BuildContext anchor;
    late StateSetter update;
    late BuildContext page;
    var show = true;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (c, setState) {
            page = c;
            update = setState;
            return show
                ? Builder(
                    builder: (c) {
                      anchor = c;
                      return const SizedBox(width: 100, height: 40);
                    },
                  )
                : const SizedBox();
          },
        ),
      ),
    );
    update(() => show = false);
    await tester.pump();
    expect(
      () => showMorphActionSheet(page, anchor: anchor),
      throwsA(
        isA<FlutterError>().having(
          (e) => e.message,
          'message',
          contains('anchor is no longer mounted'),
        ),
      ),
    );
  });
}
