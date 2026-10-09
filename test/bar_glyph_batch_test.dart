import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/bar_glyph_filter.dart';

Widget _scene({
  bool batch = true,
  double firstSigma = 1,
  double secondSigma = 1,
  double secondScale = 0.8,
  double secondOpacity = 0.6,
  double secondX = 50,
  Widget first = const ColoredBox(color: Color(0xffff0000)),
}) {
  final children = [
    Positioned(
      left: 10,
      top: 10,
      width: 24,
      height: 20,
      child: MorphBarGlyphFilter(
        sigma: firstSigma,
        scale: 0.8,
        opacity: 0.6,
        child: first,
      ),
    ),
    Positioned(
      left: secondX,
      top: 10,
      width: 24,
      height: 20,
      child: MorphBarGlyphFilter(
        sigma: secondSigma,
        scale: secondScale,
        opacity: secondOpacity,
        child: const ColoredBox(color: Color(0xff0000ff)),
      ),
    ),
  ];
  return MediaQuery(
    data: const MediaQueryData(devicePixelRatio: 2),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 400,
        height: 40,
        child: batch
            ? MorphBarGlyphStack(children: children)
            : Stack(clipBehavior: Clip.none, children: children),
      ),
    ),
  );
}

int _filters(WidgetTester tester) =>
    tester.layers.whereType<ImageFilterLayer>().length;

void main() {
  testWidgets('disjoint compatible glyphs share filter, scale and opacity', (
    tester,
  ) async {
    await tester.pumpWidget(_scene(batch: false));
    expect(_filters(tester), 2);
    final positions = tester.getRect(find.byType(ColoredBox).first);
    await tester.pumpWidget(_scene());
    expect(_filters(tester), 1);
    expect(tester.layers.whereType<OpacityLayer>().length, 1);
    expect(tester.getRect(find.byType(ColoredBox).first), positions);
    expect(tester.takeException(), isNull);
  });

  for (final (name, scene) in <(String, Widget Function())>[
    ('live sharp source', () => _scene(firstSigma: 0.2, secondSigma: 0.2)),
    ('sigma', () => _scene(secondSigma: 2)),
    ('scale', () => _scene(secondScale: 0.9)),
    ('opacity', () => _scene(secondOpacity: 0.4)),
    ('halo overlap', () => _scene(secondX: 25)),
    ('sparse union', () => _scene(secondX: 300)),
  ]) {
    testWidgets('$name retains independent filters', (tester) async {
      await tester.pumpWidget(_scene());
      expect(_filters(tester), 1);
      await tester.pumpWidget(scene());
      expect(_filters(tester), 2);
      await tester.pumpWidget(_scene());
      expect(_filters(tester), 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('child-only repaint reaches the batched surface', (tester) async {
    final changed = ValueNotifier(0);
    addTearDown(changed.dispose);
    var paints = 0;
    final marker = CustomPaint(painter: _Marker(changed, () => paints++));
    await tester.pumpWidget(_scene(first: marker));
    expect(paints, 1);
    changed.value++;
    await tester.pump();
    expect(paints, 2);
    expect(_filters(tester), 1);
  });
}

class _Marker extends CustomPainter {
  _Marker(Listenable repaint, this.onPaint) : super(repaint: repaint);
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    final paint = Paint();
    paint.color = const Color(0xff00ff00);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_Marker oldDelegate) => false;
}
