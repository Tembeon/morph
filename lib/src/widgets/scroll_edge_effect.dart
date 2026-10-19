import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/glass/renderer/internal/backdrop_capture_debug.dart';
import 'package:morph/src/glass/renderer/internal/blur_reach.dart';
import 'package:morph/src/widgets/glass_tier.dart';
import 'package:morph/src/theme/theme.dart';
import 'package:morph/src/theme/glass.dart';

/// Whether the edge effect blurs a copy of the backdrop around its band;
/// off blurs the whole pass behind it, for an A/B.
@visibleForTesting
bool debugMorphEdgeEffectBoundsBlur = true;

/// Whether the edge effect raises a blur just below Impeller's half
/// resolution threshold to it ([morphHalfResolutionSigma]). On by
/// default; `--dart-define=MORPH_EDGE_HALF_RESOLUTION=false` blurs the
/// measured radius at full resolution.
bool debugMorphEdgeEffectHalfResolution = const bool.fromEnvironment(
  'MORPH_EDGE_HALF_RESOLUTION',
  defaultValue: true,
);

/// Whether a fading hard edge effect folds its presence into the
/// saturation matrix after its blur, one color pass instead of two. On by
/// default; `--dart-define=MORPH_EDGE_FOLDED_FADE=false` composes the
/// presence as a matrix of its own.
bool debugMorphEdgeEffectFoldedFade = const bool.fromEnvironment(
  'MORPH_EDGE_FOLDED_FADE',
  defaultValue: true,
);

/// How a [MorphScrollEdgeEffect] separates the content under a bar.
enum MorphScrollEdgeEffectStyle {
  /// UIKit's `.soft` edge effect: a light blur over a band that reaches
  /// past the bar, with a fade toward the background that dissolves
  /// along the lower part of the band.
  soft,

  /// UIKit's `.hard` edge effect (the "thin film" a navigation bar uses
  /// by default): a blur with raised saturation and brightness over the
  /// bar's own band, a uniform fade toward the background and a hairline
  /// at the bar's edge.
  hard,
}

/// The look of a [MorphScrollEdgeEffect].
///
/// The values are UIKit's `PocketSettings` and the layers of
/// `UIKit.ScrollEdgeEffectView` as read on iOS 27: the band reaches
/// [softOverhang] past the bar for the soft style; the soft blur is
/// [softBlurRadius], the hard one [hardBlurRadius] (radii are taken as
/// Gaussian sigmas); the content fades toward [backgroundColor] by
/// [fadeOpacity] (UIKit's "replay" layer re-draws what lies behind the
/// content over it); the soft fade starts to dissolve at [softFadeStart]
/// of the band and is gone at its far end.
@immutable
class MorphScrollEdgeEffectAppearance implements MorphAppearance {
  /// Creates a look; the defaults are the iOS light appearance.
  const MorphScrollEdgeEffectAppearance({
    this.backgroundColor = const Color(0xFFFFFFFF),
    this.fadeOpacity = 0.5,
    this.separatorColor = const Color(0x1A000000),
    this.softBlurRadius = 1.5,
    this.hardBlurRadius = 2,
    this.softOverhang = 40,
    this.softFadeStart = 0.3407,
    this.hardSaturation = 1.25,
    this.hardBrightness = 0.03,
  });

  /// What lies behind the scroll content: the color the content fades
  /// toward under the bar.
  final Color backgroundColor;

  /// How far the content fades toward [backgroundColor]: UIKit's replay
  /// alpha, 0.5 in light mode and 0.6 in dark mode.
  final double fadeOpacity;

  /// The hairline of the hard style: black or white at 10 percent.
  final Color separatorColor;

  /// The blur of the soft style, in logical pixels.
  final double softBlurRadius;

  /// The blur of the hard style, in logical pixels; raised slightly
  /// where that halves its cost (see [MorphScrollEdgeEffect]). UIKit uses
  /// 2 under a navigation bar; a band at the bottom of the screen takes 2
  /// to 2.5 by its height, which this effect does not draw.
  final double hardBlurRadius;

  /// How far the soft band reaches past the bar's edge.
  final double softOverhang;

  /// Where along the soft band, as a fraction from the edge of the
  /// screen, the fade starts to dissolve.
  final double softFadeStart;

  /// The saturation of the content under the hard style.
  final double hardSaturation;

  /// The brightness added to the content under the hard style, as a
  /// fraction of full intensity.
  final double hardBrightness;

  /// The light appearance.
  static const light = MorphScrollEdgeEffectAppearance();

  /// The dark appearance.
  static const dark = MorphScrollEdgeEffectAppearance(
    backgroundColor: Color(0xFF000000),
    fadeOpacity: 0.6,
    separatorColor: Color(0x1AFFFFFF),
  );

  /// Resolves [explicit], then the ambient [MorphTheme], then the
  /// table for the ambient brightness.
  static MorphScrollEdgeEffectAppearance resolve(
    BuildContext context,
    MorphScrollEdgeEffectAppearance? explicit,
  ) =>
      explicit ??
      MorphThemeScope.maybeOf(
        context,
      )?.appearance<MorphScrollEdgeEffectAppearance>() ??
      switch (morphBrightnessOf(context)) {
        Brightness.dark => dark,
        Brightness.light => light,
      };

  /// The color matrix of the hard style: UIKit's saturation matrix
  /// (Rec. 709 luminance) plus the brightness offset.
  List<double> get hardColorMatrix {
    const lr = 0.2126;
    const lg = 0.7152;
    const lb = 0.0722;
    final s = hardSaturation;
    final o = hardBrightness * 255;
    return [
      lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, o, //
      lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, o, //
      lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, o, //
      0, 0, 0, 1, 0,
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is MorphScrollEdgeEffectAppearance &&
      other.backgroundColor == backgroundColor &&
      other.fadeOpacity == fadeOpacity &&
      other.separatorColor == separatorColor &&
      other.softBlurRadius == softBlurRadius &&
      other.hardBlurRadius == hardBlurRadius &&
      other.softOverhang == softOverhang &&
      other.softFadeStart == softFadeStart &&
      other.hardSaturation == hardSaturation &&
      other.hardBrightness == hardBrightness;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    fadeOpacity,
    separatorColor,
    softBlurRadius,
    hardBlurRadius,
    softOverhang,
    softFadeStart,
    hardSaturation,
    hardBrightness,
  );

  /// Copies this appearance with the given fields replaced.
  MorphScrollEdgeEffectAppearance copyWith({
    Color? backgroundColor,
    double? fadeOpacity,
    Color? separatorColor,
    double? softBlurRadius,
    double? hardBlurRadius,
    double? softOverhang,
    double? softFadeStart,
    double? hardSaturation,
    double? hardBrightness,
  }) => MorphScrollEdgeEffectAppearance(
    backgroundColor: backgroundColor ?? this.backgroundColor,
    fadeOpacity: fadeOpacity ?? this.fadeOpacity,
    separatorColor: separatorColor ?? this.separatorColor,
    softBlurRadius: softBlurRadius ?? this.softBlurRadius,
    hardBlurRadius: hardBlurRadius ?? this.hardBlurRadius,
    softOverhang: softOverhang ?? this.softOverhang,
    softFadeStart: softFadeStart ?? this.softFadeStart,
    hardSaturation: hardSaturation ?? this.hardSaturation,
    hardBrightness: hardBrightness ?? this.hardBrightness,
  );
}

/// The iOS 27 scroll edge effect: what replaces a bar's solid background
/// when content scrolls under it.
///
/// Place it over the scroll content, under the bar, filling the area the
/// bar covers. [extent] is the bar's far edge measured from the screen
/// edge (status bar included for a top bar); the soft style reaches
/// [MorphScrollEdgeEffectAppearance.softOverhang] further. The effect
/// shows only while [scrolledUnder] - while content lies under the edge; UIKit
/// switches it on and off from one frame to the next.
///
/// On the flat glass tier only the fade and hairline are drawn. Other
/// tiers copy the backdrop around each band and blur that copy:
/// a band along the edge of the screen blurring the pass itself makes
/// Impeller blur the whole pass, at full resolution for this sigma.
///
/// A blur just below the sigma Impeller blurs at half resolution is
/// raised to it, by at most 12 percent: the hard style's 2 points become
/// 2.17 at a device pixel ratio of 2.625 (a Pixel 6a), where the full
/// resolution blur of 5.2 device pixels costs about three times the half
/// resolution one. NEAR: the band differs from the measured blur by a
/// median of 4 and at most 19 channel steps along sharp edges under the
/// fade (host Impeller). Nothing changes at 3x, where 2 points already
/// blur at half resolution, nor for the soft style's 1.5 points at 2x to
/// 3x, which would need more than 12 percent. UIKit blurs the band at half
/// resolution too: its blur reads a backdrop captured at scale 0.5 (read
/// from UIKit, notes private, iOS 27.0 simulator), and the blur is uniform
/// over the band (its mask is opaque).
class MorphScrollEdgeEffect extends StatelessWidget {
  /// Creates the effect for the [edge] of a scroll view.
  const MorphScrollEdgeEffect({
    required this.extent,
    this.edge = AxisDirection.up,
    this.style = MorphScrollEdgeEffectStyle.soft,
    this.scrolledUnder = true,
    this.appearance,
    double opacity = 1,
    super.key,
  }) : assert(
         edge == AxisDirection.up || edge == AxisDirection.down,
         'The scroll edge effect draws only the top and bottom edges.',
       ),
       _opacity = null,
       _fixedOpacity = opacity,
       _repaint = null;

  /// Creates the effect whose presence [opacity] reports at paint time,
  /// repainted whenever [repaint] notifies: a fade that rebuilds nothing.
  @internal
  const MorphScrollEdgeEffect.driven({
    required this.extent,
    required double Function() this._opacity,
    required Listenable this._repaint,
    this.edge = AxisDirection.up,
    this.style = MorphScrollEdgeEffectStyle.soft,
    this.scrolledUnder = true,
    this.appearance,
    super.key,
  }) : assert(
         edge == AxisDirection.up || edge == AxisDirection.down,
         'The scroll edge effect draws only the top and bottom edges.',
       ),
       _fixedOpacity = 1;

  /// The distance from the screen edge to the bar's far edge.
  final double extent;

  /// The edge of the scroll view: [AxisDirection.up] for a navigation
  /// bar, [AxisDirection.down] for a toolbar. Only these two vertical
  /// edges are drawn; a horizontal one fails an assertion.
  final AxisDirection edge;

  /// The style of the effect (UIKit `UIScrollEdgeEffect.Style`).
  final MorphScrollEdgeEffectStyle style;

  /// Whether content lies under the edge, as a navigation bar's
  /// `scrolledUnder`.
  final bool scrolledUnder;

  /// The look; null resolves it from the theme.
  final MorphScrollEdgeEffectAppearance? appearance;

  final double Function()? _opacity;
  final double _fixedOpacity;
  final Listenable? _repaint;

  /// How present the effect is, 0 to 1, as UIKit fades the effect's view.
  ///
  /// The blurred backdrop fades with the rest of the effect. Fade the
  /// effect here rather than through an [Opacity] above it: inside an
  /// opacity layer the blur reads an empty backdrop, so the content under
  /// the bar would show sharp until the fade ends.
  double get opacity => (_opacity?.call() ?? _fixedOpacity).clamp(0.0, 1.0);

  /// The height of the band the effect covers for [style] under a bar
  /// reaching [extent].
  static double bandExtent(
    MorphScrollEdgeEffectStyle style,
    double extent,
    MorphScrollEdgeEffectAppearance appearance,
  ) => switch (style) {
    MorphScrollEdgeEffectStyle.soft => extent + appearance.softOverhang,
    MorphScrollEdgeEffectStyle.hard => extent,
  };

  @override
  Widget build(BuildContext context) {
    if (!scrolledUnder ||
        extent <= 0 ||
        (_opacity == null && _fixedOpacity <= 0)) {
      return const SizedBox.shrink();
    }
    final look = MorphScrollEdgeEffectAppearance.resolve(context, appearance);
    final band = bandExtent(style, extent, look);
    final top = edge == AxisDirection.up;
    return RepaintBoundary(
      child: IgnorePointer(
        child: Align(
          alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
          child: SizedBox(
            height: band,
            width: double.infinity,
            child: _EdgePaint(
              blurs: GlassAdaptiveScope.tierOf(context) != MorphGlassTier.flat,
              style: style,
              top: top,
              look: look,
              opacity: _opacity ?? () => _fixedOpacity,
              repaint: _repaint,
              devicePixelRatio:
                  MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgePaint extends LeafRenderObjectWidget {
  const _EdgePaint({
    required this.blurs,
    required this.style,
    required this.top,
    required this.look,
    required this.opacity,
    required this.repaint,
    required this.devicePixelRatio,
  });

  final bool blurs;
  final MorphScrollEdgeEffectStyle style;
  final bool top;
  final MorphScrollEdgeEffectAppearance look;
  final double Function() opacity;
  final Listenable? repaint;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderEdge(
    blurs: blurs,
    style: style,
    top: top,
    look: look,
    opacity: opacity,
    repaint: repaint,
    hairline: 1 / devicePixelRatio,
    devicePixelRatio: devicePixelRatio,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderEdge renderObject) {
    renderObject.blurs = blurs;
    renderObject.style = style;
    renderObject.top = top;
    renderObject.look = look;
    renderObject.opacity = opacity;
    renderObject.repaint = repaint;
    renderObject.hairline = 1 / devicePixelRatio;
    renderObject.devicePixelRatio = devicePixelRatio;
  }
}

/// The blur, the fade toward the background and the hairline of the
/// effect, faded as one by the alpha of the blurred backdrop and of the
/// paint over it, with no opacity layer above the blur; the blur reads a
/// copy of the backdrop as far around the band as its kernel reaches.
class _RenderEdge extends RenderBox {
  _RenderEdge({
    required this._blurs,
    required this._style,
    required this._top,
    required this._look,
    required this._opacity,
    required this._repaint,
    required this._hairline,
    required this._devicePixelRatio,
  });

  final LayerHandle<ClipRectLayer> _seedClip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _seed =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();
  final LayerHandle<BackdropFilterLayer> _blur =
      LayerHandle<BackdropFilterLayer>();
  final LayerHandle<OpacityLayer> _fade = LayerHandle<OpacityLayer>();

  bool _blurs;
  bool get blurs => _blurs;
  set blurs(bool value) {
    if (value == _blurs) return;
    _blurs = value;
    markNeedsPaint();
  }

  MorphScrollEdgeEffectStyle _style;
  MorphScrollEdgeEffectStyle get style => _style;
  set style(MorphScrollEdgeEffectStyle value) {
    if (value == _style) return;
    _style = value;
    markNeedsPaint();
  }

  bool _top;
  bool get top => _top;
  set top(bool value) {
    if (value == _top) return;
    _top = value;
    markNeedsPaint();
  }

  MorphScrollEdgeEffectAppearance _look;
  MorphScrollEdgeEffectAppearance get look => _look;
  set look(MorphScrollEdgeEffectAppearance value) {
    if (value == _look) return;
    _look = value;
    markNeedsPaint();
  }

  double Function() _opacity;
  double Function() get opacity => _opacity;
  set opacity(double Function() value) {
    _opacity = value;
    _tick();
  }

  Listenable? _repaint;
  Listenable? get repaint => _repaint;
  set repaint(Listenable? value) {
    if (value == _repaint) return;
    if (attached) _repaint?.removeListener(_tick);
    _repaint = value;
    if (attached) _repaint?.addListener(_tick);
    markNeedsPaint();
  }

  double _hairline;
  double get hairline => _hairline;
  set hairline(double value) {
    if (value == _hairline) return;
    _hairline = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint?.addListener(_tick);
  }

  double? _painted;

  void _tick() {
    final presence = _opacity().clamp(0.0, 1.0);
    final painted = _painted;
    if (presence == painted) return;
    final blur = _blur.layer;
    final fade = _fade.layer;
    if (painted == null ||
        painted <= 0.001 ||
        presence <= 0.001 ||
        (_blurs && blur == null) ||
        fade == null) {
      markNeedsPaint();
      return;
    }
    _painted = presence;
    if (_blurs) blur!.filter = _filter(presence);
    fade.alpha = Color.getAlphaFromOpacity(presence);
    markNeedsCompositedLayerUpdate();
  }

  @override
  void detach() {
    _repaint?.removeListener(_tick);
    super.detach();
  }

  @override
  void dispose() {
    _seedClip.layer = null;
    _seed.layer = null;
    _clip.layer = null;
    _blur.layer = null;
    _fade.layer = null;
    super.dispose();
  }

  @override
  bool get sizedByParent => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool get isRepaintBoundary => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => false;

  /// The sigma the band is blurred with: the style's radius, raised to
  /// Impeller's half resolution blur when that is invisible.
  double get _sigma {
    final radius = switch (_style) {
      MorphScrollEdgeEffectStyle.soft => _look.softBlurRadius,
      MorphScrollEdgeEffectStyle.hard => _look.hardBlurRadius,
    };
    if (!debugMorphEdgeEffectHalfResolution) return radius;
    return morphHalfResolutionSigma(radius, _devicePixelRatio);
  }

  ui.ImageFilter _filter(double presence) {
    final sigma = _sigma;
    final ui.ImageFilter blur = ui.ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
    );
    final hard = _style == MorphScrollEdgeEffectStyle.hard;
    if (hard && debugMorphEdgeEffectFoldedFade) {
      final matrix = _look.hardColorMatrix;
      matrix[18] = presence;
      return ui.ImageFilter.compose(
        outer: ui.ColorFilter.matrix(matrix),
        inner: blur,
      );
    }
    final ui.ImageFilter look = hard
        ? ui.ImageFilter.compose(
            outer: ui.ColorFilter.matrix(_look.hardColorMatrix),
            inner: blur,
          )
        : blur;
    if (presence == 1) return look;
    return ui.ImageFilter.compose(
      outer: ui.ColorFilter.matrix(<double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, presence, 0,
      ]),
      inner: look,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final presence = _opacity().clamp(0.0, 1.0);
    _painted = presence;
    if (presence <= 0.001) {
      _seedClip.layer = null;
      _seed.layer = null;
      _clip.layer = null;
      _blur.layer = null;
      _fade.layer = null;
      return;
    }
    final box = offset & size;
    if (!_blurs) {
      _seedClip.layer = null;
      _seed.layer = null;
      _clip.layer = null;
      _blur.layer = null;
      _fade.layer = context.pushOpacity(
        offset,
        Color.getAlphaFromOpacity(presence),
        (PaintingContext context, Offset _) => _paintFade(context.canvas, box),
        oldLayer: _fade.layer,
      );
      return;
    }
    void band(PaintingContext context, Offset offset) {
      _clip.layer = context.pushClipRect(true, offset, Offset.zero & size, (
        PaintingContext context,
        Offset offset,
      ) {
        final blur = _blur.layer ??= BackdropFilterLayer();
        GlassLayerOwners.note(blur, this);
        blur.filter = _filter(presence);
        context.pushLayer(blur, (PaintingContext context, Offset offset) {
          _fade.layer = context.pushOpacity(
            offset,
            Color.getAlphaFromOpacity(presence),
            (PaintingContext context, Offset _) =>
                _paintFade(context.canvas, box),
            oldLayer: _fade.layer,
          );
        }, offset);
      }, oldLayer: _clip.layer);
    }

    if (!debugMorphEdgeEffectBoundsBlur) {
      _seedClip.layer = null;
      _seed.layer = null;
      band(context, offset);
      return;
    }
    final reach = morphBlurReach(_sigma, _devicePixelRatio);
    final seed = _seed.layer ??= BackdropFilterLayer(
      filter: morphBackdropSeed,
      blendMode: BlendMode.src,
    );
    GlassLayerOwners.note(seed, this);
    _seedClip.layer = context.pushClipRect(
      true,
      offset,
      (Offset.zero & size).inflate(reach),
      (PaintingContext context, Offset offset) =>
          context.pushLayer(seed, band, offset),
      oldLayer: _seedClip.layer,
    );
  }

  void _paintFade(Canvas canvas, Rect box) {
    final fade = _look.backgroundColor.withValues(
      alpha: _look.backgroundColor.a * _look.fadeOpacity,
    );
    final paint = Paint();
    switch (_style) {
      case MorphScrollEdgeEffectStyle.soft:
        paint.shader = LinearGradient(
          begin: _top ? Alignment.topCenter : Alignment.bottomCenter,
          end: _top ? Alignment.bottomCenter : Alignment.topCenter,
          colors: [fade, fade, fade.withValues(alpha: 0)],
          stops: [0, _look.softFadeStart, 1],
        ).createShader(box);
        canvas.drawRect(box, paint);
      case MorphScrollEdgeEffectStyle.hard:
        paint.color = fade;
        canvas.drawRect(box, paint);
        paint.color = _look.separatorColor;
        canvas.drawRect(
          _top
              ? Rect.fromLTRB(
                  box.left,
                  box.bottom - _hairline,
                  box.right,
                  box.bottom,
                )
              : Rect.fromLTRB(
                  box.left,
                  box.top,
                  box.right,
                  box.top + _hairline,
                ),
          paint,
        );
    }
  }
}
