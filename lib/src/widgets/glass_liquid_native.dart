import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/glass/renderer/internal/content_snapshot.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart';
import 'package:morph/src/glass/renderer/internal/liquid_capability.dart';
import 'package:morph/src/glass/renderer/internal/multi_shader_builder.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_body_shadow.dart';
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

LiquidShape _shape(RRect shape) {
  final side = math.min(shape.width, shape.height);
  final radius = math.min(shape.tlRadiusX, side / 2);
  if (shape.width == shape.height && radius >= side / 2) {
    return const LiquidOval();
  }
  return LiquidRoundedSuperellipse(borderRadius: radius);
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

Widget _glass(
  MorphGlassRenderer renderer,
  MorphGlassSurface surface, {
  bool shadows = true,
}) {
  final base = morphLiquidAppearance(renderer, surface);
  return LiquidGlass(
    shape: _shape(surface.localShape),
    appearance: base.copyWith(
      visibility:
          base.visibility *
          MorphGlassRenderer.glassness(surface) *
          surface.opacity.clamp(0.0, 1.0),
    ),
    shadows: shadows ? _shadows(surface) : const [],
    child: const SizedBox.expand(),
  );
}

/// One glass layer of [surfaces], each its own shape, or one body shaded
/// from [field] when it is given.
Widget _layer(
  MorphGlassRenderer renderer,
  List<MorphGlassSurface> surfaces, {
  bool shared = true,
  double shrink = 0,
  double rim = 0,
  GlassField? field,
  bool shadows = true,
}) {
  final settings = morphLiquidSettings(renderer, surfaces.first);
  return ClipRect(
    clipper: const _Reach(),
    child: LiquidGlassLayer(
      settings: shrink == 0
          ? settings
          : settings.copyWith(backdropShrink: shrink, backdropShrinkRim: rim),
      useBackdropGroup: shared,
      field: field,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final surface in surfaces)
            Positioned.fromRect(
              rect: surface.bounds,
              child: _glass(renderer, surface, shadows: shadows),
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

/// One glass surface on the liquid tier, sized to its bounds.
@internal
Widget morphLiquidSurface(
  MorphGlassRenderer renderer,
  BuildContext context,
  MorphGlassSurface surface,
) => _layer(renderer, [_local(surface)], shared: !_chrome(surface));

/// One fused glass body on the liquid tier, filling its layer's box.
///
/// A body the package fused carries its distance field and is shaded from
/// it, neck included. An outline built from a path alone has no field: its
/// surfaces are shaded as their own shapes, clipped to the outline, and
/// frost fills the rest of it.
@internal
Widget morphLiquidBody(
  MorphGlassRenderer renderer,
  BuildContext context,
  MorphGlassOutline outline,
  List<MorphGlassSurface> surfaces,
) {
  final chrome = surfaces.any(_chrome);
  final field = morphGlassOutlineField(outline);
  if (field != null) {
    return CustomPaint(
      painter: MorphGlassBodyShadow(
        outline.path,
        _shadows(surfaces.first),
        surfaces.first.opacity.clamp(0.0, 1.0),
      ),
      child: _layer(
        renderer,
        surfaces,
        shared: !chrome,
        field: field,
        shadows: false,
      ),
    );
  }
  return ClipPath(
    clipper: MorphGlassOutlineClip(outline.path),
    child: Stack(
      fit: StackFit.expand,
      children: [
        _Frost(
          surface: surfaces.first,
          sigma: renderer.blur * MorphGlassDefaults.chromeFrost,
          shared: !chrome,
        ),
        _layer(renderer, surfaces, shared: !chrome),
      ],
    ),
  );
}

bool _chrome(MorphGlassSurface s) =>
    s.kind == MorphGlassKind.bar || s.kind == MorphGlassKind.menu;

/// One layer of a control on the liquid tier.
///
/// A control's glass body surfaces share a layer: the ones drawn as their
/// own shapes one layer, each fused body a layer of its own shaded from
/// its outline. A body that fuses and comes apart again (a menu and its
/// button) keeps one layer throughout, so its glass never restarts. Every backdrop copy is a full-screen readback, so body
/// glass reads the one copy of the nearest [BackdropGroup] and only lifted
/// glass, which must refract the glass and content under it, and chrome
/// that floats over content (a bar, a menu) pay for their own. Glass in
/// one group does not see what paints between its members: give a section
/// painted over the page (a card) a group of its own.
///
/// A lifted lens shows the content once more inside its outline, each
/// item grown about its own slot by the lens's magnification and against
/// the backdrop shrink, below the lens glass, which then bends it and the
/// rim of what it floats over at its bevel as UIKit's lens does.
@internal
Widget morphLiquidLayer(
  MorphGlassRenderer renderer,
  BuildContext context,
  MorphGlassLayerParts parts, {
  Widget? content,
  List<Rect> contentSlots = const [],
}) {
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
  final lenses = [
    for (final s in floating)
      if (s.kind == MorphGlassKind.lens && lifted(s)) s.shape,
  ];
  final snapshot = GlassContentSnapshot();
  final source = content == null
      ? null
      : GlassContentSource(
          snapshot: snapshot,
          capture: lenses.isNotEmpty,
          child: content,
        );
  return Stack(
    clipBehavior: Clip.none,
    children: [
      for (final (i, surface) in parts.fills.indexed)
        Positioned.fromRect(
          key: ValueKey<(String, int)>(('fill', i)),
          rect: surface.bounds,
          child: renderer.buildFill(context, surface),
        ),
      if (parts.separate.isNotEmpty)
        Positioned.fill(
          key: parts.fused.isEmpty
              ? const ValueKey<String>('body')
              : const ValueKey<String>('separate'),
          child: _layer(renderer, parts.separate, shared: !chrome),
        ),
      for (final (i, (surfaces, outline)) in parts.fused.indexed)
        Positioned.fill(
          key: i == 0
              ? const ValueKey<String>('body')
              : ValueKey<(String, int)>(('fused', i)),
          child: morphLiquidBody(renderer, context, outline, surfaces),
        ),
      for (final (i, surface) in body.indexed)
        if (surface.glow != null)
          Positioned.fromRect(
            key: ValueKey<(String, int)>(('glow', i)),
            rect: surface.bounds,
            child: renderer.buildGlow(context, surface),
          ),
      for (final (i, surface) in floating.indexed)
        if (MorphGlassRenderer.glassness(surface) < 1)
          Positioned.fromRect(
            key: ValueKey<(String, int)>(('platter', i)),
            rect: surface.bounds,
            child: _Platter(
              surface: surface,
              opacity: 1 - MorphGlassRenderer.glassness(surface),
            ),
          ),
      if (content != null)
        Positioned.fill(
          key: const ValueKey<String>('content'),
          child: ClipPath(
            clipBehavior: lenses.isEmpty ? Clip.none : Clip.antiAlias,
            clipper: _LensClip(lenses, outside: true),
            child: source!,
          ),
        ),
      for (final (i, surface) in floating.indexed)
        if (lifted(surface)) ...[
          if (content != null && surface.kind == MorphGlassKind.lens)
            Positioned.fill(
              key: ValueKey<(String, int)>(('copy', i)),
              child: MorphGlassContentCopy(
                surface: surface,
                slots: contentSlots,
                magnification:
                    1 +
                    optics(surface).magnification *
                        surface.lift.clamp(0.0, 1.0),
                grow: morphBackdropScale(surface, shrinkOf(surface)),
                axis: morphShrinkAxis(surface.bounds, optics(surface).rim),
                snapshot: snapshot,
              ),
            ),
          Positioned.fill(
            key: ValueKey<(String, int)>(('glass', i)),
            child: _layer(
              renderer,
              [surface],
              shared: false,
              shrink: shrinkOf(surface),
              rim: optics(surface).rim,
            ),
          ),
        ],
    ],
  );
}

/// Frosted glass over the whole box: the backdrop blurred by [sigma] and
/// tinted by [surface]'s color.
class _Frost extends StatelessWidget {
  const _Frost({
    required this.surface,
    required this.sigma,
    required this.shared,
  });

  final MorphGlassSurface surface;
  final double sigma;
  final bool shared;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      backdropGroupKey: shared ? BackdropGroup.of(context)?.backdropKey : null,
      filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: ColoredBox(
        color: surface.color.withValues(
          alpha: surface.color.a * surface.opacity.clamp(0.0, 1.0),
        ),
      ),
    );
  }
}

/// A resting lens, knob or thumb: an opaque platter, as UIKit draws one
/// until the finger lifts it into glass.
class _Platter extends StatelessWidget {
  const _Platter({required this.surface, required this.opacity});

  final MorphGlassSurface surface;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final shape = surface.localShape;
    return Opacity(
      opacity: opacity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface.color,
          borderRadius: BorderRadius.only(
            topLeft: shape.tlRadius,
            topRight: shape.trRadius,
            bottomLeft: shape.blRadius,
            bottomRight: shape.brRadius,
          ),
          boxShadow: _shadows(surface),
        ),
      ),
    );
  }
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
  /// Replays one source through the slot and rim transforms of a lens.
  const MorphGlassContentCopy({
    required this.surface,
    required this.slots,
    required this.magnification,
    required this.grow,
    required this.axis,
    required this.snapshot,
    super.key,
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
  const _ContentCopyPainter(this.copy);

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
