/// Text under a scale that animates, drawn without new glyph rasters on
/// every frame.
///
/// Impeller rasterizes each glyph once per font and screen scale (the
/// largest axis of the transform the text is drawn with, rounded to
/// 1/200) into its glyph atlas. A label whose scale sweeps continuously
/// meets a new scale nearly every frame, and each one rasterizes and
/// uploads the label's glyphs again on the raster thread.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

/// The screen scales text moving through a scale animation is drawn at.
@internal
abstract final class MorphGlyphScale {
  /// The grid steps per doubling of the scale: neighbors are 1.1 percent
  /// apart, so a snapped label is drawn at most 0.54 percent off its exact
  /// size about its anchor.
  static const int stepsPerOctave = 64;

  /// Draws every label at its exact scale and live: no snapping and no
  /// rasters, for comparing frames against the exact drawing.
  @visibleForTesting
  static bool debugExact = false;

  /// The nearest grid scale to [scale], a screen scale (logical to device
  /// pixels). The grid passes through [devicePixelRatio], so text at its
  /// layout size stays exact.
  static double snap(double scale, double devicePixelRatio) {
    if (debugExact || scale <= 0 || devicePixelRatio <= 0) return scale;
    final steps =
        (math.log(scale / devicePixelRatio) / math.ln2 * stepsPerOctave)
            .roundToDouble();
    return devicePixelRatio * math.pow(2, steps / stepsPerOctave);
  }

  /// The largest axis scale of [transform], the scale the glyph atlas
  /// keys text by.
  static double of(Matrix4 transform) {
    final s = transform.storage;
    final x = math.sqrt(s[0] * s[0] + s[1] * s[1] + s[2] * s[2]);
    final y = math.sqrt(s[4] * s[4] + s[5] * s[5] + s[6] * s[6]);
    return math.max(x, y);
  }
}

/// Paints with [painter] and passes it the screen scale of its box: the
/// largest axis scale of the transform from the box to the screen, device
/// pixel ratio included.
@internal
class MorphScreenScalePaint extends LeafRenderObjectWidget {
  /// Paints [painter] over the whole box, again whenever [repaint]
  /// notifies.
  const MorphScreenScalePaint({required this.painter, this.repaint, super.key});

  /// Paints into the box of [Size] whose screen scale is the [double].
  final void Function(Canvas canvas, Size size, double screenScale) painter;

  /// Repaints the box when it notifies.
  final Listenable? repaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderScreenScalePaint(painter, repaint);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderScreenScalePaint).update(painter, repaint);
  }
}

class _RenderScreenScalePaint extends RenderBox {
  _RenderScreenScalePaint(this._painter, this._repaint);

  void Function(Canvas canvas, Size size, double screenScale) _painter;

  Listenable? _repaint;

  void update(
    void Function(Canvas canvas, Size size, double screenScale) painter,
    Listenable? repaint,
  ) {
    _painter = painter;
    markNeedsPaint();
    if (identical(repaint, _repaint)) return;
    if (attached) _repaint?.removeListener(markNeedsPaint);
    _repaint = repaint;
    if (attached) _repaint?.addListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final scale = MorphGlyphScale.of(getTransformTo(null));
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    _painter(canvas, size, scale);
    canvas.restore();
  }
}

/// Paints [child] from one raster of it at the device pixel ratio while
/// [active] is true, and live otherwise.
///
/// The raster is taken when [active] turns on and again whenever the
/// child repaints; drawn under a scale it is resampled with mipmaps
/// instead of having its glyphs rasterized at that scale. Meant for text
/// under a blur, which hides the resampling: an unblurred label stays
/// live.
@internal
class MorphGlyphRaster extends SingleChildRenderObjectWidget {
  /// Draws [child] from its raster while [active] is true.
  const MorphGlyphRaster({
    required this.active,
    required super.child,
    this.sampleLogicalBounds = false,
    super.key,
  });

  /// Whether the child is drawn from its raster.
  final ValueListenable<bool> active;

  /// Samples the child's logical extent instead of stretching the rounded
  /// pixel dimensions of its raster over that extent.
  final bool sampleLogicalBounds;

  /// The smallest blur, in logical pixels on screen, that hides the
  /// resampling of a raster drawn under it.
  static const double minBlur = 0.5;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGlyphRaster(
    active,
    MediaQuery.devicePixelRatioOf(context),
    sampleLogicalBounds: sampleLogicalBounds,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderGlyphRaster).update(
      active,
      MediaQuery.devicePixelRatioOf(context),
      sampleLogicalBounds: sampleLogicalBounds,
    );
  }
}

class _RenderGlyphRaster extends RenderProxyBox {
  _RenderGlyphRaster(
    this._active,
    this._devicePixelRatio, {
    required bool sampleLogicalBounds,
    // ignore: prefer_initializing_formals
  }) : _sampleLogicalBounds = sampleLogicalBounds;

  ValueListenable<bool> _active;

  double _devicePixelRatio;

  bool _sampleLogicalBounds;

  void update(
    ValueListenable<bool> active,
    double devicePixelRatio, {
    required bool sampleLogicalBounds,
  }) {
    if (identical(active, _active) &&
        devicePixelRatio == _devicePixelRatio &&
        sampleLogicalBounds == _sampleLogicalBounds) {
      return;
    }
    if (attached) _active.removeListener(_changed);
    _active = active;
    _devicePixelRatio = devicePixelRatio;
    _sampleLogicalBounds = sampleLogicalBounds;
    if (attached) _active.addListener(_changed);
    _changed();
  }

  ui.Image? _raster;

  void _drop() {
    _raster?.dispose();
    _raster = null;
  }

  void _changed() {
    _drop();
    markNeedsPaint();
  }

  @override
  void markNeedsPaint() {
    _drop();
    super.markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _active.addListener(_changed);
  }

  @override
  void detach() {
    _active.removeListener(_changed);
    _drop();
    super.detach();
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  ui.Image _rasterize() {
    final layer = OffsetLayer();
    final context = PaintingContext(layer, Offset.zero & size);
    super.paint(context, Offset.zero);
    // ignore: invalid_use_of_protected_member
    context.stopRecordingIfNeeded();
    final image = layer.toImageSync(
      Offset.zero & size,
      pixelRatio: _devicePixelRatio,
    );
    layer.dispose();
    return image;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_active.value ||
        size.isEmpty ||
        child == null ||
        MorphGlyphScale.debugExact) {
      _drop();
      super.paint(context, offset);
      return;
    }
    final raster = _raster ??= _rasterize();
    final paint = Paint();
    paint.filterQuality = FilterQuality.medium;
    context.canvas.drawImageRect(
      raster,
      Rect.fromLTWH(
        0,
        0,
        _sampleLogicalBounds
            ? size.width * _devicePixelRatio
            : raster.width.toDouble(),
        _sampleLogicalBounds
            ? size.height * _devicePixelRatio
            : raster.height.toDouble(),
      ),
      offset & size,
      paint,
    );
  }
}

/// Paints [child] blurred by [blur] and faded to [opacity] as one draw
/// in the pass it belongs to, without an offscreen layer.
///
/// While it is blurred by half a device pixel or more, or fades, the child
/// is drawn through a single-pass Gaussian shader that also applies the opacity,
/// from a mip pyramid of one raster of it at the device pixel ratio: each
/// frame reads the finest level the blur spans at most two texels of, so
/// the pyramid lasts while the blur and the scale animate and is taken
/// again only when the child repaints or resizes. Every pyramid one frame
/// needs is taken together, in two passes. A fading child is drawn by the
/// shader at any blur, the smallest at its finest kernel, so a fade never
/// needs a layer of its own; an opaque child blurred less paints sharp.
@internal
class MorphGlyphBlur extends SingleChildRenderObjectWidget {
  /// Paints [child] blurred by [blur] logical pixels and faded to
  /// [opacity].
  const MorphGlyphBlur({
    required this.blur,
    required this.opacity,
    required super.child,
    super.key,
  });

  /// The Gaussian blur's sigma in the child's logical pixels.
  final double blur;

  /// The opacity, from 0 to 1.
  final double opacity;

  static ui.FragmentProgram? _program;
  static ui.FragmentProgram? _reduce;
  static Future<void>? _loading;

  /// Loads the blur shaders; until they have loaded every blur paints as
  /// a blur layer.
  static Future<void> precache() => _loading ??=
      Future.wait([
        ui.FragmentProgram.fromAsset(ShaderKeys.glyphReduce),
        ui.FragmentProgram.fromAsset(ShaderKeys.glyphBlur),
      ]).then((List<ui.FragmentProgram> programs) {
        _reduce = programs[0];
        _program = programs[1];
      });

  /// Number of rasters taken, for tests and benchmarks.
  @visibleForTesting
  static int debugRasterCount = 0;

  /// Number of atlas passes the rasters were taken in.
  @visibleForTesting
  static int debugAtlasCount = 0;

  @override
  RenderObject createRenderObject(BuildContext context) {
    precache().ignore();
    return _RenderGlyphBlur(
      blur,
      opacity,
      MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderGlyphBlur).update(
      blur,
      opacity,
      MediaQuery.devicePixelRatioOf(context),
    );
  }
}

class _RenderGlyphBlur extends RenderProxyBox {
  _RenderGlyphBlur(this._blur, this._opacity, this._devicePixelRatio);

  /// The largest blur in texels the shader's taps cover.
  static const double _maxSigma = 2;

  /// The largest blur, in logical pixels, drawn sharp.
  static const double minBlur = 0.05;

  /// The smallest blur, in device pixels, the shader draws on an opaque
  /// child; a smaller one paints sharp, within about a channel step of a
  /// true Gaussian on average. A fading child draws through the shader at
  /// any blur.
  static const double minScreenSigma = 0.5;

  /// The pyramid's levels below the raster: the coarsest is 1/32 of it,
  /// which a 10 point blur still spans under two texels of at a device
  /// pixel ratio of 6.
  static const int _levels = 5;

  /// Texels of clear border around each level's slot: more than the
  /// shader's taps reach beyond the drawn rect (three sigma plus a texel
  /// past the raster, then seven texels of taps).
  static const int _border = 16;

  /// The alignment of each raster in the full-resolution atlas: a
  /// multiple of every level's factor, so each level's texels cover whole
  /// blocks of the raster's, all inside the raster's own slot.
  static const int _rasterAlign = 1 << _levels;

  /// The widest atlas row, in texels.
  static const double _atlasWidth = 2048;

  /// Every attached blur, for batching the pyramids one frame needs.
  static final Set<_RenderGlyphBlur> _attached = <_RenderGlyphBlur>{};

  /// Whether this frame's paint already took every pyramid it needs.
  static bool _batched = false;

  double _blur;
  double _opacity;
  double _devicePixelRatio;

  void update(double blur, double opacity, double devicePixelRatio) {
    if (devicePixelRatio != _devicePixelRatio) {
      _devicePixelRatio = devicePixelRatio;
      _blur = blur;
      _opacity = opacity;
      markNeedsPaint();
      return;
    }
    if (blur == _blur && opacity == _opacity) return;
    final repaint = blur != _blur || _shaderScale() != null || _layerBlur;
    _blur = blur;
    _opacity = opacity;
    // A sharp child only fades: its opacity layer updates without a
    // repaint, as under [Opacity].
    if (repaint || _shaderScale() != null) {
      super.markNeedsPaint();
    } else {
      markNeedsCompositedLayerUpdate();
    }
  }

  /// The atlas holding this blur's pyramid (a clone this object owns),
  /// each level's slot in it (border included) and the size it was taken
  /// at.
  ui.Image? _atlas;
  List<Rect> _slots = const [];
  Size _pyramidSize = Size.zero;
  ui.FragmentShader? _shader;

  final LayerHandle<ImageFilterLayer> _filterLayer =
      LayerHandle<ImageFilterLayer>();

  void _drop() {
    _atlas?.dispose();
    _atlas = null;
  }

  @override
  void markNeedsPaint() {
    _drop();
    super.markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  /// Whether the last paint drew the shader, which applies the opacity
  /// itself.
  bool _shaded = false;

  @override
  OffsetLayer updateCompositedLayer({
    required covariant OpacityLayer? oldLayer,
  }) {
    final layer = oldLayer ?? OpacityLayer();
    layer.alpha = _shaded ? 255 : ui.Color.getAlphaFromOpacity(_opacity);
    return layer;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _attached.add(this);
  }

  @override
  void detach() {
    _attached.remove(this);
    _drop();
    super.detach();
  }

  @override
  void dispose() {
    _drop();
    _shader?.dispose();
    _shader = null;
    _filterLayer.layer = null;
    super.dispose();
  }

  /// The screen scale of this box (device pixels per logical pixel), or
  /// null when it paints live: no shader yet, nothing to draw, or an
  /// opaque child blurred under [minScreenSigma].
  double? _shaderScale() {
    if (MorphGlyphBlur._program == null ||
        MorphGlyphScale.debugExact ||
        child == null ||
        _opacity <= 0 ||
        !hasSize ||
        size.isEmpty ||
        (_blur <= minBlur && _opacity >= 1)) {
      return null;
    }
    final scale = MorphGlyphScale.of(getTransformTo(null)) * _devicePixelRatio;
    if (_blur * scale < minScreenSigma && _opacity >= 1) return null;
    return scale;
  }

  /// Whether the blur paints as a blur layer: only where no shader draws
  /// it (before the shader loads, or when drawing exactly). With the
  /// shader, a blur under [minScreenSigma] paints sharp.
  bool get _layerBlur =>
      _blur > minBlur &&
      (MorphGlyphBlur._program == null || MorphGlyphScale.debugExact);

  bool get _hasPyramid => _atlas != null && size == _pyramidSize;

  /// Shelf-packs boxes of [sizes] texels into rows at most [_atlasWidth]
  /// wide, each box starting on a multiple of [align]: their slots and
  /// the atlas's bounds.
  static (List<Rect>, Rect) _pack(List<Size> sizes, {int align = 1}) {
    double up(double v) => (v / align).ceilToDouble() * align;
    final slots = <Rect>[];
    var x = 0.0;
    var y = 0.0;
    var row = 0.0;
    var width = 0.0;
    for (final size in sizes) {
      if (x > 0 && x + size.width > _atlasWidth) {
        x = 0;
        y = up(y + row);
        row = 0;
      }
      slots.add(Offset(x, y) & size);
      x = up(x + size.width);
      row = math.max(row, size.height);
      width = math.max(width, x);
    }
    return (slots, Rect.fromLTWH(0, 0, width, up(y + row)));
  }

  /// Takes the pyramids of [jobs] together: every child paints once into
  /// one atlas at its device pixel ratio, and every level of every
  /// pyramid is drawn down from those, with mipmaps, into a second.
  static void _rasterize(List<_RenderGlyphBlur> jobs) {
    MorphGlyphBlur.debugRasterCount += jobs.length;
    MorphGlyphBlur.debugAtlasCount += 2;
    double aligned(double v) =>
        (v / _rasterAlign).ceilToDouble() * _rasterAlign;
    final (rasterSlots, rasterBounds) = _pack([
      for (final blur in jobs)
        Size(
          aligned(blur.size.width * blur._devicePixelRatio),
          aligned(blur.size.height * blur._devicePixelRatio),
        ),
    ], align: _rasterAlign);
    final layer = OffsetLayer();
    final context = PaintingContext(layer, rasterBounds);
    for (var i = 0; i < jobs.length; i++) {
      final blur = jobs[i];
      final child = blur.child!;
      // Clipped to its slot, so a child painting beyond its box never
      // reaches a neighbor's.
      context.pushClipRect(
        child.needsCompositing,
        Offset.zero,
        rasterSlots[i],
        (PaintingContext context, Offset offset) => context.pushTransform(
          child.needsCompositing,
          rasterSlots[i].topLeft,
          Matrix4.diagonal3Values(
            blur._devicePixelRatio,
            blur._devicePixelRatio,
            1,
          ),
          (PaintingContext context, Offset offset) =>
              context.paintChild(child, offset),
        ),
      );
    }
    // ignore: invalid_use_of_protected_member
    context.stopRecordingIfNeeded();
    final raster = layer.toImageSync(rasterBounds);
    layer.dispose();
    final sizes = <Size>[];
    for (final blur in jobs) {
      for (var k = 0; k <= _levels; k++) {
        final ratio = blur._devicePixelRatio / (1 << k);
        sizes.add(
          Size(
            (blur.size.width * ratio).ceilToDouble() + 2 * _border,
            (blur.size.height * ratio).ceilToDouble() + 2 * _border,
          ),
        );
      }
    }
    final (slots, bounds) = _pack(sizes);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, bounds);
    final paint = Paint();
    final reduce = MorphGlyphBlur._reduce!.fragmentShader();
    for (var i = 0; i < jobs.length; i++) {
      final from = rasterSlots[i].topLeft;
      for (var k = 0; k <= _levels; k++) {
        final slot = slots[i * (_levels + 1) + k];
        final factor = 1 << k;
        reduce.setFloat(0, raster.width.toDouble());
        reduce.setFloat(1, raster.height.toDouble());
        reduce.setFloat(2, factor.toDouble());
        reduce.setFloat(3, slot.left + _border);
        reduce.setFloat(4, slot.top + _border);
        reduce.setFloat(5, from.dx);
        reduce.setFloat(6, from.dy);
        reduce.setImageSampler(0, raster, filterQuality: FilterQuality.low);
        paint.shader = reduce;
        canvas.drawRect(slot.deflate(_border.toDouble()), paint);
      }
    }
    final picture = recorder.endRecording();
    reduce.dispose();
    final atlas = picture.toImageSync(
      bounds.width.ceil(),
      bounds.height.ceil(),
    );
    picture.dispose();
    raster.dispose();
    for (var i = 0; i < jobs.length; i++) {
      final blur = jobs[i];
      blur._drop();
      blur._atlas = atlas.clone();
      blur._slots = slots.sublist(i * (_levels + 1), (i + 1) * (_levels + 1));
      blur._pyramidSize = blur.size;
    }
    atlas.dispose();
  }

  /// Takes a pyramid for every attached blur that needs one this frame,
  /// together, once per frame.
  void _rasterizeFrame() {
    final jobs = <_RenderGlyphBlur>[];
    if (!_batched) {
      _batched = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => _batched = false);
      for (final other in _attached) {
        if (identical(other, this) || !other.attached) continue;
        if (!other._hasPyramid && other._shaderScale() != null) {
          jobs.add(other);
        }
      }
    }
    jobs.add(this);
    _rasterize(jobs);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || _opacity <= 0 || size.isEmpty) {
      _filterLayer.layer = null;
      _setShaded(false);
      return;
    }
    final screenScale = _shaderScale();
    if (screenScale == null) {
      // A settled child lets its pyramid go; a fading one keeps it for a
      // blur that may come back.
      if (_blur <= minBlur) _drop();
      _setShaded(false);
      _paintLive(context, offset);
      return;
    }
    _setShaded(true);
    _filterLayer.layer = null;
    if (!_hasPyramid) _rasterizeFrame();
    final atlas = _atlas!;
    // The finest level the blur spans at most [_maxSigma] texels of, and
    // no finer than about the screen: a coarser level would lose detail
    // the blur keeps, a finer one alias.
    var level = 0;
    var ratio = _devicePixelRatio;
    while (level < _levels &&
        (_blur * ratio > _maxSigma || ratio > screenScale * math.sqrt2)) {
      level++;
      ratio /= 2;
    }
    final slot = _slots[level];
    // The texels are already a box filter of one texel; the kernel adds
    // the rest, and never less than 0.4 screen pixels, so texels finer or
    // coarser than the screen never show.
    final target = math.min(_blur * ratio, _maxSigma);
    final least = 0.4 * ratio / screenScale;
    final sigma = math.sqrt(math.max(target * target - 1 / 12, least * least));
    final shader = _shader ??= MorphGlyphBlur._program!.fragmentShader();
    shader.setFloat(0, ratio);
    shader.setFloat(1, slot.left + _border);
    shader.setFloat(2, slot.top + _border);
    shader.setFloat(3, atlas.width.toDouble());
    shader.setFloat(4, atlas.height.toDouble());
    shader.setFloat(5, 1 / (sigma * sigma));
    shader.setFloat(6, _opacity.clamp(0.0, 1.0));
    // Pairs reaching three sigma past the base texel and its neighbor.
    final reachTexels = (3 * sigma).ceil();
    shader.setFloat(
      7,
      reachTexels <= 2
          ? 3
          : reachTexels <= 4
          ? 5
          : 7,
    );
    for (var i = 0; i < 8; i++) {
      shader.setFloat(8 + i, math.exp(-i * i / (2 * sigma * sigma)));
    }
    shader.setImageSampler(0, atlas, filterQuality: FilterQuality.low);
    final reach = 3 * _blur + 1 / ratio;
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final paint = Paint();
    paint.shader = shader;
    canvas.drawRect(
      Rect.fromLTRB(-reach, -reach, size.width + reach, size.height + reach),
      paint,
    );
    canvas.restore();
  }

  /// Records which path paints, and sets this box's opacity layer to
  /// match: the shader applies the opacity itself.
  void _setShaded(bool shaded) {
    _shaded = shaded;
    // ignore: invalid_use_of_protected_member
    (layer as OpacityLayer?)?.alpha = shaded
        ? 255
        : ui.Color.getAlphaFromOpacity(_opacity);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (child != null && _opacity > 0) visitor(child!);
  }

  /// Paints the child itself, under a blur layer where [_layerBlur]; this
  /// box's own opacity layer fades it.
  void _paintLive(PaintingContext context, Offset offset) {
    if (_layerBlur) {
      final layer = _filterLayer.layer ??= ImageFilterLayer();
      layer.imageFilter = ui.ImageFilter.blur(
        sigmaX: _blur,
        sigmaY: _blur,
        tileMode: TileMode.decal,
      );
      context.pushLayer(layer, super.paint, offset);
    } else {
      _filterLayer.layer = null;
      super.paint(context, offset);
    }
  }
}

/// Paints [child] at the nearest [MorphGlyphScale] grid scale of its
/// screen scale, about the center of its box.
///
/// Text under a transform whose scale sweeps continuously (a tab bar
/// swelling under a finger, a button lifting) meets a new screen scale
/// every frame and each one strikes the glyphs again. Here the child is
/// drawn at one of 64 scales per octave instead, so a sweep reuses a few
/// strikes. At a grid scale, which includes the device pixel ratio and so
/// every control at rest, the child paints with no transform at all.
///
/// The painted child is within 0.54 percent of its layout size about the
/// center of its box; hit testing, semantics and layout use the layout
/// size and are unchanged.
@internal
class MorphGlyphSnap extends SingleChildRenderObjectWidget {
  /// Snaps the screen scale [child] is drawn at.
  const MorphGlyphSnap({required super.child, super.key});

  @override
  RenderMorphGlyphSnap createRenderObject(BuildContext context) =>
      RenderMorphGlyphSnap(MediaQuery.devicePixelRatioOf(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMorphGlyphSnap renderObject,
  ) {
    renderObject.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

/// The render object of [MorphGlyphSnap].
@internal
class RenderMorphGlyphSnap extends RenderProxyBox {
  /// Snaps to the grid through [devicePixelRatio].
  RenderMorphGlyphSnap(this._devicePixelRatio);

  double _devicePixelRatio;

  /// The pixel ratio of the view, the grid's anchor: the screen scale of
  /// the box is its transform to the root, which stops before the view's
  /// own scale.
  double get devicePixelRatio => _devicePixelRatio;

  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// The factor the last paint applied, 1 when it painted untransformed.
  @visibleForTesting
  double debugFactor = 1;

  final Matrix4 _transform = Matrix4.identity();

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final screen = MorphGlyphScale.of(getTransformTo(null)) * _devicePixelRatio;
    final factor = MorphGlyphScale.snap(screen, _devicePixelRatio) / screen;
    if (!factor.isFinite || (factor - 1).abs() < 1e-6) {
      debugFactor = 1;
      context.paintChild(child, offset);
      return;
    }
    debugFactor = factor;
    final center = size.center(offset);
    _transform.setIdentity();
    _transform.translateByDouble(center.dx, center.dy, 0, 1);
    _transform.scaleByDouble(factor, factor, 1, 1);
    _transform.translateByDouble(-center.dx, -center.dy, 0, 1);
    context.pushTransform(
      needsCompositing,
      Offset.zero,
      _transform,
      (PaintingContext context, Offset _) => context.paintChild(child, offset),
    );
  }
}
