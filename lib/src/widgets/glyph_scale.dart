/// Text under a transform that animates, drawn without new glyph rasters
/// on every frame.
///
/// Impeller rasterizes each glyph once per font and screen scale (the
/// largest axis of the transform the text is drawn with, rounded to
/// 1/200) into its glyph atlas. A label whose scale sweeps continuously
/// meets a new scale nearly every frame, and each one rasterizes and
/// uploads the label's glyphs again on the raster thread.
///
/// One policy decides, per frame and per drawing, how such text is drawn
/// ([MorphGlyphPolicy]), from what the drawing observes: how fast its
/// screen scale moves, whether a blur above it hides resampling, whether
/// its content holds still, and the blur and fade it applies itself.
/// [MorphGlyphs] carries it out for a child; a widget only wraps its
/// labels and never chooses.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/internal/content_snapshot.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/live.dart';

/// The screen scales text moving through a scale animation is drawn at.
@internal
abstract final class MorphGlyphScale {
  /// The finest grid's steps per doubling of the scale: neighbors are 1.1
  /// percent apart, so a snapped label is drawn at most 0.54 percent off
  /// its exact size about its anchor.
  static const int stepsPerOctave = 64;

  /// The steps per octave of the grid a raster above the device pixel
  /// ratio is taken on: a raster is drawn at most 16 percent smaller than
  /// it was taken, or up to [rasterStretch] larger.
  static const int rasterStepsPerOctave = 4;

  /// How much larger than the device pixel ratio a raster taken at it is
  /// still drawn (2^(1/8), 9 percent): an overshoot past the rest scale
  /// (a menu card's 1.07) magnifies the rest raster instead of taking
  /// another one, with new glyph strikes, for a few frames.
  static const double rasterStretch = 1.0905077326652577;

  /// Draws every label at its exact scale and live: no snapping, rasters
  /// or shader blur, for comparing frames against the exact drawing.
  @visibleForTesting
  static bool debugExact = false;

  /// The nearest grid scale to [scale], a screen scale (logical to device
  /// pixels). The grid passes through [devicePixelRatio], so text at its
  /// layout size stays exact.
  /// [perOctave] is the grid's density, [stepsPerOctave] unless given.
  static double snap(
    double scale,
    double devicePixelRatio, {
    int perOctave = stepsPerOctave,
  }) {
    if (debugExact || scale <= 0 || devicePixelRatio <= 0) return scale;
    final steps = (math.log(scale / devicePixelRatio) / math.ln2 * perOctave)
        .roundToDouble();
    return devicePixelRatio * math.pow(2, steps / perOctave);
  }

  /// The distance from [from] to [to], screen scales, in steps of the
  /// finest grid.
  static double steps(double from, double to) =>
      (math.log(to / from) / math.ln2 * stepsPerOctave).abs();

  /// The resolution, device pixels per logical pixel, a raster of text
  /// shown at the screen scale [screen] is taken at: [devicePixelRatio]
  /// up to [rasterStretch] times that scale (the scale the text's glyphs
  /// are struck at already; smaller scales read a reduced level of the
  /// raster), above it the next scale up on the [rasterStepsPerOctave]
  /// grid.
  static double rasterRatio(double screen, double devicePixelRatio) {
    if (screen <= devicePixelRatio * rasterStretch) return devicePixelRatio;
    final steps =
        (math.log(screen / devicePixelRatio) / math.ln2 * rasterStepsPerOctave)
            .ceilToDouble();
    return devicePixelRatio * math.pow(2, steps / rasterStepsPerOctave);
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

/// How one frame of text under an animated transform is drawn.
@internal
enum MorphGlyphMode {
  /// Drawn as it is, at its exact screen scale: at rest, and in every
  /// frame that would not strike glyphs anyway. IDENTICAL.
  live,

  /// Drawn at the nearest grid scale about its center
  /// ([MorphGlyphPolicy.gridFor]): crisp glyphs, struck once per grid
  /// scale. NEAR: at most 0.54 percent off its size on the finest grid,
  /// 2.2 percent on the coarsest.
  snapped,

  /// Drawn from one raster of the child taken at
  /// [MorphGlyphScale.rasterRatio], mipmapped (a veiled drawing reads the
  /// level of its pyramid nearest the screen). NEAR: resampled, at most 9
  /// percent magnified; while it moves fast or under a blur only.
  raster,

  /// Blurred and faded by the drawing itself through one shader from the
  /// raster's pyramid ([MorphVeiledGlyphs] on Android). NEAR: within a
  /// channel step of mean error of a true Gaussian.
  shaded,
}

/// Decides how text under an animated transform draws each frame, from
/// what its drawing observes.
///
/// The cost being avoided is a glyph strike: rasterizing and uploading
/// the glyphs of every new screen scale. The choices, cheapest fidelity
/// first:
///
/// - at rest (the scale moved less than [restSteps] of the finest grid
///   since the last frame) the text is live and exact;
/// - while the scale moves fast ([fastSteps] or more a frame, held down to
///   [holdSteps] once rastering), or moves at all under a blur of
///   [coverBlur] or more that hides resampling, text whose content holds
///   still draws from one raster: no strike for the whole sweep;
/// - any other motion snaps to a grid of scales, coarser the faster the
///   scale moves ([gridFor]), so a strike is reused for four frames or
///   more: slow settles, and content that repaints every frame, where a
///   raster would be taken again every frame.
///
/// A drawing that blurs or fades its child itself draws it through the
/// pyramid shader where it is available ([MorphGlyphMode.shaded]), at
/// any scale.
///
/// A drawing that aligns ([MorphGlyphs.aligned]) snaps any motion of its
/// scale, down to the slowest drift of a spring's tail, and draws a
/// snapped frame with its origin on a whole device pixel across: the
/// atlas also keys a glyph by its x position in quarter device pixels, so
/// a label that moves while it scales meets new keys at every quarter
/// pixel it crosses, and on a grid scale with a whole-pixel origin each
/// glyph keeps one key per scale.
///
/// A drawing that does not snap (a card: a snap about its center would
/// move its far text against the card's edges) draws from its raster
/// whenever its scale moves at all, down to the slowest drift of a
/// spring's tail (each scale a tail crosses would strike the card's
/// glyphs again), and live when the scale holds still or its content
/// will not hold a raster.
@internal
abstract final class MorphGlyphPolicy {
  /// The finest-grid steps per frame under which the scale is at rest.
  /// The glyph atlas rounds scales to 1/200, about 0.2 steps at a device
  /// pixel ratio of 2.6, so slower drift strikes no more often than once
  /// in ten frames even live.
  static const double restSteps = 0.02;

  /// The finest-grid steps per frame from which a scale moves fast: a
  /// grid of any density useful for crisp text would strike every other
  /// frame or more.
  static const double fastSteps = 0.5;

  /// The finest-grid steps per frame down to which a drawing that already
  /// rasters keeps rastering, so a sweep decelerating through
  /// [fastSteps] does not flicker between a raster and crisp glyphs.
  static const double holdSteps = 0.1;

  /// The smallest blur, in logical pixels on screen, that hides the
  /// resampling of a raster drawn under it.
  static const double coverBlur = 0.5;

  /// The densities, in steps per octave, a snapped label is drawn on:
  /// each grid is a subset of the finer ones, so a strike on a coarse
  /// grid serves the finer grids too.
  static const List<int> grids = [64, 32, 16];

  /// The mode for a frame whose scale moved [steps] finest-grid steps
  /// since the last frame (null for the drawing's first frame, whose
  /// motion is unknown), drawn last frame in [previous].
  ///
  /// [canRaster] is whether the drawing can raster its content (the
  /// reduction shader has loaded and the content is not recorded again
  /// every frame); [stable] whether the content held still between the
  /// last two frames; [cover] the blur, in logical pixels, drawn over the
  /// text by something above it; [snaps] whether the drawing may snap;
  /// [aligned] whether it snaps any motion, down to the slowest drift.
  static MorphGlyphMode decide({
    required double? steps,
    MorphGlyphMode previous = MorphGlyphMode.live,
    bool canRaster = true,
    bool stable = true,
    double cover = 0,
    bool snaps = true,
    bool aligned = false,
  }) {
    final rasters = canRaster && stable;
    final hidden = cover >= coverBlur;
    if (steps == null) {
      return rasters && hidden ? MorphGlyphMode.raster : MorphGlyphMode.live;
    }
    if (steps == 0) return MorphGlyphMode.live;
    if (!snaps) return rasters ? MorphGlyphMode.raster : MorphGlyphMode.live;
    if (steps < restSteps && !aligned) return MorphGlyphMode.live;
    if (rasters &&
        (hidden ||
            steps >= fastSteps ||
            (previous == MorphGlyphMode.raster && steps >= holdSteps))) {
      return MorphGlyphMode.raster;
    }
    return MorphGlyphMode.snapped;
  }

  /// The grid, in steps per octave, a snapped label moving [steps]
  /// finest-grid steps a frame is drawn on: the finest of [grids] it
  /// crosses at most every fourth frame of, down to the coarsest.
  static int gridFor(double steps) {
    for (final grid in grids) {
      if (steps * grid / MorphGlyphScale.stepsPerOctave < 0.25) return grid;
    }
    return grids.last;
  }
}

/// The observation of one drawing of text under an animated transform:
/// its screen scale across frames and the mode [MorphGlyphPolicy] chose.
///
/// While a frame is not [MorphGlyphMode.live] the tracker asks for one
/// more paint at the start of the next frame ([onRepaint]), so a drawing
/// whose transform stops is painted once more, sees its scale at rest and
/// returns to exact.
@internal
class MorphGlyphTracker {
  /// Observes a drawing that repaints through [onRepaint].
  MorphGlyphTracker(this.onRepaint);

  /// Marks the drawing for a paint.
  VoidCallback onRepaint;

  double? _scale;
  double _steps = 0;
  MorphGlyphMode _mode = MorphGlyphMode.live;
  int? _callback;

  /// The mode of the last observed frame.
  MorphGlyphMode get mode => _mode;

  /// Whether no frame has been observed since the last [reset].
  bool get isFirst => _scale == null;

  /// The finest-grid steps the scale moved into the last observed frame.
  double get steps => _steps;

  /// The grid a snapped frame is drawn on.
  int get perOctave => MorphGlyphPolicy.gridFor(_steps);

  double? _stepsTo(double screen) {
    final from = _scale;
    if (from == null || from <= 0 || screen <= 0) return null;
    return MorphGlyphScale.steps(from, screen);
  }

  /// Records a frame drawn at the screen scale [screen] (device pixels per
  /// logical pixel) and returns its mode; the arguments are
  /// [MorphGlyphPolicy.decide]'s. With [settle] false a mode other than
  /// live does not ask for the next frame's paint.
  MorphGlyphMode observe(
    double screen, {
    bool canRaster = true,
    bool stable = true,
    double cover = 0,
    bool snaps = true,
    bool aligned = false,
    bool settle = true,
  }) {
    final steps = _stepsTo(screen);
    _scale = screen;
    _steps = steps ?? 0;
    _mode = MorphGlyphScale.debugExact
        ? MorphGlyphMode.live
        : MorphGlyphPolicy.decide(
            steps: steps,
            previous: _mode,
            canRaster: canRaster,
            stable: stable,
            cover: cover,
            snaps: snaps,
            aligned: aligned,
          );
    if (_mode != MorphGlyphMode.live && settle) _settle();
    return _mode;
  }

  /// The mode [observe] would return for [screen], without recording it.
  MorphGlyphMode peek(
    double screen, {
    bool canRaster = true,
    bool stable = true,
    double cover = 0,
    bool snaps = true,
    bool aligned = false,
  }) => MorphGlyphScale.debugExact
      ? MorphGlyphMode.live
      : MorphGlyphPolicy.decide(
          steps: _stepsTo(screen),
          previous: _mode,
          canRaster: canRaster,
          stable: stable,
          cover: cover,
          snaps: snaps,
          aligned: aligned,
        );

  /// Asks for one more paint at the start of the next frame, as [observe]
  /// does for a frame that is not live unless told not to: a drawing that
  /// observes with `settle: false` calls this when the frame it drew is
  /// not the exact one.
  void settleNext() => _settle();

  /// Records that the last observed frame, though not live, was drawn
  /// exactly as a live one would be: it is live from here on.
  void drewExact() => _mode = MorphGlyphMode.live;

  void _settle() {
    if (_callback != null) return;
    _callback = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _callback = null;
      onRepaint();
    });
  }

  /// Forgets the observed frames: the next one is a first frame.
  void reset() {
    if (_callback case final id?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    }
    _callback = null;
    _scale = null;
    _steps = 0;
    _mode = MorphGlyphMode.live;
  }
}

/// Paints with [painter] and passes it the transform from its box to the
/// root render object, in logical pixels; its screen scale is
/// [MorphGlyphScale.of] that transform.
///
/// The view's device pixel ratio is not included (the transform to the
/// root stops before the view's own scale); multiply by
/// `MediaQuery.devicePixelRatioOf` for device pixels, which
/// [MorphGlyphScale.snap] expects.
@internal
class MorphScreenScalePaint extends LeafRenderObjectWidget {
  /// Paints [painter] over the whole box, again whenever [repaint]
  /// notifies.
  const MorphScreenScalePaint({required this.painter, this.repaint, super.key});

  /// Paints into the box of [Size] whose transform to the root, without
  /// the device pixel ratio, is the [Matrix4].
  final void Function(Canvas canvas, Size size, Matrix4 toRoot) painter;

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

  void Function(Canvas canvas, Size size, Matrix4 toRoot) _painter;

  Listenable? _repaint;

  void update(
    void Function(Canvas canvas, Size size, Matrix4 toRoot) painter,
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
    final toRoot = getTransformTo(null);
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    _painter(canvas, size, toRoot);
    canvas.restore();
  }
}

/// Text (or any child holding text) whose screen scale animates, drawn
/// as [MorphGlyphPolicy] decides each frame: live and exact at rest,
/// snapped to a grid of scales while it moves slowly, from one raster of
/// itself while it moves fast or under a blur.
///
/// The drawing observes its own screen scale when it paints, so it must
/// be painted whenever the transform above it changes: no repaint
/// boundary between it and the animating transform (a boundary BELOW it,
/// inside the child, is fine: its repaints are seen by its layer). A fade
/// that runs with the transform belongs to the drawing itself
/// ([MorphGlyphs.faded]): an [Opacity] above it is such a boundary while
/// it fades. Once it leaves the live mode it paints itself every frame
/// until its scale rests. Hit testing, semantics and layout always use
/// the child's own layout. A drawing at rest adds no layer and no picture
/// of its own.
///
/// A raster is taken again when the child or a repaint boundary inside it
/// repaints, or when such a boundary changes its opacity. Rasters of every
/// drawing that needs one in a frame are taken together in one pass (a
/// second draws the pyramids veiled drawings read).
/// [morphVeiledGlyphs] blurs and fades as well.
@internal
class MorphGlyphs extends SingleChildRenderObjectWidget {
  /// Draws [child], whose screen scale may animate; [cover] is the blur,
  /// in logical pixels, something above draws over it (a fading menu
  /// card), which hides a raster's resampling; [aligned] draws a moving
  /// child as [MorphGlyphPolicy] draws an aligned drawing; without
  /// [snaps] it draws as a card does ([MorphGlyphs.faded]): from one
  /// raster while it moves, live at rest.
  const MorphGlyphs({
    required super.child,
    this.cover,
    this.aligned = false,
    this.snaps = true,
    super.key,
  }) : coverBlur = 0,
       opacity = 1,
       live = null,
       opacityOf = null;

  /// Draws [child], a card whose screen scale may animate, faded to the
  /// opacity [opacityOf] reads, again on every notification of [live].
  ///
  /// A card never snaps (a snap about its center would move its far text
  /// against its edges): it draws from one raster while it moves, down to
  /// the slowest drift of its spring's tail (NEAR: resampled), and live at
  /// rest or while its content repaints on consecutive frames
  /// (IDENTICAL). Drawn live, the fade is this drawing's own opacity
  /// layer, as an [Opacity]'s would be (IDENTICAL); drawn from its raster,
  /// the fade is the alpha of the image draw, with no offscreen pass
  /// (NEAR: one rounding instead of two, at most 1 of 255 per channel).
  const MorphGlyphs.faded({
    required Listenable this.live,
    required double Function() this.opacityOf,
    required super.child,
    super.key,
  }) : cover = null,
       coverBlur = 0,
       opacity = 1,
       snaps = false,
       aligned = false;

  const MorphGlyphs._veiled({
    required super.child,
    required this.coverBlur,
    required this.opacity,
  }) : cover = null,
       live = null,
       opacityOf = null,
       snaps = true,
       aligned = false;

  /// The blur drawn over the child from above, in logical pixels.
  final ValueListenable<double>? cover;

  /// A fixed blur drawn over the child from above, in logical pixels.
  final double coverBlur;

  /// The opacity the child is drawn with, from 0 to 1, unless
  /// [opacityOf] gives it.
  final double opacity;

  /// The source of [opacityOf], which notifies when the opacity may have
  /// changed.
  final Listenable? live;

  /// The opacity now, from 0 to 1, read on every notification of [live].
  final double Function()? opacityOf;

  /// Whether a moving child may be drawn snapped to the grid of scales.
  final bool snaps;

  /// Whether a moving child snaps down to the slowest drift of its scale
  /// and is drawn snapped with its origin on a whole device pixel across,
  /// for a label that moves while its scale animates (a tab bar's labels
  /// as the bar swells about its center).
  ///
  /// NEAR: a snapped frame is drawn up to half a device pixel (a sixth of
  /// a point at 3x) to the side of its exact place, besides the snap's
  /// own error; a drift that [MorphGlyphPolicy] would draw live and exact
  /// is snapped on the finest grid, at most 0.54 percent off its size. At
  /// rest the child is drawn exactly where it is.
  final bool aligned;

  /// The largest blur, in logical pixels, drawn sharp.
  static const double minBlur = 0.05;

  /// Whether a veiled drawing blurs and fades through the shader:
  /// Android, where the blur and opacity layers it replaces cost a render
  /// pass each (glass-renderer.md "Navigation glyph blur in one pass").
  static bool get shades =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static ui.FragmentProgram? _program;
  static ui.FragmentProgram? _reduce;
  static Future<void>? _loading;

  /// Loads the raster shaders; until they have loaded no drawing rasters
  /// (a fast sweep snaps instead) and a veiled one blurs through a blur
  /// layer.
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
  RenderMorphGlyphs createRenderObject(BuildContext context) {
    precache().ignore();
    final glyphs = RenderMorphGlyphs(MediaQuery.devicePixelRatioOf(context));
    glyphs.cover = cover;
    glyphs.coverBlur = coverBlur;
    glyphs.snaps = snaps;
    glyphs.aligned = aligned;
    _bind(glyphs);
    return glyphs;
  }

  void _bind(RenderMorphGlyphs glyphs) {
    final opacityOf = this.opacityOf;
    glyphs.bindLive(
      live,
      () => glyphs.opacity = opacityOf == null ? opacity : opacityOf(),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderMorphGlyphs renderObject,
  ) {
    renderObject.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    renderObject.cover = cover;
    renderObject.coverBlur = coverBlur;
    renderObject.snaps = snaps;
    renderObject.aligned = aligned;
    _bind(renderObject);
  }
}

/// [child] blurred by [blur] logical pixels and faded to [opacity],
/// drawn through [MorphGlyphPolicy]; the structure stays the same at any
/// blur and opacity, so [blur] 0 and [opacity] 1 cost nothing extra.
///
/// On Android ([MorphGlyphs.shades]) the blur and fade are one shader
/// draw in the pass the child belongs to ([MorphVeiledGlyphs]);
/// elsewhere they are a [MorphGlyphs] fading through its own opacity
/// layer over a blur layer (while [blur] is over [MorphGlyphs.minBlur]):
/// no repaint boundary between the animating transform above and the
/// drawing that observes it.
@internal
Widget morphVeiledGlyphs({
  required double blur,
  required double opacity,
  required Widget child,
}) {
  if (MorphGlyphs.shades) {
    return MorphVeiledGlyphs(blur: blur, opacity: opacity, child: child);
  }
  final blurred = blur > MorphGlyphs.minBlur;
  return MorphGlyphs._veiled(
    coverBlur: blurred ? blur : 0,
    opacity: opacity.clamp(0.0, 1.0),
    child: blurred
        ? ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: blur,
              sigmaY: blur,
              tileMode: TileMode.decal,
            ),
            child: child,
          )
        : child,
  );
}

/// [morphVeiledGlyphs] on Android: blurs and fades its child as one
/// shader draw from the drawing's raster pyramid
/// ([MorphGlyphMode.shaded]), and draws it sharp through the policy
/// otherwise.
@internal
class MorphVeiledGlyphs extends SingleChildRenderObjectWidget {
  /// Paints [child] blurred by [blur] logical pixels and faded to
  /// [opacity].
  const MorphVeiledGlyphs({
    required this.blur,
    required this.opacity,
    required super.child,
    super.key,
  });

  /// The Gaussian blur's sigma in the child's logical pixels.
  final double blur;

  /// The opacity, from 0 to 1.
  final double opacity;

  @override
  RenderObject createRenderObject(BuildContext context) {
    MorphGlyphs.precache().ignore();
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final glyphs = _RenderShadedGlyphs(ratio);
    glyphs.update(blur, opacity, ratio);
    return glyphs;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderShadedGlyphs).update(
      blur,
      opacity,
      MediaQuery.devicePixelRatioOf(context),
    );
  }
}

/// What a repaint boundary inside a [RenderMorphGlyphs] drew: its layer's
/// first child, alpha and offset.
typedef _BoundaryContent = ({Layer? first, int? alpha, Offset? offset});

/// The render object of [MorphGlyphs]: draws its child live, snapped or
/// from a raster as [MorphGlyphPolicy] decides each paint.
@internal
class RenderMorphGlyphs extends RenderProxyBox with MorphLiveBinding {
  /// Draws through the grid and rasters anchored at [devicePixelRatio].
  RenderMorphGlyphs(this._devicePixelRatio) {
    _tracker = MorphGlyphTracker(_repaint);
  }

  late final MorphGlyphTracker _tracker;

  /// The policy's observation of this drawing.
  @visibleForTesting
  MorphGlyphTracker get tracker => _tracker;

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

  ValueListenable<double>? _cover;

  /// The blur drawn over this box from above, in logical pixels.
  ValueListenable<double>? get cover => _cover;

  set cover(ValueListenable<double>? value) {
    if (identical(value, _cover)) return;
    if (attached) _cover?.removeListener(_repaint);
    _cover = value;
    if (attached) _cover?.addListener(_repaint);
    _repaint();
  }

  double _coverBlur = 0;

  /// A fixed blur drawn over this box from above, in logical pixels.
  double get coverBlur => _coverBlur;

  set coverBlur(double value) {
    if (value == _coverBlur) return;
    _coverBlur = value;
    _repaint();
  }

  double get _coverNow => math.max(_coverBlur, _cover?.value ?? 0);

  bool _snaps = true;

  /// Whether a moving child may be drawn snapped to the grid of scales.
  bool get snaps => _snaps;

  set snaps(bool value) {
    if (value == _snaps) return;
    _snaps = value;
    _repaint();
  }

  bool _aligned = false;

  /// Whether a moving child snaps down to the slowest drift of its scale
  /// and is drawn snapped with its origin on a whole device pixel across
  /// ([MorphGlyphs.aligned]).
  bool get aligned => _aligned;

  set aligned(bool value) {
    if (value == _aligned) return;
    _aligned = value;
    _repaint();
  }

  int _alpha = 255;

  /// The opacity the child is drawn with, from 0 to 1: drawn live, through
  /// an opacity layer of this box's own while it is between them (unlike
  /// [RenderOpacity], this box is no repaint boundary); drawn from its
  /// raster, through the alpha of the one image draw.
  double get opacity => _alpha / 255;

  set opacity(double value) {
    final alpha = ui.Color.getAlphaFromOpacity(value);
    if (alpha == _alpha) return;
    final composited = alwaysNeedsCompositing;
    final visible = _alpha > 0;
    _alpha = alpha;
    if (composited != alwaysNeedsCompositing) {
      markNeedsCompositingBitsUpdate();
    }
    _repaint();
    if (visible != (_alpha > 0)) markNeedsSemanticsUpdate();
  }

  final LayerHandle<OpacityLayer> _opacityLayer = LayerHandle<OpacityLayer>();

  @override
  bool get alwaysNeedsCompositing =>
      child != null && _alpha > 0 && _alpha < 255;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (child != null && _alpha > 0) visitor(child!);
  }

  /// The factor the last paint applied, 1 when it did not snap.
  @visibleForTesting
  double debugFactor = 1;

  /// The transform the last paint drew the child with, in this box's
  /// coordinates: identity unless it snapped.
  @visibleForTesting
  Matrix4 get debugPaintTransform => _childTransform;

  final Matrix4 _childTransform = Matrix4.identity();

  /// The mode of the last paint.
  @visibleForTesting
  MorphGlyphMode get debugMode => _tracker.mode;

  final Matrix4 _transform = Matrix4.identity();

  final LayerHandle<TransformLayer> _transformLayer =
      LayerHandle<TransformLayer>();

  /// The factor within which a snapped child paints untransformed: a
  /// scale off a grid scale by 1e-5 is keyed identically anyway.
  static const double _exactTolerance = 1e-4;

  /// The shift, in device pixels, within which an aligned child paints
  /// unshifted: far below the atlas's quarter pixel.
  static const double _exactShift = 1e-3;

  /// Every attached drawing, for batching the rasters one frame needs.
  static final Set<RenderMorphGlyphs> _attached = <RenderMorphGlyphs>{};

  /// Whether this frame's paint already took every raster it needs.
  static bool _batched = false;

  /// The frames of the latest two paints of any drawing, the latest last.
  static Duration? _paintFrameBefore;
  static Duration? _paintFrame;

  /// The frame this drawing last painted in.
  Duration? _paintedIn;

  /// Whether this drawing has not painted yet or painted in the latest
  /// frame any drawing painted in: one an ancestor hides (an opacity at
  /// zero) paints nowhere, and a raster taken for it would never be drawn.
  bool get _shown {
    final painted = _paintedIn;
    return painted == null ||
        painted == _paintFrame ||
        painted == _paintFrameBefore;
  }

  void _notePaint() {
    final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    if (now != _paintFrame) {
      _paintFrameBefore = _paintFrame;
      _paintFrame = now;
    }
    _paintedIn = now;
  }

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

  /// The atlas holding this drawing's raster or pyramid (a clone this
  /// object owns), each level's origin in it, the size and the ratio it
  /// was taken at.
  ui.Image? _atlas;
  List<Offset> _levelOrigins = const [];

  /// Whether this drawing reads a pyramid of reduced levels (the blur
  /// shader does) rather than its raster alone, which is drawn
  /// mipmapped.
  bool get _wantsPyramid => false;
  Size _pyramidSize = Size.zero;
  double _pyramidRatio = 0;

  /// The ratio the next raster of this drawing is taken at.
  double _wantRatio = 1;

  /// Whether the child repainted since the last paint, and whether it had
  /// before that paint too.
  bool _changed = false;
  bool _changedBefore = false;

  /// Every repaint boundary in the child's subtree (the child included)
  /// when the raster was taken, with what it drew then: a boundary
  /// repaints without marking this box, a repaint replaces its layer's
  /// children, a fading boundary only changes its layer's alpha, and a
  /// boundary moved by a repainting boundary around it only changes its
  /// layer's offset.
  List<(RenderObject, _BoundaryContent)> _boundaries = const [];

  /// The boundaries of [_boundaries] that no other one contains.
  List<RenderObject> _outerBoundaries = const [];

  static _BoundaryContent _contentOf(RenderObject boundary) {
    // ignore: invalid_use_of_protected_member
    final layer = boundary.layer;
    return (
      first: layer?.firstChild,
      alpha: layer is OpacityLayer ? layer.alpha : null,
      offset: layer is OffsetLayer ? layer.offset : null,
    );
  }

  /// Records the repaint boundaries the raster just drew.
  void _recordBoundaries() {
    final found = <(RenderObject, _BoundaryContent)>[];
    final outer = <RenderObject>[];
    void visit(RenderObject object, {required bool inside}) {
      final boundary = object.isRepaintBoundary;
      if (boundary) {
        found.add((object, _contentOf(object)));
        if (!inside) outer.add(object);
      }
      object.visitChildren(
        (RenderObject child) => visit(child, inside: inside || boundary),
      );
    }

    final child = this.child;
    if (child != null && child.needsCompositing) visit(child, inside: false);
    _boundaries = found;
    _outerBoundaries = outer;
  }

  /// Notes a repaint of a repaint boundary inside the child since the
  /// raster was taken.
  void _checkChildContent() {
    if (_atlas == null) return;
    for (final (boundary, content) in _boundaries) {
      if (boundary.attached && _contentOf(boundary) == content) continue;
      _changed = true;
      _drop();
      return;
    }
  }

  void _drop() {
    _atlas?.dispose();
    _atlas = null;
    _boundaries = const [];
    _outerBoundaries = const [];
  }

  final LayerHandle<ClipRectLayer> _culledLayer = LayerHandle<ClipRectLayer>();

  /// Keeps the layers of the repaint boundaries inside the child in the
  /// scene, under an empty clip, while this box draws the child from a
  /// raster. Taking the raster moved them out of the scene, and a
  /// boundary whose layer is out of the scene skips its repaints, so
  /// [_checkChildContent] would never see one. Back in the scene, a
  /// boundary repaints before this box paints (deeper first), and
  /// nothing else of the child paints again.
  void _paintCulled(PaintingContext context, Offset offset) {
    if (_outerBoundaries.isEmpty) {
      _culledLayer.layer = null;
      return;
    }
    final culled = _culledLayer.layer ??= ClipRectLayer();
    culled.clipRect = Rect.zero;
    context.pushLayer(culled, (PaintingContext context, Offset _) {
      for (final boundary in _outerBoundaries) {
        // ignore: invalid_use_of_protected_member
        final layer = boundary.layer;
        if (boundary.attached && layer != null) context.addLayer(layer);
      }
    }, offset);
  }

  /// Lets the raster go when the child is not painted at all: its
  /// boundaries' layers leave the scene with this box's, and their
  /// repaints until it paints again go unseen.
  void _dropUnpainted() {
    _culledLayer.layer = null;
    if (child?.needsCompositing ?? false) _drop();
  }

  /// Paints again, keeping the raster: the child has not changed.
  void _repaint() => super.markNeedsPaint();

  @override
  void markNeedsPaint() {
    _changed = true;
    _drop();
    super.markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _attached.add(this);
    _cover?.addListener(_repaint);
    _tracker.reset();
  }

  @override
  void detach() {
    _attached.remove(this);
    _cover?.removeListener(_repaint);
    _tracker.reset();
    _drop();
    super.detach();
  }

  @override
  void dispose() {
    _drop();
    _culledLayer.layer = null;
    _transformLayer.layer = null;
    _opacityLayer.layer = null;
    super.dispose();
  }

  /// The screen scale of this box, device pixels per logical pixel.
  double _screenScale() =>
      MorphGlyphScale.of(getTransformTo(null)) * _devicePixelRatio;

  bool get _canRaster =>
      MorphGlyphs._reduce != null && child != null && !size.isEmpty;

  bool get _stable => !(_changed && _changedBefore);

  /// Moves the content-change record on by one paint and returns whether
  /// the content held still: it changed at most once in the last two
  /// paints. The first paint after attaching (its own first layout marks
  /// it) is no change.
  bool _advanceStable() {
    if (_tracker.isFirst) {
      _changed = false;
      _changedBefore = false;
      return true;
    }
    final stable = _stable;
    _changedBefore = _changed;
    _changed = false;
    return stable;
  }

  bool _hasPyramid(double ratio) =>
      _atlas != null && size == _pyramidSize && ratio == _pyramidRatio;

  /// Whether this drawing will need a raster at [_wantRatio] this frame
  /// that it does not have; sets [_wantRatio].
  bool _needsRaster() {
    if (!attached || !hasSize || child == null || size.isEmpty) return false;
    final screen = _screenScale();
    if (!_rastersAt(screen)) return false;
    _wantRatio = MorphGlyphScale.rasterRatio(screen, _devicePixelRatio);
    return !_hasPyramid(_wantRatio);
  }

  /// Whether a frame at [screen] would draw from the raster.
  bool _rastersAt(double screen) =>
      _tracker.peek(
        screen,
        canRaster: _canRaster,
        stable: _stable,
        cover: _coverNow,
        snaps: _snaps,
        aligned: _aligned,
      ) ==
      MorphGlyphMode.raster;

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

  /// Takes the rasters of [jobs] together: every child paints once into
  /// one atlas at its raster ratio. The jobs that read a pyramid
  /// ([_wantsPyramid]) then have every level drawn down from that atlas,
  /// without mipmaps, into a second; the others read the first atlas.
  static void _rasterize(List<RenderMorphGlyphs> jobs) {
    MorphGlyphs.debugRasterCount += jobs.length;
    MorphGlyphs.debugAtlasCount += 1;
    double aligned(double v) =>
        (v / _rasterAlign).ceilToDouble() * _rasterAlign;
    // A clear margin of [_rasterAlign] texels around each raster: a
    // mipmapped read stays inside its own raster, and the raster's origin
    // stays aligned for the reduction.
    const margin = _rasterAlign;
    final (rasterSlots, rasterBounds) = _pack([
      for (final job in jobs)
        Size(
          aligned(job.size.width * job._wantRatio) + 2 * margin,
          aligned(job.size.height * job._wantRatio) + 2 * margin,
        ),
    ], align: _rasterAlign);
    final origins = [
      for (final slot in rasterSlots)
        slot.topLeft + const Offset(margin * 1.0, margin * 1.0),
    ];
    final layer = OffsetLayer();
    final context = PaintingContext(layer, rasterBounds);
    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      final child = job.child!;
      // Clipped to its slot, so a child painting beyond its box never
      // reaches a neighbor's.
      context.pushClipRect(
        child.needsCompositing,
        Offset.zero,
        rasterSlots[i].deflate(margin / 2),
        (PaintingContext context, Offset offset) => context.pushTransform(
          child.needsCompositing,
          origins[i],
          Matrix4.diagonal3Values(job._wantRatio, job._wantRatio, 1),
          (PaintingContext context, Offset offset) =>
              context.paintChild(child, offset),
        ),
      );
    }
    // ignore: invalid_use_of_protected_member
    context.stopRecordingIfNeeded();
    final raster = layer.toImageSync(rasterBounds);
    layer.dispose();
    final pyramids = [
      for (final job in jobs)
        if (job._wantsPyramid) job,
    ];
    ui.Image? atlas;
    final levelOrigins = <RenderMorphGlyphs, List<Offset>>{};
    if (pyramids.isNotEmpty) {
      MorphGlyphs.debugAtlasCount += 1;
      final sizes = <Size>[];
      for (final job in pyramids) {
        for (var k = 0; k <= _levels; k++) {
          final ratio = job._wantRatio / (1 << k);
          sizes.add(
            Size(
              (job.size.width * ratio).ceilToDouble() + 2 * _border,
              (job.size.height * ratio).ceilToDouble() + 2 * _border,
            ),
          );
        }
      }
      final (slots, bounds) = _pack(sizes);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, bounds);
      final paint = Paint();
      final reduce = MorphGlyphs._reduce!.fragmentShader();
      for (var i = 0; i < pyramids.length; i++) {
        final from = origins[jobs.indexOf(pyramids[i])];
        final levels = <Offset>[];
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
          levels.add(slot.topLeft + const Offset(_border * 1.0, _border * 1.0));
        }
        levelOrigins[pyramids[i]] = levels;
      }
      final picture = recorder.endRecording();
      reduce.dispose();
      atlas = picture.toImageSync(bounds.width.ceil(), bounds.height.ceil());
      picture.dispose();
    }
    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      job._drop();
      final levels = levelOrigins[job];
      job._atlas = levels == null ? raster.clone() : atlas!.clone();
      job._levelOrigins = levels ?? [origins[i]];
      job._pyramidSize = job.size;
      job._pyramidRatio = job._wantRatio;
      job._recordBoundaries();
    }
    raster.dispose();
    atlas?.dispose();
  }

  /// Takes this drawing's pyramid at [ratio], together with every other
  /// attached drawing that needs one this frame, once per frame.
  void _rasterizeAt(double ratio) {
    _wantRatio = ratio;
    final jobs = <RenderMorphGlyphs>[];
    if (!_batched) {
      _batched = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => _batched = false);
      for (final other in _attached) {
        if (identical(other, this) || !other._shown) continue;
        if (other._needsRaster()) jobs.add(other);
      }
    }
    jobs.add(this);
    _rasterize(jobs);
  }

  /// Whether a frame drawn without the pyramid keeps it for frames to
  /// come.
  bool get _keepsPyramid => false;

  /// The level of the pyramid to read for [screen], and its ratio: the
  /// finest no more than 1.41 times finer than the screen, so a bilinear
  /// read never skips a texel.
  (int, double) _levelFor(double screen, {double blur = 0}) {
    var level = 0;
    var ratio = _pyramidRatio;
    while (level < _levelOrigins.length - 1 &&
        (blur * ratio > _RenderShadedGlyphs._maxSigma ||
            ratio > screen * math.sqrt2)) {
      level++;
      ratio /= 2;
    }
    return (level, ratio);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    _notePaint();
    _checkChildContent();
    final stable = _advanceStable();
    final screen = _screenScale();
    final mode = _tracker.observe(
      screen,
      canRaster: _canRaster,
      stable: stable,
      cover: _coverNow,
      snaps: _snaps,
      aligned: _aligned,
      settle: false,
    );
    if (_alpha == 0) {
      _opacityLayer.layer = null;
      _dropUnpainted();
      if (mode != MorphGlyphMode.live) _tracker.settleNext();
      return;
    }
    // A raster is one image draw: it takes the fade in its paint, with no
    // offscreen pass over the card.
    if (_alpha == 255 || mode == MorphGlyphMode.raster) {
      _opacityLayer.layer = null;
      _paintSharp(context, offset, screen, mode);
      return;
    }
    _opacityLayer.layer = context.pushOpacity(
      offset,
      _alpha,
      (PaintingContext context, Offset offset) =>
          _paintSharp(context, offset, screen, mode),
      oldLayer: _opacityLayer.layer,
    );
  }

  /// The shift across, in this box's coordinates, that puts the origin of
  /// the child snapped by [factor] about the box's center on a whole
  /// device pixel; 0 under a rotation or skew, where no shift aligns it.
  double _alignment(double factor) {
    final s = getTransformTo(null).storage;
    if (s[1] != 0 || s[4] != 0 || s[3] != 0 || s[7] != 0 || s[0] <= 0) {
      return 0;
    }
    final left = size.width / 2 * (1 - factor);
    final x = (s[0] * left + s[12]) / s[15] * _devicePixelRatio;
    return (x.roundToDouble() - x) / (s[0] / s[15] * _devicePixelRatio);
  }

  /// Paints the child unblurred and opaque in [mode] at [screen].
  void _paintSharp(
    PaintingContext context,
    Offset offset,
    double screen,
    MorphGlyphMode mode,
  ) {
    final child = this.child!;
    debugFactor = 1;
    _childTransform.setIdentity();
    if (mode != MorphGlyphMode.raster && !_keepsPyramid) _drop();
    if (mode != MorphGlyphMode.raster) _culledLayer.layer = null;
    switch (mode) {
      case MorphGlyphMode.raster:
        _tracker.settleNext();
        _transformLayer.layer = null;
        final ratio = MorphGlyphScale.rasterRatio(screen, _devicePixelRatio);
        if (!_hasPyramid(ratio)) _rasterizeAt(ratio);
        final (level, at) = _levelFor(screen);
        final origin = _levelOrigins[level];
        final paint = Paint();
        paint.filterQuality = _wantsPyramid
            ? FilterQuality.low
            : FilterQuality.medium;
        paint.color = ui.Color.fromARGB(_alpha, 0, 0, 0);
        context.canvas.drawImageRect(
          _atlas!,
          Rect.fromLTWH(
            origin.dx,
            origin.dy,
            size.width * at,
            size.height * at,
          ),
          offset & size,
          paint,
        );
        _paintCulled(context, offset);
      case MorphGlyphMode.snapped:
        final snapped =
            MorphGlyphScale.snap(
              screen,
              _devicePixelRatio,
              perOctave: _tracker.perOctave,
            ) /
            screen;
        final factor =
            !snapped.isFinite || (snapped - 1).abs() < _exactTolerance
            ? 1.0
            : snapped;
        final shift = _aligned ? _alignment(factor) : 0.0;
        if (factor == 1 && (shift * screen).abs() < _exactShift) {
          // Drawn exactly: no paint is needed to return to live.
          _tracker.drewExact();
          _transformLayer.layer = null;
          _noteGlyphs();
          context.paintChild(child, offset);
          return;
        }
        _tracker.settleNext();
        debugFactor = factor;
        final center = size.center(offset);
        _transform.setIdentity();
        _transform.translateByDouble(center.dx + shift, center.dy, 0, 1);
        _transform.scaleByDouble(factor, factor, 1, 1);
        _transform.translateByDouble(-center.dx, -center.dy, 0, 1);
        final half = size.center(Offset.zero);
        _childTransform.translateByDouble(half.dx + shift, half.dy, 0, 1);
        _childTransform.scaleByDouble(factor, factor, 1, 1);
        _childTransform.translateByDouble(-half.dx, -half.dy, 0, 1);
        _noteGlyphs();
        _transformLayer.layer = context.pushTransform(
          needsCompositing,
          Offset.zero,
          _transform,
          (PaintingContext context, Offset _) =>
              context.paintChild(child, offset),
          oldLayer: _transformLayer.layer,
        );
      case MorphGlyphMode.live || MorphGlyphMode.shaded:
        _transformLayer.layer = null;
        _noteGlyphs();
        context.paintChild(child, offset);
    }
  }

  /// Tells a content source recording this paint for a lens copy how the
  /// child's glyphs are drawn, so the copy can keep them on the grid.
  void _noteGlyphs() => GlassContentSnapshot.noteGlyphs(
    this,
    _childTransform,
    size,
    aligned: _aligned,
  );
}

/// The render object of [MorphVeiledGlyphs]: blurs and fades its child as one
/// draw in the pass it belongs to, without an offscreen layer.
///
/// While it is blurred by half a device pixel or more, or fades, the
/// child is drawn through a single-pass Gaussian shader that also applies
/// the opacity, from the drawing's raster pyramid: each frame reads the
/// finest level the blur spans at most two texels of, so the pyramid
/// lasts while the blur and the scale animate and is taken again only
/// when the child repaints or resizes. A fading child is drawn by the
/// shader at any blur, the smallest at its finest kernel, so a fade never
/// needs a layer of its own; an opaque child blurred less paints sharp as
/// the policy decides.
class _RenderShadedGlyphs extends RenderMorphGlyphs {
  _RenderShadedGlyphs(super.devicePixelRatio);

  /// The largest blur in texels the shader's taps cover.
  static const double _maxSigma = 2;

  /// The smallest blur in texels the shader is given. Its weights are a
  /// Gaussian factor that underflows times a factor that overflows as the
  /// sigma shrinks; under about 0.15 texel their product is 0 times
  /// infinity, NaN, on part of every texel. At 0.2 both stay finite with
  /// margin, and the kernel is still a near-delta.
  static const double _minSigma = 0.2;

  /// The smallest blur, in device pixels, the shader draws on an opaque
  /// child; a smaller one paints sharp, within about a channel step of a
  /// true Gaussian on average. A fading child draws through the shader at
  /// any blur.
  static const double minScreenSigma = 0.5;

  double _blur = 0;
  double _opacity = 1;

  void update(double blur, double opacity, double devicePixelRatio) {
    if (devicePixelRatio != _devicePixelRatio) {
      _devicePixelRatio = devicePixelRatio;
      _blur = blur;
      _opacity = opacity;
      markNeedsPaint();
      return;
    }
    if (blur == _blur && opacity == _opacity) return;
    final repaint = blur != _blur || _shades() || _layerBlur;
    _blur = blur;
    _opacity = opacity;
    // A sharp child only fades: its opacity layer updates without a
    // repaint, as under [Opacity].
    if (repaint || _shades()) {
      _repaint();
    } else {
      markNeedsCompositedLayerUpdate();
    }
  }

  ui.FragmentShader? _shader;

  final LayerHandle<ImageFilterLayer> _filterLayer =
      LayerHandle<ImageFilterLayer>();

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
  void dispose() {
    _shader?.dispose();
    _shader = null;
    _filterLayer.layer = null;
    super.dispose();
  }

  /// Whether the child draws through the shader at the screen scale
  /// [screen] (computed when not given).
  bool _shades([double? screen]) {
    if (MorphGlyphs._program == null ||
        MorphGlyphScale.debugExact ||
        child == null ||
        _opacity <= 0 ||
        !hasSize ||
        size.isEmpty ||
        (_blur <= MorphGlyphs.minBlur && _opacity >= 1)) {
      return false;
    }
    if (_opacity < 1) return true;
    return _blur * (screen ?? _screenScale()) >= minScreenSigma;
  }

  /// Whether the blur paints as a blur layer: only where no shader draws
  /// it (before the shader loads, or when drawing exactly).
  bool get _layerBlur =>
      _blur > MorphGlyphs.minBlur &&
      (MorphGlyphs._program == null || MorphGlyphScale.debugExact);

  /// A blur too small to draw may grow again: its pyramid stays.
  @override
  bool get _keepsPyramid => _blur > MorphGlyphs.minBlur;

  @override
  bool get _wantsPyramid => true;

  @override
  bool _rastersAt(double screen) => _shades(screen) || super._rastersAt(screen);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || _opacity <= 0 || size.isEmpty) {
      _filterLayer.layer = null;
      _dropUnpainted();
      _setShaded(false);
      return;
    }
    _checkChildContent();
    final stable = _advanceStable();
    final screen = _screenScale();
    if (!_shades(screen)) {
      _setShaded(false);
      if (_layerBlur) {
        _culledLayer.layer = null;
        _tracker.observe(screen, settle: false);
        final layer = _filterLayer.layer ??= ImageFilterLayer();
        layer.imageFilter = ui.ImageFilter.blur(
          sigmaX: _blur,
          sigmaY: _blur,
          tileMode: TileMode.decal,
        );
        context.pushLayer(
          layer,
          (PaintingContext context, Offset offset) =>
              context.paintChild(child!, offset),
          offset,
        );
        return;
      }
      _filterLayer.layer = null;
      final mode = _tracker.observe(
        screen,
        canRaster: _canRaster,
        stable: stable,
        settle: false,
      );
      _paintSharp(context, offset, screen, mode);
      return;
    }
    _tracker.observe(screen, settle: false);
    _setShaded(true);
    _filterLayer.layer = null;
    final ratio = MorphGlyphScale.rasterRatio(screen, _devicePixelRatio);
    if (!_hasPyramid(ratio)) _rasterizeAt(ratio);
    final atlas = _atlas!;
    // The finest level the blur spans at most [_maxSigma] texels of, and
    // no finer than about the screen: a coarser level would lose detail
    // the blur keeps, a finer one alias.
    final (level, at) = _levelFor(screen, blur: _blur);
    final origin = _levelOrigins[level];
    // The texels are already a box filter of one texel; the kernel adds
    // the rest, and never less than 0.4 screen pixels, so texels finer or
    // coarser than the screen never show, nor less than [_minSigma].
    final target = math.min(_blur * at, _maxSigma);
    final least = math.max(0.4 * at / screen, _minSigma);
    final sigma = math.sqrt(math.max(target * target - 1 / 12, least * least));
    final shader = _shader ??= MorphGlyphs._program!.fragmentShader();
    shader.setFloat(0, at);
    shader.setFloat(1, origin.dx);
    shader.setFloat(2, origin.dy);
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
    final reach = 3 * _blur + 1 / at;
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
    _paintCulled(context, offset);
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
}
