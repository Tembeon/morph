import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/widgets/navigation_bar.dart';
import 'package:morph/src/widgets/scroll_indicator.dart';

const _screen = Size(402, 874);

Future<void> _setScreen(WidgetTester tester) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Widget _app(Widget home) =>
    MaterialApp(debugShowCheckedModeBanner: false, home: Material(child: home));

Widget _page({
  bool large = false,
  bool hidden = false,
  Widget? over,
  ScrollController? controller,
}) {
  final scaffold = MorphNavigationScaffold(
    title: 'Inbox',
    largeTitleDisplayMode: large ? .always : .never,
    navigationBarHidden: hidden,
    controller: controller,
    trailing: [
      MorphBarButtonGroup([
        MorphBarButton(id: 'add', label: 'Add', onPressed: () {}),
      ]),
    ],
    slivers: [
      SliverList.list(
        children: [
          for (var i = 0; i < 60; i++)
            SizedBox(height: 44, child: Text('Row $i')),
        ],
      ),
    ],
  );
  if (over == null) return scaffold;
  return Stack(
    children: [
      Positioned.fill(child: scaffold),
      over,
    ],
  );
}

double _rowTop(WidgetTester tester) => tester.getTopLeft(find.text('Row 0')).dy;

double _buttonTop(WidgetTester tester) =>
    tester.getTopLeft(find.text('Add')).dy;

List<RecordedInvocation> _indicatorPaint(WidgetTester tester) {
  final render = tester.renderObject<RenderCustomPaint>(
    find.descendant(
      of: find.byType(MorphScrollIndicator),
      matching: find.byType(CustomPaint),
    ),
  );
  final canvas = TestRecordingCanvas();
  render.painter!.paint(canvas, render.size);
  return [
    for (final i in canvas.invocations)
      if (i.invocation.memberName == #drawRRect) i,
  ];
}

void main() {
  testWidgets('a hidden bar slides away and the content moves up', (
    WidgetTester tester,
  ) async {
    await _setScreen(tester);
    late BuildContext below;
    final over = Builder(
      builder: (BuildContext context) {
        below = context;
        return const SizedBox.shrink();
      },
    );
    await tester.pumpWidget(_app(_page(over: over)));
    await tester.pumpAndSettle();
    final row = _rowTop(tester);
    final button = _buttonTop(tester);
    expect(row, closeTo(116, 1));

    MorphNavigationScaffold.setNavigationBarHidden(below, hidden: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = _rowTop(tester);
    expect(mid, lessThan(row));
    expect(mid, greaterThan(row - MorphNavigationBarMetrics.barHeight));
    await tester.pumpAndSettle();
    expect(
      _rowTop(tester),
      closeTo(row - MorphNavigationBarMetrics.barHeight, 0.5),
    );
    expect(_buttonTop(tester), lessThan(0));
    expect(button, greaterThan(0));

    MorphNavigationScaffold.setNavigationBarHidden(below, hidden: false);
    await tester.pumpAndSettle();
    expect(_rowTop(tester), closeTo(row, 0.5));
    expect(_buttonTop(tester), closeTo(button, 0.5));
  });

  testWidgets('hiding keeps the scroll position', (WidgetTester tester) async {
    await _setScreen(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_page(controller: controller)));
    await tester.pumpAndSettle();
    controller.jumpTo(300);
    await tester.pump();
    final row = tester.getTopLeft(find.text('Row 12')).dy;
    await tester.pumpWidget(_app(_page(controller: controller, hidden: true)));
    await tester.pumpAndSettle();
    expect(controller.offset, 300);
    expect(
      tester.getTopLeft(find.text('Row 12')).dy,
      closeTo(row - MorphNavigationBarMetrics.barHeight, 0.5),
    );
    await tester.pumpWidget(_app(_page(controller: controller)));
    await tester.pumpAndSettle();
    expect(controller.offset, 300);
    expect(tester.getTopLeft(find.text('Row 12')).dy, closeTo(row, 0.5));
  });

  testWidgets('a large title rides up with the content and fades', (
    WidgetTester tester,
  ) async {
    await _setScreen(tester);
    await tester.pumpWidget(_app(_page(large: true)));
    await tester.pumpAndSettle();
    final row = _rowTop(tester);
    await tester.pumpWidget(_app(_page(large: true, hidden: true)));
    await tester.pumpAndSettle();
    expect(
      _rowTop(tester),
      closeTo(
        row -
            MorphNavigationBarMetrics.barHeight -
            MorphNavigationBarMetrics.largeTitleHeight,
        0.5,
      ),
    );
    RenderObject? node = tester.renderObject(find.byType(MorphLargeTitle));
    while (node != null && node is! RenderOpacity) {
      node = node.parent;
    }
    expect((node! as RenderOpacity).opacity, 0);
  });

  testWidgets(
    'focusing the search toolbar hides the bar, closing it shows it',
    (WidgetTester tester) async {
      await _setScreen(tester);
      await tester.pumpWidget(
        _app(_page(over: const Positioned.fill(child: MorphSearchToolbar()))),
      );
      await tester.pumpAndSettle();
      final row = _rowTop(tester);
      await tester.tap(find.byType(EditableText));
      await tester.pumpAndSettle();
      expect(
        _rowTop(tester),
        closeTo(row - MorphNavigationBarMetrics.barHeight, 0.5),
      );
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(_rowTop(tester), closeTo(row, 0.5));
    },
  );

  testWidgets('a toolbar told not to keeps the bar', (
    WidgetTester tester,
  ) async {
    await _setScreen(tester);
    await tester.pumpWidget(
      _app(
        _page(
          over: const Positioned.fill(
            child: MorphSearchToolbar(
              hidesNavigationBarDuringPresentation: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = _rowTop(tester);
    await tester.tap(find.byType(EditableText));
    await tester.pumpAndSettle();
    expect(_rowTop(tester), row);
  });

  group('scroll indicator', () {
    test('the frame follows the offset and shortens past an end', () {
      final top = morphScrollIndicatorFrame(
        track: 700,
        visible: 700,
        content: 7000,
        offset: 0,
      )!;
      expect(top.top, 0);
      expect(top.length, 70);
      final end = morphScrollIndicatorFrame(
        track: 700,
        visible: 700,
        content: 7000,
        offset: 6300,
      )!;
      expect(end.top + end.length, 700);
      final pulled = morphScrollIndicatorFrame(
        track: 700,
        visible: 700,
        content: 7000,
        offset: -40,
      )!;
      expect(pulled.top, 0);
      expect(pulled.length, 30);
      expect(
        morphScrollIndicatorFrame(
          track: 700,
          visible: 700,
          content: 600,
          offset: 0,
        ),
        isNull,
      );
    });

    testWidgets('shows while scrolling and fades 1.07 s after rest', (
      WidgetTester tester,
    ) async {
      await _setScreen(tester);
      await tester.pumpWidget(_app(_page()));
      await tester.pumpAndSettle();
      expect(_indicatorPaint(tester), isEmpty);
      final gesture = await tester.startGesture(const Offset(200, 600));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final shown = _indicatorPaint(tester);
      expect(shown, hasLength(1));
      final rrect = shown.single.invocation.positionalArguments.first as RRect;
      expect(rrect.width, MorphScrollIndicatorTuning.thickness);
      expect(rrect.right, _screen.width - MorphScrollIndicatorTuning.edgeInset);
      expect(rrect.top, greaterThanOrEqualTo(116 + 3 - 0.01));
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(_indicatorPaint(tester), hasLength(1));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_indicatorPaint(tester), isEmpty);
    });

    testWidgets('can be turned off', (WidgetTester tester) async {
      await _setScreen(tester);
      await tester.pumpWidget(
        _app(
          const MorphNavigationScaffold(
            title: 'Inbox',
            showsVerticalScrollIndicator: false,
            slivers: [SliverToBoxAdapter(child: SizedBox(height: 3000))],
          ),
        ),
      );
      expect(find.byType(MorphScrollIndicator), findsNothing);
    });
  });
}
