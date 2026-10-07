// ignore_for_file: implementation_imports, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/internal/blur_reach.dart';
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
  _selection(_content, ['tiles', 'text']);
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
      : _selection(_only, ['bare', 'capture', 'blur', 'optics', 'glass']);
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
      ]))
        for (final plan in _selection(_plans, [
          'independent',
          'shared',
          'merged',
        ]))
          for (final mode in modes)
            for (final sigma
                in mode == 'blur' || mode == 'glass' ? sigmas : [0.0])
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
          if (c.mode != 'bare' && snapshot['backdrop_layers'] == 0) {
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
          final window = [developer.Timeline.now, 0];
          await Future<void>.delayed(const Duration(milliseconds: _sampleMs));
          window[1] = developer.Timeline.now;
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
          for (final phase in [-1.0, 0.0, 1.0]) {
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
      'shot_phases': _shots ? [-1.0, 0.0, 1.0] : <double>[],
      'order': _order,
      'case_metadata': _metadata,
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
