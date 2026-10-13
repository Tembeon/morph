import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glyph_scale.dart';
import 'package:morph/widgets.dart';

import 'support/glyph_scale_frames.dart';

void main() {
  setUpAll(() async {
    isLocalTest = true;
    await MorphGlyphs.precache();
  });

  testWidgets('menu rows draw from one raster only while they move', (
    tester,
  ) async {
    Widget app() => glyphApp(
      const MorphMenuButton(
        items: [
          MorphMenuItem(title: 'Copy'),
          MorphMenuItem(title: 'Share'),
          MorphMenuItem(title: 'Rename'),
          MorphMenuItem(title: 'Move to folder'),
          MorphMenuItem(title: 'Delete', destructive: true),
        ],
      ),
    );
    final frames = await glyphTwice(
      tester,
      app,
      (frame) async {
        await tester.tap(find.byType(MorphMenuButton));
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await frame();
        }
        await tester.tapAt(const Offset(20, 20));
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await frame();
        }
      },
      () => tester
          .renderObjectList<RenderMorphGlyphs>(find.byType(MorphGlyphs))
          .any((g) => g.debugMode != MorphGlyphMode.live),
    );
    var rastered = 0;
    var worst = (max: 0, mean: 0.0, over: 0.0);
    for (final (exact, grid, active) in frames) {
      final d = glyphDiff(exact, grid);
      if (active) {
        rastered++;
        if (d.mean > worst.mean) worst = d;
      } else {
        expect(d.max, 0);
      }
    }
    debugPrint(
      'menu: ${frames.length} frames, $rastered from the raster, worst '
      'max ${worst.max} mean ${worst.mean.toStringAsFixed(4)} '
      'over15 ${worst.over.toStringAsFixed(3)}%',
    );
    expect(rastered, greaterThan(10));
    expect(worst.over, lessThan(0.2));
  });
}
