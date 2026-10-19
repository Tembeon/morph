import 'dart:ui' as ui;

import 'package:meta/meta.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';

/// Web stand-in for the Flutter GPU geometry renderer.
///
/// Every entry point that would submit GPU work throws: the web has no
/// `flutter_gpu`, and real glass is not selected there because
/// `ImageFilter.isShaderFilterSupported` is false. Keeping the class shape
/// identical lets the render objects compile unchanged.
@internal
class FlutterGpuGeometryRenderer {
  FlutterGpuGeometryRenderer._();

  /// Always fails on the web; callers draw no liquid glass.
  static Future<FlutterGpuGeometryRenderer> fromAsset(String assetKey) =>
      Future<FlutterGpuGeometryRenderer>.error(
        UnsupportedError('Flutter GPU is not available on the web.'),
      );

  /// Nothing is ever cached on the web.
  static FlutterGpuGeometryRenderer? tryCreateCached(String assetKey) => null;

  static int get debugActiveGeometryTextureCount => 0;

  /// Matches the native renderer's reuse horizon; nothing is reused here.
  static const int reuseAfterFrames = 1;

  /// Nothing is ever deferred on the web.
  static void flushPendingSubmissions() {}

  /// Material map texels per matte pixel; shared constant with the native
  /// renderer so uniform math stays identical.
  static const int materialRasterScale = 8;

  /// The most shapes one geometry pass encodes.
  static const int maxShapes = 32;

  int debugRenderCount = 0;
  int get debugUniformBlockLength => 0;
  Object? get debugUniformArenaIdentity => null;
  ui.Image? get materialImage => null;

  // ignore: avoid_unused_constructor_parameters
  ({ui.Image image, int width, int height, int textureWidth, int textureHeight})
  render({
    required int width,
    required int height,
    required List<double> shapeData,
    required int numShapes,
    required double refractionHeight,
    required double refractionAmount,
    required double offsetX,
    required double offsetY,
    double? edgeDistanceRange,
    bool refractionFitsShape = true,
    double contourExtent = 0.5,
    bool writeMaterials = false,
    bool writeTintOnly = false,
    List<double> appearanceData = const <double>[],
    List<double> rseData = const <double>[],
    List<double> boundsData = const <double>[],
    GlassField? field,
    double fieldScale = 1,
    double mergeMinWidth = 0,
    ({double x, double y}) matteDensity = (x: 1, y: 1),
  }) => throw UnsupportedError('Flutter GPU is not available on the web.');

  /// Nothing is held on the web.
  bool get holdsOutput => false;

  void releaseOutput() {}

  void dispose() {}
}
