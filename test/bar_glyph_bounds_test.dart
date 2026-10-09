import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/bar_items.dart';
import 'package:morph/src/widgets/bar_glyph_filter.dart';
import 'package:morph/widgets.dart';

void main() {
  for (final batch in [false, true]) {
    for (final direction in TextDirection.values) {
      testWidgets(
        '${batch ? 'batched' : 'bounded'} glyphs preserve $direction placement and hit boxes',
        (tester) async {
          final previous = MorphBarItems.debugBoundedGlyphFilters;
          final previousBatch = MorphBarItems.debugBatchGlyphFilters;
          addTearDown(() {
            MorphBarItems.debugBoundedGlyphFilters = previous;
            MorphBarItems.debugBatchGlyphFilters = previousBatch;
          });
          var taps = 0;
          late StateSetter set;
          var changed = false;
          Widget app() => MaterialApp(
            home: Directionality(
              textDirection: direction,
              child: StatefulBuilder(
                builder: (context, update) {
                  set = update;
                  return Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: MorphToolbar(
                          leading: [
                            MorphBarButtonGroup([
                              MorphBarButton.back(
                                id: 'back',
                                label: 'Inbox',
                                onPressed: () => taps++,
                              ),
                            ], id: 'leading'),
                          ],
                          trailing: [
                            MorphBarButtonGroup([
                              MorphBarButton(
                                id: changed ? 'new' : 'edit',
                                label: changed ? 'Done' : 'Edit',
                                onPressed: () => taps++,
                              ),
                              MorphBarButton(
                                id: 'icon',
                                icon: const Icon(Icons.add),
                                semanticLabel: 'Add',
                                onPressed: () => taps++,
                              ),
                            ], id: 'trailing'),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );

          MorphBarItems.debugBoundedGlyphFilters = false;
          MorphBarItems.debugBatchGlyphFilters = false;
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          final backRect = tester.getRect(find.text('Inbox'));
          final textRect = tester.getRect(find.text('Edit'));
          final iconRect = tester.getRect(find.byIcon(Icons.add));
          final target = tester.getRect(
            find.byKey(const ValueKey<Object>('edit')),
          );

          await tester.pumpWidget(const SizedBox.shrink());
          MorphBarItems.debugBoundedGlyphFilters = !batch;
          MorphBarItems.debugBatchGlyphFilters = batch;
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          expect(tester.getRect(find.text('Inbox')), backRect);
          expect(tester.getRect(find.text('Edit')), textRect);
          expect(tester.getRect(find.byIcon(Icons.add)), iconRect);
          expect(
            tester.getRect(find.byKey(const ValueKey<Object>('edit'))),
            target,
          );
          final semantics = tester.ensureSemantics();
          expect(
            tester.getSemantics(find.text('Edit')).flagsCollection.isButton,
            isTrue,
          );
          await tester.tapAt(Offset(target.right - 1, target.center.dy));
          expect(taps, 1);
          semantics.dispose();
          await tester.pumpAndSettle();

          set(() => changed = true);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          if (batch) {
            expect(find.byType(MorphBarGlyphFilter), findsWidgets);
          } else {
            final filters = find.byType(ImageFiltered);
            expect(filters, findsWidgets);
            for (final element in filters.evaluate()) {
              final box = element.findRenderObject()! as RenderBox;
              expect(box.size.height, lessThan(MorphToolbar.capsuleHeight));
            }
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
