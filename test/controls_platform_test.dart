import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

Widget _host(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
  MediaQueryData media = const MediaQueryData(),
}) => MediaQuery(
  data: media,
  child: Directionality(
    textDirection: direction,
    child: Center(child: SizedBox(width: 360, child: child)),
  ),
);

class _Recorder extends MorphGlassPainter {
  final List<MorphGlassSurface> seen = [];
  final List<MorphGlassSurface> filled = [];

  List<MorphGlassSurface> of(MorphGlassKind kind) => [
    for (final s in seen)
      if (s.kind == kind) s,
  ];

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    seen.add(surface);
    return const SizedBox.expand();
  }

  @override
  Widget buildFill(BuildContext context, MorphGlassSurface surface) {
    seen.add(surface);
    filled.add(surface);
    return super.buildFill(context, surface);
  }
}

const _tabs = [
  MorphTabItem(icon: IconData(0xe318), label: 'One'),
  MorphTabItem(icon: IconData(0xe318), label: 'Two'),
  MorphTabItem(icon: IconData(0xe318), label: 'Three'),
];

Widget _segmented(
  ValueChanged<int>? onChanged, {
  int selected = 0,
  MorphSegmentedStyle? style,
}) => MorphSegmentedControl(
  segments: const ['A', 'B', 'C'],
  selected: selected,
  onChanged: onChanged,
  style: style,
);

double _opacityAbove(WidgetTester tester, Finder finder) => tester
    .widget<Opacity>(
      find.ancestor(of: finder, matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  group('semantics', () {
    testWidgets('each segment is a selectable button', (tester) async {
      final handle = tester.ensureSemantics();
      var selected = 0;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => _segmented(
              (i) => setState(() => selected = i),
              selected: selected,
            ),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.text('A')),
        isSemantics(
          label: 'A',
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
          isEnabled: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('C')),
        isSemantics(label: 'C', isSelected: false),
      );
      tester.semantics.tap(find.semantics.byLabel('C'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(selected, 2);
      expect(
        tester.getSemantics(find.text('C')),
        isSemantics(isSelected: true),
      );
      handle.dispose();
    });

    testWidgets('the tab bar is a tab bar of tabs', (tester) async {
      final handle = tester.ensureSemantics();
      var selected = 0;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => MorphTabBar(
              items: _tabs,
              selected: selected,
              onChanged: (i) => setState(() => selected = i),
            ),
          ),
        ),
      );
      final tab = tester.getSemantics(find.text('Two'));
      expect(tab.getSemanticsData().role, SemanticsRole.tab);
      expect(tab.parent?.getSemanticsData().role, SemanticsRole.tabBar);
      expect(tab, isSemantics(label: 'Two', isSelected: false));
      tester.semantics.tap(find.semantics.byLabel('Two'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(selected, 1);
      handle.dispose();
    });

    testWidgets('the switch is toggled and labelled', (tester) async {
      final handle = tester.ensureSemantics();
      var value = false;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => Center(
              child: MorphSwitch(
                value: value,
                semanticLabel: 'Wi-Fi',
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      );
      expect(
        find.semantics.byLabel('Wi-Fi').evaluate().single,
        isSemantics(label: 'Wi-Fi', isToggled: false, hasTapAction: true),
      );
      tester.semantics.tap(find.semantics.byLabel('Wi-Fi'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(value, isTrue);
      handle.dispose();
    });

    testWidgets('the slider adjusts by a tenth', (tester) async {
      final handle = tester.ensureSemantics();
      var value = 0.3;
      double? ended;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => MorphSlider(
              value: value,
              semanticLabel: 'Volume',
              onChanged: (v) => setState(() => value = v),
              onChangeEnd: (v) => ended = v,
            ),
          ),
        ),
      );
      expect(
        find.semantics.byLabel('Volume').evaluate().single,
        isSemantics(
          label: 'Volume',
          isSlider: true,
          value: '30%',
          increasedValue: '40%',
          decreasedValue: '20%',
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      tester.semantics.increase(find.semantics.byLabel('Volume'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(value, moreOrLessEquals(0.4));
      expect(ended, value);
      handle.dispose();
    });

    testWidgets('the stepper is two buttons carrying the value', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var value = 5.0;
      await tester.pumpWidget(
        _host(
          Center(
            child: StatefulBuilder(
              builder: (context, setState) => MorphStepper(
                value: value,
                max: 6,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      );
      expect(find.semantics.byLabel('Decrement'), findsOne);
      tester.semantics.tap(find.semantics.byLabel('Increment'));
      await tester.pump();
      expect(value, 6);
      final plus = find.semantics.byLabel('Increment').evaluate().single;
      expect(plus, isSemantics(value: '6', isEnabled: false));
      tester.semantics.tap(find.semantics.byLabel('Decrement'));
      await tester.pump();
      expect(value, 5);
      handle.dispose();
    });
  });

  group('keyboard', () {
    testWidgets('arrows move the segmented selection, mirrored in RTL', (
      tester,
    ) async {
      for (final direction in TextDirection.values) {
        var selected = 0;
        await tester.pumpWidget(
          _host(
            StatefulBuilder(
              builder: (context, setState) => _segmented(
                (i) => setState(() => selected = i),
                selected: selected,
              ),
            ),
            direction: direction,
          ),
        );
        Focus.of(tester.element(find.text('A'))).requestFocus();
        await tester.pump();
        final forward = direction == TextDirection.ltr
            ? LogicalKeyboardKey.arrowRight
            : LogicalKeyboardKey.arrowLeft;
        await tester.sendKeyEvent(forward);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
        expect(selected, 1, reason: '$direction');
        await tester.sendKeyEvent(forward);
        await tester.pump();
        await tester.sendKeyEvent(forward);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
        expect(selected, 2, reason: 'the selection stops at the end');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('arrows move the tab bar selection', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => MorphTabBar(
              items: _tabs,
              selected: selected,
              onChanged: (i) => setState(() => selected = i),
            ),
          ),
        ),
      );
      Focus.of(tester.element(find.text('One'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(selected, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(selected, 0);
    });

    testWidgets('Space toggles the switch and presses the button', (
      tester,
    ) async {
      var value = false;
      var taps = 0;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MorphSwitch(
                  value: value,
                  onChanged: (v) => setState(() => value = v),
                ),
                MorphGlassButton(
                  onPressed: () => taps++,
                  child: const Text('Go'),
                ),
              ],
            ),
          ),
        ),
      );
      final switchNode = Focus.of(
        tester.element(
          find
              .descendant(
                of: find.byType(MorphSwitch),
                matching: find.byType(CustomPaint),
              )
              .last,
        ),
      );
      switchNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(value, isTrue);
      Focus.of(tester.element(find.text('Go'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('arrows step the slider and the stepper', (tester) async {
      var slider = 0.5;
      var stepper = 3.0;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MorphSlider(
                  value: slider,
                  onChanged: (v) => setState(() => slider = v),
                ),
                MorphStepper(
                  value: stepper,
                  onChanged: (v) => setState(() => stepper = v),
                ),
              ],
            ),
          ),
        ),
      );
      Focus.of(
        tester.element(
          find
              .descendant(
                of: find.byType(MorphSlider),
                matching: find.byType(CustomPaint),
              )
              .last,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(slider, moreOrLessEquals(0.6));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(slider, moreOrLessEquals(0.4));

      Focus.of(
        tester.element(
          find
              .descendant(
                of: find.byType(MorphStepper),
                matching: find.byType(CustomPaint),
              )
              .last,
        ),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(stepper, 4);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(stepper, 3);
    });
  });

  group('disabled', () {
    testWidgets('a disabled segmented control ignores input and dims', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_segmented(null)));
      await tester.tap(find.text('C'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      final text = tester.widget<Text>(find.text('A'));
      expect(text.style?.fontWeight, FontWeight.w500, reason: 'A stays');
      expect(_opacityAbove(tester, find.text('A')), 0.5);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a disabled tab bar does not select and keeps its look', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const MorphTabBar(items: _tabs, selected: 0, onChanged: null)),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Three')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      final semanticsHandle = tester.ensureSemantics();
      await tester.pump();
      expect(
        tester.getSemantics(find.text('One')),
        isSemantics(isSelected: true),
      );
      semanticsHandle.dispose();
      expect(
        find.ancestor(of: find.text('One'), matching: find.byType(Opacity)),
        findsNothing,
      );
    });

    testWidgets('disabled switches and sliders dim to half', (tester) async {
      await tester.pumpWidget(
        _host(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MorphSwitch(value: true, onChanged: null),
              MorphSlider(value: 0.5, onChanged: null),
            ],
          ),
        ),
      );
      expect(_opacityAbove(tester, find.byType(CustomPaint).first), 0.5);
      final slider = find.descendant(
        of: find.byType(MorphSlider),
        matching: find.byType(Opacity),
      );
      expect(tester.widget<Opacity>(slider).opacity, 0.5);
    });
  });

  group('layout', () {
    testWidgets('an RTL segmented control has its first segment on the '
        'right and selects what is under the finger', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => _segmented(
              (i) => setState(() => selected = i),
              selected: selected,
            ),
          ),
          direction: TextDirection.rtl,
        ),
      );
      expect(
        tester.getCenter(find.text('A')).dx,
        greaterThan(tester.getCenter(find.text('C')).dx),
      );
      await tester.tap(find.text('C'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(selected, 2);
    });

    testWidgets('an RTL slider grows to the left', (tester) async {
      var value = 0.3;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 300,
              child: MorphSlider(
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
          direction: TextDirection.rtl,
        ),
      );
      final box = tester.getRect(find.byType(MorphSlider));
      final thumb = Offset(box.right - 18.5 - 0.3 * 263, box.center.dy);
      final gesture = await tester.startGesture(thumb);
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(value, greaterThan(0.4));
    });

    testWidgets('segment labels follow the text scale up to 1.4', (
      tester,
    ) async {
      Future<double> labelHeight(double scale) async {
        await tester.pumpWidget(
          _host(
            _segmented((_) {}),
            media: MediaQueryData(textScaler: TextScaler.linear(scale)),
          ),
        );
        return tester.getSize(find.text('A')).height;
      }

      final plain = await labelHeight(1);
      final large = await labelHeight(1.4);
      final huge = await labelHeight(3);
      expect(large, greaterThan(plain));
      expect(huge, large);
    });

    testWidgets('tabs widen for a long label and stop at a 1.25 scale', (
      tester,
    ) async {
      Future<double> width(double scale) async {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: MorphTabBar(
                  items: const [
                    MorphTabItem(icon: IconData(0xe318), label: 'Home'),
                    MorphTabItem(
                      icon: IconData(0xe318),
                      label: 'Notifications and settings',
                    ),
                  ],
                  selected: 0,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        return tester.getSize(find.byType(MorphTabBar)).width;
      }

      final plain = await width(1);
      expect(plain, greaterThan(86.0 * 2 + 16));
      final capped = await width(1.25);
      expect(capped, greaterThan(plain));
      expect(await width(2), capped);
    });
  });

  group('reduced motion', () {
    test('a reduced lens travels without lifting or deforming', () {
      final motion = MorphLensMotion(
        tuning: MorphLensTuning.tabBar,
        slots: const [(center: 50, width: 94), (center: 136, width: 94)],
        selected: 0,
        height: 54,
        reducedMotion: true,
      );
      motion.advance(0);
      motion.pointerDown(0.1, 136);
      var maxLift = 0.0;
      var maxDeform = 0.0;
      var maxGrowth = 0.0;
      for (var t = 0.1; t < 0.6; t += 1 / 120) {
        motion.advance(t);
        maxLift = maxLift > motion.lift ? maxLift : motion.lift;
        final deform = (motion.scaleX - 1).abs();
        maxDeform = maxDeform > deform ? maxDeform : deform;
        maxGrowth = maxGrowth > motion.chromeGrowth
            ? maxGrowth
            : motion.chromeGrowth;
      }
      motion.pointerUp(0.6, 136);
      motion.advance(2);
      expect(motion.selected, 1);
      expect(motion.center, closeTo(136, 0.05));
      expect(maxLift, 0);
      expect(maxDeform, lessThan(1e-9));
      expect(maxGrowth, 0);
      expect(motion.isSettled, isTrue);
    });

    testWidgets('a reduced glass button glows without lifting', (tester) async {
      await tester.pumpWidget(
        _host(
          Center(
            child: SizedBox(
              width: 120,
              height: 44,
              child: MorphGlassButton(
                padding: EdgeInsets.zero,
                onPressed: () {},
                child: const Text('Glass'),
              ),
            ),
          ),
          media: const MediaQueryData(disableAnimations: true),
        ),
      );
      final surface = find.descendant(
        of: find.byType(MorphGlassButton),
        matching: find.byType(CustomPaint),
      );
      final rest = tester.getRect(surface.first);
      final gesture = await tester.startGesture(rest.center);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getRect(surface.first), rest);
      await gesture.up();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
    });
  });

  group('glass painter', () {
    testWidgets('controls hand their surfaces to an installed painter', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        MorphGlass(
          painter: recorder,
          child: _host(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _segmented((_) {}),
                MorphSwitch(value: false, onChanged: (_) {}),
                MorphSlider(value: 0.5, onChanged: (_) {}),
                MorphStepper(value: 1, onChanged: (_) {}),
                MorphGlassButton(onPressed: () {}, child: const Text('Go')),
                MorphTabBar(items: _tabs, selected: 1, onChanged: (_) {}),
              ],
            ),
          ),
        ),
      );
      for (final kind in MorphGlassKind.values) {
        if (kind == MorphGlassKind.menu) continue;
        expect(recorder.of(kind), isNotEmpty, reason: '$kind');
      }
      final lenses = recorder.of(MorphGlassKind.lens);
      expect(lenses.map((s) => s.optics).toSet(), {MorphGlassOptics.large});
      expect(lenses.map((s) => s.brightness).toSet(), {Brightness.light});
      expect(lenses.map((s) => s.bounds.height).toSet(), {28.0, 54.0});
      final knob = recorder.of(MorphGlassKind.knob).last;
      expect(knob.optics, same(MorphGlassOptics.small));
      expect(knob.bounds.left, moreOrLessEquals(2));
    });

    testWidgets('only the surfaces iOS 27 draws as glass are glass', (
      tester,
    ) async {
      Future<_Recorder> record(Widget control) async {
        final recorder = _Recorder();
        await tester.pumpWidget(
          MorphGlass(painter: recorder, child: _host(control)),
        );
        return recorder;
      }

      Map<MorphGlassKind, Set<bool>> kinds(_Recorder recorder) => {
        for (final s in recorder.seen)
          s.kind: {
            for (final t in recorder.seen)
              if (t.kind == s.kind) t.glass,
          },
      };

      final cases = <String, (Widget, Map<MorphGlassKind, Set<bool>>)>{
        'segmented': (
          _segmented((_) {}),
          {
            MorphGlassKind.track: {false},
            MorphGlassKind.lens: {true},
          },
        ),
        'switch': (
          MorphSwitch(value: true, onChanged: (_) {}),
          {
            MorphGlassKind.track: {false},
            MorphGlassKind.knob: {true},
          },
        ),
        'slider': (
          MorphSlider(value: 0.5, onChanged: (_) {}),
          {
            MorphGlassKind.track: {false},
            MorphGlassKind.thumb: {true},
          },
        ),
        'stepper': (
          MorphStepper(value: 1, onChanged: (_) {}),
          {
            MorphGlassKind.track: {false},
          },
        ),
        'glass button': (
          MorphGlassButton(onPressed: () {}, child: const Text('Go')),
          {
            MorphGlassKind.button: {true},
          },
        ),
        'tab bar': (
          MorphTabBar(items: _tabs, selected: 1, onChanged: (_) {}),
          {
            MorphGlassKind.bar: {true},
            MorphGlassKind.lens: {true},
          },
        ),
      };
      for (final MapEntry(key: name, value: (control, expected))
          in cases.entries) {
        final recorder = await record(control);
        expect(kinds(recorder), expected, reason: name);
        expect(
          recorder.filled.every((MorphGlassSurface s) => !s.glass),
          isTrue,
          reason: '$name: a glass surface was drawn as a fill',
        );
        expect(
          recorder.seen.where((MorphGlassSurface s) => !s.glass).toList(),
          recorder.filled,
          reason: '$name: a plain surface reached buildSurface',
        );
      }
    });

    testWidgets(
      'controls under a painter take taps that hit nothing it built',
      (tester) async {
        var on = false;
        var segment = 0;
        await tester.pumpWidget(
          MorphGlass(
            painter: _Recorder(),
            child: _host(
              StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MorphSwitch(
                      value: on,
                      onChanged: (bool v) => setState(() => on = v),
                    ),
                    _segmented(
                      (int i) => setState(() => segment = i),
                      selected: segment,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byType(MorphSwitch));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
        expect(on, isTrue);
        await tester.tap(find.text('C'));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
        expect(segment, 2);
      },
    );

    testWidgets('a sized glass button centers its content under a painter', (
      tester,
    ) async {
      await tester.pumpWidget(
        MorphGlass(
          painter: _Recorder(),
          child: _host(
            Center(
              child: SizedBox(
                width: 200,
                height: 44,
                child: MorphGlassButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {},
                  child: const Text('Go'),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getCenter(find.text('Go')),
        tester.getCenter(find.byType(MorphGlassButton)),
      );
    });

    testWidgets('a lifted lens reports its lift to the painter', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        MorphGlass(painter: recorder, child: _host(_segmented((_) {}))),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('A')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(recorder.of(MorphGlassKind.lens).last.lift, closeTo(1, 0.02));
      await gesture.up();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(recorder.of(MorphGlassKind.lens).last.lift, closeTo(0, 0.01));
    });

    test('optics interpolate refraction by lift', () {
      const optics = MorphGlassOptics.small;
      expect(optics.displacementAt(0), 50);
      expect(optics.displacementAt(1), 9);
      expect(optics.blurRadiusAt(0), 6);
      expect(optics.blurRadiusAt(1), 0);
    });
  });

  group('theming', () {
    testWidgets('dark brightness resolves the dark tables', (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        MorphGlass(
          painter: recorder,
          child: _host(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _segmented((_) {}),
                MorphSwitch(value: true, onChanged: (_) {}),
              ],
            ),
            media: const MediaQueryData(platformBrightness: Brightness.dark),
          ),
        ),
      );
      final tracks = recorder.of(MorphGlassKind.track);
      final segmented = tracks.lastWhere((s) => s.bounds.width == 360);
      final toggle = tracks.lastWhere((s) => s.bounds.width == 63);
      expect(segmented.color, MorphSegmentedStyle.dark.trackColor);
      expect(segmented.brightness, Brightness.dark);
      expect(
        toggle.color.toARGB32(),
        MorphSwitchStyle.dark.activeColor.toARGB32(),
      );
    });

    testWidgets('a Theme decides the brightness over the platform', (
      tester,
    ) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        Theme(
          data: ThemeData(brightness: Brightness.light),
          child: MorphGlass(
            painter: recorder,
            child: _host(
              _segmented((_) {}),
              media: const MediaQueryData(platformBrightness: Brightness.dark),
            ),
          ),
        ),
      );
      expect(
        recorder.of(MorphGlassKind.track).first.color,
        MorphSegmentedStyle.light.trackColor,
      );
    });

    testWidgets('an explicit style beats the theme, which beats the table', (
      tester,
    ) async {
      const themed = MorphSegmentedStyle(trackColor: Color(0xFF00FF00));
      const explicit = MorphSegmentedStyle(trackColor: Color(0xFFFF0000));
      final recorder = _Recorder();
      Future<Color> track(MorphSegmentedStyle? style) async {
        recorder.seen.clear();
        await tester.pumpWidget(
          Theme(
            data: ThemeData(
              extensions: const [MorphWidgetsTheme(segmented: themed)],
            ),
            child: MorphGlass(
              painter: recorder,
              child: _host(_segmented((_) {}, style: style)),
            ),
          ),
        );
        return recorder.of(MorphGlassKind.track).last.color;
      }

      expect(await track(null), themed.trackColor);
      expect(await track(explicit), explicit.trackColor);
    });

    testWidgets('an explicit switch color beats its style', (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        MorphGlass(
          painter: recorder,
          child: _host(
            MorphSwitch(
              value: true,
              activeColor: const Color(0xFF123456),
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(
        recorder.of(MorphGlassKind.track).last.color.toARGB32(),
        0xFF123456,
      );
    });
  });
}
