import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/glass/renderer/internal/content_snapshot.dart';
import 'package:morph/src/glass/renderer/internal/glass_live.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart';
import 'package:morph/src/glass/renderer/internal/liquid_capability.dart';
import 'package:morph/src/glass/renderer/internal/multi_shader_builder.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/glass/renderer/liquid_glass.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_body_shadow.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/glass/renderer/internal/glass_defaults.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

final LiquidCapability _capability = LiquidCapability(
  load: () async {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      throw UnsupportedError('Impeller shader filters are unavailable.');
    }
    final geometry = await FlutterGpuGeometryRenderer.fromAsset(
      ShaderKeys.gpuGeometryShaderBundle,
    );
    geometry.dispose();
    await MultiShaderBuilder.precacheShaders([
      ShaderKeys.liquidGlassRender,
      ShaderKeys.liquidGlassMaterialRender,
      ShaderKeys.liquidGlassTintRender,
    ]);
  },
);

/// Whether the GPU context and all liquid shaders are ready.
@internal
bool get morphLiquidGlassAvailable {
  if (isLocalTest) return true;
  unawaited(_capability.precache());
  return _capability.value;
}

/// The cached runtime initialization failure, or null before failure.
@internal
String? get morphLiquidGlassUnavailableReason =>
    isLocalTest ? null : _capability.unavailableReason;

/// Notifies when runtime shader initialization completes successfully.
@internal
ValueListenable<bool> get morphLiquidGlassCapability => _capability;

/// Resolves runtime availability without throwing on unsupported devices.
@internal
Future<void> morphPrecacheLiquidGlass() => _capability.precache();

LiquidGlassSettings _preset(
  MorphGlassRenderer renderer,
  Brightness brightness,
) => switch (renderer.material) {
  MorphGlassMaterial.regular => LiquidGlassSettings(
    frost: LiquidGlassSettings.ios27RegularFrost(renderer.tint),
    tintAmount: renderer.tint,
  ),
  MorphGlassMaterial.toolbar => LiquidGlassSettings.ios27Toolbar(
    brightness: brightness,
    tintAmount: renderer.tint,
  ),
  MorphGlassMaterial.clear => LiquidGlassSettings.ios27Clear(
    tintAmount: renderer.tint,
  ),
};

/// The renderer settings of [surface] on the liquid tier: the material
/// preset scaled by [renderer]'s factors, with a lens's optics
/// interpolated by its lift.
@internal
LiquidGlassSettings morphLiquidSettings(
  MorphGlassRenderer renderer,
  MorphGlassSurface surface,
) {
  final preset = _preset(renderer, surface.brightness);
  final optics = surface.optics;
  final lift = surface.lift.clamp(0.0, 1.0);
  final frosted =
      renderer.frostControls ||
      surface.kind == MorphGlassKind.bar ||
      surface.kind == MorphGlassKind.menu;
  final frost =
      surface.blurRadius ??
      (optics != null
          ? optics.blurRadiusAt(lift)
          : frosted
          ? preset.frost
          : 0.0);
  final amount = optics == null
      ? preset.refractionAmount
      : optics.displacementAt(lift) * MorphGlassRenderer.lensRefraction;
  return preset.copyWith(
    frost: frost * renderer.blur,
    refractionAmount: amount * renderer.refraction,
    dispersion: optics == null
        ? preset.dispersion
        : MorphGlassRenderer.lensDispersion * lift,
    highlight:
        preset.highlight *
        renderer.light *
        (1 + MorphGlassDefaults.liftedHighlight * lift),
  );
}

/// The renderer appearance of [surface], tinted by its flat color.
///
/// A lifted lens, knob or thumb is clear glass: no wash and no tint, so
/// what lies under it - a track, a bar's glass - shows through at its own
/// brightness, as through UIKit's lifted lens.
@internal
LiquidGlassAppearance morphLiquidAppearance(
  MorphGlassRenderer renderer,
  MorphGlassSurface surface,
) => MorphGlassRenderer.floats(surface.kind)
    ? const LiquidGlassAppearance()
    : (switch (renderer.material) {
        MorphGlassMaterial.regular => LiquidGlassAppearance.ios27Regular(
          brightness: surface.brightness,
          tint: surface.tint ?? surface.color,
        ),
        MorphGlassMaterial.toolbar => LiquidGlassAppearance.ios27Toolbar(
          brightness: surface.brightness,
          tint: surface.tint ?? surface.color,
        ),
        MorphGlassMaterial.clear => LiquidGlassAppearance.ios27Clear(
          tint: surface.tint ?? surface.color,
        ),
      }).copyWith(transmissionGamma: surface.transmissionGamma);

/// Half the center line a lens with [bounds] shrinks the backdrop about
/// at rim weight [rim], from the lens center along its longer side.
@internal
Offset morphShrinkAxis(Rect bounds, double rim) {
  final half = rim * (bounds.longestSide - bounds.shortestSide) / 2;
  return bounds.width >= bounds.height ? Offset(half, 0) : Offset(0, half);
}

/// How far from its center [surface]'s glass reads the backdrop for a
/// point on its face when its layer shrinks the backdrop by [shrink].
///
/// The renderer fades the shrink in with the glass's visibility, so a
/// lens still turning from platter into glass shrinks less.
@internal
double morphBackdropScale(MorphGlassSurface surface, double shrink) =>
    1 +
    (1 / (1 - shrink) - 1) *
        MorphGlassRenderer.glassness(surface) *
        surface.opacity.clamp(0.0, 1.0);

LiquidShape _shape(RRect shape, {bool exact = false}) {
  final side = math.min(shape.width, shape.height);
  final radius = math.min(shape.tlRadiusX, side / 2);
  if (shape.width == shape.height && radius >= side / 2) {
    return const LiquidOval();
  }
  return exact
      ? LiquidRoundedRectangle(borderRadius: radius)
      : LiquidRoundedSuperellipse(borderRadius: radius);
}

List<BoxShadow> _shadows(MorphGlassSurface surface) =>
    surface.shadows ??
    switch (surface.kind) {
      MorphGlassKind.track || MorphGlassKind.bar => const [],
      MorphGlassKind.button ||
      MorphGlassKind.menu => const [MorphGlassDefaults.bodyShadow],
      MorphGlassKind.lens || MorphGlassKind.knob || MorphGlassKind.thumb => [
        BoxShadow(
          color: MorphGlassDefaults.floatingShadowColor,
          offset: Offset(
            0,
            MorphGlassDefaults.floatingShadowOffset +
                MorphGlassDefaults.floatingLiftOffset * surface.lift,
          ),
          blurRadius:
              MorphGlassDefaults.floatingShadowBlur +
              MorphGlassDefaults.floatingLiftBlur * surface.lift,
        ),
      ],
    };

LiquidGlassShapeFrame _shapeFrame(
  MorphGlassRenderer renderer,
  MorphGlassSurface surface, {
  required bool shadows,
  required bool exact,
}) {
  final base = morphLiquidAppearance(renderer, surface);
  return LiquidGlassShapeFrame(
    shape: _shape(surface.localShape, exact: exact),
    appearance: base.copyWith(
      visibility:
          base.visibility *
          MorphGlassRenderer.glassness(surface) *
          surface.opacity.clamp(0.0, 1.0),
    ),
    shadows: shadows ? _shadows(surface) : const [],
  );
}

/// One glass layer of the surfaces [select] picks, each its own shape, or
/// one body shaded from [field] when it is given; [exact] shapes are the
/// surfaces' own circular rounded boxes instead of continuous corners. A
/// lifted lens's layer shrinks its backdrop by [shrink] about a center
/// line of [rim] weight.
Widget _layer(
  MorphGlassRenderer renderer,
  MorphGlassSource source,
  List<MorphGlassSurface> Function(MorphGlassFrame frame) select, {
  bool shared = true,
  double Function(MorphGlassSurface surface)? shrink,
  double rim = 0,
  GlassField? Function(MorphGlassFrame frame)? field,
  bool shadows = true,
  bool exact = false,
}) {
  final count = select(source.frame).length;
  final settings = source.pick((f) {
    final surface = select(f).first;
    final settings = morphLiquidSettings(renderer, surface);
    final amount = shrink?.call(surface) ?? 0;
    return amount == 0
        ? settings
        : settings.copyWith(backdropShrink: amount, backdropShrinkRim: rim);
  });
  final fieldOf = field == null ? null : source.pick(field);
  return ClipRect(
    clipper: const _Reach(),
    child: LiquidGlassLayer.live(
      live: source.live,
      settingsOf: () => settings.value,
      fieldOf: fieldOf == null ? null : () => fieldOf.value,
      useBackdropGroup: shared,
      child: MorphLiveStack(
        live: source.live,
        children: [
          for (var i = 0; i < count; i++)
            MorphLivePositioned(
              rect: source.pick((f) => select(f)[i].bounds),
              child: LiquidGlass.live(
                live: source.pick(
                  (f) => _shapeFrame(
                    renderer,
                    select(f)[i],
                    shadows: shadows,
                    exact: exact,
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    ),
  );
}

MorphGlassSurface _local(MorphGlassSurface surface) => MorphGlassSurface(
  kind: surface.kind,
  shape: surface.localShape,
  color: surface.color,
  brightness: surface.brightness,
  lift: surface.lift,
  scaleX: surface.scaleX,
  scaleY: surface.scaleY,
  optics: surface.optics,
  blurRadius: surface.blurRadius,
  tint: surface.tint,
  transmissionGamma: surface.transmissionGamma,
  enabled: surface.enabled,
  glass: surface.glass,
  opacity: surface.opacity,
  shadows: surface.shadows,
);

/// One glass surface on the liquid tier, the one [select] picks from
/// [source], sized to its bounds.
@internal
Widget morphLiquidSurface(
  MorphGlassRenderer renderer,
  BuildContext context,
  MorphGlassSource source,
  MorphGlassSurface Function(MorphGlassFrame frame) select,
) => _layer(
  renderer,
  source,
  (f) => [_local(select(f))],
  shared: !_chrome(select(source.frame)),
);

/// One fused glass body on the liquid tier, the one [select] picks from
/// [source], filling its layer's box.
///
/// A body the package fused carries its distance field and is shaded from
/// it, neck included. A plain union is shaded from its surfaces' own
/// rounded boxes, the nearest one at every point, exactly the field it
/// would sample. An outline built from a path alone has no field: its
/// surfaces are shaded as their own shapes, clipped to the outline, and
/// frost fills the rest of it.
@internal
Widget morphLiquidBody(
  MorphGlassRenderer renderer,
  BuildContext context,
  MorphGlassSource source,
  (List<MorphGlassSurface>, MorphGlassOutline) Function(MorphGlassFrame f)
  select,
) {
  final (surfaces, outline) = select(source.frame);
  final chrome = surfaces.any(_chrome);
  final field = morphGlassOutlineField(outline);
  final exact = morphGlassOutlineShapes(outline) != null;
  List<MorphGlassSurface> members(MorphGlassFrame f) => select(f).$1;
  if (field != null || exact) {
    return CustomPaint(
      painter: MorphGlassBodyShadow.live(
        source.pick((f) {
          final (surfaces, outline) = select(f);
          return (
            outline.path,
            _shadows(surfaces.first),
            surfaces.first.opacity.clamp(0.0, 1.0),
          );
        }),
      ),
      child: _layer(
        renderer,
        source,
        members,
        shared: !chrome,
        field: (f) => morphGlassOutlineField(select(f).$2),
        shadows: false,
        exact: exact,
      ),
    );
  }
  return ClipPath(
    clipper: morphGlassOutlineClip(source, (f) => select(f).$2.path),
    child: Stack(
      fit: StackFit.expand,
      children: [
        _Frost(
          color: source.pick((f) {
            final surface = select(f).$1.first;
            return surface.color.withValues(
              alpha: surface.color.a * surface.opacity.clamp(0.0, 1.0),
            );
          }),
          sigma: renderer.blur * MorphGlassDefaults.chromeFrost,
          shared: !chrome,
        ),
        _layer(renderer, source, members, shared: !chrome),
      ],
    ),
  );
}

bool _chrome(MorphGlassSurface s) =>
    s.kind == MorphGlassKind.bar || s.kind == MorphGlassKind.menu;

class _LensRects {
  const _LensRects(this.lenses);

  final List<RRect> lenses;

  @override
  bool operator ==(Object other) =>
      other is _LensRects && _LensClip._same(other.lenses, lenses);

  @override
  int get hashCode => Object.hashAll(lenses);
}

/// One layer of a control on the liquid tier, built from [source].
///
/// A control's glass body surfaces share a layer: the ones drawn as their
/// own shapes one layer, each fused body a layer of its own shaded from
/// its outline. A body that fuses and comes apart again (a menu and its
/// button) keeps one layer throughout, so its glass never restarts. Every
/// backdrop copy is a full-screen readback, so body glass reads the one
/// copy of the nearest [BackdropGroup] and only lifted glass, which must
/// refract the glass and content under it, and chrome that floats over
/// content (a bar, a menu) pay for their own. Glass in one group does not
/// see what paints between its members: give a section painted over the
/// page (a card) a group of its own.
///
/// A lifted lens shows the content once more inside its outline, each
/// item grown about its own slot by the lens's magnification and against
/// the backdrop shrink, below the lens glass, which then bends it and the
/// rim of what it floats over at its bevel as UIKit's lens does.
///
/// Every part but the content is kept for the source's structure, so a
/// rebuild around new content leaves the glass widgets untouched.
@internal
Widget morphLiquidLayer(
  MorphGlassRenderer renderer,
  BuildContext context,
  MorphGlassSource source, {
  Widget? content,
}) {
  final parts = source.frame.parts;
  final body = parts.body;
  final floating = parts.floating;
  final chrome = body.any(_chrome);
  bool lifted(MorphGlassSurface s) => s.lift > MorphGlassRenderer.restingLift;
  final overBar = body.any((s) => s.kind == MorphGlassKind.bar);
  ({double magnification, double shrink, double rim}) optics(
    MorphGlassSurface s,
  ) => MorphGlassRenderer.liftedOptics(s.kind, overBar: overBar);
  double shrinkOf(MorphGlassSurface s) =>
      optics(s).shrink * s.lift.clamp(0.0, 1.0);
  final lensed = [
    for (final (i, s) in floating.indexed)
      if (s.kind == MorphGlassKind.lens && lifted(s)) i,
  ];
  List<RRect> lenses(MorphGlassFrame f) => [
    for (final i in lensed) f.parts.floating[i].shape,
  ];
  final snapshot = source.keep('snapshot', GlassContentSnapshot.new);
  Widget at(
    (String, int) slot,
    Rect Function(MorphGlassFrame f) rect,
    Widget Function() child,
  ) => source.keep(
    slot,
    () => MorphLivePositioned(
      key: ValueKey<(String, int)>(slot),
      rect: source.pick(rect),
      child: child(),
    ),
  );
  Widget fill(Object slot, Key key, Widget Function() child) =>
      source.keep(slot, () => Positioned.fill(key: key, child: child()));
  final live = source.live;
  return MorphLiveStack(
    live: live,
    children: [
      for (var i = 0; i < parts.fills.length; i++)
        at(
          ('fill', i),
          (f) => f.parts.fills[i].bounds,
          () => renderer.liveFill(context, source, (f) => f.parts.fills[i]),
        ),
      if (parts.separate.isNotEmpty)
        fill(
          'separate',
          parts.fused.isEmpty
              ? const ValueKey<String>('body')
              : const ValueKey<String>('separate'),
          () => _layer(
            renderer,
            source,
            (f) => f.parts.separate,
            shared: !chrome,
          ),
        ),
      for (var i = 0; i < parts.fused.length; i++)
        fill(
          ('fused', i),
          i == 0
              ? const ValueKey<String>('body')
              : ValueKey<(String, int)>(('fused', i)),
          () => morphLiquidBody(
            renderer,
            context,
            source,
            (f) => f.parts.fused[i],
          ),
        ),
      for (final (i, surface) in body.indexed)
        if (surface.glow != null)
          at(
            ('glow', i),
            (f) => f.parts.body[i].bounds,
            () => renderer.liveGlow(context, source, (f) => f.parts.body[i]),
          ),
      for (final (i, surface) in floating.indexed)
        if (MorphGlassRenderer.glassness(surface) < 1)
          at(
            ('platter', i),
            (f) => f.parts.floating[i].bounds,
            () => _Platter(source: source, select: (f) => f.parts.floating[i]),
          ),
      if (content != null)
        Positioned.fill(
          key: const ValueKey<String>('content'),
          child: ClipPath(
            clipBehavior: lensed.isEmpty ? Clip.none : Clip.antiAlias,
            clipper: live == null
                ? _LensClip(lenses(source.frame), outside: true)
                : source.keep('lens clip', () {
                    final picked = source.pick(lenses);
                    return GlassLiveClipper<Path>(
                      live: live,
                      keyOf: () => _LensRects(picked.value),
                      clipOf: (Size size) =>
                          _LensClip(picked.value, outside: true).getClip(size),
                    );
                  }),
            child: GlassContentSource(
              snapshot: snapshot,
              capture: lensed.isNotEmpty,
              live: live,
              child: content,
            ),
          ),
        ),
      for (final (i, surface) in floating.indexed)
        if (lifted(surface)) ...[
          if (content != null && surface.kind == MorphGlassKind.lens)
            fill(
              ('copy', i),
              ValueKey<(String, int)>(('copy', i)),
              () => MorphGlassContentCopy(
                frame: source.pick((f) {
                  final lens = f.parts.floating[i];
                  final lensOptics = optics(lens);
                  return MorphGlassCopyFrame(
                    surface: lens,
                    slots: f.contentSlots,
                    magnification:
                        1 +
                        lensOptics.magnification * lens.lift.clamp(0.0, 1.0),
                    grow: morphBackdropScale(lens, shrinkOf(lens)),
                    axis: morphShrinkAxis(lens.bounds, lensOptics.rim),
                  );
                }),
                snapshot: snapshot,
              ),
            ),
          fill(
            ('glass', i),
            ValueKey<(String, int)>(('glass', i)),
            () => _layer(
              renderer,
              source,
              (f) => [f.parts.floating[i]],
              shared: false,
              shrink: shrinkOf,
              rim: optics(surface).rim,
            ),
          ),
        ],
    ],
  );
}

/// Frosted glass over the whole box: the backdrop blurred by [sigma] and
/// tinted by [color].
class _Frost extends StatelessWidget {
  const _Frost({
    required this.color,
    required this.sigma,
    required this.shared,
  });

  final ValueListenable<Color> color;
  final double sigma;
  final bool shared;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      backdropGroupKey: shared ? BackdropGroup.of(context)?.backdropKey : null,
      filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: MorphLiveColoredBox(color: color),
    );
  }
}

/// A resting lens, knob or thumb: an opaque platter, as UIKit draws one
/// until the finger lifts it into glass.
class _Platter extends StatelessWidget {
  const _Platter({required this.source, required this.select});

  final MorphGlassSource source;
  final MorphGlassSurface Function(MorphGlassFrame frame) select;

  @override
  Widget build(BuildContext context) {
    final surface = source.pick(select);
    return GlassLiveOpacity(
      live: source.live,
      opacityOf: () => 1 - MorphGlassRenderer.glassness(surface.value),
      child: MorphLiveDecoratedBox(
        live: source.pick((f) {
          final surface = select(f);
          final shape = surface.localShape;
          return BoxDecoration(
            color: surface.color,
            borderRadius: BorderRadius.only(
              topLeft: shape.tlRadius,
              topRight: shape.trRadius,
              bottomLeft: shape.blRadius,
              bottomRight: shape.brRadius,
            ),
            boxShadow: _shadows(surface),
          );
        }),
      ),
    );
  }
}

/// What a lens's content copy shows in one frame.
@internal
@immutable
class MorphGlassCopyFrame {
  /// Describes one frame of a lens copy.
  const MorphGlassCopyFrame({
    required this.surface,
    required this.slots,
    required this.magnification,
    required this.grow,
    required this.axis,
  });

  /// The lifted lens in the control's coordinates.
  final MorphGlassSurface surface;

  /// The item slots whose centers anchor magnification.
  final List<Rect> slots;

  /// The content scale about each slot's center.
  final double magnification;

  /// The compensation for the glass's backdrop shrink.
  final double grow;

  /// Half the center line of the lens's rim warp.
  final Offset axis;
}

/// The content seen through a lens: each item scaled by [magnification]
/// about the center of its own slot and clipped to that slot and the lens.
///
/// The anchors are the slots, which stay put, so a label under a moving
/// lens grows in place and only the lens window slides over it, as in
/// UIKit; scaling about the lens center would carry the label along with
/// the lens.
///
/// The lens glass reads its backdrop [grow] times farther from the
/// nearest point of its center line (half of it is [axis], from the lens
/// center) than it shows it, so the copy is grown by [grow] about that
/// line first - across it beside the line, radially about each end beyond
/// it, each part exact in its own strip - and through the glass each item
/// still shows on its slot.
@internal
class MorphGlassContentCopy extends StatelessWidget {
  /// Replays one source through the slot and rim transforms of a lens,
  /// repainting on every frame of [frame].
  const MorphGlassContentCopy({
    required this.frame,
    required this.snapshot,
    super.key,
  });

  /// The lens and its transforms now.
  final ValueListenable<MorphGlassCopyFrame> frame;

  /// The lifted lens in the control's coordinates.
  MorphGlassSurface get surface => frame.value.surface;

  /// The item slots whose centers anchor magnification.
  List<Rect> get slots => frame.value.slots;

  /// The content scale about each slot's center.
  double get magnification => frame.value.magnification;

  /// The compensation for the glass's backdrop shrink.
  double get grow => frame.value.grow;

  /// Half the center line of the lens's rim warp.
  Offset get axis => frame.value.axis;

  /// The single mounted content's current paint.
  final GlassContentSnapshot snapshot;

  static Matrix4 _about(Offset center, double scale) {
    final transform = Matrix4.translationValues(center.dx, center.dy, 0);
    transform.multiply(Matrix4.diagonal3Values(scale, scale, 1));
    transform.multiply(Matrix4.translationValues(-center.dx, -center.dy, 0));
    return transform;
  }

  Matrix4 _growth(int strip) {
    final center = surface.bounds.center;
    if (axis == Offset.zero) return _about(center, grow);
    if (strip == 0) return _about(center - axis, grow);
    if (strip == 2) return _about(center + axis, grow);
    final transform = Matrix4.translationValues(center.dx, center.dy, 0);
    transform.multiply(
      Matrix4.diagonal3Values(
        axis.dx == 0 ? grow : 1,
        axis.dy == 0 ? grow : 1,
        1,
      ),
    );
    transform.multiply(Matrix4.translationValues(-center.dx, -center.dy, 0));
    return transform;
  }

  /// The painted transform for an item in [slot] through [strip].
  Matrix4 transformFor(Rect slot, int strip) {
    final transform = _growth(strip);
    transform.multiply(_about(slot.center, magnification));
    return transform;
  }

  /// The painted bounds of [rect] in [slot], before the glass's warp.
  @visibleForTesting
  Rect transformedRect(Rect rect, Rect slot, int strip) =>
      MatrixUtils.transformRect(transformFor(slot, strip), rect);

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: CustomPaint(painter: _ContentCopyPainter(this)),
    ),
  );
}

class _ContentCopyPainter extends CustomPainter {
  _ContentCopyPainter(this.copy)
    : super(
        repaint: copy.frame is GlassFixed<MorphGlassCopyFrame>
            ? null
            : copy.frame,
      );

  final MorphGlassContentCopy copy;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = copy.surface.bounds;
    final center = bounds.center;
    final axis = copy.axis;
    final start = center - axis;
    final end = center + axis;
    final reach = bounds.inflate(bounds.longestSide * copy.grow);
    final alongX = axis.dy == 0;
    final strips = axis == Offset.zero
        ? [reach]
        : alongX
        ? [
            Rect.fromLTRB(reach.left, reach.top, start.dx, reach.bottom),
            Rect.fromLTRB(start.dx, reach.top, end.dx, reach.bottom),
            Rect.fromLTRB(end.dx, reach.top, reach.right, reach.bottom),
          ]
        : [
            Rect.fromLTRB(reach.left, reach.top, reach.right, start.dy),
            Rect.fromLTRB(reach.left, start.dy, reach.right, end.dy),
            Rect.fromLTRB(reach.left, end.dy, reach.right, reach.bottom),
          ];
    final slots = copy.slots.isEmpty ? [Offset.zero & size] : copy.slots;
    canvas.save();
    canvas.clipRRect(copy.surface.shape);
    for (final (strip, clip) in strips.indexed) {
      canvas.save();
      canvas.clipRect(clip);
      canvas.transform(copy._growth(strip).storage);
      for (final slot in slots) {
        if (!slot.overlaps(bounds)) continue;
        canvas.save();
        canvas.clipRRect(copy.surface.shape);
        canvas.clipRect(slot);
        canvas.transform(
          MorphGlassContentCopy._about(slot.center, copy.magnification).storage,
        );
        copy.snapshot.paint(canvas);
        canvas.restore();
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ContentCopyPainter oldDelegate) => true;
}

/// The box a layer may paint into: its control's box grown by the reach
/// of the glass's shadows and lift, so the backdrop pass the renderer
/// blurs covers the control instead of the whole screen.
class _Reach extends CustomClipper<Rect> {
  const _Reach();

  static const double margin = 24;

  @override
  Rect getClip(Size size) => (Offset.zero & size).inflate(margin);

  @override
  bool shouldReclip(_Reach oldClipper) => false;
}

class _LensClip extends CustomClipper<Path> {
  const _LensClip(this.lenses, {required this.outside});

  final List<RRect> lenses;
  final bool outside;

  @override
  Path getClip(Size size) {
    final path = Path();
    if (outside) {
      path.fillType = PathFillType.evenOdd;
      path.addRect(
        Rect.fromLTWH(
          -size.width,
          -size.height,
          size.width * 3,
          size.height * 3,
        ),
      );
    }
    for (final lens in lenses) {
      path.addRRect(lens);
    }
    return path;
  }

  @override
  bool shouldReclip(_LensClip oldClipper) =>
      oldClipper.outside != outside || !_same(oldClipper.lenses, lenses);

  static bool _same(List<RRect> a, List<RRect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
