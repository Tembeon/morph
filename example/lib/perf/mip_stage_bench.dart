// ignore_for_file: implementation_imports, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:morph/widgets.dart' show MorphGlassRenderer;
import 'package:morph/src/glass/renderer/internal/owned_glass_backdrop.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph_example/perf/glass_stage_bench.dart' show stageBenchStats;

const _width = 1024;
const _height = 2048;
const _sigmaPx = 16.0;
const _levels = 5;
const _runs = int.fromEnvironment('MIP_RUNS', defaultValue: 3);
const _warmMs = int.fromEnvironment('MIP_WARM_MS', defaultValue: 400);
const _sampleMs = int.fromEnvironment('MIP_SAMPLE_MS', defaultValue: 1600);
const _seed = int.fromEnvironment('MIP_SEED', defaultValue: 20261008);
const _shots = bool.fromEnvironment('MIP_SHOTS');
const _nativeShots = bool.fromEnvironment('MIP_NATIVE_SHOTS');
const _optics = bool.fromEnvironment('MIP_OPTICS');

/// Measures owned GPU blur production and optional real Morph optical consumers.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Bench());
}

class _Case {
  const _Case(this.mode, this.count, this.dynamicSource);
  final String mode;
  final int count;
  final bool dynamicSource;
  String get name => 'mip-$mode-n$count-${dynamicSource ? 'fresh' : 'reuse'}';
  String get kernel => mode.startsWith('owned-') ? mode.substring(6) : mode;
  bool get pyramid => ['box', 'tent', 'wide'].contains(kernel);
  bool get cached => kernel == 'cached';
  double get sigma =>
      ['glass-zero', 'owned-raw', 'foreground', 'bare'].contains(mode)
      ? 0
      : _sigmaPx;
  double get lod => kernel == 'box' ? 4.9526399109241535 : 4.688035443343443;
}

List<_Case> _cases() {
  final modes = const String.fromEnvironment(
    'MIP_MODES',
    defaultValue: _optics
        ? 'glass-zero,glass-grouped,glass-merged,owned-raw,owned-cached,owned-tent,owned-wide,foreground'
        : 'gaussian,grouped,box,tent,wide,cached,bare',
  ).split(',');
  final counts = const String.fromEnvironment(
    'MIP_COUNTS',
    defaultValue: '1,2,4,8,16',
  ).split(',').map(int.parse).toList();
  final updates = const String.fromEnvironment(
    'MIP_UPDATES',
    defaultValue: 'fresh,reuse',
  ).split(',');
  if (_runs < 1 ||
      _warmMs < 100 ||
      _sampleMs < 100 ||
      modes.any(
        (s) => ![
          'bare',
          'gaussian',
          'grouped',
          'box',
          'tent',
          'wide',
          'cached',
          if (_optics) ...[
            'glass-zero',
            'glass-grouped',
            'glass-merged',
            'owned-raw',
            'owned-cached',
            'owned-tent',
            'owned-wide',
            'foreground',
          ],
        ].contains(s),
      ) ||
      counts.any((n) => ![1, 2, 4, 8, 16].contains(n)) ||
      updates.any((s) => !['fresh', 'reuse'].contains(s)) ||
      modes.toSet().length != modes.length ||
      counts.toSet().length != counts.length ||
      updates.toSet().length != updates.length) {
    throw ArgumentError('Invalid MIP benchmark selection');
  }
  return [
    for (final mode in modes)
      for (final n in counts)
        for (final update in updates)
          if (!['cached', 'owned-cached'].contains(mode) || update == 'reuse')
            _Case(mode, n, update == 'fresh'),
  ];
}

List<ui.Rect> _rects(int count, ui.Size size) {
  final columns = math.sqrt(count).ceil();
  final rows = (count / columns).ceil();
  final cellW = size.width / columns;
  final cellH = size.height / rows;
  final scale = math.sqrt(.3 * columns * rows / count);
  return [
    for (var i = 0; i < count; i++)
      ui.Rect.fromCenter(
        center: ui.Offset(
          cellW * (i % columns + .5),
          cellH * (i ~/ columns + .5),
        ),
        width: cellW * scale,
        height: cellH * scale,
      ),
  ];
}

class _Kernel {
  _Kernel(gpu.ShaderLibrary library, String name, String block) {
    final vertex = library['MipVertex']!;
    final fragment = library[name]!;
    pipeline = gpu.gpuContext.createRenderPipeline(vertex, fragment);
    uniforms = fragment.getUniformSlot(block);
    sampler = name != 'MipSource' ? fragment.getUniformSlot('uInput') : null;
  }
  late final gpu.RenderPipeline pipeline;
  late final gpu.UniformSlot uniforms;
  late final gpu.UniformSlot? sampler;
}

gpu.BufferView _fixedUniforms(List<double> values) {
  final bytes = ByteData.sublistView(Float32List.fromList(values));
  return gpu.BufferView(
    gpu.gpuContext.createDeviceBufferWithCopy(bytes),
    offsetInBytes: 0,
    lengthInBytes: bytes.lengthInBytes,
  );
}

// This Vulkan-only probe uses the renderer's four-target / three-scene-epoch
// retirement contract, plus producer completion. All writes and Flutter reads
// use the same GPU queue. A target cannot be reused while an older unsubmitted
// scene can still read it. Do not infer cross-backend safety from this probe.
class _Target {
  _Target(int width, int height)
    : texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        width,
        height,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
      );
  final gpu.Texture texture;
  int lastEpoch = -100;
  bool pending = false;
}

class _TextureRing {
  _TextureRing(this.width, this.height)
    : targets = [for (var i = 0; i < 4; i++) _Target(width, height)];
  final int width;
  final int height;
  final List<_Target> targets;
  _Target? current;
  _Target lease(int epoch) {
    final target = targets.firstWhere(
      (t) => t != current && !t.pending && epoch - t.lastEpoch >= 3,
      orElse: () => throw StateError('No safely retired GPU target'),
    );
    target.lastEpoch = epoch;
    target.pending = true;
    current = target;
    return target;
  }

  int get bytes => width * height * 4 * targets.length;
}

class _Producer {
  _Producer(gpu.ShaderLibrary library)
    : sourceKernel = _Kernel(library, 'MipSource', 'SourceUniforms'),
      mipKernel = _Kernel(library, 'MipDownsample', 'MipUniforms'),
      wideKernel = _Kernel(library, 'MipWide', 'WideUniforms') {
    final bytes = ByteData.sublistView(
      Float32List.fromList([
        -1,
        -1,
        0,
        0,
        1,
        -1,
        1,
        0,
        -1,
        1,
        0,
        1,
        1,
        1,
        1,
        1,
      ]),
    );
    vertices = gpu.BufferView(
      gpu.gpuContext.createDeviceBufferWithCopy(bytes),
      offsetInBytes: 0,
      lengthInBytes: bytes.lengthInBytes,
    );
    for (final kind in ['box', 'tent']) {
      rings[kind] = [
        for (var l = 1; l <= _levels; l++)
          _TextureRing(_width >> l, _height >> l),
      ];
      mipUniforms[kind] = [
        for (var l = 1; l <= _levels; l++)
          _fixedUniforms([
            (_width >> (l - 1)).toDouble(),
            (_height >> (l - 1)).toDouble(),
            kind == 'tent' ? 1 : 0,
            0,
          ]),
      ];
    }
    rings['wide'] = [
      _TextureRing(_width >> 4, _height),
      _TextureRing(_width >> 4, _height >> 4),
      _TextureRing(_width >> 5, _height >> 5),
    ];
    mipUniforms['wide'] = [
      _fixedUniforms([_width.toDouble(), _height.toDouble(), 1, 0]),
      _fixedUniforms([(_width >> 4).toDouble(), _height.toDouble(), 0, 0]),
      _fixedUniforms([
        (_width >> 4).toDouble(),
        (_height >> 4).toDouble(),
        1,
        0,
      ]),
    ];
  }
  final _Kernel sourceKernel;
  final _Kernel mipKernel;
  final _Kernel wideKernel;
  late final gpu.BufferView vertices;
  final base = _TextureRing(_width, _height);
  final rings = <String, List<_TextureRing>>{};
  final mipUniforms = <String, List<gpu.BufferView>>{};
  final images = <String, List<ui.Image>>{};
  final revisions = <String, int>{};
  final availableUniforms = <gpu.DeviceBuffer>[];
  final stopwatch = Stopwatch();
  ui.Image? source;
  ui.Image? cachedGaussian;
  int cachedGaussianWaitUs = 0;
  double? previousPhase;
  int revision = 0;
  int sourcePasses = 0;
  int mipPasses = 0;
  int submissions = 0;
  int uniformAllocations = 0;
  int recordUs = 0;
  int paintCalls = 0;
  int epoch = 0;
  Duration? previousFrame;
  String? failure;
  bool disposed = false;

  void check() {
    if (failure case final message?) throw StateError(message);
  }

  gpu.Texture _draw(
    _TextureRing ring,
    _Kernel kernel,
    gpu.BufferView uniforms, {
    gpu.Texture? input,
    gpu.DeviceBuffer? leased,
  }) {
    final target = ring.lease(epoch);
    final command = gpu.gpuContext.createCommandBuffer();
    try {
      final pass = command.createRenderPass(
        gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: target.texture,
            loadAction: gpu.LoadAction.dontCare,
          ),
        ),
      );
      pass.bindPipeline(kernel.pipeline);
      pass.bindVertexBuffer(vertices);
      pass.setPrimitiveType(gpu.PrimitiveType.triangleStrip);
      pass.bindUniform(kernel.uniforms, uniforms);
      if (input != null) {
        pass.bindTexture(
          kernel.sampler!,
          input,
          sampler: gpu.SamplerOptions(
            minFilter: gpu.MinMagFilter.linear,
            magFilter: gpu.MinMagFilter.linear,
          ),
        );
      }
      pass.draw(4);
      submissions++;
      command.submit(
        completionCallback: (success) {
          target.pending = false;
          if (!success) failure = 'GPU producer command failed';
          if (leased != null && !disposed) availableUniforms.add(leased);
        },
      );
      return target.texture;
    } on Object {
      target.pending = false;
      rethrow;
    }
  }

  void update(_Case c, double phase) {
    check();
    stopwatch.reset();
    stopwatch.start();
    paintCalls++;
    final stamp = SchedulerBinding.instance.currentFrameTimeStamp;
    if (stamp != previousFrame) {
      epoch++;
      previousFrame = stamp;
    }
    final nextPhase = c.dynamicSource ? phase : 0.0;
    if (source == null || nextPhase != previousPhase) {
      final allocate = availableUniforms.isEmpty;
      if (allocate) uniformAllocations++;
      final buffer = allocate
          ? gpu.gpuContext.createDeviceBuffer(gpu.StorageMode.hostVisible, 16)
          : availableUniforms.removeLast();
      final data = ByteData.sublistView(
        Float32List.fromList([
          _width.toDouble(),
          _height.toDouble(),
          nextPhase * 80,
          0,
        ]),
      );
      if (!buffer.overwrite(data)) throw StateError('Uniform write failed');
      _draw(
        base,
        sourceKernel,
        gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: 16),
        leased: buffer,
      );
      source?.dispose();
      source = base.current!.texture.asImage();
      previousPhase = nextPhase;
      revision++;
      sourcePasses++;
    }
    final kind = c.kernel;
    if (c.pyramid && revisions[kind] != revision) {
      var input = base.current!.texture;
      final nextImages = <ui.Image>[];
      try {
        final wide = kind == 'wide';
        for (var i = 0; i < (wide ? 3 : _levels); i++) {
          input = _draw(
            rings[kind]![i],
            wide && i < 2 ? wideKernel : mipKernel,
            mipUniforms[kind]![i],
            input: input,
          );
          if (!wide || i > 0) {
            final image = input.asImage();
            nextImages.add(image);
          }
          mipPasses++;
        }
      } on Object {
        for (final image in nextImages) {
          image.dispose();
        }
        rethrow;
      }
      for (final image in images[kind] ?? <ui.Image>[]) {
        image.dispose();
      }
      images[kind] = nextImages;
      revisions[kind] = revision;
    }
    stopwatch.stop();
    recordUs += stopwatch.elapsedMicroseconds;
  }

  Future<void> prepareCachedGaussian() async {
    if (cachedGaussian != null) return;
    if (previousPhase != 0 || source == null) {
      throw StateError('Cache input must be the canonical static source');
    }
    final elapsed = Stopwatch();
    elapsed.start();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final dpr = _optics
        ? ui.PlatformDispatcher.instance.views.first.devicePixelRatio
        : 1.0;
    canvas.scale(dpr);
    final rect = ui.Rect.fromLTWH(0, 0, _width / dpr, _height / dpr);
    final filterPaint = ui.Paint();
    filterPaint.imageFilter = ui.ImageFilter.blur(
      sigmaX: _sigmaPx / dpr,
      sigmaY: _sigmaPx / dpr,
    );
    canvas.saveLayer(rect, filterPaint);
    canvas.drawImageRect(
      source!,
      ui.Rect.fromLTWH(0, 0, _width.toDouble(), _height.toDouble()),
      rect,
      ui.Paint(),
    );
    canvas.restore();
    final picture = recorder.endRecording();
    try {
      cachedGaussian = await picture.toImage(_width, _height);
    } finally {
      picture.dispose();
    }
    elapsed.stop();
    cachedGaussianWaitUs = elapsed.elapsedMicroseconds;
  }

  int get ownedBytes =>
      (cachedGaussian == null ? 0 : _width * _height * 4) +
      base.bytes +
      rings.values.expand((s) => s).fold(0, (int a, s) => a + s.bytes);

  Map<String, int> get counters => {
    'source_passes': sourcePasses,
    'downsample_passes': mipPasses,
    'producer_submissions': submissions,
    'producer_record_us': recordUs,
    'producer_paints': paintCalls,
    'uniform_allocations': uniformAllocations,
    'surface_retained_bytes': ownedBytes,
    'surface_peak_bytes': ownedBytes,
    if (_optics)
      'owned_optical_paints': RenderLiquidGlassLayer.debugOwnedPaints,
  };

  void dispose() {
    disposed = true;
    source?.dispose();
    cachedGaussian?.dispose();
    for (final image in images.values.expand((s) => s)) {
      image.dispose();
    }
    images.clear();
    availableUniforms.clear();
  }
}

class _SourcePainter extends CustomPainter {
  _SourcePainter(this.producer, this.c, this.phase) : super(repaint: phase);
  final _Producer producer;
  final _Case c;
  final ValueNotifier<double> phase;
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    if (!_optics) producer.update(c, phase.value);
    final paint = ui.Paint();
    paint.filterQuality = ui.FilterQuality.low;
    canvas.drawImageRect(
      producer.source!,
      ui.Rect.fromLTWH(0, 0, _width.toDouble(), _height.toDouble()),
      ui.Offset.zero & size,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SourcePainter old) => old.c != c;
}

class _MipPainter extends CustomPainter {
  _MipPainter(this.producer, this.c, this.phase, this.shader, this.dpr)
    : super(repaint: phase);
  final _Producer producer;
  final _Case c;
  final ValueNotifier<double> phase;
  final ui.FragmentShader shader;
  final double dpr;
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final levels = producer.images[c.kernel]!;
    final lower = c.lod.floor();
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, c.lod - lower);
    shader.setImageSampler(
      0,
      levels[c.mode == 'wide' ? 0 : lower - 1],
      filterQuality: ui.FilterQuality.low,
    );
    shader.setImageSampler(
      1,
      levels[c.mode == 'wide' ? 1 : lower],
      filterQuality: ui.FilterQuality.low,
    );
    final paint = ui.Paint();
    paint.shader = shader;
    for (final rect in _rects(c.count, size)) {
      canvas.save();
      canvas.clipRRect(
        ui.RRect.fromRectAndRadius(
          rect.shift(ui.Offset(phase.value * 12 / dpr, 0)),
          ui.Radius.circular(12 / dpr),
        ),
      );
      canvas.drawRect(ui.Offset.zero & size, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MipPainter old) => old.c != c;
}

class _CachedPainter extends CustomPainter {
  _CachedPainter(this.producer, this.c, this.phase, this.dpr)
    : super(repaint: phase);
  final _Producer producer;
  final _Case c;
  final ValueNotifier<double> phase;
  final double dpr;
  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final image = producer.cachedGaussian;
    if (image == null) return;
    final paint = ui.Paint();
    paint.filterQuality = ui.FilterQuality.low;
    for (final rect in _rects(c.count, size)) {
      canvas.save();
      canvas.clipRRect(
        ui.RRect.fromRectAndRadius(
          rect.shift(ui.Offset(phase.value * 12 / dpr, 0)),
          ui.Radius.circular(12 / dpr),
        ),
      );
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Offset.zero & size,
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CachedPainter old) => old.c != c;
}

class _OpticalScene extends StatelessWidget {
  const _OpticalScene({
    required this.c,
    required this.phase,
    required this.dpr,
    required this.backdropKey,
  });
  final _Case c;
  final ValueNotifier<double> phase;
  final double dpr;
  final BackdropKey backdropKey;

  Widget shapes(List<ui.Rect> rects, {int firstIndex = 0}) => Stack(
    children: [
      for (var i = 0; i < rects.length; i++)
        Positioned.fromRect(
          rect: rects[i],
          child: c.mode == 'foreground'
              ? label(i + firstIndex)
              : LiquidGlass(
                  shape: LiquidRoundedRectangle(borderRadius: 12 / dpr),
                  child: label(i + firstIndex),
                ),
        ),
    ],
  );

  Widget label(int i) => Center(
    child: Text(
      'Morph $i',
      style: const TextStyle(
        color: ui.Color(0xFFFFFFFF),
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget glass(List<ui.Rect> rects, {int firstIndex = 0}) => LiquidGlassLayer(
    settings: LiquidGlassSettings.ios27ToolbarLight(frost: c.sigma / dpr),
    defaultAppearance: const LiquidGlassAppearance.ios27RegularLight(),
    backdropKey: c.mode == 'glass-grouped' ? backdropKey : null,
    child: shapes(rects, firstIndex: firstIndex),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final rects = _rects(c.count, constraints.biggest);
      final child = c.mode == 'foreground'
          ? shapes(rects)
          : c.mode == 'glass-grouped'
          ? Stack(
              children: [
                for (var i = 0; i < rects.length; i++)
                  glass([rects[i]], firstIndex: i),
              ],
            )
          : glass(rects);
      return AnimatedBuilder(
        animation: phase,
        child: child,
        builder: (context, child) => Transform.translate(
          offset: ui.Offset(phase.value * 12 / dpr, 0),
          child: child,
        ),
      );
    },
  );
}

class _Bench extends StatefulWidget {
  const _Bench();
  @override
  State<_Bench> createState() => _BenchState();
}

class _BenchState extends State<_Bench> with SingleTickerProviderStateMixin {
  final phase = ValueNotifier<double>(0);
  final timings = <ui.FrameTiming>[];
  final windows = <String, List<List<int>>>{};
  final work = <String, List<Map<String, int>>>{};
  final metadata = <String, Map<String, Object>>{};
  final order = <String>[];
  final key = GlobalKey();
  late final Ticker ticker;
  _Producer? producer;
  ui.FragmentShader? shader;
  _Case? current;
  final ownedPrograms = <String, ui.FragmentProgram>{};
  final ownedShaders =
      <RenderLiquidGlassLayer, Map<String, ui.FragmentShader>>{};
  final opticalLayers = <RenderLiquidGlassLayer>{};
  bool sourceFrameScheduled = false;

  OwnedGlassBackdrop? ownedSource(RenderLiquidGlassLayer layer) {
    final c = current;
    final root = key.currentContext?.findRenderObject();
    final variant = layer.debugOwnedVariant;
    if (c == null ||
        !layer.attached ||
        !c.mode.startsWith('owned-') ||
        root == null ||
        variant == null ||
        producer?.source == null) {
      return null;
    }
    if (c.pyramid && producer!.images[c.kernel] == null) return null;
    if (c.cached && producer!.cachedGaussian == null) return null;
    final shaders = ownedShaders.putIfAbsent(layer, () => {});
    final shader = shaders.putIfAbsent(
      variant,
      () => ownedPrograms[variant]!.fragmentShader(),
    );
    final ui.Image lower;
    final ui.Image upper;
    final double mix;
    if (c.pyramid) {
      final levels = producer!.images[c.kernel]!;
      final index = c.kernel == 'wide' ? 0 : c.lod.floor() - 1;
      lower = levels[index];
      upper = levels[index + 1];
      mix = c.lod - c.lod.floor();
    } else {
      lower = c.cached
          ? producer!.cachedGaussian ?? producer!.source!
          : producer!.source!;
      upper = lower;
      mix = 0;
    }
    return OwnedGlassBackdrop(
      shader: shader,
      lower: lower,
      upper: upper,
      sourceSize: const ui.Size(1024, 2048),
      layerToSource: layer.getTransformTo(root),
      mix: mix,
    );
  }

  void invalidateOpticalConsumers() {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      if (!sourceFrameScheduled) {
        sourceFrameScheduled = true;
        SchedulerBinding.instance.scheduleFrameCallback((_) {
          sourceFrameScheduled = false;
          if (mounted) invalidateOpticalConsumers();
        });
      }
      return;
    }
    // Repaint boundaries can be painted before their source's parent even
    // when the source is visually below them. Publish before paint begins.
    final c = current;
    if (c != null && producer != null) producer!.update(c, phase.value);
    for (final layer in opticalLayers) {
      if (layer.attached) layer.markNeedsPaint();
    }
  }

  @override
  void initState() {
    super.initState();
    ticker = createTicker(
      (time) =>
          phase.value = math.sin(time.inMicroseconds * 2 * math.pi / 2000000),
    );
    SchedulerBinding.instance.addTimingsCallback(collect);
    if (_optics) phase.addListener(invalidateOpticalConsumers);
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  void collect(List<ui.FrameTiming> batch) => timings.addAll(batch);
  @override
  void dispose() {
    ticker.dispose();
    phase.dispose();
    shader?.dispose();
    producer?.dispose();
    if (_optics) RenderLiquidGlassLayer.debugOwnedBackdrop = null;
    for (final shader in ownedShaders.values.expand((s) => s.values)) {
      shader.dispose();
    }
    SchedulerBinding.instance.removeTimingsCallback(collect);
    super.dispose();
  }

  Future<void> mount(_Case c) async {
    ticker.stop();
    setState(() => current = c);
    phase.value = 0;
    if (_optics) invalidateOpticalConsumers();
    await SchedulerBinding.instance.endOfFrame;
    if (_optics) {
      opticalLayers.clear();
      void visit(RenderObject object) {
        if (object is RenderLiquidGlassLayer) opticalLayers.add(object);
        object.visitChildren(visit);
      }

      visit(key.currentContext!.findRenderObject()!);
    }
    if (c.cached) {
      await producer!.prepareCachedGaussian();
    }
    ticker.start();
    await Future<void>.delayed(const Duration(milliseconds: _warmMs));
  }

  Future<void> run() async {
    final out = Directory(
      const String.fromEnvironment(
        'AUDIT_OUT',
        defaultValue: '/tmp/morph-mip-stage',
      ),
    );
    try {
      if (kDebugMode) throw StateError('Native stage bench requires AOT');
      final cases = _cases();
      await MorphGlassRenderer.precache();
      if (!MorphGlassRenderer.liquidAvailable) {
        throw StateError('Native GPU unavailable');
      }
      final library = await gpu.ShaderLibrary.fromAsset(
        'perf_assets/mip.shaderbundle',
      );
      if (library == null) throw StateError('Missing mip bundle');
      producer = _Producer(library);
      if (_optics) {
        for (final variant in ['direct', 'ios27']) {
          ownedPrograms[variant] = await ui.FragmentProgram.fromAsset(
            'lib/perf/shaders/owned_glass_$variant.frag',
          );
        }
        RenderLiquidGlassLayer.debugOwnedBackdrop = ownedSource;
      }
      shader = (await ui.FragmentProgram.fromAsset(
        'lib/perf/shaders/mip_consumer.frag',
      )).fragmentShader();
      for (final c in cases) {
        await mount(c);
      }
      final random = math.Random(_seed);
      for (var repeat = 0; repeat < _runs; repeat++) {
        final shuffled = [...cases];
        shuffled.shuffle(random);
        for (final c in shuffled) {
          await mount(c);
          final start = developer.Timeline.now;
          final before = producer!.counters;
          developer.Timeline.startSync('scene:${c.name}:$repeat:begin');
          developer.Timeline.finishSync();
          await Future<void>.delayed(const Duration(milliseconds: _sampleMs));
          final end = developer.Timeline.now;
          developer.Timeline.startSync('scene:${c.name}:$repeat:end');
          developer.Timeline.finishSync();
          final after = producer!.counters;
          (windows[c.name] ??= []).add([start, end]);
          (work[c.name] ??= []).add({
            for (final k in before.keys)
              k: k.startsWith('surface_') ? after[k]! : after[k]! - before[k]!,
          });
          order.add(c.name);
          metadata[c.name] = {
            'layout': 'owned-texture-n${c.count}',
            'motion': c.dynamicSource ? 'background-and-glass' : 'glass',
            'plan': c.mode == 'gaussian' ? 'independent' : 'shared',
            'mode': c.mode,
            'lens_count': c.count,
            'requested_sigma_physical': c.sigma,
            if (_optics) 'optical_layers': opticalLayers.length,
            'producer_submission': 'per-pass',
            'source_update': c.dynamicSource ? 'every-frame' : 'unchanged',
            'lod': c.pyramid ? c.lod : 0.0,
            'visible_rects_logical': [
              for (final r in _rects(
                c.count,
                ui.Size(
                  _width /
                      ui
                          .PlatformDispatcher
                          .instance
                          .views
                          .first
                          .devicePixelRatio,
                  _height /
                      ui
                          .PlatformDispatcher
                          .instance
                          .views
                          .first
                          .devicePixelRatio,
                ),
              ))
                [r.left, r.top, r.width, r.height],
            ],
          };
        }
      }
      ticker.stop();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      producer!.check();
      out.createSync(recursive: true);
      final report = makeReport();
      if (_shots || _nativeShots) {
        for (final c in cases) {
          await mount(c);
          ticker.stop();
          phase.value = 0;
          await SchedulerBinding.instance.endOfFrame;
          await SchedulerBinding.instance.endOfFrame;
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          if (_nativeShots) {
            final dpr =
                ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
            final origin = boundary.localToGlobal(ui.Offset.zero);
            final ack = File('${out.path}/screen-ack.txt');
            if (ack.existsSync()) ack.deleteSync();
            final request = File('${out.path}/screen-request.tmp');
            request.writeAsStringSync(
              jsonEncode({
                'case': c.name,
                'crop': [
                  (origin.dx * dpr).round(),
                  (origin.dy * dpr).round(),
                  _width,
                  _height,
                ],
              }),
            );
            request.renameSync('${out.path}/screen-request.json');
            final deadline = DateTime.now().add(const Duration(seconds: 30));
            while (!ack.existsSync() || ack.readAsStringSync() != c.name) {
              if (DateTime.now().isAfter(deadline)) {
                throw StateError('Native screen capture timed out: ${c.name}');
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            continue;
          }
          final image = await boundary.toImage(
            pixelRatio:
                ui.PlatformDispatcher.instance.views.first.devicePixelRatio,
          );
          try {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            if (png == null) throw StateError('Missing phase PNG');
            File('${out.path}/${c.name}.png').writeAsBytesSync(
              png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
            );
          } finally {
            image.dispose();
          }
        }
      }
      ticker.stop();
      final temporary = File('${out.path}/report.tmp');
      temporary.writeAsStringSync(jsonEncode(report));
      temporary.renameSync('${out.path}/report.json');
    } on Object catch (error, stack) {
      ticker.stop();
      out.createSync(recursive: true);
      File(
        '${out.path}/error.json',
      ).writeAsStringSync(jsonEncode({'error': '$error', 'stack': '$stack'}));
    }
  }

  Map<String, Object> makeReport() {
    final view = View.of(context);
    final budget = 1000 / view.display.refreshRate;
    return {
      'schema': 'morph-stage-bench-v1',
      'fixture': _optics
          ? 'shared-source-morph-optics'
          : 'shared-mip-owned-texture-blur-only',
      'resource_pool':
          'four targets / three scene epochs / producer completion, Vulkan only',
      'producer_submission': 'one command buffer per producer pass',
      'shot_transport': !_shots && !_nativeShots
          ? 'none'
          : _nativeShots
          ? 'adb screencap after timed windows; separate physical crop metadata'
          : 'RepaintBoundary.toImage after timed windows',
      'platform': Platform.operatingSystem,
      'build_mode': kProfileMode ? 'profile' : 'release',
      'refresh_rate': view.display.refreshRate,
      'budget_ms': budget,
      'device_pixel_ratio': view.devicePixelRatio,
      'physical_size': [_width, _height],
      'liquid_available': MorphGlassRenderer.liquidAvailable,
      'runs': _runs,
      'warm_ms': _warmMs,
      'sample_ms': _sampleMs,
      'seed': _seed,
      'order': order,
      'case_metadata': metadata,
      'cached_gaussian_initial_wait_us': producer!.cachedGaussianWaitUs,
      'windows_us': windows,
      'window_work': work,
      'limitations': [
        _optics
            ? 'Owned synthetic GPU source with Morph optics; no live Flutter backdrop acquisition.'
            : 'Owned synthetic GPU source; no live Flutter backdrop acquisition or final glass optics.',
        if (_optics)
          'Uniform appearance only. Consumers are explicitly repainted on every source/glass tick, including stock controls. Transform retention is not certified.',
        'Pyramid LOD fitted to numerical average PSF; native Gaussian equivalence is not assumed.',
        'Surface byte counters are fixed texture rings for all kernel families plus cached Gaussian; exclude native filter intermediates.',
        'CPU recording and active GPU work are not presentation latency.',
      ],
      for (final entry in windows.entries)
        entry.key: {
          'runs': [
            for (final window in entry.value)
              () {
                final frames = timings.where((f) {
                  final t = f.timestampInMicroseconds(ui.FramePhase.vsyncStart);
                  return t >= window[0] && t < window[1];
                }).toList();
                if (frames.length < 4) {
                  throw StateError('Missing timing frames');
                }
                return {
                  ...stageBenchStats(frames, budget),
                  'frames': [
                    for (final f in frames)
                      [
                        f.timestampInMicroseconds(ui.FramePhase.vsyncStart),
                        f.buildDuration.inMicroseconds,
                        f.rasterDuration.inMicroseconds,
                        f.totalSpan.inMicroseconds,
                      ],
                  ],
                };
              }(),
          ],
        },
    };
  }

  @override
  Widget build(BuildContext context) {
    final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final size = ui.Size(_width / dpr, _height / dpr);
    final c = current;
    return MediaQuery.fromView(
      view: ui.PlatformDispatcher.instance.views.first,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const ui.Color(0xFF000000),
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox.fromSize(
                size: size,
                child: c == null
                    ? const SizedBox.shrink()
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _SourcePainter(producer!, c, phase),
                            ),
                          ),
                          if (_optics)
                            Positioned.fill(
                              child: _OpticalScene(
                                c: c,
                                phase: phase,
                                dpr: dpr,
                                backdropKey: _sharedKey,
                              ),
                            )
                          else if (c.pyramid)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _MipPainter(
                                  producer!,
                                  c,
                                  phase,
                                  shader!,
                                  dpr,
                                ),
                              ),
                            )
                          else if (c.mode == 'cached')
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _CachedPainter(
                                  producer!,
                                  c,
                                  phase,
                                  dpr,
                                ),
                              ),
                            )
                          else if (c.mode != 'bare')
                            AnimatedBuilder(
                              animation: phase,
                              child: Stack(
                                children: [
                                  for (final r in _rects(c.count, size))
                                    Positioned.fromRect(
                                      rect: r,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          12 / dpr,
                                        ),
                                        child: BackdropFilter(
                                          backdropGroupKey: c.mode == 'grouped'
                                              ? _sharedKey
                                              : null,
                                          filter: ui.ImageFilter.blur(
                                            sigmaX: _sigmaPx / dpr,
                                            sigmaY: _sigmaPx / dpr,
                                          ),
                                          child: const SizedBox.expand(),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              builder: (context, child) => Transform.translate(
                                offset: ui.Offset(phase.value * 12 / dpr, 0),
                                child: child,
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  final _sharedKey = BackdropKey();
}
