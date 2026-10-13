import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/glass_painter.dart';
import 'package:morph/src/widgets/lens_driver.dart';
import 'package:morph/src/widgets/touch_listener.dart';
import 'package:morph/widgets.dart';

const _items = [
  MorphTabItem(icon: IconData(0xe318), label: 'One'),
  MorphTabItem(icon: IconData(0xe318), label: 'Two'),
  MorphTabItem(icon: IconData(0xe318), label: 'Three'),
];

class _Glass extends MorphGlassPainter {
  final Map<MorphGlassKind, MorphGlassSurface> surfaces = {};

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    surfaces[surface.kind] = surface;
    return const SizedBox.expand();
  }
}

Widget _host(Widget child, {_Glass? glass}) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: glass == null
          ? child
          : MorphGlassScope(painter: glass, child: child),
    ),
  ),
);

void main() {
  for (final tab in [false, true]) {
    testWidgets(
      'C4 ${tab ? 'tab bar' : 'segmented'} restores rejected selection',
      (tester) async {
        final glass = _Glass();
        final changes = <int>[];
        final Widget control = tab
            ? MorphTabBar(items: _items, selected: 0, onChanged: changes.add)
            : SizedBox(
                width: 360,
                child: MorphSegmentedControl(
                  segments: const [
                    MorphSegment('One'),
                    MorphSegment('Two'),
                    MorphSegment('Three'),
                  ],
                  selectedIndex: 0,
                  onChanged: changes.add,
                ),
              );
        await tester.pumpWidget(_host(control, glass: glass));
        final initial = glass.surfaces[MorphGlassKind.lens]!.shape;
        await tester.tap(find.text('Three'));
        await tester.pumpAndSettle();
        expect(changes, [2]);
        expect(
          glass.surfaces[MorphGlassKind.lens]!.shape.outerRect.center.dx,
          closeTo(initial.outerRect.center.dx, 0.01),
        );
        await tester.tap(find.text('Three'));
        await tester.pumpAndSettle();
        expect(changes, [2, 2]);
      },
    );
  }

  testWidgets('C4 switch restores rejected toggle without rebuild', (
    tester,
  ) async {
    final glass = _Glass();
    final changes = <bool>[];
    await tester.pumpWidget(
      _host(MorphSwitch(value: false, onChanged: changes.add), glass: glass),
    );
    final initial = glass.surfaces[MorphGlassKind.knob]!.shape;
    await tester.tap(find.byType(MorphSwitch));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(
      glass.surfaces[MorphGlassKind.knob]!.shape.outerRect.center.dx,
      closeTo(initial.outerRect.center.dx, 0.01),
    );
    await tester.tap(find.byType(MorphSwitch));
    await tester.pumpAndSettle();
    expect(changes, [true, true]);
  });

  testWidgets('C4 slider restores rejected drag and glide without rebuild', (
    tester,
  ) async {
    final glass = _Glass();
    final changes = <double>[];
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 300,
          child: MorphSlider(value: 0.3, onChanged: changes.add),
        ),
        glass: glass,
      ),
    );
    final rect = tester.getRect(find.byType(MorphSlider));
    final initial = glass.surfaces[MorphGlassKind.thumb]!.shape;
    final start = rect.topLeft + initial.outerRect.center;
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(changes, isNotEmpty);
    expect(
      glass.surfaces[MorphGlassKind.thumb]!.shape.outerRect.center.dx,
      closeTo(initial.outerRect.center.dx, 0.01),
    );
  });

  testWidgets('C4 slider keeps its drag and glide under a rounding parent', (
    tester,
  ) async {
    final glass = _Glass();
    var value = 0.3;
    final ended = <double>[];
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 300,
          child: StatefulBuilder(
            builder: (context, update) => MorphSlider(
              value: value,
              onChanged: (v) => update(() => value = (v * 100).round() / 100),
              onChangeEnd: ended.add,
            ),
          ),
        ),
        glass: glass,
      ),
    );
    final rect = tester.getRect(find.byType(MorphSlider));
    final thumb = glass.surfaces[MorphGlassKind.thumb]!.shape.outerRect;
    final gesture = await tester.startGesture(rect.topLeft + thumb.center);
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      glass.surfaces[MorphGlassKind.thumb]!.shape.outerRect.right,
      greaterThan(rect.width + 0.5),
      reason: 'dragging past the end stretches the track',
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(ended, [1.0]);
    expect(value, 1.0);

    await tester.flingFrom(
      rect.topLeft + glass.surfaces[MorphGlassKind.thumb]!.shape.center,
      const Offset(-90, 0),
      1000,
    );
    final atRelease = value;
    await tester.pumpAndSettle();
    expect(
      value,
      lessThan(atRelease - 0.1),
      reason: 'the glide runs on after the release',
    );
    expect(ended.last, closeTo(value, 0.005));
    expect(
      glass.surfaces[MorphGlassKind.thumb]!.shape.center.dx,
      closeTo(18.5 + value * (rect.width - 37), 0.01),
      reason: 'the thumb lands on the parent value',
    );
  });

  testWidgets('an echoed slider value rebuilds only its semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var value = 0.3;
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 300,
          child: StatefulBuilder(
            builder: (context, update) => MorphSlider(
              value: value,
              semanticLabel: 'Volume',
              onChanged: (v) => update(() => value = v),
            ),
          ),
        ),
      ),
    );
    Widget listener() => tester.widget(
      find.descendant(
        of: find.byType(MorphSlider),
        matching: find.byType(MorphTouchListener),
      ),
    );
    final before = listener();
    final rect = tester.getRect(find.byType(MorphSlider));
    final gesture = await tester.startGesture(
      Offset(rect.left + 18.5 + 0.3 * 263, rect.center.dy),
    );
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(value, greaterThan(0.4));
    expect(identical(listener(), before), isTrue);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Volume')),
      matchesSemantics(
        label: 'Volume',
        isSlider: true,
        isEnabled: true,
        hasEnabledState: true,
        value: '${(value * 100).round()}%',
        increasedValue: '${(value * 100).round() + 10}%',
        decreasedValue: '${(value * 100).round() - 10}%',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
      ),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('a tab bar rebuilt alike by its parent keeps its build', (
    tester,
  ) async {
    var selected = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, update) {
            rebuild = update;
            return MorphTabBar(
              items: [
                for (final item in _items)
                  MorphTabItem(icon: item.icon, label: item.label),
              ],
              selected: selected,
              onChanged: (i) => update(() => selected = i),
            );
          },
        ),
      ),
    );
    Widget listener() => tester.widget(
      find.descendant(
        of: find.byType(MorphTabBar),
        matching: find.byType(MorphTouchListener),
      ),
    );
    final before = listener();
    rebuild(() {});
    await tester.pump();
    expect(identical(listener(), before), isTrue);
    rebuild(() => selected = 2);
    await tester.pumpAndSettle();
    expect(identical(listener(), before), isFalse);
  });

  test('label widths are measured again only when an input changes', () {
    final widths = MorphLabelWidths();
    const style = TextStyle(fontSize: 13);
    final first = widths.of(['One', 'Two'], [style], TextScaler.noScaling);
    expect(
      identical(
        widths.of(['One', 'Two'], [style], TextScaler.noScaling),
        first,
      ),
      isTrue,
    );
    final scaled = widths.of(
      ['One', 'Two'],
      [style],
      const TextScaler.linear(2),
    );
    expect(identical(scaled, first), isFalse);
    expect(scaled[0], greaterThan(first[0]));
  });

  testWidgets('C5 segmented ignores second finger cancel and movement', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 360,
          child: StatefulBuilder(
            builder: (context, update) => MorphSegmentedControl(
              segments: const [
                MorphSegment('One'),
                MorphSegment('Two'),
                MorphSegment('Three'),
              ],
              selectedIndex: selected,
              onChanged: (i) => update(() => selected = i),
            ),
          ),
        ),
      ),
    );
    final first = await tester.startGesture(
      tester.getCenter(find.text('One')),
      pointer: 1,
    );
    await tester.pump(const Duration(milliseconds: 300));
    final second = await tester.startGesture(
      tester.getCenter(find.text('Three')),
      pointer: 2,
    );
    await second.moveTo(tester.getCenter(find.text('One')));
    await second.cancel();
    await first.moveTo(tester.getCenter(find.text('Two')));
    await first.up();
    await tester.pumpAndSettle();
    expect(selected, 1);
  });

  testWidgets('C5 tab bar ignores second finger contact and release', (
    tester,
  ) async {
    var selected = 0;
    final changes = <int>[];
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, update) => MorphTabBar(
            items: _items,
            selected: selected,
            onChanged: (i) {
              changes.add(i);
              update(() => selected = i);
            },
          ),
        ),
      ),
    );
    final first = await tester.startGesture(
      tester.getCenter(find.text('Two')),
      pointer: 1,
    );
    await tester.pump();
    final second = await tester.startGesture(
      tester.getCenter(find.text('Three')),
      pointer: 2,
    );
    await second.moveTo(tester.getCenter(find.text('One')));
    await second.up();
    expect(changes, [1]);
    await first.up();
    await tester.pumpAndSettle();
    expect(selected, 1);
  });

  testWidgets('C5 switch ignores second finger release', (tester) async {
    var value = false;
    final changes = <bool>[];
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, update) => MorphSwitch(
            value: value,
            onChanged: (v) {
              changes.add(v);
              update(() => value = v);
            },
          ),
        ),
      ),
    );
    final point = tester.getCenter(find.byType(MorphSwitch));
    final first = await tester.startGesture(point, pointer: 1);
    final second = await tester.startGesture(point, pointer: 2);
    await second.moveBy(const Offset(40, 0));
    await second.up();
    expect(changes, isEmpty);
    await first.up();
    await tester.pumpAndSettle();
    expect(changes, [true]);
  });

  testWidgets('C5 slider ignores second finger cancellation', (tester) async {
    var value = 0.3;
    final changes = <double>[];
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 300,
          child: StatefulBuilder(
            builder: (context, update) => MorphSlider(
              value: value,
              onChanged: (v) {
                changes.add(v);
                update(() => value = v);
              },
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(MorphSlider));
    final point = rect.centerLeft + const Offset(18.5 + 0.3 * 263, 0);
    final first = await tester.startGesture(point, pointer: 1);
    final second = await tester.startGesture(point, pointer: 2);
    await second.cancel();
    await first.moveBy(const Offset(20, 0));
    await first.moveBy(const Offset(50, 0));
    await first.up();
    await tester.pumpAndSettle();
    expect(changes, isNotEmpty);
    expect(value, greaterThan(0.3));
  });

  testWidgets('C7 growing segments reconciles selection after layout', (
    tester,
  ) async {
    Widget control(List<String> labels, int selected) => _host(
      SizedBox(
        width: 360,
        child: MorphSegmentedControl(
          segments: [for (final s in labels) MorphSegment(s)],
          selectedIndex: selected,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(control(const ['One', 'Two'], 0));
    await tester.pumpWidget(control(const ['One', 'Two', 'Three'], 2));
    await tester.pumpAndSettle();
    final state =
        tester.state(find.byType(MorphSegmentedControl))
            as MorphLensDriver<MorphSegmentedControl>;
    expect(state.motion.selected, 2);
    expect(state.motion.center, closeTo(300, 0.01));
  });

  testWidgets('C8 empty and out of range lists build safely', (tester) async {
    for (final selected in [-5, 20]) {
      for (final empty in [true, false]) {
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 360,
              child: MorphSegmentedControl(
                segments: empty
                    ? const []
                    : const [MorphSegment('One'), MorphSegment('Two')],
                selectedIndex: selected,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          _host(
            MorphTabBar(
              items: empty ? const [] : _items,
              selected: selected,
              onChanged: (_) {},
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 402,
              height: 600,
              child: MorphSearchTabBar(
                items: empty ? const [] : _items,
                selected: selected,
                onChanged: (_) {},
                active: true,
                onActiveChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('C8 segmented handles unbounded horizontal constraints', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MorphSegmentedControl(
              segments: const [MorphSegment('One'), MorphSegment('Two')],
              selectedIndex: 0,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(MorphSegmentedControl)).width.isFinite,
      isTrue,
    );
  });
}
