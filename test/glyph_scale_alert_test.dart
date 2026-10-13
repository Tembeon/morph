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

  testWidgets('an alert scales in from one raster and rests exact', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext context;
    Widget app() => glyphApp(
      Builder(
        builder: (BuildContext c) {
          context = c;
          return const SizedBox(width: 10, height: 10);
        },
      ),
    );
    final frames = await glyphTwice(
      tester,
      app,
      (frame) async {
        showMorphAlert(
          context,
          title: 'Title',
          message: 'A message in the alert.',
          actions: const [
            MorphAlertAction(
              title: 'Cancel',
              style: MorphAlertActionStyle.cancel,
            ),
            MorphAlertAction(title: 'OK'),
          ],
        ).ignore();
        for (var i = 0; i < 70; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await frame();
        }
        await tester.tap(find.text('OK'));
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
      if (active) {
        moving++;
        if (d.mean > worst.mean) worst = d;
      } else {
        expect(d.max, 0);
      }
    }
    debugPrint(
      'alert: ${frames.length} frames, $moving off live, worst '
      'max ${worst.max} mean ${worst.mean.toStringAsFixed(4)} '
      'over15 ${worst.over.toStringAsFixed(3)}%',
    );
    expect(moving, greaterThan(10));
    expect(worst.over, lessThan(0.5));
  });

  testWidgets('an alert draws its highlight moving under a pressed scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext context;
    Widget app() => glyphApp(
      Builder(
        builder: (BuildContext c) {
          context = c;
          return const SizedBox(width: 10, height: 10);
        },
      ),
    );
    final frames = await glyphTwice(
      tester,
      app,
      (frame) async {
        showMorphAlert(
          context,
          title: 'Title',
          message: 'A message in the alert.',
          actions: const [
            MorphAlertAction(
              title: 'Cancel',
              style: MorphAlertActionStyle.cancel,
            ),
            MorphAlertAction(title: 'OK'),
          ],
        ).ignore();
        for (var i = 0; i < 70; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Cancel')),
        );
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await frame();
        }
        await gesture.moveTo(tester.getCenter(find.text('OK')));
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await frame();
        }
        await gesture.cancel();
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      },
      () => tester
          .renderObjectList<RenderMorphGlyphs>(find.byType(MorphGlyphs))
          .any((g) => g.debugMode != MorphGlyphMode.live),
    );
    var moving = 0;
    var worst = (max: 0, mean: 0.0, over: 0.0);
    for (final (exact, grid, active) in frames) {
      final d = glyphDiff(exact, grid, threshold: 3);
      if (active) moving++;
      if (d.mean > worst.mean) worst = d;
    }
    debugPrint(
      'alert highlight: ${frames.length} frames, $moving off live, worst '
      'max ${worst.max} mean ${worst.mean.toStringAsFixed(4)} '
      'over3 ${worst.over.toStringAsFixed(3)}%',
    );
    expect(moving, greaterThan(0));
    expect(worst.over, lessThan(0.5));
  });
}
