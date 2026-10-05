/// The synthetic shader harness: deterministic glass cases rendered
/// offscreen through the package's runtime shaders and through a frozen
/// copy of them (example/shader_audit/baseline), compared pixel by pixel in
/// the same app on the same device, and timed against each other.
///
/// The frozen copy is the shader tree of commit a64140c with the 32-shape
/// contributor decode of 7864ada; replace it
/// (example/shader_audit/baseline) to compare against another revision.
library;

// The harness drives the renderer's internals directly.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
// The harness renders the renderer's own layers, below the widget layer.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/glass_field.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/renderer.dart';
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/shaders.dart';

/// The asset folder of the frozen baseline shaders.
const String baselineShaderRoot = 'shader_audit/baseline/';

/// The logical size of the region every case is drawn in.
const Size harnessRegion = Size(360, 640);

/// Which copy of the runtime shaders a render uses.
enum ShaderVariant {
  /// The package's live shaders.
  candidate,

  /// The frozen copy in example/shader_audit/baseline.
  baseline,
}

/// One glass shape of a case.
class HarnessShape {
  /// Creates a shape at [rect] (logical px in the region).
  const HarnessShape(this.rect, this.shape, this.appearance);

  /// Where the shape sits in the region.
  final Rect rect;

  /// The outline.
  final LiquidShape shape;

  /// The material of the shape.
  final LiquidGlassAppearance appearance;
}

/// One deterministic input to the shaders: a layer's settings, its shapes
/// and, for a fused body, its field.
class HarnessCase {
  /// Creates a case.
  const HarnessCase(
    this.name,
    this.settings,
    this.shapes, {
    this.fake = false,
    this.field,
  });

  /// The case's name, also its file name.
  final String name;

  /// The layer's settings.
  final LiquidGlassSettings settings;

  /// The shapes the layer shades.
  final List<HarnessShape> shapes;

  /// Whether the layer draws fake glass.
  final bool fake;

  /// The fused body's distance field, for a field case.
  final GlassField? field;
}

const Color _blue = Color(0xFF007AFF);

LiquidShape _rse(double radius) =>
    LiquidRoundedSuperellipse(borderRadius: radius);

/// Three shapes, one in each band of the backdrop: a 44 pt capsule over
/// the stripes, a large continuous-corner rectangle across the gradient
/// and a circle over the noise.
List<HarnessShape> _trio(LiquidGlassAppearance appearance) => [
  HarnessShape(const Rect.fromLTWH(40, 80, 220, 44), _rse(22), appearance),
  HarnessShape(const Rect.fromLTWH(70, 220, 200, 150), _rse(40), appearance),
  HarnessShape(
    const Rect.fromLTWH(140, 470, 72, 72),
    const LiquidOval(),
    appearance,
  ),
];

const LiquidGlassAppearance _darkRegular =
    LiquidGlassAppearance.ios27RegularDark();

/// The lifted lens of the widget layer: clear direct-model glass with
/// dispersion and a backdrop shrink along its long side.
const LiquidGlassSettings _liftedLens = LiquidGlassSettings(
  frost: 0,
  refractionAmount: 120,
  dispersion: -0.25,
  backdropShrink: 0.3,
  backdropShrinkRim: 1,
  highlight: 1.4,
);

/// Every case of the harness, each pinning a path of the final shaders.
final List<HarnessCase> harnessCases = [
  HarnessCase(
    'regular-dark',
    const LiquidGlassSettings(frost: 0),
    _trio(_darkRegular),
  ),
  HarnessCase(
    'regular-light',
    const LiquidGlassSettings(frost: 0),
    _trio(const LiquidGlassAppearance.ios27RegularLight()),
  ),
  HarnessCase(
    'toolbar-dark-blur',
    LiquidGlassSettings.ios27ToolbarDark(),
    _trio(const LiquidGlassAppearance.ios27ToolbarDark()),
  ),
  HarnessCase(
    'toolbar-light-slider',
    LiquidGlassSettings.ios27ToolbarLight(tintAmount: 0.7),
    _trio(const LiquidGlassAppearance.ios27ToolbarLight()),
  ),
  HarnessCase(
    'clear-rest',
    LiquidGlassSettings.ios27Clear(),
    _trio(const LiquidGlassAppearance.ios27Clear()),
  ),
  const HarnessCase('lens-lifted', _liftedLens, [
    HarnessShape(
      Rect.fromLTWH(30, 70, 150, 64),
      LiquidRoundedSuperellipse(borderRadius: 32),
      LiquidGlassAppearance(),
    ),
    HarnessShape(
      Rect.fromLTWH(160, 250, 64, 120),
      LiquidRoundedSuperellipse(borderRadius: 32),
      LiquidGlassAppearance(),
    ),
  ]),
  HarnessCase(
    'prominent-dark',
    const LiquidGlassSettings(frost: 0),
    _trio(const LiquidGlassAppearance.ios27RegularDark(tint: _blue)),
  ),
  HarnessCase(
    'prominent-light',
    const LiquidGlassSettings(frost: 0),
    _trio(
      const LiquidGlassAppearance.ios27RegularLight(tint: Color(0xCCFF3B30)),
    ),
  ),
  HarnessCase(
    'direct-gamma',
    const LiquidGlassSettings(frost: 0),
    _trio(
      const LiquidGlassAppearance(
        tint: Color(0x40FFFFFF),
        saturation: 1.2,
        transmissionGamma: 1.4,
        vibrancy: 0.1,
      ),
    ),
  ),
  HarnessCase('tint-pair', const LiquidGlassSettings(frost: 0), [
    HarnessShape(const Rect.fromLTWH(30, 90, 140, 44), _rse(22), _darkRegular),
    HarnessShape(
      const Rect.fromLTWH(176, 90, 140, 44),
      _rse(22),
      const LiquidGlassAppearance.ios27RegularDark(tint: Color(0x9934C759)),
    ),
    HarnessShape(
      const Rect.fromLTWH(60, 250, 220, 120),
      _rse(36),
      const LiquidGlassAppearance.ios27RegularDark(tint: Color(0xCCFF9500)),
    ),
  ]),
  HarnessCase('mixed-models', const LiquidGlassSettings(frost: 0), [
    HarnessShape(const Rect.fromLTWH(30, 90, 140, 44), _rse(22), _darkRegular),
    HarnessShape(
      const Rect.fromLTWH(176, 90, 140, 44),
      _rse(22),
      const LiquidGlassAppearance.ios27Clear(),
    ),
    HarnessShape(
      const Rect.fromLTWH(60, 250, 220, 120),
      _rse(36),
      const LiquidGlassAppearance(
        tint: Color(0x40FF2D55),
        transmissionGamma: 1.3,
        vibrancy: 0.1,
      ),
    ),
    const HarnessShape(
      Rect.fromLTWH(120, 460, 120, 120),
      LiquidOval(),
      LiquidGlassAppearance.ios27RegularLight(visibility: 0.6),
    ),
  ]),
  HarnessCase('fused-field', const LiquidGlassSettings(frost: 0), [
    HarnessShape(const Rect.fromLTWH(40, 300, 150, 52), _rse(26), _darkRegular),
    HarnessShape(
      const Rect.fromLTWH(170, 300, 150, 52),
      _rse(26),
      _darkRegular,
    ),
  ], field: _fusedField()),
  HarnessCase('big-sheet', const LiquidGlassSettings(frost: 0), [
    HarnessShape(const Rect.fromLTWH(10, 20, 340, 600), _rse(34), _darkRegular),
  ]),
  HarnessCase('menu-frosted', LiquidGlassSettings.ios27ToolbarDark(), [
    HarnessShape(
      const Rect.fromLTWH(40, 120, 260, 400),
      _rse(26),
      const LiquidGlassAppearance.ios27ToolbarDark(),
    ),
  ]),
  HarnessCase(
    'visibility-half',
    const LiquidGlassSettings(frost: 0),
    _trio(const LiquidGlassAppearance.ios27RegularDark(visibility: 0.5)),
  ),
  HarnessCase(
    'visibility-half-frosted',
    LiquidGlassSettings.ios27ToolbarLight(),
    _trio(const LiquidGlassAppearance.ios27ToolbarLight(visibility: 0.5)),
  ),
  HarnessCase(
    'fake-regular-dark',
    const LiquidGlassSettings(frost: 0),
    _trio(_darkRegular),
    fake: true,
  ),
  HarnessCase(
    'fake-clear',
    LiquidGlassSettings.ios27Clear(),
    _trio(const LiquidGlassAppearance.ios27Clear()),
    fake: true,
  ),
  HarnessCase('fake-big-sheet', const LiquidGlassSettings(frost: 0), [
    HarnessShape(
      const Rect.fromLTWH(10, 20, 340, 600),
      _rse(34),
      const LiquidGlassAppearance.ios27RegularLight(tint: _blue),
    ),
  ], fake: true),
];

/// Two 52 pt capsules fused by a polynomial smooth minimum of 20 pt,
/// sampled every 4 pt with central-difference gradients, as the package's
/// fusion hands a field to the renderer.
GlassField _fusedField() {
  const step = 4.0;
  const origin = Offset(24, 284);
  const cols = 80;
  const rows = 22;
  double box(Offset p, Rect r, double radius) {
    final q = Offset(
      (p.dx - r.center.dx).abs() - r.width / 2 + radius,
      (p.dy - r.center.dy).abs() - r.height / 2 + radius,
    );
    final outside = Offset(math.max(q.dx, 0), math.max(q.dy, 0)).distance;
    return outside + math.min(math.max(q.dx, q.dy), 0) - radius;
  }

  double sd(Offset p) {
    const k = 20.0;
    final a = box(p, const Rect.fromLTWH(40, 300, 150, 52), 26);
    final b = box(p, const Rect.fromLTWH(170, 300, 150, 52), 26);
    final h = (0.5 + 0.5 * (b - a) / k).clamp(0.0, 1.0);
    return b + (a - b) * h - k * h * (1 - h);
  }

  final samples = Float32List(cols * rows * 4);
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      final p = origin + Offset(i * step, j * step);
      const e = 0.5;
      final gx =
          (sd(p + const Offset(e, 0)) - sd(p - const Offset(e, 0))) / (2 * e);
      final gy =
          (sd(p + const Offset(0, e)) - sd(p - const Offset(0, e))) / (2 * e);
      final n = (j * cols + i) * 4;
      samples[n] = sd(p);
      samples[n + 1] = gx;
      samples[n + 2] = gy;
      samples[n + 3] = 26;
    }
  }
  return GlassField(
    samples: samples,
    cols: cols,
    rows: rows,
    origin: origin,
    step: step,
  );
}

/// The synthetic backdrop: [width] x [height] device pixels in three bands
/// - hard stripes, a smooth gradient and seeded noise - a pure function of
/// its arguments.
Uint8List harnessBackdropPixels(int width, int height, {int seed = 0x5EED27}) {
  final pixels = Uint8List(width * height * 4);
  var state = seed;
  int next() {
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
    return state >> 24;
  }

  final band = height ~/ 3;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      int r;
      int g;
      int b;
      if (y < band) {
        final stripe = (x ~/ 3 + y ~/ 7) % 4;
        final diagonal = ((x + y) ~/ 2) % 5 == 0;
        r = stripe == 0 || diagonal ? 255 : (stripe == 2 ? 40 : 0);
        g = stripe == 1 ? 220 : (diagonal ? 255 : 16);
        b = stripe == 3 ? 255 : (x % 2 == 0 ? 30 : 0);
      } else if (y < 2 * band) {
        r = x * 255 ~/ math.max(width - 1, 1);
        g = (y - band) * 255 ~/ math.max(band - 1, 1);
        b = 128 + ((x + y) % 64);
      } else {
        r = next();
        g = next();
        b = next();
      }
      pixels[i] = r;
      pixels[i + 1] = g;
      pixels[i + 2] = b;
      pixels[i + 3] = 255;
    }
  }
  return pixels;
}

/// Decodes [harnessBackdropPixels] into an image.
Future<ui.Image> harnessBackdrop(int width, int height) {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    harnessBackdropPixels(width, height),
    width,
    height,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

/// The scene of [glassCase]: the backdrop at device pixel (0, 0) and
/// [copies] stacked glass layers of the case over it.
Widget harnessScene({
  required HarnessCase glassCase,
  required ui.Image backdrop,
  required double devicePixelRatio,
  required GlobalKey boundary,
  required ShaderVariant variant,
  int copies = 1,
}) {
  final size = Size(
    backdrop.width / devicePixelRatio,
    backdrop.height / devicePixelRatio,
  );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: boundary,
        child: SizedBox.fromSize(
          size: size,
          child: Stack(
            children: [
              Positioned.fill(
                child: RawImage(
                  image: backdrop,
                  scale: devicePixelRatio,
                  filterQuality: FilterQuality.none,
                  fit: BoxFit.none,
                  alignment: Alignment.topLeft,
                ),
              ),
              for (var copy = 0; copy < copies; copy++)
                Positioned.fill(
                  key: ValueKey('${glassCase.name}-${variant.name}-$copy'),
                  child: LiquidGlassLayer(
                    settings: glassCase.settings,
                    fake: glassCase.fake,
                    field: glassCase.field,
                    defaultAppearance: _darkRegular,
                    child: Stack(
                      children: [
                        for (final s in glassCase.shapes)
                          Positioned.fromRect(
                            rect: s.rect,
                            child: LiquidGlass(
                              shape: s.shape,
                              appearance: s.appearance,
                              child: const SizedBox.expand(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Points the renderer at [variant]'s runtime shaders.
void useShaderVariant(ShaderVariant variant) {
  ShaderKeys.debugRuntimeRoot = switch (variant) {
    ShaderVariant.candidate => null,
    ShaderVariant.baseline => baselineShaderRoot,
  };
}

/// One offscreen capture: premultiplied RGBA bytes of the region.
class HarnessShot {
  /// Creates a shot of [width] x [height] [bytes].
  const HarnessShot(this.width, this.height, this.bytes);

  /// Device pixels across.
  final int width;

  /// Device pixels down.
  final int height;

  /// Raw RGBA, row-major.
  final Uint8List bytes;

  /// The 64-bit FNV-1a hash of [bytes], as hex.
  String get hash {
    var h = 0xcbf29ce484222325;
    for (final b in bytes) {
      h = (h ^ b) * 0x100000001b3;
    }
    return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }
}

/// Per-channel difference of two shots of the same size.
class HarnessDiff {
  /// Compares [a] and [b].
  factory HarnessDiff.of(HarnessShot a, HarnessShot b) {
    final channels = [0, 0, 0, 0];
    var pixels = 0;
    var worstX = -1;
    var worstY = -1;
    var worst = 0;
    final hist = <int, int>{};
    for (var p = 0; p < a.width * a.height; p++) {
      var pixelMax = 0;
      for (var c = 0; c < 4; c++) {
        final d = (a.bytes[p * 4 + c] - b.bytes[p * 4 + c]).abs();
        if (d > channels[c]) channels[c] = d;
        if (d > pixelMax) pixelMax = d;
      }
      if (pixelMax > 0) {
        pixels++;
        hist[pixelMax] = (hist[pixelMax] ?? 0) + 1;
        if (pixelMax > worst) {
          worst = pixelMax;
          worstX = p % a.width;
          worstY = p ~/ a.width;
        }
      }
    }
    return HarnessDiff._(channels, pixels, worstX, worstY, hist);
  }

  HarnessDiff._(
    this.channels,
    this.pixels,
    this.worstX,
    this.worstY,
    this.histogram,
  );

  /// The largest difference of R, G, B and A.
  final List<int> channels;

  /// The pixels that differ in any channel.
  final int pixels;

  /// Where the largest difference is.
  final int worstX;

  /// Where the largest difference is.
  final int worstY;

  /// Differing pixels by their largest channel difference.
  final Map<int, int> histogram;

  /// The largest channel difference.
  int get max => channels.reduce(math.max);

  /// The report entry.
  Map<String, Object> toJson() => {
    'max': max,
    'channels': channels,
    'pixels': pixels,
    'worst': [worstX, worstY],
    'histogram': {for (final e in histogram.entries) '${e.key}': e.value},
  };
}

/// Drives the cases on a [WidgetTester].
class ShaderHarness {
  /// Creates a harness at the view's device pixel ratio.
  ShaderHarness(this.tester);

  /// The tester whose view the scenes render in.
  final WidgetTester tester;

  final GlobalKey _boundary = GlobalKey();

  ui.Image? _backdrop;

  /// The device pixel ratio the region renders at.
  double get devicePixelRatio => tester.view.devicePixelRatio;

  /// The backdrop, built once.
  Future<ui.Image> backdrop() async => _backdrop ??= (await tester.runAsync(
    () => harnessBackdrop(
      (harnessRegion.width * devicePixelRatio).round(),
      (harnessRegion.height * devicePixelRatio).round(),
    ),
  ))!;

  /// Mounts [glassCase] on [variant]'s shaders and waits until its matte
  /// and shaders are ready.
  Future<void> show(
    HarnessCase glassCase,
    ShaderVariant variant, {
    int copies = 1,
  }) async {
    final image = await backdrop();
    useShaderVariant(variant);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      harnessScene(
        glassCase: glassCase,
        backdrop: image,
        devicePixelRatio: devicePixelRatio,
        boundary: _boundary,
        variant: variant,
        copies: copies,
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// The boundary's render object.
  RenderRepaintBoundary get boundary =>
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  /// Renders the mounted scene offscreen.
  Future<ui.Image> render() async => (await tester.runAsync(
    () => boundary.toImage(pixelRatio: devicePixelRatio),
  ))!;

  /// Renders the mounted scene and reads it back.
  Future<HarnessShot> shoot() async {
    final image = await render();
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final shot = HarnessShot(
      image.width,
      image.height,
      data!.buffer.asUint8List(),
    );
    image.dispose();
    return shot;
  }

  /// Encodes [shot] as a PNG.
  Future<Uint8List> png(HarnessShot shot) async {
    final bytes = (await tester.runAsync(() async {
      final buffer = await ui.ImmutableBuffer.fromUint8List(shot.bytes);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: shot.width,
        height: shot.height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      return data;
    }))!;
    return bytes.buffer.asUint8List();
  }

  /// The CLOCK_MONOTONIC window (microseconds) of the last [time], the
  /// clock of the kernel's GPU work periods on Android.
  (int, int) lastWindow = (0, 0);

  /// Milliseconds per offscreen render of the mounted scene, over
  /// [frames] renders whose last is read back, so the time covers the GPU
  /// work of all of them.
  Future<double> time(int frames) async {
    final elapsed = await tester.runAsync(() async {
      final start = Timeline.now;
      final watch = Stopwatch();
      watch.start();
      ui.Image? last;
      for (var i = 0; i < frames; i++) {
        last?.dispose();
        last = await boundary.toImage(pixelRatio: devicePixelRatio);
      }
      await last!.toByteData(format: ui.ImageByteFormat.rawRgba);
      last.dispose();
      watch.stop();
      lastWindow = (start, Timeline.now);
      return watch.elapsedMicroseconds;
    });
    return elapsed! / 1000 / frames;
  }
}

/// The cases named in [only] (comma separated), or all of them.
List<HarnessCase> harnessCasesNamed(String only) {
  if (only.isEmpty) return harnessCases;
  final names = only.split(',').map((s) => s.trim()).toSet();
  return [
    for (final c in harnessCases)
      if (names.contains(c.name)) c,
  ];
}

/// Renders every case on both variants and compares them: per case the
/// candidate's hash, the difference between two captures of one mount
/// (`repeat`) and between two mounts (`remount`) - both must be zero, the
/// noise floor of every other number - and the difference from the
/// baseline (`diff`). Writes `<case>.candidate.png` and
/// `<case>.baseline.png` into [outDir] when it is given.
Future<Map<String, Object>> runShaderParity(
  ShaderHarness harness, {
  required List<HarnessCase> cases,
  String? outDir,
}) async {
  final results = <String, Object>{};
  for (final glassCase in cases) {
    await harness.show(glassCase, ShaderVariant.candidate);
    final first = await harness.shoot();
    final repeat = await harness.shoot();
    await harness.show(glassCase, ShaderVariant.baseline);
    final base = await harness.shoot();
    await harness.show(glassCase, ShaderVariant.candidate);
    final remount = await harness.shoot();
    final diff = HarnessDiff.of(first, base);
    results[glassCase.name] = {
      'candidate': first.hash,
      'baseline': base.hash,
      'repeat': HarnessDiff.of(first, repeat).max,
      'remount': HarnessDiff.of(first, remount).max,
      'diff': diff.toJson(),
    };
    if (outDir != null) {
      File(
        '$outDir/${glassCase.name}.candidate.png',
      ).writeAsBytesSync(await harness.png(first));
      File(
        '$outDir/${glassCase.name}.baseline.png',
      ).writeAsBytesSync(await harness.png(base));
    }
  }
  useShaderVariant(ShaderVariant.candidate);
  return {
    'device_pixel_ratio': harness.devicePixelRatio,
    'region': [harnessRegion.width, harnessRegion.height],
    'cases': results,
  };
}

/// Times [cases] on both variants with 1 and [copies] stacked layers, in
/// alternating blocks (ABBA), [frames] offscreen renders per sample. Each
/// block's layer cost is the difference of its two layer counts divided by
/// the extra layers, so the fixed costs (backdrop, readback) cancel; the
/// report keeps every block and the medians of the layer costs and of the
/// blocks' paired gains.
Future<Map<String, Object>> runShaderBench(
  ShaderHarness harness, {
  required List<HarnessCase> cases,
  int copies = 6,
  int blocks = 8,
  int frames = 40,
}) async {
  double median(List<double> v) {
    final sorted = [...v];
    sorted.sort();
    final n = sorted.length;
    return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }

  final results = <String, Object>{};
  for (final glassCase in cases) {
    final layer = <ShaderVariant, List<double>>{
      for (final v in ShaderVariant.values) v: [],
    };
    final gains = <double>[];
    final windows = <Map<String, Object>>[];
    for (var block = 0; block < blocks; block++) {
      final order = block.isEven
          ? ShaderVariant.values
          : ShaderVariant.values.reversed;
      final blockLayer = <ShaderVariant, double>{};
      for (final variant in order) {
        final ms = <int, double>{};
        for (final k in [1, copies]) {
          await harness.show(glassCase, variant, copies: k);
          await harness.time(4);
          ms[k] = await harness.time(frames);
          windows.add({
            'block': block,
            'variant': variant.name,
            'copies': k,
            'frames': frames,
            'start_us': harness.lastWindow.$1,
            'end_us': harness.lastWindow.$2,
          });
        }
        blockLayer[variant] = (ms[copies]! - ms[1]!) / (copies - 1);
        layer[variant]!.add(blockLayer[variant]!);
      }
      final base = blockLayer[ShaderVariant.baseline]!;
      gains.add(
        base == 0
            ? 0
            : (base - blockLayer[ShaderVariant.candidate]!) / base * 100,
      );
    }
    final candidate = median(layer[ShaderVariant.candidate]!);
    final baseline = median(layer[ShaderVariant.baseline]!);
    final gain = median(gains);
    // The bench's progress in the device log.
    // ignore: avoid_print
    print(
      'SHADER_BENCH ${glassCase.name} baseline $baseline '
      'candidate $candidate gain $gain',
    );
    results[glassCase.name] = {
      'layer_ms_baseline_blocks': layer[ShaderVariant.baseline]!,
      'layer_ms_candidate_blocks': layer[ShaderVariant.candidate]!,
      'gain_percent_blocks': gains,
      'windows': windows,
      'layer_ms_candidate': candidate,
      'layer_ms_baseline': baseline,
      'layer_gain_percent': gain,
    };
  }
  useShaderVariant(ShaderVariant.candidate);
  return {
    'device_pixel_ratio': harness.devicePixelRatio,
    'copies': copies,
    'frames': frames,
    'blocks': blocks,
    'cases': results,
  };
}
