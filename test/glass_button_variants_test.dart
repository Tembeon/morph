import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/glass_painter.dart';
import 'package:morph/widgets.dart';

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
    MorphWidgetsThemeScope(
      data: MorphWidgetsTheme(tint: tint),
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
}
