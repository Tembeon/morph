import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/glyph_scale.dart';
import 'package:morph/widgets.dart';

/// The frame every glyph scale scene is drawn in.
/// The key of the scene's repaint boundary.
const glyphFrameKey = ValueKey<String>('frame');

/// The scene around [body]: the liquid renderer over black.
Widget glyphApp(Widget body) => WidgetsApp(
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
    key: glyphFrameKey,
    child: ColoredBox(color: const Color(0xFF000000), child: child),
  ),
  home: MorphGlassScope(
    painter: const MorphGlassRenderer(tier: MorphGlassTier.liquid),
    child: Center(child: body),
  ),
);

/// The scene's current frame at 3x, RGBA.
Future<Uint8List> glyphFrame(WidgetTester tester) async {
  final boundary =
      tester.renderObject(find.byKey(glyphFrameKey)) as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData();
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

/// The largest channel difference of two frames, their mean channel
/// difference per pixel and the share of pixels over [threshold], in
/// percent.
({int max, double mean, double over}) glyphDiff(
  Uint8List a,
  Uint8List b, {
  int threshold = 15,
}) {
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
    if (m > threshold) over++;
  }
  final pixels = a.length / 4;
  return (max: max, mean: sum / pixels, over: over / pixels * 100);
}

/// Plays [script] twice, once exact and once with the glyph grid, and
/// returns every pumped frame of both.
Future<List<(Uint8List, Uint8List, bool)>> glyphTwice(
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
      frames.add((await glyphFrame(tester), active()));
    });
    runs.add(frames);
  }
  MorphGlyphScale.debugExact = false;
  return [
    for (var i = 0; i < runs[0].length; i++)
      (runs[0][i].$1, runs[1][i].$1, runs[1][i].$2),
  ];
}
