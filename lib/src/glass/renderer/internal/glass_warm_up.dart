import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart';
import 'package:morph/src/glass/renderer/internal/fake_glass_color.dart';
import 'package:morph/src/glass/renderer/internal/paint_fake_glass_surface.dart';
import 'package:morph/src/glass/renderer/internal/shader_filter.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/glass/renderer/rendering/liquid_glass_layer.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

/// The longest precache waits for one warm-up scene on the raster thread.
const Duration _sceneTimeout = Duration(seconds: 2);

/// The side of one warm-up cell, in logical pixels.
const double _cell = 24;

/// Frost sigmas, in logical pixels, that cover each downsample class the
/// glass blurs reach: unscaled, half, quarter and eighth.
const List<double> _frostSigmas = [1, 2, 8, 14];

/// The draws the last completed [morphWarmLiquidPipelines] rasterized, or
/// null before one completed.
///
/// `filters` counts the backdrop filters of one row, `solidPaints` the
/// final shaders painted over a declared solid backdrop.
@visibleForTesting
({int filters, int solidPaints})? debugMorphLiquidWarmUpDraws;

/// Draws once with every Flutter GPU pipeline of the geometry passes, then
/// rasterizes an offscreen scene with every liquid glass filter the layer
/// builds and every final shader painted as a layer over a solid backdrop
/// paints it, so the pipelines the first glass frame needs already exist.
///
/// Flutter GPU creates a pipeline at its first draw, on the UI thread, and
/// Impeller creates the variant a backdrop filter needs (its subpass's
/// sample count and stencil) at the filter's first draw, on the raster
/// thread. A final shader painted as an ordinary rect (source over, into
/// the current pass) is a pipeline of its own. Nothing reaches the screen.
/// A failure leaves the capability untouched: the real frame then pays the
/// cost it would have paid anyway.
@internal
Future<void> morphWarmLiquidPipelines(
  FlutterGpuGeometryRenderer geometry,
  List<String> finalShaderKeys,
) async {
  final images = <ui.Image>[];
  try {
    final appearance = List<double>.filled(
      FlutterGpuGeometryRenderer.maxShapes * 2 * 4,
      0,
    );
    final shapes = geometry.render(
      width: 8,
      height: 8,
      shapeData: const [],
      numShapes: 1,
      refractionHeight: 1,
      refractionAmount: 1,
      offsetX: 0,
      offsetY: 0,
      writeMaterials: true,
      appearanceData: appearance,
    );
    final matte = shapes.image.clone();
    images.add(matte);
    final material = geometry.materialImage!.clone();
    images.add(material);
    geometry.render(
      width: 8,
      height: 8,
      shapeData: const [],
      numShapes: 1,
      refractionHeight: 1,
      refractionAmount: 1,
      offsetX: 0,
      offsetY: 0,
      writeMaterials: true,
      writeTintOnly: true,
      appearanceData: appearance,
      field: GlassField(
        samples: Float32List(2 * 2 * 4),
        cols: 2,
        rows: 2,
        origin: Offset.zero,
        step: 1,
      ),
    );
    final tint = geometry.materialImage!.clone();
    images.add(tint);
    FlutterGpuGeometryRenderer.flushPendingSubmissions();

    final programs = [
      ...await Future.wait(finalShaderKeys.map(ui.FragmentProgram.fromAsset)),
    ];
    final warmedKeys = [...finalShaderKeys];
    // The analytic variants are warmed only where layers use them; one
    // that does not load is left out rather than failing the warm-up.
    if (RenderLiquidGlassLayer.analyticGeometryEnabled) {
      await RenderLiquidGlassLayer.precacheAnalyticShaders();
      for (final key in [
        ...ShaderKeys.liquidGlassAnalyticRenders,
        ...ShaderKeys.liquidGlassAnalyticFusedRenders,
      ]) {
        if (RenderLiquidGlassLayer.analyticProgram(key) case final program?) {
          programs.add(program);
          warmedKeys.add(key);
        }
      }
    }
    final analyticKeys = {
      ...ShaderKeys.liquidGlassAnalyticRenders,
      ...ShaderKeys.liquidGlassAnalyticFusedRenders,
    };
    final filters = <ui.ImageFilter>[];
    final tintKeys = {
      ShaderKeys.liquidGlassTintRender,
      ShaderKeys.liquidGlassTintIos27Render,
    };
    final solids = <ui.FragmentShader>[];
    for (final (index, program) in programs.indexed) {
      final key = warmedKeys[index];
      void bind(ui.FragmentShader shader) {
        shader.setImageSampler(0, matte, filterQuality: FilterQuality.low);
        // The analytic variants read no matte and no material map.
        if (!analyticKeys.contains(key)) shader.setImageSampler(1, matte);
        if (key == ShaderKeys.liquidGlassMaterialRender) {
          shader.setImageSampler(2, material);
          shader.setImageSampler(3, material, filterQuality: FilterQuality.low);
        } else if (tintKeys.contains(key)) {
          shader.setImageSampler(2, tint, filterQuality: FilterQuality.low);
        }
      }

      final shader = program.fragmentShader();
      bind(shader);
      // A layer over a solid backdrop paints the same variant with an
      // opaque uSolidBackdrop. Its own instance: the filter below keeps the
      // uniforms it is created with, and no layer's shader is touched.
      final solid = program.fragmentShader();
      bind(solid);
      solid.setFloat(0, _cell);
      solid.setFloat(1, _cell);
      for (var i = 0; i < 4; i++) {
        solid.setFloat(RenderLiquidGlassLayer.solidBackdropUniform + i, 1);
      }
      solids.add(solid);
      final filter = morphGlassShaderFilter(shader);
      filters.add(filter);
      for (final sigma in _frostSigmas) {
        filters.add(
          ui.ImageFilter.compose(
            inner: ui.ImageFilter.blur(
              tileMode: TileMode.mirror,
              sigmaX: sigma,
              sigmaY: sigma,
            ),
            outer: filter,
          ),
        );
      }
    }
    for (final sigma in _frostSigmas) {
      filters.add(ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));
    }
    try {
      await _rasterize((row, cell) {
        final layers = <Layer>[];
        for (final filter in filters) {
          final clip = ClipRectLayer(clipRect: cell(layers.length));
          clip.append(_backdrop(filter, row));
          layers.add(clip);
        }
        // A paint reads no backdrop key: the first row alone draws them.
        if (row == null) {
          for (final solid in solids) {
            layers.add(_solidPaint(solid, cell(layers.length)));
          }
        }
        return layers;
      }, filters.length + solids.length);
      debugMorphLiquidWarmUpDraws = (
        filters: filters.length,
        solidPaints: solids.length,
      );
    } finally {
      // A new shader's uniform buffer is not zeroed: leave no opaque
      // backdrop behind in memory a later shader may be given.
      for (final solid in solids) {
        for (var i = 0; i < 4; i++) {
          solid.setFloat(RenderLiquidGlassLayer.solidBackdropUniform + i, 0);
        }
      }
    }
  } on Object catch (error) {
    _report(error);
  } finally {
    for (final image in images) {
      image.dispose();
    }
  }
}

/// The final shader's draw as a layer over a solid backdrop records it: one
/// hard-edged rect, source over, into the current pass.
PictureLayer _solidPaint(ui.FragmentShader shader, Rect bounds) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, bounds);
  final paint = Paint();
  paint.shader = shader;
  paint.isAntiAlias = false;
  canvas.drawRect(bounds, paint);
  final layer = PictureLayer(bounds);
  layer.picture = recorder.endRecording();
  return layer;
}

/// Rasterizes an offscreen scene with the fake glass layers: the
/// backdrop through the fake face's color matrix, alone and over each
/// frost, inside an antialiased rounded clip and an outline path, under
/// the fake surface shader, and the glass shadows.
///
/// Runs only under Impeller, which creates these pipeline variants at
/// their first draw; elsewhere it completes at once.
@internal
Future<void> morphWarmFakePipelines() async {
  if (!ui.ImageFilter.isShaderFilterSupported) return;
  try {
    await morphRasterizeFakeWarmUp();
  } on Object catch (error) {
    _report(error);
  }
}

/// Rasterizes the fake glass warm-up scene on any backend, throwing what
/// it meets; without the surface shader's asset (flutter_test) it draws
/// the filters alone.
@visibleForTesting
Future<void> morphRasterizeFakeWarmUp() async {
  ui.FragmentShader? shader;
  try {
    final program = await ui.FragmentProgram.fromAsset(
      ShaderKeys.fakeGlassSurface,
    );
    shader = program.fragmentShader();
  } on Exception catch (error) {
    _report(error);
  }
  final face = ui.ColorFilter.matrix(
    fakeGlassFaceMatrix(
      emission: const Color(0xFF202020),
      transmittance: 0.6,
      lift: 1,
      chromaGain: 1,
    ),
  );
  final filters = <ui.ImageFilter>[
    face,
    for (final sigma in _frostSigmas)
      ui.ImageFilter.compose(
        inner: ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.mirror,
        ),
        outer: face,
      ),
  ];
  final count = filters.length * 2;
  return _rasterize((row, cell) {
    final layers = <Layer>[];
    for (final filter in filters) {
      for (final outline in [false, true]) {
        final bounds = cell(layers.length);
        final ContainerLayer clip;
        if (outline) {
          final path = Path();
          path.addRRect(
            RRect.fromRectAndRadius(
              bounds.deflate(4),
              const Radius.circular(6),
            ),
          );
          path.addOval(bounds.topLeft & const Size(10, 10));
          clip = ClipPathLayer(clipPath: path);
        } else {
          clip = ClipRRectLayer(
            clipRRect: RRect.fromRectAndRadius(
              bounds,
              const Radius.circular(8),
            ),
          );
        }
        clip.append(_backdrop(filter, row));
        if (shader != null) clip.append(_surface(shader, bounds));
        layers.add(clip);
      }
    }
    return layers;
  }, count);
}

BackdropFilterLayer _backdrop(ui.ImageFilter filter, BackdropKey? key) {
  final layer = BackdropFilterLayer(filter: filter);
  layer.backdropKey = key;
  return layer;
}

/// Rasterizes two rows of [count] cells: [build] fills a row for a backdrop
/// key (null for the first row, one shared key for the second), given the
/// rect of a cell index in that row.
Future<void> _rasterize(
  List<Layer> Function(BackdropKey? key, Rect Function(int index) cell) build,
  int count,
) async {
  final view = ui.PlatformDispatcher.instance.implicitView;
  final pixelRatio = view?.devicePixelRatio ?? 1;
  final bounds = Rect.fromLTWH(0, 0, _cell * count, _cell * 2);
  final root = OffsetLayer();
  final handle = LayerHandle<OffsetLayer>(root);
  try {
    final backdrop = PictureLayer(bounds);
    backdrop.picture = _backdropPicture(bounds);
    root.append(backdrop);
    for (final (row, key) in [(0, null), (1, BackdropKey())]) {
      final layers = build(
        key,
        (index) => Rect.fromLTWH(
          index * _cell + 2,
          row * _cell + 2,
          _cell - 4,
          _cell - 4,
        ),
      );
      layers.forEach(root.append);
    }
    final pending = root.toImage(bounds, pixelRatio: pixelRatio);
    try {
      final image = await pending.timeout(_sceneTimeout);
      image.dispose();
    } on TimeoutException {
      unawaited(pending.then((image) => image.dispose()));
    }
  } finally {
    handle.layer = null;
  }
}

/// A backdrop for the filters to read, with the glass shadows over it: an
/// even-odd cutout clip, and blurred rounded rectangles and superellipses
/// inside a bounded layer.
ui.Picture _backdropPicture(Rect bounds) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, bounds);
  final fill = Paint();
  fill.color = const Color(0xFF3A6EA5);
  canvas.drawRect(bounds, fill);
  final shadow = Paint();
  shadow.color = const Color(0x40000000);
  shadow.maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  const shape = Rect.fromLTWH(4, 4, _cell - 8, _cell - 8);
  final outside = Path();
  outside.fillType = PathFillType.evenOdd;
  outside.addRect(shape.inflate(8));
  outside.addRRect(RRect.fromRectAndRadius(shape, const Radius.circular(6)));
  canvas.saveLayer(shape.inflate(12), Paint());
  canvas.save();
  canvas.clipPath(outside);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      shape.shift(const Offset(0, 2)),
      const Radius.circular(6),
    ),
    shadow,
  );
  canvas.drawRSuperellipse(
    RSuperellipse.fromRectAndRadius(
      shape.shift(const Offset(_cell, 2)),
      const Radius.circular(6),
    ),
    shadow,
  );
  canvas.restore();
  canvas.restore();
  return recorder.endRecording();
}

/// The fake surface shader's draw over a cell: its tint, rim, bevel and
/// highlight.
PictureLayer _surface(ui.FragmentShader shader, Rect bounds) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, bounds);
  canvas.translate(bounds.left, bounds.top);
  paintFakeGlassSurface(
    canvas,
    shader: shader,
    size: bounds.size,
    shape: const LiquidRoundedSuperellipse(borderRadius: 8),
    settings: const LiquidGlassSettings(),
    appearance: const LiquidGlassAppearance(),
    devicePixelRatio: 3,
  );
  final layer = PictureLayer(bounds.inflate(4));
  layer.picture = recorder.endRecording();
  return layer;
}

void _report(Object error) {
  if (kDebugMode) debugPrint('morph: glass warm-up skipped: $error');
}
