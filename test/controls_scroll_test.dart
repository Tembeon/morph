import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

class _State {
  bool switchOn = false;
  int segment = 0;
  int tab = 0;
  int taps = 0;
  int holds = 0;
  double stepper = 5;
  double slider = 0.5;
  final List<String> picked = [];
}

const _tabs = [
  MorphTabItem(icon: IconData(0xe318), label: 'One'),
  MorphTabItem(icon: IconData(0xe318), label: 'Two'),
  MorphTabItem(icon: IconData(0xe318), label: 'Three'),
];

List<Widget> _controls(_State s, StateSetter setState) => [
  Center(
    child: MorphSwitch(
      value: s.switchOn,
      onChanged: (bool v) => setState(() => s.switchOn = v),
    ),
  ),
  const SizedBox(height: 40),
  SizedBox(
    width: 300,
    child: MorphSegmentedControl(
      segments: const ['A', 'B'],
      selected: s.segment,
      onChanged: (int v) => setState(() => s.segment = v),
    ),
  ),
  const SizedBox(height: 40),
  Center(
    child: MorphGlassButton(onPressed: () => s.taps++, child: const Text('Go')),
  ),
  const SizedBox(height: 40),
  Center(
    child: MorphStepper(
      value: s.stepper,
      onChanged: (double v) => setState(() => s.stepper = v),
    ),
  ),
  const SizedBox(height: 40),
  Center(
    child: SizedBox(
      width: 300,
      child: MorphSlider(
        value: s.slider,
        onChanged: (double v) => setState(() => s.slider = v),
      ),
    ),
  ),
  const SizedBox(height: 40),
  Center(
    child: SizedBox(
      width: 360,
      child: MorphTabBar(
        items: _tabs,
        selected: s.tab,
        onChanged: (int v) => setState(() => s.tab = v),
      ),
    ),
  ),
  const SizedBox(height: 40),
  Center(
    child: MorphMenuButton(
      items: [
        for (final title in const ['Copy', 'Share', 'Rename'])
          MorphMenuItem(title: title, onSelected: () => s.picked.add(title)),
      ],
    ),
  ),
  const SizedBox(height: 40),
  Center(
    child: MorphContextMenuRegion(
      onHold: () => s.holds++,
      below: MorphSatellite(
        height: 40,
        builder: (BuildContext context, MorphFlight flight) =>
            const Text('reply'),
      ),
      child: const SizedBox(
        width: 160,
        height: 48,
        child: ColoredBox(color: Color(0xFF334455), child: Text('hero')),
      ),
    ),
  ),
];

Future<_State> _pump(WidgetTester tester, {Axis axis = .vertical}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = _State();
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF007AFF),
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(
            settings: settings,
            pageBuilder:
                (
                  BuildContext context,
                  Animation<double> animation,
                  Animation<double> secondaryAnimation,
                ) => builder(context),
          ),
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => switch (axis) {
          Axis.vertical => ListView(
            children: [
              const SizedBox(height: 60),
              ..._controls(state, setState),
              const SizedBox(height: 1200),
            ],
          ),
          Axis.horizontal => ListView(
            scrollDirection: .horizontal,
            children: [
              const SizedBox(width: 20),
              SizedBox(
                width: 380,
                child: Column(children: _controls(state, setState)),
              ),
              const SizedBox(width: 1200),
            ],
          ),
        },
      ),
    ),
  );
  return state;
}

double _offset(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;

/// Drags from [at] by [step] on each of [count] frames, after holding
/// still for [hold].
Future<TestGesture> _drag(
  WidgetTester tester,
  Offset at,
  Offset step, {
  int count = 10,
  Duration hold = Duration.zero,
}) async {
  final gesture = await tester.startGesture(at);
  await tester.pump();
  if (hold > Duration.zero) await tester.pump(hold);
  for (var i = 0; i < count; i++) {
    await gesture.moveBy(step);
    await tester.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

Future<void> _scrollHome(WidgetTester tester) async {
  tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
}

Offset _thumb(WidgetTester tester) {
  final slider = tester.getRect(find.byType(MorphSlider));
  return Offset(
    slider.left + 18.5 + 0.5 * (slider.width - 37),
    slider.center.dy,
  );
}

Finder get _glassSurface => find
    .descendant(
      of: find.byType(MorphGlassButton),
      matching: find.byType(CustomPaint),
    )
    .first;

void main() {
  group('inside a vertical list', () {
    testWidgets('a quick vertical swipe scrolls and leaves the controls be', (
      tester,
    ) async {
      final s = await _pump(tester);
      final probes = <(Finder, Offset Function(Rect))>[
        (
          find.byType(MorphSwitch),
          (Rect r) => r.centerLeft + const Offset(12, 0),
        ),
        (
          find.byType(MorphSegmentedControl),
          (Rect r) => r.centerRight - const Offset(40, 0),
        ),
        (find.byType(MorphGlassButton), (Rect r) => r.center),
        (
          find.byType(MorphStepper),
          (Rect r) => r.centerRight - const Offset(20, 0),
        ),
        (find.byType(MorphSlider), (Rect r) => _thumb(tester)),
        (
          find.byType(MorphTabBar),
          (Rect r) => tester.getCenter(find.text('One')),
        ),
        (find.byType(MorphMenuButton), (Rect r) => r.center),
        (find.byType(MorphContextMenuRegion), (Rect r) => r.center),
      ];
      for (final (finder, point) in probes) {
        final before = tester.getRect(finder);
        final gesture = await _drag(tester, point(before), const Offset(0, -6));
        expect(tester.getRect(finder).top, lessThan(before.top - 30));
        await gesture.up();
        await tester.pumpAndSettle();
        await _scrollHome(tester);
      }
      expect(s.switchOn, isFalse);
      expect(s.segment, 0);
      expect(s.tab, 0);
      expect(s.taps, 0);
      expect(s.stepper, 5);
      expect(s.slider, 0.5);
      expect(s.holds, 0);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('taps still land', (tester) async {
      final s = await _pump(tester);
      await tester.tap(find.byType(MorphSwitch));
      await tester.pumpAndSettle();
      expect(s.switchOn, isTrue);
      await tester.tap(find.byType(MorphGlassButton));
      await tester.pumpAndSettle();
      expect(s.taps, 1);
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      expect(s.segment, 1);
    });

    testWidgets('a horizontal slider drag is the slider\'s, not the list\'s', (
      tester,
    ) async {
      final s = await _pump(tester);
      final gesture = await _drag(tester, _thumb(tester), const Offset(8, -3));
      expect(_offset(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(s.slider, greaterThan(0.7));
      expect(_offset(tester), 0);
    });

    testWidgets('a vertical swipe on the slider scrolls and cancels it', (
      tester,
    ) async {
      final s = await _pump(tester);
      final gesture = await _drag(tester, _thumb(tester), const Offset(1, -8));
      expect(_offset(tester), greaterThan(30));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(s.slider, 0.5);
    });

    testWidgets('a held glass button keeps its touch when the finger moves', (
      tester,
    ) async {
      final s = await _pump(tester);
      final rest = tester.getRect(_glassSurface);
      final gesture = await _drag(
        tester,
        rest.center,
        const Offset(0, -12),
        count: 14,
        hold: const Duration(milliseconds: 200),
      );
      expect(_offset(tester), 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(_glassSurface).width, greaterThan(rest.width + 4));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(s.taps, 0, reason: 'released far outside the button');
      expect(_offset(tester), 0);
      expect(
        tester.getRect(_glassSurface).width,
        moreOrLessEquals(rest.width, epsilon: 0.5),
      );
    });

    testWidgets('a pressed glass button lets go when a quick swipe scrolls', (
      tester,
    ) async {
      await _pump(tester);
      final rest = tester.getRect(_glassSurface);
      final gesture = await _drag(tester, rest.center, const Offset(0, -6));
      await tester.pumpAndSettle();
      expect(_offset(tester), greaterThan(30));
      expect(
        tester.getRect(_glassSurface).width,
        moreOrLessEquals(rest.width, epsilon: 0.5),
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a switch drag toggles it and the list stays', (tester) async {
      final s = await _pump(tester);
      final track = tester.getRect(find.byType(MorphSwitch));
      final gesture = await _drag(
        tester,
        track.centerLeft + const Offset(12, 0),
        const Offset(5, 2),
        count: 8,
      );
      expect(_offset(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(s.switchOn, isTrue);
      expect(_offset(tester), 0);
    });

    testWidgets('a segmented scrub selects and the list stays', (tester) async {
      final s = await _pump(tester);
      final from = tester.getCenter(find.text('A'));
      final to = tester.getCenter(find.text('B'));
      final gesture = await _drag(
        tester,
        from,
        Offset((to.dx - from.dx) / 10, 2),
      );
      expect(_offset(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(s.segment, 1);
      expect(_offset(tester), 0);
    });

    testWidgets('a tab bar scrub selects and the list stays', (tester) async {
      final s = await _pump(tester);
      final from = tester.getCenter(find.text('One'));
      final to = tester.getCenter(find.text('Three'));
      final gesture = await _drag(
        tester,
        from,
        Offset((to.dx - from.dx) / 10, 2),
      );
      expect(_offset(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(s.tab, 2);
      expect(_offset(tester), 0);
    });

    testWidgets('a held stepper repeats and the list never takes it', (
      tester,
    ) async {
      final s = await _pump(tester);
      final stepper = tester.getRect(find.byType(MorphStepper));
      final gesture = await tester.startGesture(
        stepper.centerRight - const Offset(20, 0),
      );
      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(s.stepper, 7);
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, -8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_offset(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(s.stepper, 7);
      expect(_offset(tester), 0);
    });

    testWidgets('a menu button hold slides onto a row and the list stays', (
      tester,
    ) async {
      final s = await _pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MorphMenuButton)),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Rename'), findsOneWidget);
      final from = tester.getCenter(find.byType(MorphMenuButton));
      final to = tester.getCenter(find.text('Rename'));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy((to - from) / 8);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_offset(tester), 0);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 20));
      expect(s.picked, ['Rename']);
      await tester.pumpAndSettle();
      expect(_offset(tester), 0);
    });

    testWidgets('a held context menu region opens and the list stays', (
      tester,
    ) async {
      final s = await _pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('hero')),
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(s.holds, 1);
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, -10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_offset(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('reply'), findsOneWidget);
    });

    testWidgets('a context menu press that wanders after the delay keeps the '
        'list still and never opens', (tester) async {
      final s = await _pump(tester);
      final gesture = await _drag(
        tester,
        tester.getCenter(find.text('hero')),
        const Offset(0, -10),
        count: 6,
        hold: const Duration(milliseconds: 200),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(_offset(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(s.holds, 0);
      expect(find.text('reply'), findsNothing);
    });
  });

  group('inside a horizontal list', () {
    testWidgets('a quick horizontal swipe on the slider scrolls the list', (
      tester,
    ) async {
      final s = await _pump(tester, axis: .horizontal);
      final gesture = await _drag(tester, _thumb(tester), const Offset(-8, 0));
      expect(_offset(tester), greaterThan(30));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(s.slider, 0.5);
    });

    testWidgets('a held slider drags and the list stays', (tester) async {
      final s = await _pump(tester, axis: .horizontal);
      final gesture = await _drag(
        tester,
        _thumb(tester),
        const Offset(8, 0),
        hold: const Duration(milliseconds: 200),
      );
      expect(_offset(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(s.slider, greaterThan(0.7));
      expect(_offset(tester), 0);
    });

    testWidgets('a vertical drag on a switch leaves the list still', (
      tester,
    ) async {
      await _pump(tester, axis: .horizontal);
      final track = tester.getRect(find.byType(MorphSwitch));
      final gesture = await _drag(
        tester,
        track.centerLeft + const Offset(12, 0),
        const Offset(0, 6),
        count: 6,
      );
      expect(_offset(tester), 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_offset(tester), 0);
    });
  });
}
