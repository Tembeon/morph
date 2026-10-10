import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/glyph_scale.dart';
import 'package:morph/widgets.dart';

/// Records the canvas transform each paint starts with.
class _Recorder extends CustomPainter {
  _Recorder(this.log);

  final List<Float64List> log;

  @override
  void paint(Canvas canvas, Size size) => log.add(canvas.getTransform());

  @override
  bool shouldRepaint(_Recorder oldDelegate) => true;
}

const Size _box = Size(100, 40);

Widget _tree(double scale, List<Float64List> log, {required bool snap}) {
  final Widget painted = CustomPaint(size: _box, painter: _Recorder(log));
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: snap ? MorphGlyphSnap(child: painted) : painted,
      ),
    ),
  );
}

/// The recorded transform's x scale and where it sends the box center.
({double scale, Offset center}) _read(Float64List m) {
  final matrix = Matrix4.fromFloat64List(m);
  final p = MatrixUtils.transformPoint(
    matrix,
    Offset(_box.width / 2, _box.height / 2),
  );
  return (scale: math.sqrt(m[0] * m[0] + m[1] * m[1]), center: p);
}

Future<({double scale, Offset center})> _paint(
  WidgetTester tester,
  double scale, {
  required bool snap,
}) async {
  final log = <Float64List>[];
  await tester.pumpWidget(_tree(scale, log, snap: snap));
  return _read(log.last);
}

void main() {
  testWidgets('a grid scale paints with no transform of its own', (
    tester,
  ) async {
    // The grid passes through the pixel ratio: 2^(8/64) is a step.
    final scale = math.pow(2, 8 / MorphGlyphScale.stepsPerOctave).toDouble();
    final plain = await _paint(tester, scale, snap: false);
    final snapped = await _paint(tester, scale, snap: true);
    final snap = tester.renderObject<RenderMorphGlyphSnap>(
      find.byType(MorphGlyphSnap),
    );
    expect(snap.debugFactor, 1);
    expect(snapped.scale, plain.scale);
    expect(snapped.center, plain.center);
  });

  testWidgets('at rest the label is untouched', (tester) async {
    final plain = await _paint(tester, 1, snap: false);
    final snapped = await _paint(tester, 1, snap: true);
    final snap = tester.renderObject<RenderMorphGlyphSnap>(
      find.byType(MorphGlyphSnap),
    );
    expect(snap.debugFactor, 1);
    expect(snapped.scale, plain.scale);
    expect(snapped.center, plain.center);
  });

  testWidgets('between grid scales the label snaps about its center', (
    tester,
  ) async {
    // Four and a half steps: as far from the grid as a scale gets.
    final scale = math.pow(2, 4.5 / MorphGlyphScale.stepsPerOctave).toDouble();
    final plain = await _paint(tester, scale, snap: false);
    final snapped = await _paint(tester, scale, snap: true);
    final snap = tester.renderObject<RenderMorphGlyphSnap>(
      find.byType(MorphGlyphSnap),
    );
    final factor = snap.debugFactor;
    expect(factor, isNot(1));
    expect((factor - 1).abs(), lessThan(0.0055));
    expect(snapped.scale, closeTo(plain.scale * factor, 1e-5));
    // The snapped scale is a grid scale: 2^(n/64) of the layout size.
    final steps =
        math.log(snapped.scale) / math.ln2 * MorphGlyphScale.stepsPerOctave;
    expect(steps, closeTo(steps.roundToDouble(), 1e-4));
    // About the center of the box: it stays where the plain label's is.
    expect(snapped.center.dx, closeTo(plain.center.dx, 1e-4));
    expect(snapped.center.dy, closeTo(plain.center.dy, 1e-4));
  });

  testWidgets('a sweep of scales visits a few grid scales', (tester) async {
    final seen = <double>{};
    for (var i = 0; i <= 60; i++) {
      final scale = 1 + 0.04 * i / 60;
      final snapped = await _paint(tester, scale, snap: true);
      seen.add(double.parse(snapped.scale.toStringAsFixed(6)));
    }
    // 61 distinct scales across about 5.6 steps of the grid.
    expect(seen.length, lessThanOrEqualTo(7));
  });

  testWidgets('exact drawing paints every scale as it is', (tester) async {
    MorphGlyphScale.debugExact = true;
    addTearDown(() => MorphGlyphScale.debugExact = false);
    final plain = await _paint(tester, 1.0123, snap: false);
    final snapped = await _paint(tester, 1.0123, snap: true);
    expect(snapped.scale, plain.scale);
  });

  testWidgets('a new pixel ratio repaints and layout is unchanged', (
    tester,
  ) async {
    await _paint(tester, 1.02, snap: true);
    final snap = tester.renderObject<RenderMorphGlyphSnap>(
      find.byType(MorphGlyphSnap),
    );
    expect(snap.size, _box);
    snap.devicePixelRatio = snap.devicePixelRatio;
    expect(snap.debugNeedsPaint, isFalse);
    snap.devicePixelRatio = snap.devicePixelRatio * 2;
    expect(snap.debugNeedsPaint, isTrue);
    expect(snap.size, _box);
  });

  testWidgets('a tab bar snaps the labels of both rows', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(),
          child: Center(
            child: MorphTabBar(
              items: const [
                MorphTabItem(label: 'One', icon: IconData(0x41)),
                MorphTabItem(label: 'Two', icon: IconData(0x42)),
                MorphTabItem(label: 'Three', icon: IconData(0x43)),
              ],
              selected: 0,
              onChanged: (int i) {},
            ),
          ),
        ),
      ),
    );
    // A row outside the lens and one inside it, a snap per tab.
    expect(find.byType(MorphGlyphSnap), findsNWidgets(6));
  });
}
