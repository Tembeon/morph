// The test reads the widget layer's internals.
// ignore_for_file: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/liquid_field.dart';
import 'package:morph/src/widgets/flat_body_shader.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/widgets.dart';

const double _spacing = 12;
const Color _color = Color(0xE6F2F2F7);

/// A row of capsules [height] high (or the heights given per capsule),
/// [widths] wide, [gaps] apart, centered on one line.
List<RRect> _row(
  List<double> widths,
  List<double> gaps, {
  List<double>? heights,
}) {
  final shapes = <RRect>[];
  var left = 16.0;
  for (var i = 0; i < widths.length; i++) {
    final h = heights?[i] ?? 44.0;
    shapes.add(
      RRect.fromLTRBR(
        left,
        40 - h / 2,
        left + widths[i],
        40 + h / 2,
        Radius.circular(h / 2),
      ),
    );
    if (i < gaps.length) left += widths[i] + gaps[i];
  }
  return shapes;
}

/// Every row the comparison draws: two to four capsules, gaps around the
/// spacing, closed necks and overlaps.
final List<List<RRect>> _rows = [
  for (final gap in [-4.0, 0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 11.0])
    _row([44, 44], [gap]),
  _row([44, 60, 44], [6, 9]),
  _row([44, 60, 44], [2, 4]),
  _row([80, 44, 44], [10, 3]),
  _row([44, 44, 44, 44], [3, 7, 10]),
  _row([44, 44, 44, 44], [5, 5, 5]),
  _row([60, 44, 52, 44], [11, 1, 8]),
  _row([44, 44], [4], heights: [44, 36]),
  _row([44, 60, 44], [8, 2], heights: [36, 44, 36]),
];

const _width = 320;
const _height = 80;

Future<Uint8List> _render(
  WidgetTester tester,
  double ratio,
  void Function(Canvas canvas) draw,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(ratio);
  draw(canvas);
  final picture = recorder.endRecording();
  final bytes = await tester.runAsync(() async {
    final image = await picture.toImage(
      (_width * ratio).round(),
      (_height * ratio).round(),
    );
    final data = await image.toByteData();
    image.dispose();
    return data!.buffer.asUint8List();
  });
  picture.dispose();
  return bytes!;
}

Future<Uint8List> _path(WidgetTester tester, double ratio, Path path) =>
    _render(tester, ratio, (canvas) {
      final paint = Paint();
      paint.color = _color;
      canvas.drawPath(path, paint);
    });

Future<Uint8List> _shader(
  WidgetTester tester,
  double ratio,
  List<RRect> shapes,
) => _render(tester, ratio, (canvas) {
  expect(
    MorphFlatBodyShader.paint(canvas, shapes, _spacing, ratio, fill: _color),
    isTrue,
  );
});

/// The merge law evaluated per pixel on the CPU ([LiquidField.eval]) with
/// the shader's coverage: what the shader must draw, up to float
/// precision and the 8-bit rounding of premultiplication.
Uint8List _law(double ratio, List<RRect> shapes) {
  final field = LiquidField([
    for (final shape in shapes)
      MorphMass.box(shape.outerRect, radius: shape.tlRadiusX),
  ], k: _spacing);
  final w = (_width * ratio).round();
  final h = (_height * ratio).round();
  final out = Uint8List(w * h * 4);
  final a = _color.a;
  for (var j = 0; j < h; j++) {
    for (var i = 0; i < w; i++) {
      final d = field.eval(Offset((i + 0.5) / ratio, (j + 0.5) / ratio));
      final cover = (0.5 - d * ratio).clamp(0.0, 1.0);
      final at = (j * w + i) * 4;
      out[at] = (_color.r * a * cover * 255).round();
      out[at + 1] = (_color.g * a * cover * 255).round();
      out[at + 2] = (_color.b * a * cover * 255).round();
      out[at + 3] = (a * cover * 255).round();
    }
  }
  return out;
}

/// The largest and the mean channel difference of two frames over the
/// pixels either covers.
({int max, double mean}) _diff(Uint8List a, Uint8List b) {
  var max = 0;
  var sum = 0;
  var covered = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i + 3] == 0 && b[i + 3] == 0) continue;
    covered++;
    var m = 0;
    for (var k = 0; k < 4; k++) {
      m = math.max(m, (a[i + k] - b[i + k]).abs());
    }
    max = math.max(max, m);
    sum += m;
  }
  return (max: max, mean: covered == 0 ? 0 : sum / covered);
}

String _mean(double sum) => (sum / _rows.length).toStringAsFixed(3);

String _f(({int max, double mean}) d) =>
    '${d.max}/${d.mean.toStringAsFixed(3)}';

MorphGlassSurface _bar(RRect shape, {Color color = _color}) =>
    MorphGlassSurface(
      kind: MorphGlassKind.bar,
      shape: shape,
      color: color,
      brightness: Brightness.light,
    );

MorphBarButton _icon(String id) => MorphBarButton(
  id: id,
  icon: const SizedBox.square(dimension: 24),
  semanticLabel: id,
  onPressed: () {},
);

Widget _toolbar(List<MorphBarButtonGroup> leading) {
  final bar = MorphToolbar(
    leading: leading,
    trailing: [
      MorphBarButtonGroup([_icon('compose')]),
    ],
  );
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(402, 874),
        padding: EdgeInsets.only(top: 62, bottom: 34),
      ),
      child: Stack(children: [Positioned.fill(child: bar)]),
    ),
  );
}

void main() {
  setUpAll(() => isLocalTest = true);
  setUp(debugClearMorphGlassOutlines);
  tearDown(() {
    MorphFlatBodyShader.debugEnabled = null;
    debugMorphFusionStep = 2;
    debugClearMorphGlassOutlines();
  });

  testWidgets('the shader fills the merge law: against the CPU law per '
      'pixel, the traced outline and a fine trace', (tester) async {
    await tester.runAsync(MorphFlatBodyShader.precache);
    expect(MorphFlatBodyShader.ready, isTrue);
    for (final ratio in [2.0, 3.0]) {
      // Per comparison: the largest max and the sum of the per-row means.
      final worst = <String, int>{};
      final sums = <String, double>{};
      void add(String name, ({int max, double mean}) d) {
        worst[name] = math.max(worst[name] ?? 0, d.max);
        sums[name] = (sums[name] ?? 0) + d.mean;
      }

      for (final shapes in _rows) {
        final shaded = await _shader(tester, ratio, shapes);
        final law = _law(ratio, shapes);
        debugMorphFusionStep = 2;
        debugClearMorphGlassOutlines();
        final traced = await _path(
          tester,
          ratio,
          morphGlassContainerOutline(shapes, _spacing, withField: false).path,
        );
        debugMorphFusionStep = 0.25;
        debugClearMorphGlassOutlines();
        final fine = await _path(
          tester,
          ratio,
          morphGlassContainerOutline(shapes, _spacing, withField: false).path,
        );
        final row = {
          'shader vs law': _diff(shaded, law),
          'shader vs 2 pt trace': _diff(shaded, traced),
          'shader vs 0.25 pt trace': _diff(shaded, fine),
          '2 pt trace vs law': _diff(traced, law),
          '0.25 pt trace vs law': _diff(fine, law),
        };
        row.forEach(add);
        final boxes = [
          for (final s in shapes)
            '${s.left.toStringAsFixed(0)}-${s.right.toStringAsFixed(0)}',
        ].join(' ');
        final values = [
          for (final MapEntry(:key, :value) in row.entries) '$key ${_f(value)}',
        ].join(', ');
        debugPrint(
          'dpr $ratio, ${shapes.length} capsules $boxes (max/mean): '
          '$values',
        );
        // The shader is the law, up to float precision.
        expect(
          row['shader vs law']!.max,
          lessThanOrEqualTo(2),
          reason: 'dpr $ratio $shapes',
        );
      }
      final summary = [
        for (final name in worst.keys)
          '$name ${worst[name]}/${_mean(sums[name]!)}',
      ].join(', ');
      debugPrint(
        'dpr $ratio over ${_rows.length} rows (largest max / mean of the '
        'per-row means): $summary',
      );
    }
  });

  test('flat container bodies of up to four boxes carry their boxes and '
      'trace nothing', () {
    MorphFlatBodyShader.debugEnabled = true;
    final shapes = _row([44, 44, 44], [4, 6]);
    final traces = morphGlassOutlineDebugTraces;
    final frame = MorphGlassFrame([
      for (final s in shapes) _bar(s),
    ], spacing: _spacing);
    final (members, outline) = frame.partsFor(MorphGlassTier.flat).fused.single;
    expect(members, hasLength(3));
    final merged = morphGlassOutlineMergedBoxes(outline);
    expect(merged?.boxes, shapes);
    expect(merged?.spacing, _spacing);
    expect(morphGlassOutlineDebugTraces, traces);
    // The same shapes hand back the same outline; a moved one stays merged.
    expect(
      MorphGlassFrame([
        for (final s in shapes) _bar(s),
      ], spacing: _spacing).partsFor(MorphGlassTier.flat).fused.single.$2,
      same(outline),
    );
    final moved = outline.shift(const Offset(3, 1));
    expect(morphGlassOutlineMergedBoxes(moved)?.boxes, [
      for (final s in shapes) s.shift(const Offset(3, 1)),
    ]);
    expect(morphGlassOutlineDebugTraces, traces);
    // The path is traced only when read, by the package's own fusion.
    expect(
      outline.path.getBounds(),
      morphGlassContainerOutline(
        shapes,
        _spacing,
        withField: false,
      ).path.getBounds(),
    );
    // Five boxes and the other tiers keep the traced outline.
    final five = _row([44, 44, 44, 44, 44], [4, 4, 4, 4]);
    final fiveFrame = MorphGlassFrame([
      for (final s in five) _bar(s),
    ], spacing: _spacing);
    expect(
      morphGlassOutlineMergedBoxes(
        fiveFrame.partsFor(MorphGlassTier.flat).fused.single.$2,
      ),
      isNull,
    );
    expect(
      morphGlassOutlineMergedBoxes(
        frame.partsFor(MorphGlassTier.fake).fused.single.$2,
      ),
      isNull,
    );
    MorphFlatBodyShader.debugEnabled = false;
    expect(
      morphGlassOutlineMergedBoxes(
        MorphGlassFrame([
          for (final s in shapes) _bar(s),
        ], spacing: _spacing).partsFor(MorphGlassTier.flat).fused.single.$2,
      ),
      isNull,
    );
  });

  Future<Uint8List> layer(WidgetTester tester, List<RRect> shapes) async {
    const key = ValueKey<String>('layer');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: _width.toDouble(),
              height: _height.toDouble(),
              child: Builder(
                builder: (context) =>
                    const MorphGlassRenderer(
                      tier: MorphGlassTier.flat,
                    ).buildLayer(context, [
                      for (final s in shapes) _bar(s),
                    ], spacing: _spacing),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData();
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  testWidgets('the flat renderer fills merged bodies by the shader', (
    tester,
  ) async {
    await tester.runAsync(MorphFlatBodyShader.precache);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);
    final shapes = _row([44, 60, 44], [6, 9]);
    final traced = await layer(tester, shapes);
    MorphFlatBodyShader.debugEnabled = true;
    debugClearMorphGlassOutlines();
    final traces = morphGlassOutlineDebugTraces;
    final shaded = await layer(tester, shapes);
    expect(morphGlassOutlineDebugTraces, traces);
    final d = _diff(shaded, traced);
    debugPrint('flat renderer layer, shader vs traced outline: ${_f(d)}');
    expect(d.mean, lessThan(1));
  });

  testWidgets('flat bar capsules without a painter fuse through the shader', (
    tester,
  ) async {
    await tester.runAsync(MorphFlatBodyShader.precache);
    MorphFlatBodyShader.debugEnabled = true;
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _toolbar([
        MorphBarButtonGroup([_icon('trash'), _icon('folder')]),
      ]),
    );
    await tester.pumpAndSettle();
    final bar = find.byType(MorphToolbar);
    final traces = morphGlassOutlineDebugTraces;
    await tester.pumpWidget(
      _toolbar([
        MorphBarButtonGroup([_icon('trash')]),
        MorphBarButtonGroup([_icon('folder')]),
      ]),
    );
    var fused = false;
    for (var i = 0; i < 30 && !fused; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final object = tester.renderObject<RenderBox>(bar);
      // A fused body is a shaded rect over its bounds: its fill and its
      // shadow's, under a blur layer.
      final pattern = paints;
      pattern.something(_shadedRect);
      pattern.something(_shadedRect);
      fused = _paints(object, pattern);
      if (fused) {
        final traced = paints;
        traced.path();
        expect(object, isNot(traced));
      }
    }
    expect(fused, isTrue);
    expect(morphGlassOutlineDebugTraces, traces);
    await tester.pumpAndSettle();
  });
}

bool _shadedRect(Symbol method, List<dynamic> arguments) =>
    method == #drawRect && (arguments[1] as Paint).shader != null;

bool _paints(RenderObject object, Object matcher) {
  try {
    expect(object, matcher);
    return true;
  } on TestFailure {
    return false;
  }
}
