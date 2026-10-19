import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
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

  testWidgets('a raster refreshes with its child and is released at rest', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetDevicePixelRatio);
    final live = <ui.Image>{};
    var counting = true;
    final oldCreate = ui.Image.onCreate;
    final oldDispose = ui.Image.onDispose;
    ui.Image.onCreate = (image) {
      oldCreate?.call(image);
      if (counting) live.add(image);
    };
    ui.Image.onDispose = (image) {
      oldDispose?.call(image);
      live.remove(image);
    };
    addTearDown(() {
      ui.Image.onCreate = oldCreate;
      ui.Image.onDispose = oldDispose;
    });
    final cover = ValueNotifier<double>(1);
    addTearDown(cover.dispose);
    const key = ValueKey<String>('retained');
    Widget app(Color color, double scale) => glyphApp(
      Transform.scale(
        scale: scale,
        child: MorphGlyphs(
          cover: cover,
          child: SizedBox(
            key: key,
            width: 37.125,
            height: 22.25,
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
    RenderMorphGlyphs glyphs() =>
        tester.renderObject<RenderMorphGlyphs>(find.byType(MorphGlyphs));
    Future<List<int>> center() async {
      counting = false;
      final rect = tester.getRect(find.byKey(key));
      final boundary =
          tester.renderObject(find.byKey(glyphFrameKey))
              as RenderRepaintBoundary;
      final width = (boundary.size.width * 3).ceil();
      final offset =
          ((rect.center.dy * 3).floor() * width +
              (rect.center.dx * 3).floor()) *
          4;
      final pixel = (await glyphFrame(tester)).sublist(offset, offset + 4);
      counting = true;
      return pixel;
    }

    // Covered on its first frame: drawn from a raster.
    await tester.pumpWidget(app(const Color(0xFFFF0000), 0.8));
    expect(glyphs().debugMode, MorphGlyphMode.raster);
    expect(await center(), [255, 0, 0, 255]);
    expect(live, isNotEmpty);
    final first = {...live};
    // The child repaints while it moves: the raster is taken again, the
    // old one let go.
    await tester.pumpWidget(app(const Color(0xFF0000FF), 0.85));
    expect(glyphs().debugMode, MorphGlyphMode.raster);
    expect(await center(), [0, 0, 255, 255]);
    expect(live.intersection(first), isEmpty);
    // At rest the label is live and the raster released.
    cover.value = 0;
    await tester.pump();
    expect(glyphs().debugMode, MorphGlyphMode.live);
    expect(await center(), [0, 0, 255, 255]);
    expect(live, isEmpty);
    await tester.pumpWidget(const SizedBox());
    expect(live, isEmpty);
  });

  test('the grid passes through the device pixel ratio', () {
    for (final ratio in [1.0, 2.0, 2.625, 3.0]) {
      expect(MorphGlyphScale.snap(ratio, ratio), ratio);
      for (var s = 0.2; s < 3; s += 0.0137) {
        final snapped = MorphGlyphScale.snap(ratio * s, ratio);
        expect((snapped / (ratio * s) - 1).abs(), lessThan(0.0055));
      }
    }
    final grid = {
      for (var s = 1.0; s < 1.435; s += 0.0005)
        MorphGlyphScale.snap(2.625 * s, 2.625),
    };
    expect(grid.length, lessThanOrEqualTo(35));
  });

  testWidgets('a tab bar draws exact at rest and near while it moves', (
    tester,
  ) async {
    var selected = 0;
    Widget app() {
      selected = 0;
      return glyphApp(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => MorphTabBar(
            items: const [
              MorphTabItem(label: 'One', icon: IconData(0x41)),
              MorphTabItem(label: 'Two', icon: IconData(0x42)),
              MorphTabItem(label: 'Three', icon: IconData(0x43)),
              MorphTabItem(label: 'Four', icon: IconData(0x44)),
            ],
            selected: selected,
            onChanged: (int i) => setState(() => selected = i),
          ),
        ),
      );
    }

    final frames = await glyphTwice(tester, app, (frame) async {
      final bar = tester.getRect(find.byType(MorphTabBar));
      final from = Offset(bar.left + bar.width / 8, bar.center.dy);
      final to = Offset(bar.left + bar.width * 5 / 8, bar.center.dy);
      final gesture = await tester.startGesture(from);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await frame();
      }
      for (var i = 1; i <= 20; i++) {
        await gesture.moveTo(Offset.lerp(from, to, i / 20)!);
        await tester.pump(const Duration(milliseconds: 16));
        await frame();
      }
      await gesture.up();
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await frame();
      }
    }, () => true);
    var changed = 0;
    var worst = (max: 0, mean: 0.0, over: 0.0);
    for (final (exact, grid, _) in frames) {
      final d = glyphDiff(exact, grid);
      if (d.max > 0) changed++;
      if (d.mean > worst.mean) worst = d;
    }
    debugPrint(
      'tab bar: ${frames.length} frames, $changed differ, worst '
      'max ${worst.max} mean ${worst.mean.toStringAsFixed(4)} '
      'over15 ${worst.over.toStringAsFixed(3)}%',
    );
    expect(glyphDiff(frames.first.$1, frames.first.$2).max, 0);
    expect(glyphDiff(frames.last.$1, frames.last.$2).max, 0);
    expect(worst.over, lessThan(0.2));
  });
}
