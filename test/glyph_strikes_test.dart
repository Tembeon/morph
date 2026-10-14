import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/content_snapshot.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_liquid_draw.dart';
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
  _Atlas(this.tester) {
    MorphGlassContentCopy.debugOnItem = (slot, strip, base, item) =>
        _items.add((slot, strip, base, item));
  }

  final WidgetTester tester;
  final Set<(String, int, int, int)> _held = {};
  final List<(Rect, Rect, Float64List, Float64List)> _items = [];
  int frames = 0;
  int strikeFrames = 0;

  /// The glyph keys first struck in the last run of a bench.
  int lastRunKeys = 0;

  /// The glyph keys struck so far.
  int get keys => _held.length;

  /// The distinct screen scales, in the atlas's 1/200 steps, struck so far.
  Set<int> get scales => {for (final key in _held) key.$3};

  void dispose() => MorphGlassContentCopy.debugOnItem = null;

  bool _strike(RenderParagraph p, Matrix4 m) {
    final scale = (MorphGlyphScale.of(m) * 200).round();
    final style = p.text.style;
    final font =
        '${style?.fontFamily} ${style?.fontSize} '
        '${style?.fontWeight}';
    final text = p.text.toPlainText();
    var struck = false;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x20 || unit == 0x0A) continue;
      final local = p.getOffsetForCaret(TextPosition(offset: i), Rect.zero);
      final x = MatrixUtils.transformPoint(m, local).dx + 0.125;
      final quarter = ((x - x.floorToDouble()) * 4).floor();
      if (_held.add((font, unit, scale, quarter))) struck = true;
    }
    return struck;
  }

  void frame({bool count = true}) {
    var struck = false;
    for (final p in tester.allRenderObjects.whereType<RenderParagraph>()) {
      if (!p.attached || !p.hasSize || _hidden(p)) continue;
      if (_strike(p, _drawn(p))) struck = true;
    }
    if (_copies()) struck = true;
    _items.clear();
    if (!count) return;
    frames++;
    if (struck) strikeFrames++;
  }

  /// Strikes the glyphs the lens copies replayed this frame: every item
  /// the copy drew replays the content's recorded paint, the paragraphs
  /// centered in the item's slot, under the copy's transform.
  bool _copies() {
    if (_items.isEmpty) return false;
    final copy = tester.renderObject(
      find.descendant(
        of: find.byType(MorphGlassContentCopy),
        matching: find.byType(MorphScreenScalePaint),
      ),
    );
    final source = tester.renderObject(find.byType(GlassContentSource));
    final lens = tester
        .widget<MorphGlassContentCopy>(find.byType(MorphGlassContentCopy))
        .surface
        .bounds;
    final device = Matrix4.diagonal3Values(
      _ratio,
      _ratio,
      1,
    ).multiplied(copy.getTransformTo(null));
    var struck = false;
    for (final (slot, strip, base, item) in _items) {
      final local = Matrix4.inverted(
        Matrix4.fromFloat64List(base),
      ).multiplied(Matrix4.fromFloat64List(item));
      final screen = device.multiplied(local);
      for (final p in tester.allRenderObjects.whereType<RenderParagraph>()) {
        if (!p.attached || !p.hasSize || _hidden(p)) continue;
        if (!_inside(p, source) || _rastered(p)) continue;
        final content = _content(p, source);
        final bounds = MatrixUtils.transformRect(content, Offset.zero & p.size);
        if (!slot.contains(bounds.center)) continue;
        final shown = MatrixUtils.transformRect(local, bounds);
        if (!shown.overlaps(strip) || !shown.overlaps(lens)) continue;
        if (_strike(p, screen.multiplied(content))) struck = true;
      }
    }
    return struck;
  }

  /// Whether [p] was recorded into its content as an image: a raster of
  /// a [RenderMorphGlyphs] above it.
  static bool _rastered(RenderParagraph p) {
    for (RenderObject? o = p.parent; o != null; o = o.parent) {
      if (o is RenderMorphGlyphs) {
        return o.debugMode == MorphGlyphMode.raster ||
            o.debugMode == MorphGlyphMode.shaded;
      }
    }
    return false;
  }

  static bool _inside(RenderObject p, RenderObject ancestor) {
    for (RenderObject? o = p.parent; o != null; o = o.parent) {
      if (identical(o, ancestor)) return true;
    }
    return false;
  }

  /// The transform [p] is recorded with in [source]'s coordinates.
  static Matrix4 _content(RenderParagraph p, RenderObject source) {
    RenderMorphGlyphs? glyphs;
    for (RenderObject? o = p.parent; o != source; o = o!.parent) {
      if (o is RenderMorphGlyphs) {
        glyphs = o;
        break;
      }
    }
    if (glyphs == null) return p.getTransformTo(source);
    return glyphs
        .getTransformTo(source)
        .multiplied(glyphs.debugPaintTransform)
        .multiplied(p.getTransformTo(glyphs));
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
      case MorphGlyphMode.snapped || MorphGlyphMode.live:
        return device
            .multiplied(outer)
            .multiplied(glyphs.debugPaintTransform)
            .multiplied(inner);
    }
  }
}

Widget _app(Widget body, MorphGlassTier tier) => WidgetsApp(
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
  home: MorphGlassScope(
    painter: MorphGlassRenderer(tier: tier),
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

  Future<_Atlas> bench(
    WidgetTester tester,
    String name,
    Widget body,
    Future<void> Function(_Bench bench) cell, {
    required int ceiling,
    MorphGlassTier tier = MorphGlassTier.flat,
  }) async {
    tester.view.devicePixelRatio = _ratio;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(body, tier));
    await tester.pump(const Duration(milliseconds: 100));
    final run = _Bench(tester);
    addTearDown(run.atlas.dispose);
    run.atlas.frame(count: false);
    final keys = <int>[];
    for (var i = 0; i < 3; i++) {
      final before = run.atlas.keys;
      await cell(run);
      keys.add(run.atlas.keys - before);
    }
    run.atlas.lastRunKeys = keys.last;
    debugPrint(
      '$name: ${run.atlas.strikeFrames} strike frames of '
      '${run.atlas.frames}, new keys per run ${keys.join(' / ')}, '
      '${run.atlas.scales.length} scales',
    );
    expect(run.atlas.strikeFrames, lessThanOrEqualTo(ceiling));
    return run.atlas;
  }

  Widget tabBar() {
    var selected = 0;
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) => MorphTabBar(
        items: const [
          MorphTabItem(label: 'Home', icon: IconData(0x41)),
          MorphTabItem(label: 'Library', icon: IconData(0x42)),
          MorphTabItem(label: 'Radio', icon: IconData(0x43)),
        ],
        selected: selected,
        onChanged: (int i) => setState(() => selected = i),
      ),
    );
  }

  Future<void> tabTap(WidgetTester tester, _Bench run) async {
    for (final label in ['Radio', 'Home']) {
      await run.tap(tester.getCenter(find.text(label).first));
      await run.frames(900);
    }
  }

  Future<void> tabDrag(WidgetTester tester, _Bench run) async {
    final a = tester.getCenter(find.text('Home').first);
    final b = tester.getCenter(find.text('Radio').first);
    await run.land();
    final gesture = await tester.startGesture(a);
    await run.frames(300);
    for (var i = 1; i <= 40; i++) {
      await gesture.moveTo(Offset.lerp(a, b, i / 40)!);
      await run.frames(16);
    }
    await gesture.up();
    await run.frames(900);
    await run.tap(a);
    await run.frames(900);
  }

  // Strike frames over three runs before the alert and the date picker
  // drew through the glyph policy: tab bar 16, alert 67, date picker 124.
  // Before the tab bar's labels aligned, strike frames (glyph keys new in
  // each run): tap flat 16 (192 / 33 / 22), drag flat 39 (492 / 56 / 13),
  // tap liquid 124 (1369 / 612 / 235), drag liquid 161 (1783 / 559 / 223),
  // the liquid tier's mostly its lens copy's.
  const ceilings = {
    ('tap', MorphGlassTier.flat): 4,
    ('drag', MorphGlassTier.flat): 6,
    ('tap', MorphGlassTier.liquid): 39,
    ('drag', MorphGlassTier.liquid): 36,
  };
  for (final MapEntry(key: (cell, tier), value: ceiling) in ceilings.entries) {
    testWidgets('tab-bar/$cell/${tier.name} strikes mostly its first visits', (
      tester,
    ) async {
      final atlas = await bench(
        tester,
        'tab-bar/$cell/${tier.name}',
        tabBar(),
        (run) => cell == 'tap' ? tabTap(tester, run) : tabDrag(tester, run),
        tier: tier,
        ceiling: ceiling,
      );
      expect(atlas.lastRunKeys, lessThanOrEqualTo(30));
    });
  }

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
