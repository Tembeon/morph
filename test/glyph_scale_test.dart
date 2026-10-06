import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glyph_scale.dart';
import 'package:morph/widgets.dart';

const _frameKey = ValueKey<String>('frame');

Widget _app(Widget body) => WidgetsApp(
  color: const Color(0xFF007AFF),
  pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
      PageRouteBuilder<T>(
        settings: settings,
        pageBuilder:
            (
              BuildContext context,
              Animation<double> animation,
              Animation<double> secondaryAnimation,
            ) => builder(context),
      ),
  builder: (BuildContext context, Widget? child) => RepaintBoundary(
    key: _frameKey,
    child: ColoredBox(color: const Color(0xFF000000), child: child),
  ),
  home: MorphGlass(
    painter: const MorphGlassRenderer(tier: MorphGlassTier.liquid),
    child: Center(child: body),
  ),
);

Future<Uint8List> _frame(WidgetTester tester) async {
  final boundary =
      tester.renderObject(find.byKey(_frameKey)) as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData();
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

/// The largest channel difference of two frames, their mean channel
/// difference per pixel and the share of pixels over 15, in percent.
({int max, double mean, double over}) _diff(Uint8List a, Uint8List b) {
  var max = 0;
  var sum = 0;
  var over = 0;
  for (var i = 0; i < a.length; i += 4) {
    var m = 0;
    for (var k = 0; k < 3; k++) {
      m = math.max(m, (a[i + k] - b[i + k]).abs());
    }
    max = math.max(max, m);
    sum += m;
    if (m > 15) over++;
  }
  final pixels = a.length / 4;
  return (max: max, mean: sum / pixels, over: over / pixels * 100);
}

/// Plays [script] twice, once exact and once with the glyph grid, and
/// returns every pumped frame of both.
Future<List<(Uint8List, Uint8List, bool)>> _twice(
  WidgetTester tester,
  Widget Function() app,
  Future<void> Function(Future<void> Function() frame) script,
  bool Function() active,
) async {
  final runs = <List<(Uint8List, bool)>>[];
  for (final exact in [true, false]) {
    MorphGlyphScale.debugExact = exact;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 100));
    final frames = <(Uint8List, bool)>[];
    await script(() async {
      frames.add((await _frame(tester), active()));
    });
    runs.add(frames);
  }
  MorphGlyphScale.debugExact = false;
  return [
    for (var i = 0; i < runs[0].length; i++)
      (runs[0][i].$1, runs[1][i].$1, runs[1][i].$2),
  ];
}

void main() {
  setUpAll(() => isLocalTest = true);

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

  testWidgets('a tab bar lens draws its copy on the grid only while lifting', (
    tester,
  ) async {
    var selected = 0;
    Widget app() {
      selected = 0;
      return _app(
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

    final frames = await _twice(tester, app, (frame) async {
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
      final d = _diff(exact, grid);
      if (d.max > 0) changed++;
      if (d.mean > worst.mean) worst = d;
    }
    debugPrint(
      'tab bar: ${frames.length} frames, $changed differ, worst '
      'max ${worst.max} mean ${worst.mean.toStringAsFixed(4)} '
      'over15 ${worst.over.toStringAsFixed(3)}%',
    );
    expect(_diff(frames.first.$1, frames.first.$2).max, 0);
    expect(_diff(frames.last.$1, frames.last.$2).max, 0);
    expect(worst.over, lessThan(0.2));
  });

  testWidgets('menu rows draw from one raster only under the content blur', (
    tester,
  ) async {
    Widget app() => _app(
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
    final frames = await _twice(
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
      () {
        final raster = find.byType(MorphGlyphRaster);
        if (raster.evaluate().isEmpty) return false;
        return tester.widget<MorphGlyphRaster>(raster.first).active.value;
      },
    );
    var rastered = 0;
    var worst = (max: 0, mean: 0.0, over: 0.0);
    for (final (exact, grid, active) in frames) {
      final d = _diff(exact, grid);
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
