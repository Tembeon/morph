import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/glass_painter.dart';
import 'package:morph/src/glass/renderer/liquid_glass_color_model.dart';
import 'package:morph/src/widgets/glass_liquid_draw.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

class _Recording extends MorphGlassPainter {
  final List<MorphGlassSurface> surfaces = [];

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    surfaces.add(surface);
    return buildFill(context, surface);
  }
}

Widget _scene(Widget child, {MorphGlassPainter? painter}) {
  final Widget centered = Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  );
  return painter == null
      ? centered
      : MorphGlassScope(painter: painter, child: centered);
}

void main() {
  testWidgets('hands the painter a resting regular glass surface', (
    tester,
  ) async {
    final painter = _Recording();
    await tester.pumpWidget(
      _scene(
        const MorphGlassEffect(child: SizedBox(width: 120, height: 44)),
        painter: painter,
      ),
    );
    final surface = painter.surfaces.last;
    expect(surface.kind, MorphGlassKind.button);
    expect(surface.style, isNull);
    expect(surface.color, MorphGlassButtonAppearance.light.fillColor);
    expect(surface.lift, 0);
    expect(surface.shape.outerRect.size, const Size(120, 44));
    expect(surface.shape.tlRadiusX, 22);
  });

  testWidgets('clear glass is untinted, tinted glass is filled', (
    tester,
  ) async {
    final painter = _Recording();
    await tester.pumpWidget(
      _scene(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MorphGlassEffect(
              style: MorphGlassStyle.clear,
              child: SizedBox(width: 80, height: 40),
            ),
            MorphGlassEffect(
              style: MorphGlassStyle.clear,
              tint: Color(0xFFFF9500),
              child: SizedBox(width: 80, height: 40),
            ),
          ],
        ),
        painter: painter,
      ),
    );
    final [clear, tinted] = painter.surfaces.sublist(
      painter.surfaces.length - 2,
    );
    expect(clear.style, MorphGlassStyle.clear);
    expect(clear.tint, const Color(0x00000000));
    expect(tinted.color, const Color(0xFFFF9500));
    expect(tinted.tint, isNull);
  });

  testWidgets('a rounded rectangle and a circle keep their outline', (
    tester,
  ) async {
    final painter = _Recording();
    await tester.pumpWidget(
      _scene(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MorphGlassEffect(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: SizedBox(width: 100, height: 60),
            ),
            MorphGlassEffect(
              shape: CircleBorder(),
              child: SizedBox(width: 50, height: 50),
            ),
          ],
        ),
        painter: painter,
      ),
    );
    final [box, circle] = painter.surfaces.sublist(painter.surfaces.length - 2);
    expect(box.shape.tlRadiusX, 12);
    expect(circle.shape.tlRadiusX, 25);
  });

  testWidgets('interactive glass lifts under a finger and passes the tap', (
    tester,
  ) async {
    final painter = _Recording();
    var taps = 0;
    await tester.pumpWidget(
      _scene(
        MorphGlassEffect(
          interactive: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox(width: 120, height: 44),
          ),
        ),
        painter: painter,
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(MorphGlassEffect)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(painter.surfaces.last.lift, greaterThan(0.5));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(painter.surfaces.last.lift, 0);
  });

  testWidgets('without a painter it draws flat', (tester) async {
    await tester.pumpWidget(
      _scene(const MorphGlassEffect(child: SizedBox(width: 60, height: 30))),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byType(MorphGlassEffect),
        matching: find.byType(CustomPaint),
      ),
      findsWidgets,
    );
  });

  test('a clear surface draws the clear material on a regular renderer', () {
    const renderer = GlassBuiltInPainter();
    MorphGlassSurface surface(MorphGlassStyle? style) => MorphGlassSurface(
      kind: MorphGlassKind.button,
      shape: RRect.fromLTRBR(0, 0, 80, 40, const Radius.circular(20)),
      color: const Color(0x00000000),
      brightness: Brightness.light,
      style: style,
    );
    expect(
      morphLiquidAppearance(
        renderer,
        surface(MorphGlassStyle.clear),
      ).colorModel,
      const LiquidGlassColorModel.ios27Clear(),
    );
    expect(
      morphLiquidAppearance(renderer, surface(null)).colorModel,
      morphLiquidAppearance(
        renderer,
        surface(MorphGlassStyle.regular),
      ).colorModel,
    );
    expect(
      morphLiquidSettings(renderer, surface(MorphGlassStyle.clear)),
      isNot(morphLiquidSettings(renderer, surface(null))),
    );
  });
}
