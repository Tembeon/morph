import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:morph/src/glass/renderer/glass_field.dart';

/// Renders the liquid glass geometry SDF shader using flutter_gpu.
///
/// Each output (matte, material map) cycles through a ring of textures that
/// only grow. A render draws into the top-left sub-rect of a texture no
/// in-flight frame reads and reports the texture size, so the final shader
/// scales its UVs to that sub-rect. Resizing geometry therefore reuses the
/// same textures instead of allocating, which matters because a
/// `gpu.Texture` is only freed when the GC finalizes its wrapper. The layer
/// reuses the image without calling [render] when geometry is unchanged
/// (including uniform translation).
///
/// This renderer owns the image handles returned by [gpu.Texture.asImage].
/// Replacing/disposal releases those handles; recorded scenes hold independent
/// native references. A scene rasterized more than [reuseAfterFrames] frames
/// after it was recorded may show a newer matte.
@internal
class FlutterGpuGeometryRenderer {
  FlutterGpuGeometryRenderer._fromShared(_SharedGeometryResources resources) {
    _pipeline = resources.pipeline;
    _fieldPipeline = resources.fieldPipeline;
    _fieldUniformSlot = resources.fieldUniformSlot;
    _fieldTextureSlot = resources.fieldTextureSlot;
    _fieldUniformData = ByteData(resources.fieldUniformSize);
    _fieldOffsets = resources.fieldOffsets;
    _materialGradientPipeline = resources.materialGradientPipeline;
    _materialTintGradientPipeline = resources.materialTintGradientPipeline;
    _uniformSlot = resources.uniformSlot;
    _uniformSize = resources.uniformSize;
    _offsetUOffset = resources.offsetUOffset;
    _offsetUTextureSize = resources.offsetUTextureSize;
    _offsetOpticalProps = resources.offsetOpticalProps;
    _offsetContourProps = resources.offsetContourProps;
    _offsetShapeData = resources.offsetShapeData;
    _offsetRseData = resources.offsetRseData;
    _offsetShapeTints = resources.offsetShapeTints;
    _offsetShapeResponses = resources.offsetShapeResponses;
    _offsetShapeBounds = resources.offsetShapeBounds;
    _vertexBufferView = resources.vertexBufferView;
    _uniformData = ByteData(_uniformSize);
    assert(() {
      _debugActiveRendererCount++;
      return true;
    }(), 'Track live geometry renderers in debug builds.');
  }

  // Flutter's centered half-pixel coverage transition.
  static const double _geometryAaHalfWidth = 0.5;

  static Future<FlutterGpuGeometryRenderer> fromAsset(String assetKey) async {
    final cachedResources = _resolvedAssetResources[assetKey];
    if (cachedResources != null) {
      return FlutterGpuGeometryRenderer._fromShared(cachedResources);
    }
    final resourcesFuture = _assetResources[assetKey] ??= () async {
      debugShaderBundleLoadCount++;
      final library = await gpu.ShaderLibrary.fromAsset(assetKey);
      final vertexShader = library?['GeometryVertex'];
      final fragmentShader = library?['GeometryFragment'];
      final fieldFragmentShader = library?['GeometryFieldFragment'];
      final materialGradientFragmentShader =
          library?['MaterialGradientFragment'];
      final materialTintGradientFragmentShader =
          library?['MaterialTintGradientFragment'];
      if (vertexShader == null ||
          fragmentShader == null ||
          fieldFragmentShader == null ||
          materialGradientFragmentShader == null ||
          materialTintGradientFragmentShader == null) {
        throw StateError(
          'LiquidGlass requires Flutter GPU. Run with Flutter 3.47 or newer '
          'and enable Flutter GPU for the target platform.',
        );
      }
      return _SharedGeometryResources(
        vertexShader: vertexShader,
        fragmentShader: fragmentShader,
        fieldFragmentShader: fieldFragmentShader,
        materialGradientFragmentShader: materialGradientFragmentShader,
        materialTintGradientFragmentShader: materialTintGradientFragmentShader,
      );
    }();
    final resources = await resourcesFuture;
    final renderer = FlutterGpuGeometryRenderer._fromShared(resources);
    _resolvedAssetResources[assetKey] = resources;
    return renderer;
  }

  /// The number of shader bundle loads attempted in this isolate.
  @visibleForTesting
  static int debugShaderBundleLoadCount = 0;

  /// Synchronously builds a renderer from already resolved shared resources.
  ///
  /// Returns null until [fromAsset] resolves [assetKey]. Failed asynchronous
  /// loads remain cached for the lifetime of the isolate.
  static FlutterGpuGeometryRenderer? tryCreateCached(String assetKey) {
    final resources = _resolvedAssetResources[assetKey];
    return resources == null
        ? null
        : FlutterGpuGeometryRenderer._fromShared(resources);
  }

  /// Completes once the Flutter GPU context exists without blocking.
  ///
  /// Workaround for Flutter 3.47.1 on Android: the engine creates the
  /// Impeller context on the raster thread after startup, off the critical
  /// path (`shell/common/shell.cc`), and reading `gpu.gpuContext` before
  /// then blocks the UI thread until it exists, which takes 100 ms or more on
  /// some Vulkan devices. The first rasterized frame needs the context, so
  /// waiting for it avoids the block. This initializes the widgets binding
  /// if needed, including before `runApp`. Remove it once the engine creates
  /// the context before the first frame or offers a non-blocking way to wait
  /// for it. On every other platform it completes immediately.
  static Future<void> waitUntilGpuContextAvailable() async {
    if (!Platform.isAndroid) return;
    await WidgetsFlutterBinding.ensureInitialized()
        .waitUntilFirstFrameRasterized;
  }

  static final Map<String, Future<_SharedGeometryResources>> _assetResources =
      {};
  static final Map<String, _SharedGeometryResources> _resolvedAssetResources =
      {};

  /// One bump allocator for every geometry pass in the current frame.
  ///
  /// A HostBuffer retains four device-buffer blocks, so one per renderer
  /// would cost four blocks per layer. A single scratch sized for a frame of
  /// layers keeps that off the native heap.
  static gpu.HostBuffer? _sharedHostBuffer;
  static int _sharedHostBufferBlockLength = 0;
  static Duration? _sharedHostBufferFrame;

  static const int _hostBufferSlotsPerFrame = 32;

  // These ownership counters exclude clones held by callers and native
  // references retained by submitted scenes; they are not GPU memory metrics.
  static int _debugActiveRendererCount = 0;
  static int _debugActiveGeometryTextureCount = 0;
  static int _debugActiveMaterialTextureCount = 0;
  static int _debugTotalRenderCount = 0;

  /// Counts SDF submissions across all owners, including temporary renderers.
  @visibleForTesting
  static int get debugTotalRenderCount => _debugTotalRenderCount;

  @visibleForTesting
  static int get debugActiveRendererCount => _debugActiveRendererCount;

  @visibleForTesting
  static int get debugActiveGeometryTextureCount =>
      _debugActiveGeometryTextureCount;

  @visibleForTesting
  static int get debugActiveMaterialTextureCount =>
      _debugActiveMaterialTextureCount;

  static gpu.HostBuffer _hostBufferForUniformSize(int uniformSize) {
    final alignment = gpu.gpuContext.minimumUniformByteAlignment;
    final alignedSize =
        ((uniformSize + alignment - 1) ~/ alignment) * alignment;
    final blockLength = alignedSize * _hostBufferSlotsPerFrame;
    if (_sharedHostBuffer == null ||
        _sharedHostBufferBlockLength < blockLength) {
      _sharedHostBuffer = gpu.gpuContext.createHostBuffer(
        blockLengthInBytes: blockLength,
      );
      _sharedHostBufferBlockLength = blockLength;
    }
    // This is also defined for direct renderer callers outside
    // handleDrawFrame while still advancing once per engine frame in
    // production.
    final timestamp = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (_sharedHostBufferFrame != timestamp) {
      _sharedHostBuffer!.reset();
      _sharedHostBufferFrame = timestamp;
    }
    return _sharedHostBuffer!;
  }

  late final gpu.RenderPipeline _pipeline;
  late final gpu.RenderPipeline _fieldPipeline;
  late final gpu.UniformSlot _fieldUniformSlot;
  late final gpu.UniformSlot _fieldTextureSlot;
  late final ByteData _fieldUniformData;
  late final _FieldUniformOffsets _fieldOffsets;
  final _FieldTextures _fieldTextures = _FieldTextures();
  late final gpu.RenderPipeline _materialGradientPipeline;
  late final gpu.RenderPipeline _materialTintGradientPipeline;

  @visibleForTesting
  Object get debugPipelineIdentity => _pipeline;

  @visibleForTesting
  int get debugHostBufferBlockLength => _sharedHostBufferBlockLength;

  @visibleForTesting
  Object? get debugHostBufferIdentity => _sharedHostBuffer;

  /// Number of geometry command buffers submitted by this renderer.
  @visibleForTesting
  int debugRenderCount = 0;

  @visibleForTesting
  bool get debugDisposed => _disposed;

  bool _disposed = false;

  // Uniform slot reflection.
  late final gpu.UniformSlot _uniformSlot;
  late final int _uniformSize;
  late final int _offsetUOffset;
  late final int _offsetUTextureSize;
  late final int _offsetOpticalProps;
  late final int _offsetContourProps;
  late final int _offsetShapeData;
  late final int _offsetRseData;
  late final int _offsetShapeTints;
  late final int _offsetShapeResponses;
  late final int _offsetShapeBounds;
  late final ByteData _uniformData;
  int _writtenShapeFloats = 0;
  int _writtenRseFloats = 0;

  // Latest matte. Older scenes retain their own native references.
  gpu.Texture? _texture;
  ui.Image? _image;
  gpu.RenderTarget? _renderTarget;
  gpu.Texture? _materialTexture;
  ui.Image? _materialImage;
  gpu.RenderTarget? _materialRenderTarget;

  // Appearance blending is decorative and only visible while shapes merge.
  // One sample per 8x8 full-resolution block makes its SDF work 64x smaller.
  static const int materialRasterScale = 8;

  late final gpu.BufferView _vertexBufferView;

  /// Low-resolution contributor map from the latest appearance render.
  ///
  /// The map fills the top-left sub-rect of the image; its size follows from
  /// the matte size, as in the final shader.
  ui.Image? get materialImage => _materialImage;

  final _TextureRing _mattes = _TextureRing();
  final _TextureRing _materials = _TextureRing();

  /// Renders a new geometry matte and returns it as a [ui.Image].
  ///
  /// The matte fills the top-left `width` x `height` of the image, which is
  /// `textureWidth` x `textureHeight`. The returned image is a non-owning
  /// wrapper - do NOT dispose it. Its texture is written again
  /// [reuseAfterFrames] frames after a later render replaces it.
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
  }) {
    assert(() {
      debugRenderCount++;
      _debugTotalRenderCount++;
      return true;
    }(), 'Track geometry submissions in debug builds.');
    final matteWidth = _bucketDimension(width);
    final matteHeight = _bucketDimension(height);
    final (viewWidth, viewHeight) = _viewCapacity();

    _ensureFrameCounter();
    _lastRenderFrame = _completedFrames;
    if (_texture != null) {
      // Release our handle; earlier submitted scenes hold their own.
      _image?.dispose();
      _image = null;
      _renderTarget = null;
      _texture = null;
      assert(() {
        _debugActiveGeometryTextureCount--;
        return true;
      }(), 'Track replaced geometry textures in debug builds.');
    }
    // The shader writes every pixel of the sub-rect; the rest of the texture
    // is undefined and never sampled, so no clear or copy is needed.
    final matte = _mattes.next(
      _completedFrames,
      width: matteWidth,
      height: matteHeight,
      maxWidth: viewWidth,
      maxHeight: viewHeight,
    );
    _texture = matte.texture;
    _renderTarget = matte.renderTarget;
    _image = _texture!.asImage();
    assert(() {
      _debugActiveGeometryTextureCount++;
      return true;
    }(), 'Track live geometry textures in debug builds.');

    final materialMapWidth = math.max(
      1,
      (matteWidth + materialRasterScale - 1) ~/ materialRasterScale,
    );
    final materialMapHeight = math.max(
      1,
      (matteHeight + materialRasterScale - 1) ~/ materialRasterScale,
    );
    final materialWidth = writeTintOnly
        ? materialMapWidth
        : math.max(16, materialMapWidth);
    final materialHeight = writeTintOnly
        ? materialMapHeight
        : materialMapHeight + 2;
    if (_materialTexture != null) {
      _materialImage?.dispose();
      _materialImage = null;
      _materialRenderTarget = null;
      _materialTexture = null;
      assert(() {
        _debugActiveMaterialTextureCount--;
        return true;
      }(), 'Track replaced material textures in debug builds.');
    }
    if (writeMaterials) {
      final material = _materials.next(
        _completedFrames,
        width: materialWidth,
        height: materialHeight,
        maxWidth: math.max(
          16,
          (viewWidth + materialRasterScale - 1) ~/ materialRasterScale,
        ),
        maxHeight:
            (viewHeight + materialRasterScale - 1) ~/ materialRasterScale + 2,
      );
      _materialTexture = material.texture;
      _materialRenderTarget = material.renderTarget;
      _materialImage = _materialTexture!.asImage();
      assert(() {
        _debugActiveMaterialTextureCount++;
        return true;
      }(), 'Track live material textures in debug builds.');
    } else {
      _materials.releaseCurrent(_completedFrames);
    }
    if (_mattes.spareCount + _materials.spareCount > 0) {
      _renderersWithSpares.add(this);
    }

    _packUniformData(
      offsetX: offsetX,
      offsetY: offsetY,
      textureWidth: matteWidth.toDouble(),
      textureHeight: matteHeight.toDouble(),
      refractionHeight: refractionHeight,
      refractionAmount: refractionAmount,
      edgeDistanceRange: edgeDistanceRange ?? math.max(12, refractionHeight),
      refractionFitsShape: refractionFitsShape,
      contourExtent: contourExtent,
      materialScale: writeMaterials ? materialRasterScale.toDouble() : 1.0,
      materialMapWidth: writeMaterials ? materialMapWidth.toDouble() : 1.0,
      materialMapHeight: writeMaterials ? materialMapHeight.toDouble() : 1.0,
      geometryAaHalfWidth: _geometryAaHalfWidth,
      numShapes: numShapes.toDouble(),
      shapeData: shapeData,
      rseData: rseData,
      appearanceData: appearanceData,
      boundsData: boundsData,
    );

    final uniformView = _hostBufferForUniformSize(
      _uniformSize,
    ).emplace(_uniformData);

    final geometryCommandBuffer = gpu.gpuContext.createCommandBuffer();
    gpu.Texture? fieldTexture;
    try {
      fieldTexture = field == null
          ? null
          : _uploadField(field, geometryCommandBuffer);
    } on Object {
      geometryCommandBuffer.submit();
      rethrow;
    }
    gpu.BufferView? fieldUniformView;
    if (field != null && fieldTexture != null) {
      _packFieldUniformData(
        field: field,
        fieldScale: fieldScale,
        texture: fieldTexture,
      );
      fieldUniformView = _hostBufferForUniformSize(
        _uniformSize,
      ).emplace(_fieldUniformData);
    }
    final geometryPass = geometryCommandBuffer.createRenderPass(_renderTarget!);
    if (fieldTexture == null || fieldUniformView == null) {
      geometryPass
        ..bindPipeline(_pipeline)
        ..setPrimitiveType(gpu.PrimitiveType.triangleStrip)
        ..bindUniform(_uniformSlot, uniformView)
        ..bindVertexBuffer(_vertexBufferView);
    } else {
      geometryPass.bindPipeline(_fieldPipeline);
      geometryPass.setPrimitiveType(gpu.PrimitiveType.triangleStrip);
      geometryPass.bindUniform(_fieldUniformSlot, fieldUniformView);
      geometryPass.bindTexture(_fieldTextureSlot, fieldTexture);
      geometryPass.bindVertexBuffer(_vertexBufferView);
    }
    _restrictTo(geometryPass, _texture!, matteWidth, matteHeight);
    geometryPass.draw(4);
    _submitOrDefer(geometryCommandBuffer);
    if (writeMaterials) {
      final materialCommandBuffer = gpu.gpuContext.createCommandBuffer();
      final materialPass =
          materialCommandBuffer.createRenderPass(_materialRenderTarget!)
            ..bindPipeline(
              writeTintOnly
                  ? _materialTintGradientPipeline
                  : _materialGradientPipeline,
            )
            ..setPrimitiveType(gpu.PrimitiveType.triangleStrip)
            ..bindUniform(_uniformSlot, uniformView)
            ..bindVertexBuffer(_vertexBufferView);
      _restrictTo(
        materialPass,
        _materialTexture!,
        materialWidth,
        materialHeight,
      );
      materialPass.draw(4);
      _submitOrDefer(materialCommandBuffer);
    }

    return (
      image: _image!,
      width: matteWidth,
      height: matteHeight,
      textureWidth: _texture!.width,
      textureHeight: _texture!.height,
    );
  }

  /// The texture holding [field], its copy recorded on [geometry] where a
  /// copy may precede the geometry pass on one command buffer, else on a
  /// command buffer of its own submitted ahead of it.
  gpu.Texture _uploadField(GlassField field, gpu.CommandBuffer geometry) {
    final held = _fieldTextures.held(field, _completedFrames);
    if (held != null) return held;
    if (_uploadsShareCommandBuffer) {
      return _fieldTextures.upload(field, _completedFrames, geometry);
    }
    final upload = gpu.gpuContext.createCommandBuffer();
    try {
      final texture = _fieldTextures.upload(field, _completedFrames, upload);
      _submitOrDefer(upload);
      return texture;
    } on Object {
      if (!upload.submitted) upload.submit();
      rethrow;
    }
  }

  /// Limits [pass] to the top-left [width] x [height] of [texture].
  ///
  /// `gl_FragCoord` stays framebuffer-relative, so the shaders need no
  /// offset for a sub-rect at the origin.
  static void _restrictTo(
    gpu.RenderPass pass,
    gpu.Texture texture,
    int width,
    int height,
  ) {
    if (texture.width == width && texture.height == height) return;
    pass
      ..setViewport(gpu.Viewport(width: width, height: height))
      ..setScissor(gpu.Scissor(width: width, height: height));
  }

  /// Largest view in physical pixels, the cap for texture growth.
  static (int, int) _viewCapacity() {
    var width = 0;
    var height = 0;
    for (final view in WidgetsBinding.instance.platformDispatcher.views) {
      width = math.max(width, view.physicalSize.width.ceil());
      height = math.max(height, view.physicalSize.height.ceil());
    }
    return (_bucketDimension(width), _bucketDimension(height));
  }

  static int _bucketDimension(int value) => (value + 63) & ~63;

  // Every pass gets its own command buffer. Flutter GPU (3.47.1) begins the
  // backend pass in `createRenderPass` and ends it only in `submit`, so a
  // second pass on the same command buffer nests inside the first:
  //
  // - Vulkan (Pixel 10, PowerVR; also flutter_tester on SwiftShader):
  //     Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x60
  //     #00 vulkan.powervr.so (CmdEndRenderPass2+188)
  //     #04 libflutter.so (InternalFlutterGpu_CommandBuffer_Submit+56)
  // - Metal (macOS, AGX G16X):
  //     -[AGXG16XFamilyCommandBuffer renderCommandEncoderWithDescriptor:]:
  //     failed assertion `A command encoder is already encoding to this
  //     command buffer'
  //       impeller::RenderPassMTL::RenderPassMTL
  //       impeller::CommandBufferMTL::OnCreateRenderPass
  //       flutter::gpu::RenderPass::Begin
  //
  // Share a command buffer across passes only once the engine ends a pass
  // before the next begins.
  // A copy recorded before a render pass on the same command buffer is
  // encoded ahead of it on Vulkan and GLES, which saves the copy a queue
  // submission of its own. Metal opens a blit encoder when the copy is
  // recorded and closes it only on submit, so the render pass's encoder
  // would nest: there the copy gets its own command buffer, submitted
  // first.
  static final bool _uploadsShareCommandBuffer =
      !(Platform.isIOS || Platform.isMacOS);

  static final MorphDeferredSubmissions<gpu.CommandBuffer> _pending =
      MorphDeferredSubmissions((commandBuffer) {
        commandBuffer.submit();
        assert(() {
          debugBatchedSubmitCount++;
          return true;
        }(), 'Count batched submissions in debug builds.');
      });
  static bool _postFrameFlushScheduled = false;

  /// Command buffers submitted by [flushPendingSubmissions].
  @visibleForTesting
  static int debugBatchedSubmitCount = 0;

  /// Flushes left to the post-frame safety net because no glass layer of the
  /// frame's scene flushed first.
  @visibleForTesting
  static int debugPostFrameFlushCount = 0;

  /// Passes whose submission was deferred to [flushPendingSubmissions].
  @visibleForTesting
  static int debugDeferredPassCount = 0;

  // Only the paint and compositing phases are followed by a scene build that
  // flushes before the scene reaches the raster thread.
  static bool get _deferring =>
      SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks;

  static void _submitOrDefer(gpu.CommandBuffer commandBuffer) {
    if (!_deferring) {
      commandBuffer.submit();
      return;
    }
    assert(() {
      debugDeferredPassCount++;
      return true;
    }(), 'Count deferred geometry passes in debug builds.');
    _pending.add(commandBuffer);
    if (_postFrameFlushScheduled) return;
    _postFrameFlushScheduled = true;
    // Covers passes whose layer was painted but not composited.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _postFrameFlushScheduled = false;
      if (_pending.isEmpty) return;
      assert(() {
        debugPostFrameFlushCount++;
        return true;
      }(), 'Count safety-net flushes in debug builds.');
      flushPendingSubmissions();
    });
  }

  /// Submits the passes recorded since the last flush, in recording order.
  ///
  /// Glass layers call this while the scene is built, which is before the
  /// scene is handed to the raster thread, so every matte a scene samples has
  /// been submitted ahead of it on the GPU queue. A post-frame callback
  /// flushes passes of layers that were painted but not composited.
  static void flushPendingSubmissions() => _pending.flush();

  /// Frames after its replacement before a texture may be rendered into
  /// again.
  ///
  /// A texture replaced during frame E was last sampled by frame E - 1's
  /// scene. The engine keeps at most two frames in its pipeline and frees a
  /// slot only after rasterizing and submitting that frame (`Animator`'s
  /// `FramePipeline(2)`; `Pipeline::Consume` signals after the consumer
  /// returns), so when frame E + 1 paints, frame E - 1 has been submitted.
  /// Flutter GPU submits to the same queue as the raster thread (the IO
  /// manager's context is the platform view's), and the GPU orders a write
  /// after earlier reads on that queue: Metal tracks hazards on these
  /// non-heap textures, and every Impeller Vulkan render pass declares an
  /// external dependency on earlier fragment-shader reads. GLES submits on
  /// the raster thread in posting order.
  static const int reuseAfterFrames = 1;

  /// Spare textures are dropped after this many frames without a render,
  /// and released ones after this many frames unclaimed.
  static const int _idleFramesBeforeTrim = 120;

  /// Released textures kept for other renderers, app-wide.
  static const int _maxReleased = 4;

  static int _completedFrames = 0;
  static bool _countingFrames = false;
  static final Set<FlutterGpuGeometryRenderer> _renderersWithSpares = {};
  static final List<_RingTexture> _released = [];

  /// Counts frames that submit a scene, the unit [reuseAfterFrames] is in.
  ///
  /// Renders outside a frame, as in unit tests, do not advance the count,
  /// so their textures are never reused.
  static void _ensureFrameCounter() {
    if (_countingFrames) return;
    _countingFrames = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (!RendererBinding.instance.sendFramesToEngine) return;
      _completedFrames++;
      _released.removeWhere((texture) {
        final stale =
            _completedFrames - texture.retiredFrame > _idleFramesBeforeTrim;
        if (stale) _countDropped();
        return stale;
      });
      if (_renderersWithSpares.isEmpty) return;
      for (final renderer in _renderersWithSpares.toList()) {
        if (_completedFrames - renderer._lastRenderFrame >
            _idleFramesBeforeTrim) {
          renderer._mattes.dropSpares();
          renderer._materials.dropSpares();
          _renderersWithSpares.remove(renderer);
        }
      }
    });
  }

  int _lastRenderFrame = 0;

  /// Textures this renderer holds that are not in use.
  @visibleForTesting
  int get debugRetiredTextureCount =>
      _mattes.spareCount + _materials.spareCount;

  /// Matte textures this renderer holds, including the one in use.
  @visibleForTesting
  int get debugMatteTextureCount => _mattes.textureCount;

  /// The latest matte texture, compared by identity in tests.
  @visibleForTesting
  Object? get debugMatteTexture => _texture;

  /// Size of the latest matte texture.
  @visibleForTesting
  (int, int)? get debugMatteTextureSize => switch (_texture) {
    final texture? => (texture.width, texture.height),
    null => null,
  };

  /// Renders that wrote into a reused texture instead of allocating one.
  @visibleForTesting
  static int debugReusedTextureCount = 0;

  /// Textures allocated, all renderers.
  @visibleForTesting
  static int debugAllocatedTextureCount = 0;

  /// Textures dropped, all renderers. Once a texture has lived a few young
  /// GCs its wrapper is promoted, and dropping it pins its storage until an
  /// old-generation GC.
  @visibleForTesting
  static int debugDroppedTextureCount = 0;

  /// Released textures waiting for another renderer.
  @visibleForTesting
  static int get debugReleasedTextureCount => _released.length;

  static void _countDropped() {
    assert(() {
      debugDroppedTextureCount++;
      return true;
    }(), 'Count dropped geometry textures in debug builds.');
  }

  /// A mature released texture that holds [width] x [height] without
  /// wasting more than 1.5x per dimension, or null.
  static _RingTexture? _claimReleased(int frame, int width, int height) {
    for (var index = 0; index < _released.length; index++) {
      final texture = _released[index];
      if (frame - texture.retiredFrame < reuseAfterFrames) continue;
      if (texture.covers(width, height) &&
          texture.texture.width * texture.texture.height * 4 <=
              width * height * 9) {
        return _released.removeAt(index);
      }
    }
    return null;
  }

  void _packUniformData({
    required double offsetX,
    required double offsetY,
    required double textureWidth,
    required double textureHeight,
    required double refractionHeight,
    required double refractionAmount,
    required double edgeDistanceRange,
    required bool refractionFitsShape,
    required double contourExtent,
    required double materialScale,
    required double materialMapWidth,
    required double materialMapHeight,
    required double geometryAaHalfWidth,
    required double numShapes,
    required List<double> shapeData,
    required List<double> rseData,
    required List<double> appearanceData,
    required List<double> boundsData,
  }) {
    final floatData = _uniformData.buffer.asFloat32List();

    final uOffsetIndex = _offsetUOffset ~/ 4;
    floatData[uOffsetIndex] = offsetX;
    floatData[uOffsetIndex + 1] = offsetY;

    final textureSizeIndex = _offsetUTextureSize ~/ 4;
    // X selects shape-fitted refraction; Y is the bevel's edge displacement,
    // which is also the codec scale.
    floatData[textureSizeIndex] = refractionFitsShape ? 1 : 0;
    floatData[textureSizeIndex + 1] = math.max(1e-3, refractionAmount);

    final opticalPropsIndex = _offsetOpticalProps ~/ 4;
    floatData[opticalPropsIndex] = math.max(0, refractionHeight);
    // uOpticalProps.y is the centered-AA half-width: 0.5 (Flutter's
    // one-pixel transition) unless the harness overrides it.
    floatData[opticalPropsIndex + 1] = geometryAaHalfWidth.clamp(0.0, 1.0);
    floatData[opticalPropsIndex + 2] = math.max(1, edgeDistanceRange);
    floatData[opticalPropsIndex + 3] = numShapes;

    final contourPropsIndex = _offsetContourProps ~/ 4;
    floatData[contourPropsIndex] = math.max(0.5, contourExtent);
    floatData[contourPropsIndex + 1] = materialScale;
    floatData[contourPropsIndex + 2] = materialMapWidth;
    floatData[contourPropsIndex + 3] = materialMapHeight;

    final shapeDataStartIndex = _offsetShapeData ~/ 4;
    final shapeFloats = shapeData.length < 192 ? shapeData.length : 192;
    for (var i = 0; i < shapeFloats; i++) {
      floatData[shapeDataStartIndex + i] = shapeData[i];
    }
    for (var i = shapeFloats; i < _writtenShapeFloats; i++) {
      floatData[shapeDataStartIndex + i] = 0;
    }
    _writtenShapeFloats = shapeFloats;

    final rseDataStartIndex = _offsetRseData ~/ 4;
    final rseFloats = rseData.length < 192 ? rseData.length : 192;
    for (var i = 0; i < rseFloats; i++) {
      floatData[rseDataStartIndex + i] = rseData[i];
    }
    for (var i = rseFloats; i < _writtenRseFloats; i++) {
      floatData[rseDataStartIndex + i] = 0;
    }
    _writtenRseFloats = rseFloats;

    if (appearanceData.isNotEmpty && appearanceData.length != 16 * 2 * 4) {
      throw ArgumentError.value(
        appearanceData.length,
        'appearanceData.length',
        'must contain two vec4 rows for each of 16 shapes',
      );
    }
    if (appearanceData.isNotEmpty) {
      final shapeTintsStartIndex = _offsetShapeTints ~/ 4;
      final shapeResponsesStartIndex = _offsetShapeResponses ~/ 4;
      for (var i = 0; i < 16 * 4; i++) {
        floatData[shapeTintsStartIndex + i] = appearanceData[i];
        floatData[shapeResponsesStartIndex + i] = appearanceData[16 * 4 + i];
      }
    }

    // Shapes without bounds are never culled.
    final boundsStartIndex = _offsetShapeBounds ~/ 4;
    final boundsFloats = math.min(boundsData.length, 16 * 4);
    for (var i = 0; i < 16 * 4; i++) {
      floatData[boundsStartIndex + i] = i < boundsFloats
          ? boundsData[i]
          : (i % 4 < 2 ? -1e9 : 1e9);
    }
  }

  /// Writes the field pass's uniforms: the geometry pass's optical values
  /// (already packed for the shape pass) and the field's frame.
  void _packFieldUniformData({
    required GlassField field,
    required double fieldScale,
    required gpu.Texture texture,
  }) {
    final from = _uniformData.buffer.asFloat32List();
    final to = _fieldUniformData.buffer.asFloat32List();
    void copy(int fromOffset, int toOffset, int count) {
      for (var i = 0; i < count; i++) {
        to[toOffset ~/ 4 + i] = from[fromOffset ~/ 4 + i];
      }
    }

    final offsets = _fieldOffsets;
    copy(_offsetUOffset, offsets.offset, 2);
    copy(_offsetUTextureSize, offsets.textureSize, 2);
    copy(_offsetOpticalProps, offsets.opticalProps, 4);
    copy(_offsetContourProps, offsets.contourProps, 4);
    final frame = offsets.fieldFrame ~/ 4;
    to[frame] = field.origin.dx * fieldScale;
    to[frame + 1] = field.origin.dy * fieldScale;
    to[frame + 2] = field.step * fieldScale;
    to[frame + 3] = fieldScale;
    final size = offsets.fieldSize ~/ 4;
    to[size] = field.cols.toDouble();
    to[size + 1] = field.rows.toDouble();
    to[size + 2] = 1 / texture.width;
    to[size + 3] = 1 / texture.height;
  }

  /// Releases borrowed output handles, keeping reusable rendering resources.
  ///
  /// Callers retaining an output must clone its images before calling this.
  /// Independent clones and submitted native scenes remain valid.
  void releaseOutput() {
    _mattes.release(_completedFrames);
    _materials.release(_completedFrames);
    _renderersWithSpares.remove(this);
    _renderTarget = null;
    _image?.dispose();
    _image = null;
    _materialRenderTarget = null;
    _materialImage?.dispose();
    _materialImage = null;
    if (_materialTexture != null) {
      assert(() {
        _debugActiveMaterialTextureCount--;
        return true;
      }(), 'Track disposed material textures in debug builds.');
    }
    _materialTexture = null;
    if (_texture != null) {
      assert(() {
        _debugActiveGeometryTextureCount--;
        return true;
      }(), 'Track disposed geometry textures in debug builds.');
    }
    _texture = null;
  }

  /// Releases the current output and retires this renderer.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    releaseOutput();
    _fieldTextures.release();
    assert(() {
      _debugActiveRendererCount--;
      return true;
    }(), 'Track disposed geometry renderers in debug builds.');
  }
}

/// A texture and its render target.
final class _RingTexture {
  _RingTexture(this.texture)
    : renderTarget = gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: texture,
          loadAction: gpu.LoadAction.dontCare,
        ),
      );

  final gpu.Texture texture;
  final gpu.RenderTarget renderTarget;

  /// Frame count when this texture was last replaced or released.
  int retiredFrame = 0;

  bool covers(int width, int height) =>
      texture.width >= width && texture.height >= height;
}

/// The textures one output of a renderer cycles through.
///
/// Every texture is at least the ring's capacity, which only grows: in 1.5x
/// steps, capped at the view unless one render needs more. A resize within
/// the capacity reuses the ring; growth drops the smaller textures.
final class _TextureRing {
  /// Spares beyond the one a steady ring needs, for frames that render
  /// twice.
  static const int _maxSpares = 2;

  _RingTexture? _current;
  final List<_RingTexture> _spares = [];
  int _width = 0;
  int _height = 0;

  int get spareCount => _spares.length;
  int get textureCount => _spares.length + (_current == null ? 0 : 1);

  /// Replaces the texture in use with one that holds [width] x [height].
  _RingTexture next(
    int frame, {
    required int width,
    required int height,
    required int maxWidth,
    required int maxHeight,
  }) {
    final previous = _current;
    _current = null;
    if (width > _width || height > _height) {
      _width = _grow(_width, width, maxWidth);
      _height = _grow(_height, height, maxHeight);
      dropSpares(keep: (texture) => texture.covers(_width, _height));
    }
    if (previous != null) {
      if (previous.covers(_width, _height)) {
        previous.retiredFrame = frame;
        _spares.add(previous);
      } else {
        FlutterGpuGeometryRenderer._countDropped();
      }
    }
    // Spares retire in frame order, so the first is the oldest.
    if (_spares.isNotEmpty &&
        frame - _spares.first.retiredFrame >=
            FlutterGpuGeometryRenderer.reuseAfterFrames) {
      assert(() {
        FlutterGpuGeometryRenderer.debugReusedTextureCount++;
        return true;
      }(), 'Count reused geometry textures in debug builds.');
      return _current = _spares.removeAt(0);
    }
    while (_spares.length > _maxSpares) {
      _spares.removeAt(0);
      FlutterGpuGeometryRenderer._countDropped();
    }
    final released = FlutterGpuGeometryRenderer._claimReleased(
      frame,
      _width,
      _height,
    );
    if (released != null) {
      assert(() {
        FlutterGpuGeometryRenderer.debugReusedTextureCount++;
        return true;
      }(), 'Count reused geometry textures in debug builds.');
      return _current = released;
    }
    return _current = _allocate(_width, _height);
  }

  /// Retires the texture in use without replacing it.
  void releaseCurrent(int frame) {
    final previous = _current;
    _current = null;
    if (previous == null) return;
    previous.retiredFrame = frame;
    _spares.add(previous);
  }

  /// Drops spare textures, except those [keep] accepts.
  void dropSpares({bool Function(_RingTexture texture)? keep}) {
    _spares.removeWhere((texture) {
      if (keep?.call(texture) ?? false) return false;
      FlutterGpuGeometryRenderer._countDropped();
      return true;
    });
  }

  /// Hands every texture to the app-wide released list.
  void release(int frame) {
    final textures = [..._spares, ?_current];
    _spares.clear();
    _current = null;
    _width = 0;
    _height = 0;
    final released = FlutterGpuGeometryRenderer._released;
    for (final texture in textures) {
      texture.retiredFrame = frame;
      released.add(texture);
    }
    while (released.length > FlutterGpuGeometryRenderer._maxReleased) {
      released.removeAt(0);
      FlutterGpuGeometryRenderer._countDropped();
    }
  }

  static int _grow(int capacity, int needed, int limit) {
    if (needed <= capacity) return capacity;
    if (capacity == 0) return needed;
    final stepped = (capacity * 3 + 1) >> 1;
    return math.max(needed, math.min(stepped, limit));
  }

  static _RingTexture _allocate(int width, int height) {
    assert(() {
      FlutterGpuGeometryRenderer.debugAllocatedTextureCount++;
      return true;
    }(), 'Count allocated geometry textures in debug builds.');
    return _RingTexture(
      gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        width,
        height,
      ),
    );
  }
}

/// Byte offsets of the members of the field pass's uniform block.
typedef _FieldUniformOffsets = ({
  int offset,
  int textureSize,
  int opticalProps,
  int contourProps,
  int fieldFrame,
  int fieldSize,
});

/// Field textures in GPU memory, each with the host buffer its samples are
/// staged in, reused after three frames.
///
/// Sizes are rounded up to [_bucket] nodes, so a field that changes size
/// every frame - a menu opening - reuses its textures instead of creating
/// one per frame. A field fills the top-left of its texture; the field
/// pass reads only that region, at the same texel centers whatever the
/// texture's size. The samples are copied into the texture by a command
/// recorded on the caller's command buffer, not by a submission of their
/// own. At most four textures survive; command buffers in flight retain
/// theirs.
final class _FieldTextures {
  static const int _reuseAfterFrames = 3;
  static const int _maxTextures = 4;
  static const int _bucket = 16;
  static const int _bytesPerNode = 16;

  final List<_FieldTexture> _textures = [];

  static int _capacity(int nodes) => (nodes + _bucket - 1) ~/ _bucket * _bucket;

  /// The texture already holding [field], or null.
  gpu.Texture? held(GlassField field, int frame) {
    for (final entry in _textures) {
      if (identical(entry.samples, field.samples) &&
          entry.cols == field.cols &&
          entry.rows == field.rows) {
        entry.frame = frame;
        return entry.texture;
      }
    }
    return null;
  }

  /// A texture holding [field], its samples copied into it by a command
  /// recorded on [commands].
  gpu.Texture upload(GlassField field, int frame, gpu.CommandBuffer commands) {
    final held = this.held(field, frame);
    if (held != null) return held;
    _FieldTexture? slot;
    for (final entry in _textures) {
      if (entry.texture.width >= field.cols &&
          entry.texture.height >= field.rows &&
          frame - entry.frame >= _reuseAfterFrames) {
        slot = entry;
        break;
      }
    }
    if (slot == null) {
      final width = _capacity(field.cols);
      final height = _capacity(field.rows);
      slot = _FieldTexture(
        gpu.gpuContext.createTexture(
          gpu.StorageMode.devicePrivate,
          width,
          height,
          format: gpu.PixelFormat.r32g32b32a32Float,
          enableRenderTargetUsage: false,
        ),
        gpu.gpuContext.createDeviceBuffer(
          gpu.StorageMode.hostVisible,
          width * height * _bytesPerNode,
        ),
      );
      if (_textures.length >= _maxTextures) _textures.removeAt(0);
      _textures.add(slot);
    }
    final bytes = ByteData.sublistView(field.samples);
    slot.buffer.overwrite(bytes);
    commands.copyBufferToTexture(
      gpu.BufferView(
        slot.buffer,
        offsetInBytes: 0,
        lengthInBytes: bytes.lengthInBytes,
      ),
      gpu.TextureRegion(slot.texture, width: field.cols, height: field.rows),
    );
    slot.samples = field.samples;
    slot.cols = field.cols;
    slot.rows = field.rows;
    slot.frame = frame;
    return slot.texture;
  }

  void release() => _textures.clear();
}

/// A field texture, the host buffer its samples are staged in, and the
/// field it holds.
final class _FieldTexture {
  _FieldTexture(this.texture, this.buffer);

  final gpu.Texture texture;
  final gpu.DeviceBuffer buffer;
  Float32List? samples;
  int cols = 0;
  int rows = 0;
  int frame = -_FieldTextures._reuseAfterFrames;
}

class _SharedGeometryResources {
  _SharedGeometryResources({
    required gpu.Shader vertexShader,
    required gpu.Shader fragmentShader,
    required gpu.Shader fieldFragmentShader,
    required gpu.Shader materialGradientFragmentShader,
    required gpu.Shader materialTintGradientFragmentShader,
  }) {
    pipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      fragmentShader,
    );
    fieldPipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      fieldFragmentShader,
    );
    fieldUniformSlot = fieldFragmentShader.getUniformSlot('FieldUniforms');
    fieldTextureSlot = fieldFragmentShader.getUniformSlot('uField');
    fieldUniformSize = fieldUniformSlot.sizeInBytes ?? 0;
    int member(String name) =>
        fieldUniformSlot.getMemberOffsetInBytes(name) ?? 0;
    fieldOffsets = (
      offset: member('uOffset'),
      textureSize: member('uTextureSize'),
      opticalProps: member('uOpticalProps'),
      contourProps: member('uContourProps'),
      fieldFrame: member('uFieldFrame'),
      fieldSize: member('uFieldSize'),
    );
    materialGradientPipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      materialGradientFragmentShader,
    );
    materialTintGradientPipeline = gpu.gpuContext.createRenderPipeline(
      vertexShader,
      materialTintGradientFragmentShader,
    );
    uniformSlot = fragmentShader.getUniformSlot('GeometryUniforms');
    uniformSize = uniformSlot.sizeInBytes ?? 0;
    offsetUOffset = uniformSlot.getMemberOffsetInBytes('uOffset') ?? 0;
    offsetUTextureSize =
        uniformSlot.getMemberOffsetInBytes('uTextureSize') ?? 0;
    offsetOpticalProps =
        uniformSlot.getMemberOffsetInBytes('uOpticalProps') ?? 0;
    offsetContourProps =
        uniformSlot.getMemberOffsetInBytes('uContourProps') ?? 0;
    offsetShapeData = uniformSlot.getMemberOffsetInBytes('uShapeData') ?? 0;
    offsetRseData = uniformSlot.getMemberOffsetInBytes('uRseData') ?? 0;
    offsetShapeTints = uniformSlot.getMemberOffsetInBytes('uShapeTints') ?? 0;
    offsetShapeResponses =
        uniformSlot.getMemberOffsetInBytes('uShapeResponses') ?? 0;
    offsetShapeBounds = uniformSlot.getMemberOffsetInBytes('uShapeBounds') ?? 0;
    final vertices = Float32List.fromList([
      -1.0, -1.0, 0.0, 0.0, //
      1.0, -1.0, 1.0, 0.0, //
      -1.0, 1.0, 0.0, 1.0, //
      1.0, 1.0, 1.0, 1.0, //
    ]);
    vertexBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(vertices),
    );
    vertexBufferView = gpu.BufferView(
      vertexBuffer,
      offsetInBytes: 0,
      lengthInBytes: vertexBuffer.sizeInBytes,
    );
  }

  late final gpu.RenderPipeline pipeline;
  late final gpu.RenderPipeline fieldPipeline;
  late final gpu.UniformSlot fieldUniformSlot;
  late final gpu.UniformSlot fieldTextureSlot;
  late final int fieldUniformSize;
  late final _FieldUniformOffsets fieldOffsets;
  late final gpu.RenderPipeline materialGradientPipeline;
  late final gpu.RenderPipeline materialTintGradientPipeline;
  late final gpu.UniformSlot uniformSlot;
  late final int uniformSize;
  late final int offsetUOffset;
  late final int offsetUTextureSize;
  late final int offsetOpticalProps;
  late final int offsetContourProps;
  late final int offsetShapeData;
  late final int offsetRseData;
  late final int offsetShapeTints;
  late final int offsetShapeResponses;
  late final int offsetShapeBounds;
  late final gpu.DeviceBuffer vertexBuffer;
  late final gpu.BufferView vertexBufferView;
}

/// Command buffers recorded during a frame and submitted together, at most
/// [limit] at a time.
///
/// A Metal command queue holds 64 uncompleted command buffers and the
/// raster thread draws from the same queue; creating one more while every
/// slot is taken blocks the UI thread until a buffer completes, and a
/// buffer that is recorded but not submitted never completes. Deferring
/// more than [limit] passes would therefore freeze the app on a frame with
/// many glass layers, so [add] submits the batch as soon as it is full.
@internal
final class MorphDeferredSubmissions<T> {
  /// Creates an empty batch that hands each entry to [submit].
  MorphDeferredSubmissions(this.submit, {this.limit = defaultLimit});

  /// The most entries a frame holds before they are submitted.
  static const int defaultLimit = 16;

  /// Submits one entry.
  final void Function(T entry) submit;

  /// The most entries held before [add] submits them.
  final int limit;

  final List<T> _entries = [];

  /// Whether nothing waits for submission.
  bool get isEmpty => _entries.isEmpty;

  /// The number of entries waiting for submission.
  int get length => _entries.length;

  /// Holds [entry], submitting the batch once it reaches [limit].
  void add(T entry) {
    _entries.add(entry);
    if (_entries.length >= limit) flush();
  }

  /// Submits every held entry in recording order.
  ///
  /// The batch is empty afterwards even when an entry fails: a failure is
  /// reported and the remaining entries are still submitted, so one bad
  /// pass never holds the others back.
  void flush() {
    if (_entries.isEmpty) return;
    final entries = List<T>.of(_entries);
    _entries.clear();
    for (final entry in entries) {
      try {
        submit(entry);
      } on Object catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'morph glass',
            context: ErrorDescription('while submitting a glass geometry pass'),
          ),
        );
      }
    }
  }
}
