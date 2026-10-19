import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:morph/src/glass/renderer/composition/glass_cost_probe.dart';
import 'package:morph/src/glass/renderer/internal/ancestor_clip.dart';
import 'package:morph/src/glass/renderer/internal/backdrop_cache.dart';
import 'package:morph/src/glass/renderer/internal/filter_pass_transform.dart';
import 'package:morph/src/glass/renderer/internal/snap_rect_to_pixels.dart';
import 'package:morph/src/glass/renderer/pass/final_pass.dart';
import 'package:morph/src/glass/renderer/pass/glass_frost.dart';
import 'package:morph/src/glass/renderer/renderer.dart';

/// What a [GlassBackdropDraw] reads from the glass layer it draws for.
@internal
abstract interface class GlassDrawSource implements RenderObject {
  /// The layer's settings.
  LiquidGlassSettings get settings;

  /// The layer's device pixel ratio.
  double get devicePixelRatio;

  /// The backdrop key the layer's filter reads, or null for its own read.
  BackdropKey? get backdropKey;

  /// Where the layer's frost is blurred.
  GlassFrost get frost;

  /// Whether a frost that needs a blur pass blurs a copy of the backdrop
  /// around the glass instead of the whole pass.
  bool get blursOwnBackdrop;

  /// The cached backdrop the glass may paint over, or null.
  GlassBackdropCache? get backdropCache;

  /// The opaque color the glass is declared to lie on, or null.
  Color? get solidBackdrop;

  /// Whether the committed shapes exist but none can be drawn.
  bool get drawableEmpty;

  /// Whether the geometry can be drawn again without a new encode.
  bool get hasReusableGeometry;

  /// The offset the layer last painted at.
  Offset get retainedPaintOffset;

  /// The translation applied to the layer's retained effect since it
  /// painted.
  Offset get effectTranslation;

  /// The bounds of the clips between the layer and its shapes, or null.
  Rect? get effectClipBounds;

  /// Whether the layer paints inside a seeded fractional-opacity pass.
  bool get seededOpacity;

  /// The screen transform the compositing hook tracked this frame, or null.
  Matrix4? get compositingScreen;
}

/// The engine layers one glass layer's final pass draws into, and where
/// its fragment coordinates come from: the backdrop filter under its clip,
/// the seed pass of a lifted lens, the picture over a declared solid or a
/// cached backdrop.
///
/// The filter clip stays on pixel buckets of the translated frame, so
/// retained compositor motion does not resize its render target. A blur
/// whose clip leaves its pass makes Impeller blur the whole pass, so a
/// small animated frost reads a seeded copy of its own surroundings. Over a
/// solid backdrop the glass is a paint, whose fragment coordinates are the
/// canvas's; over a cached copy it is a paint in screen device pixels, and a
/// frame whose copy is not exact reads through the filter, synced to that
/// frame (never an older frame on screen). The probes of
/// [debugGlassCostProbe] replace parts of this composition.
@internal
final class GlassBackdropDraw {
  /// Draws the glass of [_source] with [_pass].
  GlassBackdropDraw(this._source, this._pass);

  final GlassDrawSource _source;
  final GlassFinalPass _pass;

  final _shaderHandle = LayerHandle<BackdropFilterLayer>();
  final _clipRectLayerHandle = LayerHandle<ClipRectLayer>();
  final _seedClipHandle = LayerHandle<ClipRectLayer>();
  final _seedHandle = LayerHandle<BackdropFilterLayer>();

  // The slot of the picture the glass is recorded into over a solid or a
  // cached backdrop; a retained geometry refresh replaces the picture in
  // it.
  final _solidHandle = LayerHandle<ContainerLayer>();

  /// Whether a layer that blurs its own backdrop copies it; off blurs the
  /// whole pass as every other layer does, for an A/B.
  @visibleForTesting
  static bool debugSeedsBlur = true;

  static final BackdropKey _probeKey = BackdropKey();
  static final Set<String> _probeLogged = {};

  // Decided when the layer paints; the copy itself is taken while the
  // frame composites.
  bool _cachesBackdrop = false;

  /// Whether the layer's last paint chose its cached backdrop.
  bool get cachesBackdrop => _cachesBackdrop;

  /// Whether the cached backdrop can serve the glass now.
  bool get wantsCachedBackdrop {
    final cache = _source.backdropCache;
    return cache != null &&
        debugMorphBackdropCache &&
        debugGlassCostProbe == GlassCostProbe.off &&
        cache.ready;
  }

  /// The opaque color the glass is shaded over without a backdrop read, or
  /// null when the layer reads its backdrop.
  Color? get solid {
    if (debugGlassCostProbe == GlassCostProbe.solid) {
      return const Color(0xFF000000);
    }
    final color = _source.solidBackdrop;
    return color != null && color.a == 1 ? color : null;
  }

  /// Whether the layer drew its glass as a paint over a solid backdrop in
  /// its last frame.
  bool get drawsOverSolid => _solidHandle.layer != null;

  bool get _seedsBlur =>
      _source.blursOwnBackdrop &&
      debugSeedsBlur &&
      _source.frost.passSigma > 0 &&
      _source.backdropKey == null &&
      !_source.seededOpacity;

  // The logical pixels around the blurred coverage the frost blur reads.
  double get _seedMargin =>
      morphBlurReach(_source.frost.passSigma, _source.devicePixelRatio);

  // The seed pass's clip in the translated frame, on the filter clip's
  // pixel buckets so retained motion does not resize the pass.
  Rect? get _seedClip {
    final clip = _filterClip;
    if (clip == null) return null;
    final translation = _source.effectTranslation;
    return clip
        .shift(translation)
        .inflate(_seedMargin)
        .expandToPixelBuckets(_source.devicePixelRatio)
        .shift(-translation);
  }

  // Impeller bounds the seed pass by its clip and every clip above it,
  // rounded out to device pixels; the glass shader's fragment coordinates
  // start at that origin.
  Offset _seedPassOrigin(Matrix4 layerToScreen) {
    final seed = _seedClip;
    if (seed == null) return Offset.zero;
    final dpr = _source.devicePixelRatio;
    var screen = MatrixUtils.transformRect(layerToScreen, seed);
    if (screenClipAbove(_source) case final above?) {
      screen = screen.intersect(above);
    }
    return Offset(
      (screen.left * dpr).floorToDouble() / dpr,
      (screen.top * dpr).floorToDouble() / dpr,
    );
  }

  /// The most recent layer-local clip used by the native glass filter.
  Rect? filterBounds;
  Rect? _filterMaterialBounds;
  // The bounds the last sync was given, before a shader frost grew them.
  Rect? _filterGlassBounds;
  Offset _filterPaintOffset = Offset.zero;

  // The native filter clip, kept on stable pixel buckets in the translated
  // frame so retained compositor motion does not resize its render target.
  Rect? get _filterClip {
    final bounds = _filterMaterialBounds;
    if (bounds == null) return null;
    final translation = _source.effectTranslation;
    return bounds
        .shift(translation)
        .expandToPixelBuckets(_source.devicePixelRatio)
        .shift(-translation);
  }

  // MARK: Mapping

  (double, double, double, double, double, double)? _coordinateMapping;
  Rect? _backdropBounds;
  final Matrix4 _globalToMatte = Matrix4.zero();

  /// The layer's transform into the pass its filter samples. During
  /// compositing it may be the tracked screen transform itself: callers
  /// read it and never modify it.
  Matrix4 get passTransform {
    final seeding = _source.seededOpacity;
    final translation = _source.effectTranslation;
    final screen = _source.compositingScreen;
    final ownPass = _seedsBlur;
    final transform = filterPassTransform(
      _source,
      screen: seeding || ownPass || translation != Offset.zero
          ? screen?.clone()
          : screen,
      seeding: seeding,
      devicePixelRatio: _source.devicePixelRatio,
      translation: translation,
    );
    if (ownPass) {
      final origin = _seedPassOrigin(transform);
      transform.leftTranslateByDouble(-origin.dx, -origin.dy, 0, 1);
    }
    return transform;
  }

  /// Layer-local rect the native filter captures backdrop for, or `null`
  /// when it is unbounded. Refraction mirrors samples that would leave it:
  /// outside the clip the filter input is transparent.
  Rect? get backdropSampleBounds {
    final clip = _filterClip;
    if (clip == null || _source.frost.passSigma <= 0) return clip;
    final translation = _source.effectTranslation;
    var captured = clip.shift(translation);
    if (_source.effectClipBounds case final retained?) {
      captured = captured.intersect(retained);
    }
    if (localPaintClipAbove(_source) case final above?) {
      captured = captured.intersect(above);
    }
    return captured.shift(-translation);
  }

  /// Writes the fragment-to-matte mapping of the current path into the
  /// pass; true when it changed.
  bool syncMapping() {
    final solid = this.solid != null;
    final mapping = solid ? _solidMapping() : _currentMapping();
    final backdropBounds = solid ? null : backdropSampleBounds;
    final changed =
        mapping != _coordinateMapping || backdropBounds != _backdropBounds;
    _coordinateMapping = mapping;
    _backdropBounds = backdropBounds;
    if (changed) _pass.markInputsChanged();
    _pass.writeMapping(mapping, backdropBounds);
    return changed;
  }

  (double, double, double, double, double, double) _currentMapping() {
    final layerToPass = passTransform;
    final globalToMatte = _globalToMatte;
    if (globalToMatte.copyInverse(layerToPass) == 0.0) {
      throw ArgumentError.value(
        layerToPass,
        'other',
        'Matrix cannot be inverted',
      );
    }
    final m = globalToMatte.storage;
    final originX = _mappedX(m, 0, 0);
    final originY = _mappedY(m, 0, 0);
    final dpr = _source.devicePixelRatio;
    return (
      _mappedX(m, 1, 0) - originX,
      _mappedX(m, 0, 1) - originX,
      _mappedY(m, 1, 0) - originY,
      _mappedY(m, 0, 1) - originY,
      originX * dpr,
      originY * dpr,
    );
  }

  // Over a solid backdrop the glass is a paint, whose fragment coordinates
  // are the logical canvas coordinates it is recorded in: the layer's own
  // coordinates shifted by its paint offset. The matte is the layer's own
  // coordinates in device pixels, so neither the pass nor any ancestor
  // transform enters, and compositor motion never changes the mapping.
  (double, double, double, double, double, double) _solidMapping() {
    final offset = _source.retainedPaintOffset;
    final dpr = _source.devicePixelRatio;
    return (dpr, 0, 0, dpr, -offset.dx * dpr, -offset.dy * dpr);
  }

  // MatrixUtils.transformPoint, one coordinate at a time.
  static double _mappedX(Float64List m, double x, double y) {
    final rx = m[0] * x + m[4] * y + m[12];
    final rw = m[3] * x + m[7] * y + m[15];
    return rw == 1.0 ? rx : rx / rw;
  }

  static double _mappedY(Float64List m, double x, double y) {
    final ry = m[1] * x + m[5] * y + m[13];
    final rw = m[3] * x + m[7] * y + m[15];
    return rw == 1.0 ? ry : ry / rw;
  }

  // MARK: Filter

  // Unblurred, the filter input is the backdrop inside the filter's own clip.
  // With a blur pass, Impeller re-rasterizes the blurred input into the
  // filter's coverage, which every clip around the filter narrows: the
  // retained clips between this layer and its shapes, and the clips above
  // this layer up to its pass. The texture is transparent outside it.
  ui.ImageFilter? _cachedFilter;

  /// The filter over the pass's current uniforms: the one made before
  /// while none changed (the engine copies a shader's uniforms into the
  /// native filter when it converts it).
  ui.ImageFilter filter() {
    final inputsChanged = _pass.takeInputsChanged();
    if (_cachedFilter != null && !inputsChanged) return _cachedFilter!;
    if (debugGlassCostProbe == GlassCostProbe.copy) {
      return _cachedFilter = morphBackdropSeed;
    }
    final shader = _pass.shaderFilter();
    final frostSigma = _source.frost.passSigma;
    if (debugGlassCostProbe != GlassCostProbe.off && _probeLogged.length < 60) {
      final bounds = filterBounds;
      final screen = bounds == null || !_source.attached
          ? null
          : MatrixUtils.transformRect(_source.getTransformTo(null), bounds);
      final key =
          'sigma ${frostSigma.toStringAsFixed(2)} '
          '${(screen?.width ?? 0) ~/ 20 * 20}x${(screen?.height ?? 0) ~/ 20 * 20} '
          'top ${(screen?.top ?? 0) ~/ 100 * 100}';
      if (_probeLogged.add(key)) debugPrint('MORPH_GLASS_LAYER $key');
    }
    if (debugGlassCostProbe == GlassCostProbe.nofrost) {
      return _cachedFilter = shader;
    }
    final filter = frostSigma > 0
        ? ui.ImageFilter.compose(
            inner: _pass.frostBlur(frostSigma),
            outer: shader,
          )
        : shader;
    _cachedFilter = filter;
    return filter;
  }

  /// Hands the retained glass the final pass's changed uniforms without a
  /// paint: a filter over them for the retained backdrop filter, or the
  /// glass recorded again into its slot over a solid backdrop. False when
  /// the glass must paint instead (nothing retained, nothing to draw, or
  /// glass over a cached backdrop, which compositing records).
  bool refreshUniforms() {
    if (!_source.attached ||
        _source.drawableEmpty ||
        !_source.hasReusableGeometry) {
      return false;
    }
    if (_solidHandle.layer != null) {
      final solid = this.solid;
      final bounds = filterBounds;
      if (_cachesBackdrop || solid == null || bounds == null) return false;
      _recordSolid(solid, bounds, _filterPaintOffset);
      return true;
    }
    final layer = _shaderHandle.layer;
    if (layer == null) return false;
    layer.filter = filter();
    return true;
  }

  /// Updates the filter's clip, mapping and filter for glass within
  /// [glassBounds] painted at [offset]; returns the filter's clip. Both a
  /// paint and a retained geometry refresh ([retained]) sync; it never
  /// paints children.
  Rect sync(Rect glassBounds, Offset offset, {bool retained = false}) {
    final dpr = _source.devicePixelRatio;
    // A frost the final pass blurs reads three sigma past the rim.
    final shaderFrost = _source.frost.shaderSigma;
    final materialBounds = shaderFrost > 0
        ? glassBounds.inflate(3 * shaderFrost / dpr)
        : glassBounds;
    final filterBounds = materialBounds.expandToPixelBuckets(dpr);
    _filterGlassBounds = glassBounds;
    _filterMaterialBounds = materialBounds;
    _filterPaintOffset = offset;
    this.filterBounds = filterBounds;
    if (solid case final solid?) {
      _recordSolid(solid, filterBounds, offset);
      return filterBounds;
    }
    _clipRectLayerHandle.layer?.clipRect = filterBounds.shift(offset);
    if (_seedClipHandle.layer case final seedClip?) {
      if (_seedClip case final seed?) seedClip.clipRect = seed.shift(offset);
    }
    final drawableEmpty = _source.drawableEmpty;
    if (retained &&
        (_seedsBlur && !drawableEmpty) != (_seedClipHandle.layer != null)) {
      _source.markNeedsPaint();
    }
    if (drawableEmpty) {
      _shaderHandle.layer?.remove();
      _shaderHandle.layer = null;
      _cachedFilter = null;
    } else {
      syncMapping();
      _pass.readBackdrop();
      final shader = _shaderHandle.layer ??= BackdropFilterLayer();
      shader.filter = filter();
      shader.backdropKey = switch (debugGlassCostProbe) {
        GlassCostProbe.shared => _probeKey,
        _ => _source.backdropKey,
      };
      GlassLayerOwners.note(shader, _source);
      if (_clipRectLayerHandle.layer case final clip?) {
        if (!identical(shader.parent, clip)) {
          shader.remove();
          clip.append(shader);
        }
      }
    }
    return filterBounds;
  }

  /// Paints the glass within [materialBounds] at [offset]: through the
  /// backdrop filter (under a seed pass for a lifted lens), or as a picture
  /// over a solid or a cached backdrop.
  void paint(PaintingContext context, Offset offset, Rect materialBounds) {
    if (!_source.attached) return;
    if (debugGlassCostProbe == GlassCostProbe.skip) {
      release();
      return;
    }
    _cachesBackdrop = wantsCachedBackdrop;
    if (_cachesBackdrop) {
      // The filter stays ready: a frame whose copy is not exact reads the
      // backdrop through it. Compositing picks the path.
      _seedClipHandle.layer = null;
      _seedHandle.layer = null;
      sync(materialBounds, offset);
      context.addLayer(_solidHandle.layer ??= ContainerLayer());
      return;
    }
    if (solid != null) {
      _releaseFilter();
      sync(materialBounds, offset);
      context.addLayer(_solidHandle.layer!);
      return;
    }
    _solidHandle.layer = null;
    // The engine snapshots this shader's uniforms into the native image
    // filter at creation, so the composed filter can only be reused while
    // every snapshotted input is unchanged. Repaints with identical shader
    // inputs (for example a static layer invalidated by foreground content)
    // skip all Dart and native filter allocation.
    final filterBounds = sync(materialBounds, offset);
    final shaderLayer = _shaderHandle.layer;
    assert(() {
      if (!_source.drawableEmpty && shaderLayer != null) {
        debugRegisterBackdropCapture(_source, _source.backdropKey);
      }
      return true;
    }(), 'Count independent backdrop captures in debug builds.');

    void paintFilter(PaintingContext context, Offset offset) {
      _clipRectLayerHandle.layer = context.pushClipRect(
        _source.needsCompositing,
        offset,
        filterBounds,
        (context, offset) {
          if (_source.drawableEmpty) return;
          context.pushLayer(shaderLayer!, (context, offset) {}, offset);
        },
        oldLayer: _clipRectLayerHandle.layer,
      );
    }

    final seed = _seedsBlur && !_source.drawableEmpty ? _seedClip : null;
    if (seed == null) {
      _seedClipHandle.layer = null;
      _seedHandle.layer = null;
      paintFilter(context, offset);
      return;
    }
    final seedLayer = _seedHandle.layer ??= BackdropFilterLayer(
      filter: morphBackdropSeed,
    );
    GlassLayerOwners.note(seedLayer, _source);
    _seedClipHandle.layer = context.pushClipRect(
      _source.needsCompositing,
      offset,
      seed,
      (context, offset) => context.pushLayer(seedLayer, paintFilter, offset),
      oldLayer: _seedClipHandle.layer,
    );
  }

  // Records the glass as one rect painted with the final shader over
  // [solid], into the layer's own picture so a retained geometry refresh
  // can replace it without painting. The shader snapshots its uniforms and
  // samplers when the rect is recorded, as the filter does when it is
  // created. The background sampler keeps whatever image is bound to it
  // (the matte or the blank image); the shader never reads it.
  void _recordSolid(Color solid, Rect filterBounds, Offset offset) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = filterBounds.shift(offset);
    if (!_source.drawableEmpty) {
      syncMapping();
      final shader = _pass.overSolid(
        solid,
        filterBounds.size * _source.devicePixelRatio,
      );
      final paint = Paint();
      paint.shader = shader;
      // The filter path clips its output to this rect with a hard edge.
      paint.isAntiAlias = false;
      canvas.drawRect(rect, paint);
    }
    final slot = _solidHandle.layer ??= ContainerLayer();
    slot.removeAllChildren();
    final picture = PictureLayer(rect);
    picture.picture = recorder.endRecording();
    slot.append(picture);
  }

  /// Drops native backdrop-filter state while the glass draws nothing.
  void release() {
    _releaseFilter();
    _solidHandle.layer = null;
  }

  void _releaseFilter() {
    _shaderHandle.layer = null;
    _clipRectLayerHandle.layer = null;
    _seedClipHandle.layer = null;
    _seedHandle.layer = null;
    _cachedFilter = null;
  }

  // MARK: Compositing

  /// The compositing hook, after every paint of the frame: draws over the
  /// cached copy, or through the filter synced to this frame; a cache that
  /// came or went asks for a paint.
  void composite() {
    if (_source.backdropCache != null &&
        _cachesBackdrop != wantsCachedBackdrop) {
      // The source came or went: paint picks the path again next frame.
      _source.markNeedsPaint();
    } else if (_cachesBackdrop) {
      _composeCached();
    }
  }

  // Records the glass as one rect painted with the final shader over the
  // cache's copy of the backdrop. The rect is drawn in screen device pixels
  // (the canvas undoes the layer's transform), so the shader's fragment
  // coordinates are the screen coordinates its filter mapping expects and
  // the copy is sampled where the backdrop filter would have read.
  void _composeCached() {
    final slot = _solidHandle.layer;
    final bounds = _filterGlassBounds;
    if (slot == null || bounds == null) return;
    slot.removeAllChildren();
    if (_source.drawableEmpty) return;
    if (_recordCached(slot, bounds)) return;
    // No exact copy this frame: the backdrop filter, its mapping synced to
    // this frame's transform.
    final offset = _filterPaintOffset;
    final filterBounds = sync(bounds, offset);
    final shaderLayer = _shaderHandle.layer;
    if (shaderLayer == null) return;
    final clip = _clipRectLayerHandle.layer ??= ClipRectLayer();
    clip.clipRect = filterBounds.shift(offset);
    clip.clipBehavior = Clip.hardEdge;
    if (!identical(shaderLayer.parent, clip)) {
      shaderLayer.remove();
      clip.append(shaderLayer);
    }
    slot.append(clip);
  }

  bool _recordCached(ContainerLayer slot, Rect bounds) {
    final cache = _source.backdropCache!;
    final dpr = _source.devicePixelRatio;
    final translation = _source.effectTranslation;
    final screen = _source.getTransformTo(null);
    screen.multiply(
      Matrix4.translationValues(translation.dx, translation.dy, 0),
    );
    final filterBounds = bounds.expandToPixelBuckets(dpr);
    final logical = MatrixUtils.transformRect(screen, filterBounds);
    final sigma = _source.frost.passSigma;
    // Everything the glass may sample: its bounds, the frost's kernel and
    // the refraction's reach (dispersion stays inside it).
    final copy = cache.imageFor(
      sigma: sigma,
      devicePixelRatio: dpr,
      region: logical.inflate(
        3 * sigma + _source.settings.effectiveRefractionAmount + 2,
      ),
    );
    if (copy == null) return false;
    final (image, corner) = copy;
    syncMapping();
    // The copy starts at [corner]: fragment coordinates are taken from
    // there, so the filter->matte offset moves by the basis times it.
    final origin = corner * dpr;
    final shader = _pass.overCopy(
      image,
      filterToMatteOffset: switch (_coordinateMapping) {
        (final b0, final b1, final b2, final b3, final ox, final oy) => Offset(
          ox + b0 * origin.dx + b1 * origin.dy,
          oy + b2 * origin.dx + b3 * origin.dy,
        ),
        null => null,
      },
      overlay: cache.overlay,
    );
    final device = Rect.fromLTRB(
      logical.left * dpr,
      logical.top * dpr,
      logical.right * dpr,
      logical.bottom * dpr,
    );
    final canvasToScreen = screen.clone();
    canvasToScreen.multiply(
      Matrix4.translationValues(
        -_filterPaintOffset.dx,
        -_filterPaintOffset.dy,
        0,
      ),
    );
    final screenToCanvas = Matrix4.zero();
    if (screenToCanvas.copyInverse(canvasToScreen) == 0) return false;
    screenToCanvas.multiply(Matrix4.diagonal3Values(1 / dpr, 1 / dpr, 1));
    screenToCanvas.multiply(Matrix4.translationValues(origin.dx, origin.dy, 0));
    final drawn = device.shift(-origin);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.transform(screenToCanvas.storage);
    final paint = Paint();
    paint.shader = shader;
    paint.isAntiAlias = false;
    canvas.drawRect(drawn, paint);
    final picture = PictureLayer(
      MatrixUtils.transformRect(screenToCanvas, drawn),
    );
    picture.picture = recorder.endRecording();
    slot.append(picture);
    return true;
  }

  /// Follows retained compositor motion without a paint: the clips move
  /// with it and the mapping is synced into the retained filter; true when
  /// the mapping moved.
  bool translated() {
    if (_cachesBackdrop) return false;
    final clip = _filterClip;
    if (clip != null && _clipRectLayerHandle.layer != null) {
      _clipRectLayerHandle.layer!.clipRect = clip.shift(_filterPaintOffset);
    }
    if (_seedClipHandle.layer case final seedClip?) {
      if (_seedClip case final seed?) {
        seedClip.clipRect = seed.shift(_filterPaintOffset);
      }
    }
    final mapped =
        !_source.drawableEmpty && _source.hasReusableGeometry && syncMapping();
    if (mapped) _shaderHandle.layer?.filter = filter();
    return mapped;
  }

  /// A pass-origin change - the probe enabling, or a capture's clip moving
  /// with paint-only changes inside it - moves no tracked transform, so the
  /// translation poll misses it: re-syncs the mapping into the retained
  /// filter, or asks for a paint when its inputs cannot be reused. Returns
  /// whether the drawn glass is retained, so a geometry refresh can redraw
  /// it in place.
  bool missed() {
    if (syncMapping()) {
      if (!_source.drawableEmpty &&
          _source.hasReusableGeometry &&
          _shaderHandle.layer != null) {
        _shaderHandle.layer!.filter = filter();
      } else {
        _source.markNeedsPaint();
      }
    }
    return solid != null
        ? _solidHandle.layer != null
        : (_shaderHandle.layer != null || _source.drawableEmpty) &&
              _clipRectLayerHandle.layer != null;
  }

  /// Drops every engine layer.
  void dispose() {
    _shaderHandle.layer = null;
    _clipRectLayerHandle.layer = null;
    _seedClipHandle.layer = null;
    _seedHandle.layer = null;
    _solidHandle.layer = null;
    _cachedFilter = null;
  }
}
