import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/morph.dart';

void main() {
  setUpAll(() => isLocalTest = true);

  testWidgets(
    'controlled toolbar search restores the shared bar from a parent rebuild',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 62 * 3);
      addTearDown(tester.view.reset);
      final active = ValueNotifier<bool>(false);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MorphNavigationStack(
            home: ValueListenableBuilder<bool>(
              valueListenable: active,
              builder: (context, searching, child) => Stack(
                children: [
                  const Positioned.fill(
                    child: MorphNavigationScaffold(
                      title: 'Inbox',
                      slivers: [SliverToBoxAdapter(child: Text('Content'))],
                    ),
                  ),
                  Positioned.fill(child: MorphSearchToolbar(active: searching)),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      active.value = true;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.text('Content')).dy, closeTo(62, 0.5));
      active.value = false;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.text('Content')).dy, closeTo(116, 0.5));
    },
  );

  testWidgets('a stacked search keeps its controller text visible at rest', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Saved query');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MorphNavigationScaffold(
          title: 'Search',
          search: MorphNavigationSearch(controller: controller),
          slivers: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(MorphSearchField).first,
        matching: find.text('Saved query'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'right-to-left stacked search puts the close button at the trailing edge',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 62 * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MorphNavigationScaffold(
              title: 'Search',
              largeTitleDisplayMode: MorphLargeTitleDisplayMode.always,
              search: MorphNavigationSearch(),
              slivers: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(201, 190));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.bySemanticsLabel('Close')),
        rectMoreOrLessEquals(
          const Rect.fromLTWH(16, 62, 44, 44),
          epsilon: 0.01,
        ),
      );
      expect(
        tester.getRect(find.byType(MorphSearchField).last),
        rectMoreOrLessEquals(
          const Rect.fromLTRB(70, 62, 386, 106),
          epsilon: 0.01,
        ),
      );
    },
  );
}
