import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/live.dart';
import 'package:morph/widgets.dart';
import 'package:morph/motion.dart';

const _screen = Size(402, 874);

Widget _page(String title, {Widget? strip}) => MorphNavigationScaffold(
  title: title,
  slivers: [
    const SliverToBoxAdapter(child: SizedBox(height: 300)),
    if (strip != null) SliverToBoxAdapter(child: strip),
    const SliverToBoxAdapter(child: SizedBox(height: 2000)),
  ],
);

Finder _scaffold(String title) => find.byWidgetPredicate(
  (w) => w is MorphNavigationScaffold && w.title == title,
);

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

Future<void> _pump(
  WidgetTester tester, {
  bool contentPop = true,
  Widget? strip,
  BorderRadius? displayCorners,
}) async {
  tester.view.physicalSize = _screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  late BuildContext inbox;
  Widget app = MaterialApp(
    home: MorphNavigationStack(
      contentPopGestureEnabled: contentPop,
      home: Builder(
        builder: (BuildContext context) {
          inbox = context;
          return _page('Inbox');
        },
      ),
    ),
  );
  if (displayCorners != null) {
    app = MediaQuery(
      data: MediaQueryData(
        size: _screen,
        devicePixelRatio: 3,
        displayCornerRadii: displayCorners,
      ),
      child: app,
    );
  }
  await tester.pumpWidget(app);
  await _settle(tester);
  Navigator.of(inbox).push(
    MorphNavigationRoute<void>(builder: (_) => _page('Message', strip: strip)),
  );
  await _settle(tester);
  expect(tester.getTopLeft(_scaffold('Message')).dx, closeTo(0, 0.5));
}

Future<TestGesture> _drag(WidgetTester tester, Offset from, double dx) async {
  final gesture = await tester.startGesture(from);
  for (var i = 0; i < 14; i++) {
    await gesture.moveBy(Offset(dx / 14, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

/// The continuous clip of the card the page [title] sits in.
RenderMorphLiveBox _card(WidgetTester tester, String title) => tester
    .renderObjectList<RenderMorphLiveBox>(
      find.ancestor(of: _scaffold(title), matching: find.byType(MorphLiveBox)),
    )
    .firstWhere((box) => box.continuous);

/// The opacities of every dimming layer of the stack's pages now.
List<double> _dims(WidgetTester tester) => [
  for (final box in tester.renderObjectList<RenderCustomPaint>(
    find.byKey(const ValueKey<String>('morph.navigation.dim')),
  ))
    (() {
      final canvas = TestRecordingCanvas();
      box.painter!.paint(canvas, box.size);
      final draws = canvas.invocations.where(
        (i) => i.invocation.memberName == #drawRect,
      );
      return draws.isEmpty
          ? 0.0
          : (draws.single.invocation.positionalArguments[1]! as Paint).color.a;
    })(),
];

void main() {
  test('device dim samples pin the maximum and the linear cover law', () {
    // iPhone 16 Pro pages-hold20/40/60/85, black alpha 0.1.
    const samples = [
      (65.33, 0.08375),
      (145.67, 0.06376),
      (229.0, 0.04303),
      (327.33, 0.01857),
    ];
    for (final (x, alpha) in samples) {
      expect(
        MorphNavigationTuning.underDimOpacity * (1 - x / 402),
        closeTo(alpha, 1e-5),
      );
    }
  });

  testWidgets('the moving page is a card with the display corners and the '
      'page under it dims with the progress', (tester) async {
    await _pump(tester);
    expect(_card(tester, 'Message').clipOf!(), isNull);
    expect(_dims(tester), everyElement(closeTo(0, 1e-9)));

    final gesture = await _drag(tester, const Offset(4, 600), 160);
    final out = tester.getTopLeft(_scaffold('Message')).dx / _screen.width;
    expect(out, greaterThan(0.2));
    final clip = _card(tester, 'Message').clipOf!()!;
    expect(clip.tlRadiusX, MorphNavigationTuning.fallbackCardRadius);
    expect(clip.blRadiusX, MorphNavigationTuning.fallbackCardRadius);
    expect(clip.width, _screen.width);
    final dims = _dims(tester);
    final expectedDim =
        Color.getAlphaFromOpacity(
          MorphNavigationTuning.underDimOpacity * (1 - out),
        ) /
        255;
    expect(dims.reduce((a, b) => a > b ? a : b), closeTo(expectedDim, 1e-3));

    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await _settle(tester);
    expect(tester.getTopLeft(_scaffold('Message')).dx, closeTo(0, 0.5));
    expect(_card(tester, 'Message').clipOf!(), isNull);
    expect(_dims(tester), everyElement(closeTo(0, 1e-9)));
  });

  testWidgets('the card takes the corner radius the display reports', (
    tester,
  ) async {
    await _pump(tester, displayCorners: BorderRadius.circular(55));
    final gesture = await _drag(tester, const Offset(4, 600), 120);
    expect(_card(tester, 'Message').clipOf!()!.tlRadiusX, 55);
    await gesture.up();
    await _settle(tester);
  });

  group('the content back swipe', () {
    for (final angle in [29.0, 30.0]) {
      testWidgets('device content swipe at $angle degrees', (tester) async {
        await _pump(tester);
        final gesture = await tester.startGesture(const Offset(120, 700));
        final radians = angle * math.pi / 180;
        final step =
            Offset(200 * math.cos(radians), -200 * math.sin(radians)) / 30;
        for (var i = 0; i < 30; i++) {
          await gesture.moveBy(step);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 600));
        final x = tester.getTopLeft(_scaffold('Message')).dx;
        if (angle < 30) {
          expect(x, greaterThan(120));
        } else {
          expect(x, closeTo(0, 0.5));
        }
        await gesture.up();
        await _settle(tester);
        expect(
          _scaffold('Message'),
          angle < 30 ? findsNothing : findsOneWidget,
        );
      });
    }

    testWidgets('a drag toward the trailing side from inside the page pops '
        'it', (tester) async {
      await _pump(tester);
      final gesture = await _drag(tester, const Offset(150, 700), 200);
      expect(
        tester.getTopLeft(_scaffold('Message')).dx,
        inInclusiveRange(140, 201),
      );
      await gesture.up();
      await _settle(tester);
      expect(_scaffold('Message'), findsNothing);
    });

    testWidgets('a drag toward the leading side does nothing', (tester) async {
      await _pump(tester);
      final gesture = await _drag(tester, const Offset(300, 700), -160);
      expect(tester.getTopLeft(_scaffold('Message')).dx, closeTo(0, 0.5));
      await gesture.up();
      await _settle(tester);
      expect(_scaffold('Message'), findsOneWidget);
    });

    testWidgets('off, only the edge pops', (tester) async {
      await _pump(tester, contentPop: false);
      final gesture = await _drag(tester, const Offset(150, 700), 200);
      expect(tester.getTopLeft(_scaffold('Message')).dx, closeTo(0, 0.5));
      await gesture.up();
      await _settle(tester);
      expect(_scaffold('Message'), findsOneWidget);
      final edge = await _drag(tester, const Offset(4, 700), 200);
      await edge.up();
      await _settle(tester);
      expect(_scaffold('Message'), findsNothing);
    });

    testWidgets('a horizontal scrollable under the finger keeps its drag', (
      tester,
    ) async {
      final controller = ScrollController(initialScrollOffset: 300);
      addTearDown(controller.dispose);
      await _pump(
        tester,
        strip: SizedBox(
          height: 200,
          child: ListView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < 9; i++)
                const SizedBox(
                  width: 134,
                  child: ColoredBox(color: Color(0xFF808080)),
                ),
            ],
          ),
        ),
      );
      final strip = tester.getCenter(find.byType(ListView));
      final gesture = await _drag(tester, strip, 160);
      expect(tester.getTopLeft(_scaffold('Message')).dx, closeTo(0, 0.5));
      expect(controller.offset, lessThan(300));
      await gesture.up();
      await _settle(tester);
      expect(_scaffold('Message'), findsOneWidget);
    });
  });
}
