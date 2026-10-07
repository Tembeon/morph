// ignore_for_file: implementation_imports, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/internal/blur_reach.dart';
import 'package:morph/src/glass/renderer/internal/owned_input_experiment.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/widgets.dart' show MorphGlassRenderer;

const _runs = int.fromEnvironment('STAGE_RUNS', defaultValue: 3);
const _warmMs = int.fromEnvironment('STAGE_WARM_MS', defaultValue: 600);
const _sampleMs = int.fromEnvironment('STAGE_SAMPLE_MS', defaultValue: 2400);
const _seed = int.fromEnvironment('STAGE_SEED', defaultValue: 20261007);
const _layouts = String.fromEnvironment(
  'STAGE_LAYOUTS',
  defaultValue: 'single',
);
const _motions = String.fromEnvironment(
  'STAGE_MOTIONS',
  defaultValue: 'background',
);
const _plans = String.fromEnvironment(
  'STAGE_PLANS',
  defaultValue: 'independent',
);
const _sigmas = String.fromEnvironment('STAGE_SIGMAS', defaultValue: '2,10');
const _only = String.fromEnvironment('STAGE_MODES');
const _content = String.fromEnvironment('STAGE_CONTENT', defaultValue: 'tiles');
const _shots = bool.fromEnvironment('STAGE_SHOTS');
final _shotPhases = const String.fromEnvironment(
  'STAGE_SHOT_PHASES',
  defaultValue: '-1,0,1',
).split(',').map(double.parse).toList();

/// Runs the standalone AOT stage benchmark, without a test binding.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const _Bench());
}

class _Case {
  const _Case(this.layout, this.motion, this.plan, this.mode, this.sigma);

  final String layout;
  final String motion;
  final String plan;
  final String mode;
  final double sigma;

  String get name => '$layout-$motion-$plan-$mode-s$sigma';

  Map<String, Object> get metadata => {
    'layout': layout,
    'motion': motion,
    'plan': plan,
    'mode': mode,
    'requested_sigma_logical': sigma,
    'content': _content,
    if (mode.startsWith('mix-')) 'source_workload': motion,
    'gpu_implementation': mode.startsWith('mix-')
        ? 'shared versioned ROI, raster-side passes, original Morph optics'
        : 'fused bilinear ROI pyramid, persistent intermediates, image surfaces',
  };
}

List<String> _selection(String value, List<String> allowed) {
  final selected = value.split(',');
  if (selected.any((s) => !allowed.contains(s)) ||
      selected.toSet().length != selected.length) {
    throw ArgumentError('Expected distinct members of $allowed, got $value');
  }
  return selected;
}

List<_Case> _cases() {
  _selection(_content, ['tiles', 'text', 'edge']);
  if (_runs < 1 || _warmMs < 100 || _sampleMs < 100) {
    throw ArgumentError(
      'Positive runs and warm/sample windows >= 100 ms required',
    );
  }
  final sigmas = _sigmas.split(',').map(double.parse).toList();
  if (sigmas.isEmpty ||
      sigmas.any((s) => !s.isFinite || s <= 0) ||
      sigmas.toSet().length != sigmas.length) {
    throw ArgumentError(
      'STAGE_SIGMAS requires distinct positive finite numbers',
    );
  }
  final modes = _only.isEmpty
      ? ['bare', 'capture', 'blur', 'optics', 'glass']
      : _selection(_only, [
          'bare',
          'capture',
          'blur',
          'optics',
          'glass',
          'gpu-bare',
          'gpu-copy',
          'gpu-gaussian',
          'gpu-dual',
          'gpu-dual3',
          'gpu-canvas',
          'gpu-retained',
          'mix-bare',
          'mix-native',
          'mix-gaussian',
          'mix-dual',
        ]);
  if (modes.any((m) => m.startsWith('gpu-')) &&
      (_motions != 'background' ||
          _plans != 'independent' ||
          _layouts.split(',').any((l) => !['single', 'large'].contains(l)))) {
    throw ArgumentError(
      'Owned GPU experiments require single/large, background, independent',
    );
  }
  if (modes.any((m) => m.startsWith('mix-')) &&
      (_plans != 'merged' ||
          _motions
              .split(',')
              .any((m) => !['background', 'updates', 'dynamic'].contains(m)))) {
    throw ArgumentError(
      'Combined experiments require merged and source motion',
    );
  }
  return [
    for (final layout in _selection(_layouts, [
      'single',
      'cluster',
      'spread',
      'large',
    ]))
      for (final motion in _selection(_motions, [
        'background',
        'glass',
        'both',
        'updates',
        'dynamic',
      ]))
        for (final plan in _selection(_plans, [
          'independent',
          'shared',
          'merged',
        ]))
          for (final mode in modes)
            for (final sigma
                in (mode.startsWith('mix-') && mode != 'mix-bare') ||
                        mode == 'blur' ||
                        mode == 'glass' ||
                        mode == 'gpu-gaussian' ||
                        mode == 'gpu-canvas' ||
                        mode == 'gpu-retained' ||
                        mode.startsWith('gpu-dual') ||
                        mode == 'gpu-copy'
                    ? (mode == 'gpu-dual3'
                          ? sigmas.where((s) => s > 3).toList()
                          : sigmas)
                    : [0.0])
              _Case(layout, motion, plan, mode, sigma),
  ];
}

/// Synthetic glass footprints, with the same total area in cluster/spread.
List<Rect> stageBenchRects(String layout, Size size) {
  final w = size.width;
  final h = size.height;
  return switch (layout) {
    'single' => [Rect.fromLTWH(w * .12, h * .38, w * .76, h * .16)],
    'large' => [Rect.fromLTWH(w * .08, h * .16, w * .84, h * .68)],
    'cluster' || 'spread' => [
      for (final x in layout == 'cluster' ? [.27, .52] : [.08, .70])
        for (final y in layout == 'cluster' ? [.34, .48] : [.14, .72])
          Rect.fromLTWH(w * x, h * y, w * .22, h * .12),
    ],
    _ => throw ArgumentError.value(layout, 'layout'),
  };
}

/// Frame statistics over every rendered frame, including cheap baseline frames.
Map<String, num> stageBenchStats(List<ui.FrameTiming> frames, double budgetMs) {
  if (frames.isEmpty) throw StateError('No frame timings in measured window');
  double percentile(List<double> values, double q) {
    values.sort();
    return values[math.max(0, (values.length * q).ceil() - 1)];
  }

  final build = [for (final f in frames) f.buildDuration.inMicroseconds / 1000];
  final raster = [
    for (final f in frames) f.rasterDuration.inMicroseconds / 1000,
  ];
  return {
    'n': frames.length,
    for (final q in [.5, .95, .99]) ...{
      'build_p${(q * 100).round()}': percentile(build, q),
      'raster_p${(q * 100).round()}': percentile(raster, q),
    },
    'build_mean': build.reduce((a, b) => a + b) / build.length,
    'raster_mean': raster.reduce((a, b) => a + b) / raster.length,
    'over_budget': frames
        .where(
          (f) =>
              f.buildDuration.inMicroseconds > budgetMs * 1000 ||
              f.rasterDuration.inMicroseconds > budgetMs * 1000,
        )
        .length,
  };
}

class _Bench extends StatefulWidget {
  const _Bench();

  @override
  State<_Bench> createState() => _BenchState();
}

class _BenchState extends State<_Bench> with SingleTickerProviderStateMixin {
  final _phase = ValueNotifier<double>(0);
  final _timings = <ui.FrameTiming>[];
  final _windows = <String, List<List<int>>>{};
  final _metadata = <String, Map<String, Object>>{};
  final _order = <String>[];
  final _mixWindows = <String, List<Map<String, Object>>>{};
  final _sceneKey = GlobalKey();
  late final Ticker _ticker;
  _Case? _current;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _phase.value = math.sin(
        elapsed.inMicroseconds * 2 * math.pi / (_sampleMs * 1000),
      );
    });
    SchedulerBinding.instance.addTimingsCallback(_collect);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _collect(List<ui.FrameTiming> batch) => _timings.addAll(batch);

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_collect);
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  void _mark(_Case c, int run, String edge) {
    developer.Timeline.startSync('scene:${c.name}:$run:$edge');
    developer.Timeline.finishSync();
  }

  Map<String, Object> _layerSnapshot() {
    var filters = 0;
    var independent = 0;
    final keys = <BackdropKey>{};
    final bounds = <List<double>>[];
    final blurSigmas = <double>[];
    void visitLayer(Layer layer) {
      // ignore: invalid_use_of_protected_member
      if (layer is BackdropFilterLayer && layer.engineLayer != null) {
        filters++;
        if (layer.backdropKey case final key?) {
          keys.add(key);
        } else {
          independent++;
        }
      }
      if (layer is ContainerLayer) {
        for (
          var child = layer.firstChild;
          child != null;
          child = child.nextSibling
        ) {
          visitLayer(child);
        }
      }
    }

    void visitRender(RenderObject object) {
      if (object is RenderLiquidGlassLayer) {
        blurSigmas.add(object.blurPassSigma);
        if (object.debugFilterBounds case final r?) {
          bounds.add([r.left, r.top, r.width, r.height]);
        }
      }
      object.visitChildren(visitRender);
    }

    for (final view in RendererBinding.instance.renderViews) {
      // ignore: invalid_use_of_protected_member
      if (view.layer case final layer?) visitLayer(layer);
    }
    _sceneKey.currentContext?.findRenderObject()?.visitChildren(visitRender);
    return {
      'owned_gpu': _OwnedSource.diagnostics(),
      'backdrop_layers': filters,
      'distinct_capture_keys': independent + keys.length,
      'liquid_filter_rects_logical': bounds,
      'liquid_blur_pass_sigmas_logical': blurSigmas,
    };
  }

  Future<void> _mount(_Case c) async {
    _ticker.stop();
    _phase.value = 0;
    setState(() => _current = c);
    await SchedulerBinding.instance.endOfFrame;
    if (c.mode.startsWith('gpu-')) {
      final context = _sceneKey.currentContext!;
      if (!context.mounted) throw StateError('Scene unmounted during setup');
      final box = context.findRenderObject()! as RenderBox;
      await _OwnedSource.obtain(box.size, View.of(context).devicePixelRatio);
      await SchedulerBinding.instance.endOfFrame;
    }
    _ticker.start();
    await Future<void>.delayed(const Duration(milliseconds: _warmMs));
  }

  Future<void> _run() async {
    final out = Directory(
      const String.fromEnvironment(
        'AUDIT_OUT',
        defaultValue: '/tmp/morph-stage',
      ),
    );
    try {
      if (kDebugMode) {
        throw StateError('Stage timings require a profile or release build');
      }
      final cases = _cases();
      await MorphGlassRenderer.precache();
      if (cases.any((c) => c.mode.startsWith('mix-'))) {
        OwnedGlassExperiment.program = await ui.FragmentProgram.fromAsset(
          'packages/morph/lib/src/glass/renderer/shaders/owned_glass_ios27.frag',
        );
        _MixSource.canvasProgram = await ui.FragmentProgram.fromAsset(
          'shaders/dual_canvas.frag',
        );
      }
      if (!MorphGlassRenderer.liquidAvailable) {
        throw StateError(
          'Liquid unavailable: ${MorphGlassRenderer.liquidUnavailableReason}',
        );
      }
      for (final c in cases) {
        await _mount(c);
      }
      final random = math.Random(_seed);
      for (var run = 0; run < _runs; run++) {
        final order = [...cases];
        order.shuffle(random);
        for (final c in order) {
          await _mount(c);
          final snapshot = _layerSnapshot();
          if (!c.mode.startsWith('mix-') &&
              !c.mode.startsWith('gpu-') &&
              c.mode != 'bare' &&
              snapshot['backdrop_layers'] == 0) {
            throw StateError('Missing backdrop layer in ${c.name}');
          }
          final size =
              (_sceneKey.currentContext!.findRenderObject()! as RenderBox).size;
          final rects = stageBenchRects(c.layout, size);
          _metadata[c.name] = {...c.metadata, ...snapshot};
          _metadata[c.name]!['visible_rects_logical'] = [
            for (final r in rects) [r.left, r.top, r.width, r.height],
          ];
          _order.add(c.name);
          _mark(c, run, 'begin');
          final countersBefore = _MixSource.active?.counters;
          final window = [developer.Timeline.now, 0];
          await Future<void>.delayed(const Duration(milliseconds: _sampleMs));
          window[1] = developer.Timeline.now;
          if (_MixSource.active case final source?) {
            final after = source.counters;
            (_mixWindows[c.name] ??= []).add({
              ...after,
              for (final key in [
                'recordings',
                'roi_captures',
                'blur_passes',
                'cache_hits',
                'unavailable_immediate_gpu_textures',
              ])
                key: (after[key]! as int) - (countersBefore![key]! as int),
            });
          }
          _mark(c, run, 'end');
          (_windows[c.name] ??= []).add(window);
        }
      }
      _ticker.stop();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final report = _report();
      out.createSync(recursive: true);
      if (_shots) {
        for (final c in cases) {
          await _mount(c);
          _ticker.stop();
          for (final phase in _shotPhases) {
            _phase.value = phase;
            await SchedulerBinding.instance.endOfFrame;
            await SchedulerBinding.instance.endOfFrame;
            final boundary =
                _sceneKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final shot = await boundary.toImage(
              pixelRatio: View.of(_sceneKey.currentContext!).devicePixelRatio,
            );
            try {
              final bytes = await shot.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (bytes == null) throw StateError('Missing PNG for ${c.name}');
              File('${out.path}/${c.name}-p$phase.png').writeAsBytesSync(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              );
            } finally {
              shot.dispose();
            }
          }
        }
      }
      final temporary = File('${out.path}/report.tmp');
      temporary.writeAsStringSync(jsonEncode(report));
      temporary.renameSync('${out.path}/report.json');
      developer.log('STAGE_BENCH done ${out.path}/report.json');
      setState(() => _current = null);
    } on Object catch (error, stack) {
      _ticker.stop();
      out.createSync(recursive: true);
      File(
        '${out.path}/error.json',
      ).writeAsStringSync(jsonEncode({'error': '$error', 'stack': '$stack'}));
      developer.log('STAGE_BENCH failed', error: error, stackTrace: stack);
    }
  }

  Map<String, Object> _report() {
    final view = ui.PlatformDispatcher.instance.views.first;
    final rate = view.display.refreshRate > 0 ? view.display.refreshRate : 60.0;
    final budget = 1000 / rate;
    return {
      'schema': 'morph-stage-bench-v1',
      'platform': Platform.operatingSystem,
      'build_mode': kProfileMode ? 'profile' : 'release',
      'refresh_rate': rate,
      'budget_ms': budget,
      'device_pixel_ratio': view.devicePixelRatio,
      'physical_size': [view.physicalSize.width, view.physicalSize.height],
      'liquid_available': MorphGlassRenderer.liquidAvailable,
      'runs': _runs,
      'warm_ms': _warmMs,
      'sample_ms': _sampleMs,
      'seed': _seed,
      'shot_phases': _shots ? _shotPhases : <double>[],
      'order': _order,
      'case_metadata': _metadata,
      'owned_source_windows': _mixWindows,
      'windows_us': _windows,
      'attribution':
          'comparative proxies; capture graph is not engine-verified',
      for (final entry in _windows.entries)
        entry.key: () {
          final runs = [
            for (final window in entry.value)
              () {
                final frames = _timings.where((f) {
                  final t = f.timestampInMicroseconds(ui.FramePhase.vsyncStart);
                  return t >= window[0] && t < window[1];
                }).toList();
                if (frames.length < 4) {
                  throw StateError('Insufficient timings for ${entry.key}');
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
          ];
          return {
            'runs': runs,
            'median': {
              for (final key in ['n', 'build_p95', 'raster_p95', 'over_budget'])
                key: () {
                  final values = [
                    for (final r in runs) (r[key]! as num).toDouble(),
                  ];
                  values.sort();
                  final mid = values.length ~/ 2;
                  return values.length.isOdd
                      ? values[mid]
                      : (values[mid - 1] + values[mid]) / 2;
                }(),
            },
          };
        }(),
    };
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery.fromView(
      view: ui.PlatformDispatcher.instance.views.first,
      child: RepaintBoundary(
        key: _sceneKey,
        child: _current == null
            ? const ColoredBox(color: Color(0xFF141829))
            : _Scene(
                key: ValueKey(_current!.name),
                config: _current!,
                phase: _phase,
              ),
      ),
    ),
  );
}

class _Scene extends StatefulWidget {
  const _Scene({required this.config, required this.phase, super.key});

  final _Case config;
  final ValueListenable<double> phase;

  @override
  State<_Scene> createState() => _SceneState();
}

class _SceneState extends State<_Scene> {
  _Case get config => widget.config;
  ValueListenable<double> get phase => widget.phase;
  late final _Background _background = _Background(
    config.motion == 'glass' ? null : phase,
  );

  @override
  void dispose() {
    _background.disposeText();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (config.mode.startsWith('mix-')) return _MixScene(config, phase);
      if (config.mode.startsWith('gpu-')) {
        return _OwnedScene(config: config, phase: phase);
      }
      final rects = stageBenchRects(config.layout, constraints.biggest);
      final sharedKey = BackdropKey();
      final effectiveSigma = morphHalfResolutionSigma(
        config.sigma,
        View.of(context).devicePixelRatio,
      );
      Widget shapes(List<Rect> regions) => Stack(
        children: [
          for (final rect in regions)
            Positioned.fromRect(
              rect: rect,
              child: const LiquidGlass(
                shape: LiquidRoundedRectangle(borderRadius: 18),
                child: SizedBox.expand(),
              ),
            ),
        ],
      );
      Widget glass(List<Rect> regions) => LiquidGlassLayer(
        settings: LiquidGlassSettings.ios27ToolbarDark(
          frost: config.mode == 'optics' ? 0 : config.sigma,
        ),
        defaultAppearance: const LiquidGlassAppearance.ios27RegularDark(),
        backdropKey: config.plan == 'shared' ? sharedKey : null,
        child: shapes(regions),
      );
      Widget proxy(Rect rect) => Positioned.fromRect(
        rect: rect,
        child: ClipRect(
          child: BackdropFilter(
            backdropGroupKey: config.plan == 'shared' ? sharedKey : null,
            filter: config.mode == 'capture'
                ? morphBackdropSeed
                : ui.ImageFilter.blur(
                    sigmaX: effectiveSigma,
                    sigmaY: effectiveSigma,
                    tileMode: TileMode.mirror,
                  ),
            child: const SizedBox.expand(),
          ),
        ),
      );
      Widget foreground() {
        if (config.mode == 'bare') return const SizedBox.expand();
        if (config.mode == 'glass' || config.mode == 'optics') {
          return config.plan == 'merged'
              ? glass(rects)
              : Stack(
                  children: [
                    for (final rect in rects) glass([rect]),
                  ],
                );
        }
        return Stack(
          children: [
            if (config.plan == 'merged')
              proxy(rects.reduce((a, b) => a.expandToInclude(b)))
            else
              for (final rect in rects) proxy(rect),
          ],
        );
      }

      final front = foreground();
      return Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _background, isComplex: true),
            ),
          ),
          Positioned.fill(
            child: config.motion == 'background'
                ? front
                : AnimatedBuilder(
                    animation: phase,
                    child: front,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(6 * phase.value, 0),
                      child: child,
                    ),
                  ),
          ),
        ],
      );
    },
  );
}

class _Background extends CustomPainter {
  _Background(this.phase) : super(repaint: phase) {
    if (_content == 'text') {
      _text = TextPainter(
        text: const TextSpan(
          text: 'Morph 0123\nFine detail',
          style: TextStyle(color: Color(0xFF101629), fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      );
      _text!.layout(maxWidth: 64);
    }
  }

  final ValueListenable<double>? phase;
  final _paint = Paint();
  TextPainter? _text;

  void disposeText() => _text?.dispose();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFF141829), BlendMode.src);
    final shift = 28 * (phase?.value ?? 0);
    for (var y = -64.0; y < size.height + 64; y += 64) {
      for (var x = -64.0; x < size.width + 64; x += 64) {
        _paint.color = ((x / 64 + y / 64).round().isEven)
            ? const Color(0xFFDC925D)
            : const Color(0xFF4266B8);
        canvas.drawRect(Rect.fromLTWH(x + shift, y, 48, 48), _paint);
        _paint.color = const Color(0xFFC9E5ED);
        canvas.drawRect(Rect.fromLTWH(x + shift + 8, y + 12, 1, 24), _paint);
        _text?.paint(canvas, Offset(x + shift + 2, y + 2));
      }
    }
  }

  @override
  bool shouldRepaint(_Background oldDelegate) => oldDelegate.phase != phase;
}

class _OwnedScene extends StatelessWidget {
  const _OwnedScene({required this.config, required this.phase});
  final _Case config;
  final ValueListenable<double> phase;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final dpr = View.of(context).devicePixelRatio;
      final size = constraints.biggest;
      final requestedRect = stageBenchRects(config.layout, size).single;
      final rect = Rect.fromLTRB(
        (requestedRect.left * dpr).floor() / dpr,
        (requestedRect.top * dpr).floor() / dpr,
        (requestedRect.right * dpr).ceil() / dpr,
        (requestedRect.bottom * dpr).ceil() / dpr,
      );
      return FutureBuilder<_OwnedSource>(
        future: _OwnedSource.obtain(size, dpr),
        builder: (context, snapshot) {
          if (snapshot.hasError) throw StateError('${snapshot.error}');
          final source = snapshot.data;
          if (source == null) return const SizedBox.expand();
          final painter = _OwnedPainter(source, phase, rect, config);
          return Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: painter)),
              if (config.mode == 'gpu-gaussian')
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: morphHalfResolutionSigma(config.sigma, dpr),
                        sigmaY: morphHalfResolutionSigma(config.sigma, dpr),
                        tileMode: TileMode.mirror,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}

class _OwnedSource {
  _OwnedSource(
    this.image,
    this.texture,
    this.size,
    this.dpr,
    this.library,
    this.finalProgram,
    this.canvasProgram,
  );
  final ui.Image image;
  final gpu.Texture texture;
  final Size size;
  final double dpr;
  final gpu.ShaderLibrary library;
  final ui.FragmentProgram finalProgram;
  final ui.FragmentProgram canvasProgram;
  final canvasPlans = <String, _CanvasPlan>{};
  final plans = <String, _DualPlan>{};
  static final _sources = <String, Future<_OwnedSource>>{};
  static final _ready = <_OwnedSource>[];
  static int epoch = 0;
  static bool counting = false;
  static List<Map<String, Object>> diagnostics() => [
    for (final source in _ready)
      for (final entry in source.plans.entries)
        {
          'plan': entry.key,
          'source_pixels': [source.texture.width, source.texture.height],
          'roi_pixels': [entry.value.roi.width, entry.value.roi.height],
          'intermediate_pixels': [
            for (final pass in entry.value.passes)
              [pass.target.width, pass.target.height],
          ],
          'surface_pixels': [entry.value.outputWidth, entry.value.outputHeight],
          'surface_backing_textures':
              entry.value.surface?.debugBackingTextureCount ??
              entry.value.outputTextures.length,
          'gpu_render_passes': entry.value.passes.length + 1,
          'cpu_encoding_us': [
            for (final pass in [...entry.value.passes, entry.value.finalPass])
              pass.cpuSummary,
          ],
          'fused_final': entry.value.fusedFinal,
          'retained_source_cache': entry.value.retain,
          'executed_gpu_passes': entry.value.executedPasses,
          'owned_target_capacity_bytes': entry.value.capacityBytes,
          'first_pass_uniform_buffers': entry.value.passes.isEmpty
              ? entry.value.finalPass.dynamicBufferCount
              : entry.value.passes.first.dynamicBufferCount,
        },
  ];

  static Future<_OwnedSource> obtain(Size size, double dpr) => _sources
      .putIfAbsent('${size.width}/${size.height}/$dpr/$_content', () async {
        if (!counting) {
          counting = true;
          SchedulerBinding.instance.addPersistentFrameCallback((_) {
            if (RendererBinding.instance.sendFramesToEngine) epoch++;
          });
        }
        final library = await gpu.ShaderLibrary.fromAsset(
          'packages/morph/build/shaderbundles/morph_glass.shaderbundle',
        );
        if (library == null) throw StateError('Missing experimental bundle');
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.scale(dpr);
        if (_content == 'edge') {
          canvas.drawColor(const Color(0xFF000000), BlendMode.src);
          final edgePaint = Paint();
          edgePaint.color = const Color(0xFFFFFFFF);
          canvas.drawRect(
            Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height),
            edgePaint,
          );
        } else {
          final background = _Background(null);
          background.paint(canvas, size);
          background.disposeText();
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          (size.width * dpr).ceil(),
          (size.height * dpr).ceil(),
        );
        picture.dispose();
        final result = _OwnedSource(
          image,
          gpu.Texture.fromImage(gpu.gpuContext, image),
          size,
          dpr,
          library,
          await ui.FragmentProgram.fromAsset('shaders/dual_final.frag'),
          await ui.FragmentProgram.fromAsset('shaders/dual_canvas.frag'),
        );
        _ready.add(result);
        return result;
      });

  _DualPlan plan(
    Rect rect,
    double sigma, {
    required bool copy,
    required int maxLevels,
    required bool retain,
  }) => plans.putIfAbsent(
    '${rect.left}/${rect.top}/${rect.width}/${rect.height}/$sigma/$copy/$maxLevels/$retain',
    () => _DualPlan(
      this,
      rect,
      sigma,
      copy: copy,
      maxLevels: maxLevels,
      retain: retain,
    ),
  );
}

class _OwnedPainter extends CustomPainter {
  _OwnedPainter(this.source, this.phase, this.rect, this.config)
    : super(repaint: phase);
  final _OwnedSource source;
  final ValueListenable<double> phase;
  final Rect rect;
  final _Case config;
  final _paint = _linearPaint();
  static Paint _linearPaint() {
    final paint = Paint();
    paint.filterQuality = FilterQuality.low;
    return paint;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final shift = 28 * phase.value;
    canvas.drawImageRect(
      source.image,
      Rect.fromLTWH(
        -shift * source.dpr,
        0,
        source.image.width.toDouble(),
        source.image.height.toDouble(),
      ),
      Offset.zero & size,
      _paint,
    );
    if (config.mode == 'gpu-canvas') {
      final key =
          '${rect.left}/${rect.top}/${rect.width}/${rect.height}/${config.sigma}';
      final plan = source.canvasPlans.putIfAbsent(
        key,
        () => _CanvasPlan(source, rect, config.sigma),
      );
      plan.paint(canvas, shift);
    }
    if (config.mode == 'gpu-retained' ||
        config.mode.startsWith('gpu-dual') ||
        config.mode == 'gpu-copy') {
      final plan = source.plan(
        rect,
        config.sigma,
        copy: config.mode == 'gpu-copy',
        maxLevels: config.mode == 'gpu-dual3' ? 3 : 6,
        retain: config.mode == 'gpu-retained',
      );
      plan.paint(canvas, shift);
    }
  }

  @override
  bool shouldRepaint(_OwnedPainter oldDelegate) =>
      oldDelegate.config != config || oldDelegate.source != source;
}

class _GpuKernel {
  _GpuKernel(gpu.ShaderLibrary library, String name) {
    final fragment = library[name]!;
    pipeline = gpu.gpuContext.createRenderPipeline(
      library['DualVertex']!,
      fragment,
    );
    uniforms = fragment.getUniformSlot('BlurUniforms');
    sampler = fragment.getUniformSlot('sourceTexture');
    uvOffset = uniforms.getMemberOffsetInBytes('uvRect')!;
    halfOffset = uniforms.getMemberOffsetInBytes('halfOffset')!;
  }
  late final gpu.RenderPipeline pipeline;
  late final gpu.UniformSlot uniforms;
  late final gpu.UniformSlot sampler;
  late final int uvOffset;
  late final int halfOffset;
}

class _DualPass {
  _DualPass(this.kernel, this.input, this.target, this.uv, this.offset) {
    bytes = ByteData(kernel.uniforms.sizeInBytes!);
    _encode(uv.left);
    final buffer = gpu.gpuContext.createDeviceBufferWithCopy(bytes);
    uniformView = gpu.BufferView(
      buffer,
      offsetInBytes: 0,
      lengthInBytes: bytes.lengthInBytes,
    );
  }
  final _GpuKernel kernel;
  final gpu.Texture input;
  final gpu.Texture target;
  final Rect uv;
  final double offset;
  late final ByteData bytes;
  late final gpu.BufferView uniformView;
  final available = <gpu.DeviceBuffer>[];
  int dynamicBufferCount = 0;
  static const diagnose = bool.fromEnvironment('STAGE_GPU_DIAGNOSTIC');
  final clock = Stopwatch();
  final cpu = <String, List<int>>{};
  int previousUs = 0;
  void mark(String label) {
    if (!diagnose) return;
    final now = clock.elapsedMicroseconds;
    (cpu[label] ??= []).add(now - previousUs);
    previousUs = now;
  }

  Map<String, Object> get cpuSummary => {
    for (final entry in cpu.entries)
      entry.key: {
        'n': entry.value.length,
        'mean': entry.value.reduce((a, b) => a + b) / entry.value.length,
        'max': entry.value.reduce(math.max),
      },
  };
  gpu.DeviceBuffer? pendingBuffer;

  void _encode(double left) {
    final values = [left, uv.top, uv.width, uv.height];
    for (var i = 0; i < 4; i++) {
      bytes.setFloat32(kernel.uvOffset + 4 * i, values[i], Endian.host);
    }
    bytes.setFloat32(kernel.halfOffset, .5 * offset / input.width, Endian.host);
    bytes.setFloat32(
      kernel.halfOffset + 4,
      .5 * offset / input.height,
      Endian.host,
    );
  }

  gpu.CommandBuffer encode(
    gpu.BufferView vertices,
    gpu.Texture destination, {
    double? left,
  }) {
    if (diagnose) {
      clock.reset();
      clock.start();
      previousUs = 0;
    }
    gpu.DeviceBuffer? leased;
    var view = uniformView;
    if (left != null) {
      _encode(left);
      if (available.isEmpty) {
        dynamicBufferCount++;
        leased = gpu.gpuContext.createDeviceBuffer(
          gpu.StorageMode.hostVisible,
          bytes.lengthInBytes,
        );
      } else {
        leased = available.removeLast();
      }
      if (!leased.overwrite(bytes)) throw StateError('Uniform upload failed');
      view = gpu.BufferView(
        leased,
        offsetInBytes: 0,
        lengthInBytes: bytes.lengthInBytes,
      );
    }
    mark('uniforms');
    final command = gpu.gpuContext.createCommandBuffer();
    mark('command');
    final pass = command.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: destination,
          loadAction: gpu.LoadAction.dontCare,
        ),
      ),
    );
    mark('render_pass');
    pass.bindPipeline(kernel.pipeline);
    pass.setPrimitiveType(gpu.PrimitiveType.triangleStrip);
    pass.bindVertexBuffer(vertices);
    pass.bindUniform(kernel.uniforms, view);
    pass.bindTexture(
      kernel.sampler,
      input,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
      ),
    );
    mark('bindings');
    pass.draw(4);
    mark('draw');
    pendingBuffer = leased;
    return command;
  }

  void submit(gpu.CommandBuffer command) {
    if (diagnose) {
      clock.reset();
      clock.start();
      previousUs = 0;
    }
    final buffer = pendingBuffer;
    pendingBuffer = null;
    command.submit(
      completionCallback: buffer == null
          ? null
          : (success) {
              if (!success) throw StateError('Blur command failed');
              available.add(buffer);
            },
    );
    mark('submit');
  }
}

class _DualPlan {
  _DualPlan(
    this.source,
    this.rect,
    double sigma, {
    required bool copy,
    required int maxLevels,
    required this.retain,
  }) {
    final vertexData = Float32List.fromList([
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
    ]);
    final buffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(vertexData),
    );
    vertices = gpu.BufferView(
      buffer,
      offsetInBytes: 0,
      lengthInBytes: buffer.sizeInBytes,
    );
    final down = _GpuKernel(source.library, 'DualDown');
    final up = _GpuKernel(source.library, 'DualUp');
    final blit = _GpuKernel(source.library, 'DualCopy');
    final dpr = source.dpr;
    final sigmaPx = sigma * dpr;
    final levels = copy
        ? 0
        : (math.log(sigmaPx) / math.ln2).floor().clamp(1, maxLevels);
    final scale = double.parse(
      sigma <= 3
          ? const String.fromEnvironment(
              'STAGE_DUAL_SMALL_SCALE',
              defaultValue: '0.75',
            )
          : const String.fromEnvironment(
              'STAGE_DUAL_LARGE_SCALE',
              defaultValue: '0.756',
            ),
    );
    final offset = copy
        ? 0.0
        : scale * sigmaPx / math.sqrt(35 / 72 * (math.pow(4, levels) - 1));
    final logicalRoi = copy
        ? rect
        : rect.inflate(
            (4 * sigmaPx + 2 * math.pow(2, levels)) / dpr + (retain ? 28 : 0),
          );
    roi = Rect.fromLTRB(
      (logicalRoi.left * dpr).floorToDouble(),
      (logicalRoi.top * dpr).floorToDouble(),
      (logicalRoi.right * dpr).ceilToDouble(),
      (logicalRoi.bottom * dpr).ceilToDouble(),
    );
    final intermediate = <gpu.Texture>[];
    var input = source.texture;
    for (var i = 1; i <= levels; i++) {
      final texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        (roi.width / math.pow(2, i)).ceil(),
        (roi.height / math.pow(2, i)).ceil(),
      );
      intermediate.add(texture);
      final uv = i == 1
          ? Rect.fromLTWH(
              roi.left / input.width,
              roi.top / input.height,
              roi.width / input.width,
              roi.height / input.height,
            )
          : const Rect.fromLTWH(0, 0, 1, 1);
      passes.add(_DualPass(down, input, texture, uv, offset));
      input = texture;
    }
    for (var i = levels - 2; i >= 0; i--) {
      final target = intermediate[i];
      passes.add(
        _DualPass(up, input, target, const Rect.fromLTWH(0, 0, 1, 1), offset),
      );
      input = target;
    }
    final fused =
        !copy &&
        const bool.fromEnvironment('STAGE_FUSED_FINAL', defaultValue: true);
    fusedFinal = fused;
    if (fused) {
      final last = passes.removeLast();
      _configureOutput(last.target.width, last.target.height);
      finalPass = last;
      finalShader = source.finalProgram.fragmentShader();
      finalShader!.setFloat(0, rect.left);
      finalShader!.setFloat(1, rect.top);
      finalShader!.setFloat(2, rect.width);
      finalShader!.setFloat(3, rect.height);
      finalShader!.setFloat(4, (rect.left * dpr - roi.left) / roi.width);
      finalShader!.setFloat(5, (rect.top * dpr - roi.top) / roi.height);
      finalShader!.setFloat(6, rect.width * dpr / roi.width);
      finalShader!.setFloat(7, rect.height * dpr / roi.height);
      finalShader!.setFloat(8, .5 * offset / outputWidth);
      finalShader!.setFloat(9, .5 * offset / outputHeight);
    } else {
      _configureOutput((rect.width * dpr).ceil(), (rect.height * dpr).ceil());
      final visible = Rect.fromLTWH(
        (rect.left * dpr - roi.left) / roi.width,
        (rect.top * dpr - roi.top) / roi.height,
        rect.width * dpr / roi.width,
        rect.height * dpr / roi.height,
      );
      final uv = copy
          ? Rect.fromLTWH(
              rect.left * dpr / input.width,
              rect.top * dpr / input.height,
              rect.width * dpr / input.width,
              rect.height * dpr / input.height,
            )
          : visible;
      finalPass = _DualPass(copy ? blit : up, input, input, uv, offset);
    }
  }
  final _OwnedSource source;
  final Rect rect;
  final bool retain;
  ui.Image? retainedImage;
  int executedPasses = 0;
  late final Rect roi;
  late final gpu.BufferView vertices;
  final passes = <_DualPass>[];
  late final _DualPass finalPass;
  gpu.GpuImageSurface? surface;
  late final int outputWidth;
  late final int outputHeight;
  final outputTextures = <gpu.Texture>[];
  final lastUsed = <int>[];

  void _configureOutput(int width, int height) {
    outputWidth = width;
    outputHeight = height;
    if (const bool.fromEnvironment('STAGE_IMAGE_SURFACE')) {
      surface = gpu.gpuContext.createImageSurface(width, height);
    } else {
      for (var i = 0; i < (retain ? 1 : 3); i++) {
        outputTextures.add(
          gpu.gpuContext.createTexture(
            gpu.StorageMode.devicePrivate,
            width,
            height,
          ),
        );
        lastUsed.add(-100);
      }
    }
  }

  gpu.Texture _leaseOutput() {
    var index = lastUsed.indexWhere((epoch) => _OwnedSource.epoch - epoch >= 3);
    if (index < 0) {
      index = outputTextures.length;
      outputTextures.add(
        gpu.gpuContext.createTexture(
          gpu.StorageMode.devicePrivate,
          outputWidth,
          outputHeight,
        ),
      );
      lastUsed.add(-100);
    }
    lastUsed[index] = _OwnedSource.epoch;
    return outputTextures[index];
  }

  late final bool fusedFinal;
  ui.FragmentShader? finalShader;
  final outputPaint = Paint();

  int get capacityBytes {
    final scratch = <gpu.Texture>{
      for (final p in passes) p.target,
      finalPass.target,
    };
    scratch.remove(source.texture);
    final scratchBytes = scratch.fold<int>(
      0,
      (sum, t) => sum + t.width * t.height * 4,
    );
    final count = surface?.debugBackingTextureCount ?? outputTextures.length;
    return scratchBytes + count * outputWidth * outputHeight * 4;
  }

  void paint(Canvas canvas, double shift) {
    if (retain && retainedImage != null) {
      finalShader!.setFloat(
        4,
        (rect.left * source.dpr - roi.left - shift * source.dpr) / roi.width,
      );
      canvas.drawRect(rect, outputPaint);
      return;
    }
    final requestedShift = shift;
    final renderShift = retain ? 0.0 : shift;
    for (var i = 0; i < passes.length; i++) {
      final pass = passes[i];
      final command = pass.encode(
        vertices,
        pass.target,
        left: i == 0
            ? pass.uv.left - renderShift * source.dpr / source.texture.width
            : null,
      );
      pass.submit(command);
      executedPasses++;
    }
    final frame = surface?.acquireNextFrame();
    final destination = frame?.colorTexture ?? _leaseOutput();
    final command = finalPass.encode(
      vertices,
      destination,
      left: passes.isEmpty
          ? finalPass.uv.left - renderShift * source.dpr / source.texture.width
          : null,
    );
    frame?.present(command);
    finalPass.submit(command);
    executedPasses++;
    final image = surface?.currentImage ?? destination.asImage();
    try {
      if (fusedFinal) {
        if (retain) {
          retainedImage = image;
          finalShader!.setFloat(
            4,
            (rect.left * source.dpr - roi.left - requestedShift * source.dpr) /
                roi.width,
          );
        }
        finalShader!.setImageSampler(
          0,
          image,
          filterQuality: FilterQuality.low,
        );
        outputPaint.shader = finalShader;
        canvas.drawRect(rect, outputPaint);
      } else {
        outputPaint.filterQuality = FilterQuality.low;
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          rect,
          outputPaint,
        );
      }
    } finally {
      if (!retain) image.dispose();
    }
  }
}

class _CanvasPlan {
  _CanvasPlan(this.source, this.rect, double sigma) {
    final sigmaPx = sigma * source.dpr;
    levels = (math.log(sigmaPx) / math.ln2).floor().clamp(1, 6);
    final scale = double.parse(
      sigma <= 3
          ? const String.fromEnvironment(
              'STAGE_DUAL_SMALL_SCALE',
              defaultValue: '0.75',
            )
          : const String.fromEnvironment(
              'STAGE_DUAL_LARGE_SCALE',
              defaultValue: '0.756',
            ),
    );
    offset = scale * sigmaPx / math.sqrt(35 / 72 * (math.pow(4, levels) - 1));
    final logical = rect.inflate(
      (4 * sigmaPx + 2 * math.pow(2, levels)) / source.dpr,
    );
    roi = Rect.fromLTRB(
      (logical.left * source.dpr).floorToDouble(),
      (logical.top * source.dpr).floorToDouble(),
      (logical.right * source.dpr).ceilToDouble(),
      (logical.bottom * source.dpr).ceilToDouble(),
    );
    for (var i = 0; i < levels * 2 - 1; i++) {
      shaders.add(source.canvasProgram.fragmentShader());
    }
    finalShader = source.finalProgram.fragmentShader();
    finalShader.setFloat(0, rect.left);
    finalShader.setFloat(1, rect.top);
    finalShader.setFloat(2, rect.width);
    finalShader.setFloat(3, rect.height);
    finalShader.setFloat(4, (rect.left * source.dpr - roi.left) / roi.width);
    finalShader.setFloat(5, (rect.top * source.dpr - roi.top) / roi.height);
    finalShader.setFloat(6, rect.width * source.dpr / roi.width);
    finalShader.setFloat(7, rect.height * source.dpr / roi.height);
  }
  final _OwnedSource source;
  final Rect rect;
  late final int levels;
  late final double offset;
  late final Rect roi;
  final shaders = <ui.FragmentShader>[];
  late final ui.FragmentShader finalShader;
  final paintPass = Paint();
  final finalPaint = Paint();

  void paint(Canvas canvas, double shift) {
    final images = <ui.Image>[];
    var input = source.image;
    var passIndex = 0;
    ui.Image render(int level, {required bool up}) {
      final width = (roi.width / math.pow(2, level)).ceil();
      final height = (roi.height / math.pow(2, level)).ceil();
      final shader = shaders[passIndex++];
      final uv = passIndex == 1
          ? Rect.fromLTWH(
              (roi.left - shift * source.dpr) / input.width,
              roi.top / input.height,
              roi.width / input.width,
              roi.height / input.height,
            )
          : const Rect.fromLTWH(0, 0, 1, 1);
      final values = [
        width.toDouble(),
        height.toDouble(),
        uv.left,
        uv.top,
        uv.width,
        uv.height,
        .5 * offset / input.width,
        .5 * offset / input.height,
        up ? 1.0 : 0.0,
      ];
      for (var i = 0; i < values.length; i++) {
        shader.setFloat(i, values[i]);
      }
      shader.setImageSampler(0, input, filterQuality: FilterQuality.low);
      paintPass.shader = shader;
      paintPass.isAntiAlias = false;
      final recorder = ui.PictureRecorder();
      final targetCanvas = Canvas(recorder);
      targetCanvas.drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        paintPass,
      );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(width, height);
      picture.dispose();
      images.add(image);
      return image;
    }

    try {
      for (var i = 1; i <= levels; i++) {
        input = render(i, up: false);
      }
      for (var i = levels - 1; i >= 1; i--) {
        input = render(i, up: true);
      }
      finalShader.setFloat(8, .5 * offset / input.width);
      finalShader.setFloat(9, .5 * offset / input.height);
      finalShader.setImageSampler(0, input, filterQuality: FilterQuality.low);
      finalPaint.shader = finalShader;
      canvas.drawRect(rect, finalPaint);
    } finally {
      for (final image in images) {
        image.dispose();
      }
    }
  }
}

class _MixSource {
  _MixSource(this.phase, this.size, this.dpr, this.config);
  final ValueListenable<double> phase;
  final Size size;
  final double dpr;
  final _Case config;
  ui.Picture? picture;
  ui.Picture? basePicture;
  ui.Image? blurred;
  Object? version;
  Object? blurredVersion;
  Rect? region;
  Offset halfOffset = Offset.zero;
  int recordings = 0;
  int captures = 0;
  int blurPasses = 0;
  int hits = 0;
  int unavailableTextures = 0;
  static _MixSource? active;
  static ui.FragmentProgram? canvasProgram;
  final shaders = <ui.FragmentShader>[];

  Map<String, Object> get counters => {
    'recordings': recordings,
    'roi_captures': captures,
    'blur_passes': blurPasses,
    'cache_hits': hits,
    'unavailable_immediate_gpu_textures': unavailableTextures,
    'source_version': '$version',
    'blur_version': '$blurredVersion',
    'roi_logical': region == null
        ? <double>[]
        : [region!.left, region!.top, region!.width, region!.height],
    'rss_bytes': ProcessInfo.currentRss,
    'retained_output_bytes': blurred == null
        ? 0
        : blurred!.width * blurred!.height * 4,
  };

  void ensurePicture() {
    final p = phase.value;
    final Object next = config.motion == 'updates'
        ? ((p + 1) * 8).floor()
        : config.motion == 'dynamic'
        ? p
        : 0;
    if (version == next) return;
    version = next;
    recordings++;
    picture?.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (basePicture == null) {
      final baseRecorder = ui.PictureRecorder();
      final background = _Background(null);
      background.paint(Canvas(baseRecorder), size);
      background.disposeText();
      basePicture = baseRecorder.endRecording();
    }
    canvas.drawPicture(basePicture!);
    if (config.motion != 'background') {
      final paint = Paint();
      final v = next as num;
      paint.color = v.toInt().isEven
          ? const Color(0xFF39EA94)
          : const Color(0xFFEB4EA1);
      final dx = config.motion == 'dynamic' ? p * 35 : v.toDouble() * 3;
      canvas.drawRect(
        Rect.fromLTWH(size.width * .40 + dx, size.height * .42, 26, 70),
        paint,
      );
      paint.color = const Color(0xFF09101F);
      canvas.drawRect(
        Rect.fromLTWH(size.width * .40 + dx + 4, size.height * .42, 1, 70),
        paint,
      );
    }
    picture = recorder.endRecording();
  }

  OwnedGlassInput input() {
    ensurePicture();
    if (blurredVersion == version && blurred != null) {
      hits++;
      return OwnedGlassInput(
        blurred!,
        region!,
        Offset(28 * phase.value, 0),
        halfOffset,
      );
    }
    final rects = stageBenchRects(config.layout, size);
    final sigma = morphHalfResolutionSigma(config.sigma, dpr);
    final levels = (math.log(config.sigma * dpr) / math.ln2).floor().clamp(
      1,
      6,
    );
    final margin =
        math.max(
          morphBlurReach(sigma, dpr),
          (4 * config.sigma * dpr + 2 * math.pow(2, levels)) / dpr,
        ) +
        28 +
        24;
    final logical = rects
        .reduce((a, b) => a.expandToInclude(b))
        .inflate(margin)
        .intersect(Offset.zero & size);
    final bucket = config.mode == 'mix-gaussian' && config.sigma <= 3
        ? 2.0
        : 1.0;
    final roi = Rect.fromLTRB(
      (logical.left * dpr / bucket).floor() * bucket / dpr,
      (logical.top * dpr / bucket).floor() * bucket / dpr,
      (logical.right * dpr / bucket).ceil() * bucket / dpr,
      (logical.bottom * dpr / bucket).ceil() * bucket / dpr,
    );
    region = roi;
    final width = (roi.width * dpr).round();
    final height = (roi.height * dpr).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final fusedGaussian = config.mode == 'mix-gaussian';
    if (fusedGaussian) {
      final paint = Paint();
      paint.imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.mirror,
      );
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        paint,
      );
    }
    canvas.scale(dpr);
    canvas.translate(-roi.left, -roi.top);
    canvas.drawPicture(picture!);
    if (fusedGaussian) canvas.restore();
    final capturePicture = recorder.endRecording();
    var image = capturePicture.toImageSync(width, height);
    capturePicture.dispose();
    captures++;
    if (const bool.fromEnvironment('STAGE_TEXTURE_PROBE')) {
      try {
        gpu.Texture.fromImage(gpu.gpuContext, image);
      } on Object {
        unavailableTextures++;
      }
    }
    blurred?.dispose();
    if (config.mode == 'mix-gaussian') {
      blurred = image;
      halfOffset = Offset.zero;
      blurPasses++;
    } else {
      final offset =
          (config.sigma <= 3 ? .75 : .756) *
          config.sigma *
          dpr /
          math.sqrt(35 / 72 * (math.pow(4, levels) - 1));
      var slot = 0;
      ui.Image pass(
        ui.Image input,
        int outWidth,
        int outHeight, {
        required bool up,
      }) {
        if (shaders.length <= slot) {
          shaders.add(canvasProgram!.fragmentShader());
        }
        final shader = shaders[slot++];
        shader.setFloat(0, outWidth.toDouble());
        shader.setFloat(1, outHeight.toDouble());
        shader.setFloat(2, 0);
        shader.setFloat(3, 0);
        shader.setFloat(4, 1);
        shader.setFloat(5, 1);
        shader.setFloat(6, .5 * offset / input.width);
        shader.setFloat(7, .5 * offset / input.height);
        shader.setFloat(8, up ? 1 : 0);
        shader.setImageSampler(0, input, filterQuality: FilterQuality.low);
        final r = ui.PictureRecorder();
        final c = Canvas(r);
        final paint = Paint();
        paint.shader = shader;
        c.drawRect(
          Rect.fromLTWH(0, 0, outWidth.toDouble(), outHeight.toDouble()),
          paint,
        );
        final p = r.endRecording();
        final result = p.toImageSync(outWidth, outHeight);
        p.dispose();
        input.dispose();
        blurPasses++;
        return result;
      }

      for (var level = 1; level <= levels; level++) {
        image = pass(
          image,
          (width / math.pow(2, level)).ceil(),
          (height / math.pow(2, level)).ceil(),
          up: false,
        );
      }
      for (var level = levels - 1; level >= 1; level--) {
        image = pass(
          image,
          (width / math.pow(2, level)).ceil(),
          (height / math.pow(2, level)).ceil(),
          up: true,
        );
      }
      blurred = image;
      halfOffset = Offset(
        .5 * offset / image.width,
        .5 * offset / image.height,
      );
    }
    blurredVersion = version;
    return OwnedGlassInput(
      blurred!,
      roi,
      Offset(28 * phase.value, 0),
      halfOffset,
    );
  }

  void dispose() {
    picture?.dispose();
    basePicture?.dispose();
    blurred?.dispose();
    for (final shader in shaders) {
      shader.dispose();
    }
  }
}

class _MixScene extends StatefulWidget {
  const _MixScene(this.config, this.phase);
  final _Case config;
  final ValueListenable<double> phase;
  @override
  State<_MixScene> createState() => _MixSceneState();
}

class _MixSceneState extends State<_MixScene> {
  _MixSource? source;
  @override
  void dispose() {
    if (identical(_MixSource.active, source)) {
      OwnedGlassExperiment.read = null;
      _MixSource.active = null;
    }
    source?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final s = source ??= _MixSource(
        widget.phase,
        constraints.biggest,
        View.of(context).devicePixelRatio,
        widget.config,
      );
      _MixSource.active = s;
      OwnedGlassExperiment.read =
          widget.config.mode == 'mix-native' || widget.config.mode == 'mix-bare'
          ? null
          : s.input;
      final regions = stageBenchRects(
        widget.config.layout,
        constraints.biggest,
      );
      final glass = LiquidGlassLayer(
        settings: LiquidGlassSettings.ios27ToolbarDark(
          frost: widget.config.sigma,
        ),
        defaultAppearance: const LiquidGlassAppearance.ios27RegularDark(),
        child: Stack(
          children: [
            for (final rect in regions)
              Positioned.fromRect(
                rect: rect,
                child: const LiquidGlass(
                  shape: LiquidRoundedRectangle(borderRadius: 18),
                  child: SizedBox.expand(),
                ),
              ),
          ],
        ),
      );
      return Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _MixBackground(s))),
          if (widget.config.mode != 'mix-bare')
            Positioned.fill(child: _MixPulse(widget.phase, child: glass)),
        ],
      );
    },
  );
}

class _MixBackground extends CustomPainter {
  _MixBackground(this.source) : super(repaint: source.phase);
  final _MixSource source;
  @override
  void paint(Canvas canvas, Size size) {
    source.ensurePicture();
    canvas.drawColor(const Color(0xFF141829), BlendMode.src);
    canvas.save();
    canvas.translate(28 * source.phase.value, 0);
    canvas.drawPicture(source.picture!);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MixBackground oldDelegate) =>
      oldDelegate.source != source;
}

class _MixPulse extends SingleChildRenderObjectWidget {
  const _MixPulse(this.phase, {required super.child});
  final Listenable phase;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MixPulseRender(phase);
}

class _MixPulseRender extends RenderProxyBox {
  _MixPulseRender(this.phase) {
    phase.addListener(invalidate);
  }
  final Listenable phase;
  void invalidate() {
    void visit(RenderObject object) {
      if (object is RenderLiquidGlassLayer) object.markNeedsPaint();
      object.visitChildren(visit);
    }

    if (child case final child?) visit(child);
  }

  @override
  void dispose() {
    phase.removeListener(invalidate);
    super.dispose();
  }
}
