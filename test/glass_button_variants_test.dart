import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/glass_painter.dart';
import 'package:morph/src/widgets/glass_glow.dart';
import 'package:morph/morph.dart';

class _Recording extends MorphGlassPainter {
  final List<MorphGlassSurface> surfaces = [];

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    surfaces.add(surface);
    return buildFill(context, surface);
  }
}

Future<MorphGlassSurface> _surfaceOf(
  WidgetTester tester,
  Widget button, {
  Color? tint,
}) async {
  final painter = _Recording();
  await tester.pumpWidget(
    MorphTheme(
      data: MorphThemeData(tint: tint),
      child: MorphGlassScope(
        painter: painter,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: button),
        ),
      ),
    ),
  );
  return painter.surfaces.last;
}

void main() {
  testWidgets('a regular button keeps the renderer material', (tester) async {
    final surface = await _surfaceOf(
      tester,
      MorphGlassButton(onPressed: () {}, child: const Text('A')),
    );
    expect(surface.style, isNull);
    expect(surface.color, MorphGlassButtonAppearance.light.fillColor);
  });

  testWidgets('a clear button asks for untinted clear glass', (tester) async {
    final surface = await _surfaceOf(
      tester,
      MorphGlassButton.clear(onPressed: () {}, child: const Text('A')),
    );
    expect(surface.style, MorphGlassStyle.clear);
    expect(surface.tint, const Color(0x00000000));
    expect(surface.color, MorphGlassButtonAppearance.light.clearFillColor);
  });

  testWidgets('prominent buttons default to the ambient accent', (
    tester,
  ) async {
    const accent = Color(0xFF34C759);
    final prominent = await _surfaceOf(
      tester,
      MorphGlassButton.prominent(onPressed: () {}, child: const Text('A')),
      tint: accent,
    );
    expect(prominent.color, accent);
    expect(prominent.style, isNull);
    final clear = await _surfaceOf(
      tester,
      MorphGlassButton.prominentClear(onPressed: () {}, child: const Text('A')),
      tint: accent,
    );
    expect(clear.color, accent);
    expect(clear.style, MorphGlassStyle.clear);
    expect(clear.tint, isNull);
    final systemBlue = await _surfaceOf(
      tester,
      MorphGlassButton.prominent(onPressed: () {}, child: const Text('A')),
    );
    expect(systemBlue.color, MorphGlassButtonAppearance.light.prominentColor);
  });

  testWidgets('an explicit tint wins over the accent', (tester) async {
    final surface = await _surfaceOf(
      tester,
      MorphGlassButton.prominent(
        onPressed: () {},
        tint: const Color(0xFFFF3B30),
        child: const Text('A'),
      ),
      tint: const Color(0xFF34C759),
    );
    expect(surface.color, const Color(0xFFFF3B30));
  });

  test('the touch glow gain follows the glass', () {
    const dark = Brightness.dark;
    const light = Brightness.light;
    expect(MorphTouchGlowMotion.spotGainOfWhite(0.75), closeTo(3, 1e-9));
    expect(MorphTouchGlowMotion.spotGainOfWhite(0.4), closeTo(0.667, 1e-3));
    expect(MorphTouchGlowMotion.spotGainFor(dark), 3);
    expect(MorphTouchGlowMotion.spotGainFor(light), 0.667);
    expect(
      MorphTouchGlowMotion.spotGainFor(light, clear: true),
      closeTo(7 / 3, 1e-9),
    );
    expect(
      MorphTouchGlowMotion.spotGainFor(
        dark,
        tint: const Color(0xFF000000),
        clear: true,
      ),
      closeTo(7 / 3, 1e-9),
    );
    expect(
      MorphTouchGlowMotion.spotGainFor(dark, tint: const Color(0xFFFFFFFF)),
      closeTo(1 / 3, 1e-9),
    );
  });

  for (final (name, menu) in [
    ('a button', null),
    ('a menu button', const <MorphMenuEntry>[MorphMenuItem(title: 'Copy')]),
  ]) {
    testWidgets('$name with only an icon announces its semantic label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: MorphGlassButton(
              onPressed: () {},
              menu: menu,
              semanticLabel: 'Share',
              child: const SizedBox.square(dimension: 20),
            ),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Share')),
        isSemantics(label: 'Share', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  }
}
