import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/flex_spec.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_glow.dart';
import 'package:morph/src/widgets/tab_bar.dart';

class _Recorder extends MorphGlassPainter {
  final List<MorphGlassSurface> bars = [];

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    if (surface.kind == MorphGlassKind.bar) bars.add(surface);
    return const SizedBox.expand();
  }
}

const _tabs = [
  MorphTabItem(icon: IconData(0xe318), label: 'One'),
  MorphTabItem(icon: IconData(0xe318), label: 'Two'),
  MorphTabItem(icon: IconData(0xe318), label: 'Three'),
];

Widget _bar(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

typedef _Errors = ({
  double wash,
  double washRms,
  double spot,
  double spotRms,
  double scale,
  int rows,
});

List<Map<String, Object?>> _rows(String name) => [
  for (final line in File(
    'test/fixtures/ios27-device/tabglow/$name.jsonl',
  ).readAsLinesSync())
    if (line.isNotEmpty) jsonDecode(line) as Map<String, Object?>,
];

double _d(Map<String, Object?> row, String key) =>
    (row[key]! as num).toDouble();

MorphTouchGlowMotion _motion() {
  final spec = MorphFlexSpec.forSize(const Size(274, 62));
  return MorphTouchGlowMotion(
    washPeak: spec.bigGlowOpacity,
    spotPeak: spec.littleGlowOpacity,
  );
}

_Errors _replay(String name) {
  final motion = _motion();
  var wash = 0.0;
  var spot = 0.0;
  var scale = 0.0;
  var washSum = 0.0;
  var spotSum = 0.0;
  var washRows = 0;
  var spotRows = 0;
  for (final row in _rows(name)) {
    final t = _d(row, 't');
    switch (row['k']) {
      case 'touch':
        final at = Offset(_d(row, 'x'), _d(row, 'y'));
        switch (row['phase']) {
          case 0:
            motion.pointerDown(t, at);
          case 1:
            motion.pointerMove(t, at);
          case 3 || 4:
            motion.pointerUp(t);
        }
      case 'big':
        final error = (motion.washOpacity(t) - _d(row, 'a')).abs();
        wash = math.max(wash, error);
        washSum += error * error;
        washRows++;
      case 'little':
        final a = _d(row, 'a');
        final error = (motion.spotOpacity(t) - a).abs();
        spot = math.max(spot, error);
        spotSum += error * error;
        spotRows++;
        if (a > 0.02) {
          scale = math.max(scale, (motion.spotScale(t) - _d(row, 's')).abs());
        }
    }
  }
  return (
    wash: wash,
    washRms: math.sqrt(washSum / washRows),
    spot: spot,
    spotRms: math.sqrt(spotSum / spotRows),
    scale: scale,
    rows: washRows + spotRows,
  );
}

void main() {
  test('the bar flex spec gives the measured glow peaks', () {
    final spec = MorphFlexSpec.forSize(const Size(274, 62));
    expect(spec.bigGlowOpacity, closeTo(0.845, 1e-3));
    expect(spec.littleGlowOpacity, closeTo(0.2845, 1e-3));
  });

  for (final name in [
    'tabbar3-glow-dark',
    'tabbar3-glow-light',
    'tabbar3-glow-drags',
  ]) {
    test('the touch glow replays $name', () {
      final errors = _replay(name);
      expect(errors.rows, greaterThan(100));
      expect(errors.washRms, lessThan(0.03), reason: 'wash opacity rms');
      expect(errors.spotRms, lessThan(0.012), reason: 'spot opacity rms');
      expect(errors.wash, lessThan(0.25), reason: 'one 60 Hz frame of rise');
      expect(errors.spot, lessThan(0.085), reason: 'one 60 Hz frame of rise');
      expect(errors.scale, lessThan(0.2), reason: 'spot scale');
    });
  }

  test('a held finger keeps both glows at their peaks', () {
    final motion = _motion();
    motion.pointerDown(0, const Offset(100, 31));
    expect(motion.washOpacity(1), closeTo(0.845, 1e-3));
    expect(motion.spotOpacity(1), closeTo(0.2845, 1e-3));
    expect(motion.spotScale(1), 1);
    expect(motion.isSettled(1), isFalse);
  });

  test('a drag past 50 px spreads the spot at half strength', () {
    final motion = _motion();
    motion.pointerDown(0, const Offset(100, 31));
    motion.pointerMove(0.5, const Offset(145, 31));
    expect(motion.spotScale(1.5), 1);
    motion.pointerMove(1.5, const Offset(151, 31));
    expect(motion.spotScale(3), closeTo(2, 1e-3));
    expect(motion.spotOpacity(3), closeTo(0.2845 / 2, 1e-3));
    expect(motion.center, const Offset(151, 31));
  });

  test('a release fades the glows while the spot spreads fourfold', () {
    final motion = _motion();
    motion.pointerDown(0, const Offset(100, 31));
    motion.pointerUp(1);
    expect(motion.washOpacity(1.02), closeTo(0.845, 1e-3));
    expect(motion.spotScale(1.5), greaterThan(3));
    expect(motion.washOpacity(2), 0);
    expect(motion.isSettled(2), isTrue);
  });

  test('the glow brightens gray by the measured matrices', () {
    final motion = _motion();
    motion.pointerDown(0, const Offset(100, 31));
    final glow = motion.glowAt(1, Brightness.dark)!;
    expect(32 + 255 * glow.wash, closeTo(42.8, 0.2));
    expect(glow.factorAt(0), closeTo(1 + 3 * 0.38 * 0.2845, 1e-3));
    final light = motion.glowAt(1, Brightness.light)!;
    expect(light.factorAt(0), lessThan(glow.factorAt(0)));
  });

  testWidgets('a pressed tab bar hands its glow to the painter', (
    tester,
  ) async {
    final painter = _Recorder();
    await tester.pumpWidget(
      _bar(
        MorphGlass(
          painter: painter,
          child: MorphTabBar(items: _tabs, selected: 0, onChanged: (_) {}),
        ),
      ),
    );
    MorphGlassSurface bar() => painter.bars.last;
    expect(bar().glow, isNull);
    final origin = tester.getTopLeft(find.byType(MorphTabBar));
    final touch = tester.getCenter(find.text('Two'));
    final gesture = await tester.startGesture(touch);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final glow = bar().glow!;
    expect(glow.wash, closeTo(0.05 * 0.845, 1e-3));
    expect(glow.radius, closeTo(0.568 * 93, 0.1));
    expect(glow.center.dx, closeTo((touch - origin).dx, 0.5));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(bar().glow, isNull);
  });

  testWidgets('the tabs inside the lens wear the selected style', (
    tester,
  ) async {
    await tester.pumpWidget(
      _bar(MorphTabBar(items: _tabs, selected: 1, onChanged: (_) {})),
    );
    final clips = tester
        .widgetList<ClipPath>(
          find.descendant(
            of: find.byType(MorphTabBar),
            matching: find.byType(ClipPath),
          ),
        )
        .toList();
    expect(clips, hasLength(2));
    final box = tester.renderObject<RenderBox>(
      find
          .descendant(
            of: find.byType(MorphTabBar),
            matching: find.byType(ClipPath),
          )
          .first,
    );
    final outside = clips[0].clipper!.getClip(box.size);
    final inside = clips[1].clipper!.getClip(box.size);
    final pitch = box.size.width / 3;
    for (var i = 0; i < 3; i++) {
      final center = Offset(pitch * (i + 0.5), box.size.height / 2);
      expect(inside.contains(center), i == 1);
      expect(outside.contains(center), i != 1);
    }
    final copies = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((RichText r) => r.text)
        .whereType<TextSpan>()
        .where((TextSpan s) => s.text == 'Two');
    expect(
      copies.map((TextSpan s) => s.style?.color),
      contains(MorphTabBarStyle.light.selectedColor),
    );
  });
}
