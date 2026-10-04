import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/scope.dart';
import 'package:morph/src/widgets/navigation_stack.dart';
import 'package:morph/src/widgets/sheet.dart';
import 'package:morph/src/widgets/sheet_motion.dart';

void main() {
  for (final sheet in [true, false]) {
    for (final kind in ['missing', 'empty', 'direct']) {
      testWidgets('${sheet ? 'sheet' : 'page'} accepts a $kind source id', (
        tester,
      ) async {
        final nav = GlobalKey<NavigatorState>();
        late BuildContext context;
        await tester.pumpWidget(
          MorphScope(
            child: MaterialApp(
              navigatorKey: nav,
              home: Builder(
                builder: (c) {
                  context = c;
                  return Center(
                    child: MorphTag(
                      id: 'source',
                      child: SizedBox(
                        width: kind == 'empty' ? 0 : 100,
                        height: kind == 'empty' ? 0 : 80,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        final id = kind == 'missing' ? 'unknown' : 'source';
        final Future<void> result;
        if (kind == 'direct') {
          result = nav.currentState!.push<void>(
            sheet
                ? MorphSheetRoute<void>(
                    source: id,
                    detents: const [MorphSheetDetent.medium],
                    builder: (_) => const Text('content'),
                  )
                : MorphNavigationRoute<void>(
                    zoomSource: id,
                    builder: (_) =>
                        const SizedBox.expand(child: Text('content')),
                  ),
          );
        } else if (sheet) {
          result = presentMorphSheet<void>(
            context,
            from: id,
            detents: const [MorphSheetDetent.medium],
            builder: (_) => const Text('content'),
          );
        } else {
          result = pushMorphZoom<void>(
            context,
            from: id,
            builder: (_) => const SizedBox.expand(child: Text('content')),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('content'), findsOneWidget);
        expect(tester.takeException(), isNull);
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        await result;
        expect(find.text('content'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
