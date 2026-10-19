import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glyph_scale.dart';
import 'package:morph/morph.dart';

import 'support/glyph_scale_frames.dart';

void main() {
  setUpAll(() async {
    isLocalTest = true;
    await MorphGlyphs.precache();
  });

  testWidgets('a date picker overlay scales in from one raster', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget app() => glyphApp(
      MorphDatePicker(
        value: DateTime(2026, 10, 12),
        today: DateTime(2026, 10, 12),
        onChanged: (_) {},
      ),
    );
    final frames = await glyphTwice(
      tester,
      app,
      (frame) async {
        await tester.tap(find.byType(MorphDatePicker));
        for (var i = 0; i < 70; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await frame();
        }
        await tester.tapAt(const Offset(20, 20));
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await frame();
        }
      },
      () => tester
          .renderObjectList<RenderMorphGlyphs>(find.byType(MorphGlyphs))
          .any((g) => g.debugMode != MorphGlyphMode.live),
    );
    var moving = 0;
    var worst = (max: 0, mean: 0.0, over: 0.0);
    for (final (exact, grid, active) in frames) {
      final d = glyphDiff(exact, grid);
      if (active) {
        moving++;
        if (d.mean > worst.mean) worst = d;
      } else {
        expect(d.max, 0);
      }
    }
    debugPrint(
      'date picker: ${frames.length} frames, $moving off live, worst '
      'max ${worst.max} mean ${worst.mean.toStringAsFixed(4)} '
      'over15 ${worst.over.toStringAsFixed(3)}%',
    );
    expect(moving, greaterThan(10));
    expect(worst.over, lessThan(0.5));
  });

  for (final (name, wait, act)
      in <(String, int, Future<void> Function(WidgetTester))>[
        ('a day', 36, (tester) => tester.tap(find.text('20').last)),
        (
          'the next month',
          60,
          (tester) {
            final title = tester.getRect(find.text('October 2026').last);
            final overlay = tester.getRect(find.byType(MorphGlyphs).last);
            return tester.tapAt(Offset(overlay.right - 24, title.center.dy));
          },
        ),
      ]) {
    testWidgets('a date picker still settling draws $name changing', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget app() => glyphApp(
        MorphDatePicker(
          value: DateTime(2026, 10, 12),
          today: DateTime(2026, 10, 12),
          onChanged: (_) {},
        ),
      );
      final frames = await glyphTwice(
        tester,
        app,
        (frame) async {
          await tester.tap(find.byType(MorphDatePicker));
          for (var i = 0; i < wait; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          await act(tester);
          for (var i = 0; i < 40; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            await frame();
          }
        },
        () => tester
            .renderObjectList<RenderMorphGlyphs>(find.byType(MorphGlyphs))
            .any((g) => g.debugMode != MorphGlyphMode.live),
      );
      var moving = 0;
      var worst = (max: 0, mean: 0.0, over: 0.0);
      for (final (exact, grid, active) in frames) {
        final d = glyphDiff(exact, grid);
        if (active) moving++;
        if (d.mean > worst.mean) worst = d;
      }
      debugPrint(
        'date picker $name: ${frames.length} frames, $moving off live, '
        'worst max ${worst.max} mean ${worst.mean.toStringAsFixed(4)} '
        'over15 ${worst.over.toStringAsFixed(3)}%',
      );
      expect(moving, greaterThan(0));
      expect(worst.over, lessThan(0.5));
    });
  }
}
