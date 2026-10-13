import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glyph_scale.dart';
import 'package:morph/widgets.dart';

/// The device pixel ratio of the Pixel 6a the matrix cells run on.
const double _ratio = 2.625;

/// Replays which glyphs Impeller's glyph atlas has to rasterize and upload
/// (typographer_context_skia.cc CollectNewGlyphs): every glyph of every
/// painted paragraph is keyed as the atlas keys it (font, screen scale
/// rounded to 1/200, x subpixel quarter), and a frame that meets a key
/// the atlas does not hold yet is a strike frame, the frames the Pixel
/// spends 6 - 9 ms of raster time in UpdateAtlasBitmap. The atlas keeps
/// every glyph it struck, as Impeller's does until its texture reaches
/// the largest size.
class _Atlas {
  _Atlas(this.tester);

  final WidgetTester tester;
  final Set<(String, int, int, int)> _held = {};
  int frames = 0;
  int strikeFrames = 0;

  void frame({bool count = true}) {
    var struck = false;
    for (final p in tester.allRenderObjects.whereType<RenderParagraph>()) {
      if (!p.attached || !p.hasSize || _hidden(p)) continue;
      final m = _drawn(p);
      final scale = (MorphGlyphScale.of(m) * 200).round();
      final style = p.text.style;
      final font =
          '${style?.fontFamily} ${style?.fontSize} '
          '${style?.fontWeight}';
      final text = p.text.toPlainText();
      for (var i = 0; i < text.length; i++) {
        final unit = text.codeUnitAt(i);
        if (unit == 0x20 || unit == 0x0A) continue;
        final local = p.getOffsetForCaret(TextPosition(offset: i), Rect.zero);
        final x = MatrixUtils.transformPoint(m, local).dx + 0.125;
        final quarter = ((x - x.floorToDouble()) * 4).floor();
        if (_held.add((font, unit, scale, quarter))) struck = true;
      }
    }
    if (!count) return;
    frames++;
    if (struck) strikeFrames++;
  }

  static bool _hidden(RenderObject p) {
    for (RenderObject? o = p.parent; o != null; o = o.parent) {
      if (o is RenderOpacity && o.opacity == 0) return true;
      if (o is RenderAnimatedOpacity && o.opacity.value == 0) return true;
      if (o is RenderMorphGlyphs && o.opacity == 0) return true;
      if (o is RenderOffstage && o.offstage) return true;
    }
    return false;
  }

  /// The device transform [p] draws its glyphs with: through the snap of
  /// a [RenderMorphGlyphs] above it, or into its raster.
  static Matrix4 _drawn(RenderParagraph p) {
    RenderMorphGlyphs? glyphs;
    for (RenderObject? o = p.parent; o != null; o = o.parent) {
      if (o is RenderMorphGlyphs) {
        glyphs = o;
        break;
      }
    }
    final device = Matrix4.diagonal3Values(_ratio, _ratio, 1);
    if (glyphs == null) return device.multiplied(p.getTransformTo(null));
    final inner = p.getTransformTo(glyphs);
    final outer = glyphs.getTransformTo(null);
    switch (glyphs.debugMode) {
      case MorphGlyphMode.raster || MorphGlyphMode.shaded:
        final screen = MorphGlyphScale.of(outer) * _ratio;
        final r = MorphGlyphScale.rasterRatio(screen, _ratio);
        return Matrix4.diagonal3Values(r, r, 1).multiplied(inner);
      case MorphGlyphMode.snapped:
        final f = glyphs.debugFactor;
        final c = glyphs.size.center(Offset.zero);
        final snap = Matrix4.translationValues(c.dx, c.dy, 0)
            .multiplied(Matrix4.diagonal3Values(f, f, 1))
            .multiplied(Matrix4.translationValues(-c.dx, -c.dy, 0));
        return device.multiplied(outer).multiplied(snap).multiplied(inner);
      case MorphGlyphMode.live:
        return device.multiplied(outer).multiplied(inner);
    }
  }
}

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
  home: MorphGlass(
    painter: const MorphGlassRenderer(tier: MorphGlassTier.flat),
    child: Center(child: body),
  ),
);

/// Plays a matrix cell three times, as the device bench does, with
/// frame times jittered by up to a millisecond either way and touches
/// landing at a different phase of the frame each time: the device never
/// samples a spring at the same times twice.
class _Bench {
  _Bench(this.tester) : atlas = _Atlas(tester);

  final WidgetTester tester;
  final _Atlas atlas;
  int _seed = 1;
  int _phase = 0;

  Future<void> frames(int ms) async {
    for (var t = 0; t < ms; t += 16) {
      _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
      await tester.pump(Duration(microseconds: 15667 + _seed % 2000));
      atlas.frame();
    }
  }

  Future<void> land() async {
    _phase = (_phase + 7) % 16;
    await tester.pump(Duration(milliseconds: _phase));
    atlas.frame();
  }

  /// A touch at [at] held 60 ms, as the bench's taps are.
  Future<void> tap(Offset at) async {
    await land();
    final gesture = await tester.startGesture(at);
    await frames(60);
    await gesture.up();
  }
}

void main() {
  setUpAll(() async {
    isLocalTest = true;
    await MorphGlyphs.precache();
  });

  Future<void> bench(
    WidgetTester tester,
    String name,
    Widget body,
    Future<void> Function(_Bench bench) cell, {
    required int ceiling,
  }) async {
    tester.view.devicePixelRatio = _ratio;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(body));
    await tester.pump(const Duration(milliseconds: 100));
    final run = _Bench(tester);
    run.atlas.frame(count: false);
    for (var i = 0; i < 3; i++) {
      await cell(run);
    }
    debugPrint(
      '$name: ${run.atlas.strikeFrames} strike frames of '
      '${run.atlas.frames}',
    );
    expect(run.atlas.strikeFrames, lessThanOrEqualTo(ceiling));
  }

  // Strike frames over three runs before the alert and the date picker
  // drew through the glyph policy: tab bar 16, alert 67, date picker 124.
  // The tab bar's are the live drift of its swell's tail (below
  // MorphGlyphPolicy.restSteps) and the first visits of its grid scales.
  testWidgets('tab-bar/tap strikes its first visits and its drift', (
    tester,
  ) async {
    var selected = 0;
    await bench(
      tester,
      'tab-bar/tap',
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => MorphTabBar(
          items: const [
            MorphTabItem(label: 'Home', icon: IconData(0x41)),
            MorphTabItem(label: 'Library', icon: IconData(0x42)),
            MorphTabItem(label: 'Radio', icon: IconData(0x43)),
          ],
          selected: selected,
          onChanged: (int i) => setState(() => selected = i),
        ),
      ),
      (run) async {
        for (final label in ['Radio', 'Home']) {
          await run.tap(tester.getCenter(find.text(label).first));
          await run.frames(900);
        }
      },
      ceiling: 16,
    );
  });

  testWidgets('alert/open-close strikes only its first visits', (tester) async {
    late BuildContext context;
    await bench(
      tester,
      'alert/open-close',
      Builder(
        builder: (BuildContext c) {
          context = c;
          return const SizedBox(width: 10, height: 10);
        },
      ),
      (run) async {
        await run.land();
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
        await run.frames(900);
        await run.tap(tester.getCenter(find.text('OK')));
        await run.frames(900);
      },
      ceiling: 3,
    );
  });

  testWidgets('date-picker/open-close strikes only its first visits', (
    tester,
  ) async {
    var value = DateTime(2026, 10, 12);
    await bench(
      tester,
      'date-picker/open-close',
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) =>
            MorphDatePicker(
              value: value,
              today: DateTime(2026, 10, 12),
              onChanged: (DateTime v) => setState(() => value = v),
            ),
      ),
      (run) async {
        await run.tap(tester.getCenter(find.byType(MorphDatePicker)));
        await run.frames(900);
        await run.tap(const Offset(20, 120));
        await run.frames(900);
      },
      ceiling: 2,
    );
  });
}
