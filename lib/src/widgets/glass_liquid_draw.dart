/// The glass layers of the liquid tier: the renderer's layers over the
/// package's shapes. Shared by every build; the web, without Flutter GPU,
/// never reaches them and draws its glass flat.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/glass/renderer/internal/raster_phase.dart';
import 'package:morph/src/glass/renderer/liquid_glass.dart';
import 'package:morph/src/glass/renderer/liquid_glass_glow.dart';
import 'package:morph/src/glass/renderer/renderer.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_body_shadow.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_container.dart';
import 'package:morph/src/widgets/glass_glow.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/src/widgets/glass_renderer.dart';
import 'package:morph/src/widgets/glyph_scale.dart';

MorphGlassMaterial _materialOf(
  GlassBuiltInPainter renderer,
  MorphGlassSurface surface,
) => switch (surface.style) {
  null => renderer.material,
  MorphGlassStyle.regular => MorphGlassMaterial.regular,
  MorphGlassStyle.clear => MorphGlassMaterial.clear,
};

LiquidGlassSettings _preset(
  GlassBuiltInPainter renderer,
  MorphGlassSurface surface,
) => switch (_materialOf(renderer, surface)) {
  MorphGlassMaterial.regular => LiquidGlassSettings(
    frost: LiquidGlassSettings.ios27RegularFrost(renderer.tint),
    tintAmount: renderer.tint,
  ),
  MorphGlassMaterial.toolbar => LiquidGlassSettings.ios27Toolbar(
    brightness: surface.brightness,
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
  GlassBuiltInPainter renderer,
  MorphGlassSurface surface,
) {
  final preset = _preset(renderer, surface);
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
      : optics.displacementAt(lift) * GlassBuiltInPainter.lensRefraction;
  return preset.copyWith(
    frost: frost * renderer.blur,
    refractionAmount: amount * renderer.refraction,
    dispersion: optics == null
        ? preset.dispersion
        : GlassBuiltInPainter.lensDispersion * lift,
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
  GlassBuiltInPainter renderer,
  MorphGlassSurface surface,
) => GlassBuiltInPainter.floats(surface.kind)
    ? const LiquidGlassAppearance()
    : (switch (_materialOf(renderer, surface)) {
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
        GlassBuiltInPainter.glassness(surface) *
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
  GlassBuiltInPainter renderer,
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
          GlassBuiltInPainter.glassness(surface) *
          surface.opacity.clamp(0.0, 1.0),
    ),
    shadows: shadows ? _shadows(surface) : const [],
  );
}

/// The touch glow of the first lit surface of [surfaces], which share the
/// coordinates of their layer, as the liquid tier's final pass applies it:
/// one glow per layer pass, and a control lights at most one surface.
LiquidGlassGlow? _glowOf(List<MorphGlassSurface> surfaces) {
  for (final surface in surfaces) {
    final glow = surface.glow;
    if (glow == null || !glow.isVisible) continue;
    return LiquidGlassGlow(
      clip: surface.shape,
      center: glow.center,
      radius: glow.radius,
      gain: glow.gain,
      wash: glow.wash,
    );
  }
  return null;
}

/// One glass layer of the surfaces [select] picks, each its own shape, or
/// one body shaded from [field] when it is given; [exact] shapes are the
/// surfaces' own circular rounded boxes instead of continuous corners. A
/// lifted lens's layer shrinks its backdrop by [shrink] about a center
/// line of [rim] weight. The layer's final pass applies the touch glow of
/// its lit surface ([_glowOf]).
///
/// With [slots] the layer holds that many shapes whatever [select] picks,
/// the ones past its pick absent ([_slotShapes]), and reads its settings
/// from [anchor] while the pick is empty.
Widget _layer(
  GlassBuiltInPainter renderer,
  MorphGlassSource source,
  List<MorphGlassSurface> Function(MorphGlassFrame frame) select, {
  GlassRead read = GlassRead.plane,
  double Function(MorphGlassSurface surface)? shrink,
  double rim = 0,
  GlassField? Function(MorphGlassFrame frame)? field,
  bool shadows = true,
  bool exact = false,
  int? slots,
  MorphGlassSurface Function(MorphGlassFrame frame)? anchor,
}) {
  MorphGlassSurface first(MorphGlassFrame f) {
    final surfaces = select(f);
    return surfaces.isEmpty ? anchor!(f) : surfaces.first;
  }

  final count = slots ?? select(source.frame).length;
  final settings = source.pick((f) {
    final surface = first(f);
    final settings = morphLiquidSettings(renderer, surface);
    final amount = shrink?.call(surface) ?? 0;
    return amount == 0
        ? settings
        : settings.copyWith(backdropShrink: amount, backdropShrinkRim: rim);
  });
  final fieldOf = field == null ? null : source.pick(field);
  final glow = source.pick((f) => _glowOf(select(f)));
  return ClipRect(
    clipper: const _Reach(),
    child: LiquidGlassLayer.live(
      live: source.live,
      settingsOf: () => settings.value,
      defaultAppearance: morphLiquidAppearance(renderer, first(source.frame)),
      fieldOf: fieldOf == null ? null : () => fieldOf.value,
      glowOf: () => glow.value,
      glows: source.glows,
      read: read,
      child: slots == null
          ? _shapes(
              renderer,
              source,
              select,
              count: count,
              shadows: shadows,
              exact: exact,
            )
          : _slotShapes(
              renderer,
              source,
              select,
              anchor!,
              count: count,
              shadows: shadows,
              exact: exact,
            ),
    ),
  );
}

/// The shapes of the surfaces [select] picks, registered with the
/// nearest glass layer above them.
Widget _shapes(
  GlassBuiltInPainter renderer,
  MorphGlassSource source,
  List<MorphGlassSurface> Function(MorphGlassFrame frame) select, {
  required int count,
  bool shadows = true,
  bool exact = false,
}) => MorphLiveStack(
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
        ),
      ),
  ],
);

/// [count] shape slots, the first ones showing the surfaces [select]
/// picks in its order and the rest absent from their layer
/// ([LiquidGlassShapeFrame.present]): the same shapes as [_shapes] of the
/// pick, whatever its length.
///
/// An absent slot keeps the kind of shadows of [anchor]'s surface, so a
/// slot that turns present builds nothing.
Widget _slotShapes(
  GlassBuiltInPainter renderer,
  MorphGlassSource source,
  List<MorphGlassSurface> Function(MorphGlassFrame frame) select,
  MorphGlassSurface Function(MorphGlassFrame frame) anchor, {
  required int count,
  bool shadows = true,
  bool exact = false,
}) => MorphLiveStack(
  live: source.live,
  children: [
    for (var i = 0; i < count; i++)
      MorphLivePositioned(
        rect: source.pick((f) {
          final surfaces = select(f);
          return i < surfaces.length ? surfaces[i].bounds : Rect.zero;
        }),
        child: LiquidGlass.live(
          live: source.pick((f) {
            final surfaces = select(f);
            if (i < surfaces.length) {
              return _shapeFrame(
                renderer,
                surfaces[i],
                shadows: shadows,
                exact: exact,
              );
            }
            final surface = anchor(f);
            return LiquidGlassShapeFrame(
              shape: _shape(surface.localShape, exact: exact),
              appearance: morphLiquidAppearance(
                renderer,
                surface,
              ).copyWith(visibility: 0),
              shadows: shadows ? _shadows(surface) : const [],
              present: false,
            );
          }),
        ),
      ),
  ],
);

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
  glow: switch (surface.glow) {
    final glow? => MorphGlassGlow(
      wash: glow.wash,
      center: glow.center - surface.bounds.topLeft,
      radius: glow.radius,
      gain: glow.gain,
    ),
    null => null,
  },
  shadows: surface.shadows,
);

/// One glass surface on the liquid tier, the one [select] picks from
/// [source], sized to its bounds.
@internal
Widget morphLiquidSurface(
  GlassBuiltInPainter renderer,
  BuildContext context,
  MorphGlassSource source,
  MorphGlassSurface Function(MorphGlassFrame frame) select,
) => _layer(
  renderer,
  source,
  (f) => [_local(select(f))],
  read: _chrome(select(source.frame)) ? GlassRead.own : GlassRead.plane,
);

/// One fused glass body on the liquid tier, the one [select] picks from
/// [source], filling its layer's box.
///
/// A body the package fused carries its distance field and is shaded from
/// it, neck included. A plain union is shaded from its surfaces' own
/// rounded boxes, the nearest one at every point, exactly the field it
/// would sample. An outline built from a path alone has no field to shade,
/// so it is drawn as the flat tier draws it ([morphGlassLiveBody]).
@internal
Widget morphLiquidBody(
  GlassBuiltInPainter renderer,
  BuildContext context,
  MorphGlassSource source,
  (List<MorphGlassSurface>, MorphGlassOutline) Function(MorphGlassFrame f)
  select,
) {
  final (surfaces, outline) = select(source.frame);
  final exact = morphGlassOutlineShapes(outline) != null;
  if (morphGlassOutlineField(outline) == null && !exact) {
    return morphGlassLiveBody(source, select);
  }
  return CustomPaint(
    painter: MorphGlassBodyShadow.live(
      source.pick((f) {
        final (surfaces, outline) = select(f);
        return (
          outline.path,
          _shadows(surfaces.first),
          surfaces.first.opacity.clamp(0.0, 1.0),
          morphGlassOutlineShadowCover(outline),
        );
      }),
    ),
    child: _layer(
      renderer,
      source,
      (f) => select(f).$1,
      read: surfaces.any(_chrome) ? GlassRead.own : GlassRead.plane,
      field: (f) => morphGlassOutlineField(select(f).$2),
      shadows: false,
      exact: exact,
    ),
  );
}

/// [morphLiquidBody] of a slot: the fused body [select] picks, shaded
/// from its field, or nothing while it picks none, when it neither paints
/// nor takes hits; a body of a container with spacing always carries a
/// field. Its layer holds [count] member slots and reads its settings
/// from [anchor] while it is empty.
Widget _slotBody(
  GlassBuiltInPainter renderer,
  MorphGlassSource source,
  (List<MorphGlassSurface>, MorphGlassOutline)? Function(MorphGlassFrame f)
  select,
  MorphGlassSurface Function(MorphGlassFrame frame) anchor, {
  required int count,
}) {
  final body = source.pick(select);
  return MorphLiveTemplate(
    live: source.live,
    template: () => IgnorePointer(ignoring: body.value == null),
    child: CustomPaint(
      painter: MorphGlassBodyShadow.live(
        source.pick((f) {
          final body = select(f);
          if (body == null) return _noBodyShadow;
          final (surfaces, outline) = body;
          return (
            outline.path,
            _shadows(surfaces.first),
            surfaces.first.opacity.clamp(0.0, 1.0),
            morphGlassOutlineShadowCover(outline),
          );
        }),
      ),
      child: _layer(
        renderer,
        source,
        (f) => select(f)?.$1 ?? const [],
        field: (f) => switch (select(f)) {
          (_, final outline) => morphGlassOutlineField(outline),
          null => null,
        },
        shadows: false,
        slots: count,
        anchor: anchor,
      ),
    ),
  );
}

final (Path, List<BoxShadow>, double, Path?) _noBodyShadow = (
  Path(),
  const <BoxShadow>[],
  0.0,
  null,
);

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
  GlassBuiltInPainter renderer,
  BuildContext context,
  MorphGlassSource source, {
  Widget? content,
}) {
  // The liquid tier with analytic geometry merges small fused bodies in
  // its shader; every other tier draws the package's fused outlines.
  final tier = renderer.effectiveTier;
  if (source.live != null && morphGlassLayerSlots(source.frame)) {
    return _slottedLayer(renderer, context, source, content: content);
  }
  final parts = source.frame.partsFor(tier);
  final body = parts.body;
  final floating = parts.floating;
  final chrome = body.any(_chrome);
  final joined =
      MorphGlassContainerScope.maybeOf(context)?.holds(context) ?? false;
  bool lifted(MorphGlassSurface s) => s.lift > GlassBuiltInPainter.restingLift;
  final overBar = body.any((s) => s.kind == MorphGlassKind.bar);
  ({double magnification, double shrink, double rim}) optics(
    MorphGlassSurface s,
  ) => GlassBuiltInPainter.liftedOptics(s.kind, overBar: overBar);
  double shrinkOf(MorphGlassSurface s) =>
      optics(s).shrink * s.lift.clamp(0.0, 1.0);
  final lensed = [
    for (final (i, s) in floating.indexed)
      if (s.kind == MorphGlassKind.lens && lifted(s)) i,
  ];
  List<RRect> lenses(MorphGlassFrame f) => [
    for (final i in lensed) f.partsFor(tier).floating[i].shape,
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
          (f) => f.partsFor(tier).fills[i].bounds,
          () => renderer.liveFill(
            context,
            source,
            (f) => f.partsFor(tier).fills[i],
          ),
        ),
      if (parts.separate.isNotEmpty)
        fill(
          'separate',
          parts.fused.isEmpty
              ? const ValueKey<String>('body')
              : const ValueKey<String>('separate'),
          () => joined
              ? GlassRasterAnchor(
                  child: _shapes(
                    renderer,
                    source,
                    (f) => f.partsFor(tier).separate,
                    count: parts.separate.length,
                  ),
                )
              : _layer(
                  renderer,
                  source,
                  (f) => f.partsFor(tier).separate,
                  read: chrome ? GlassRead.own : GlassRead.plane,
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
            (f) => f.partsFor(tier).fused[i],
          ),
        ),
      for (final (i, surface) in floating.indexed)
        if (GlassBuiltInPainter.glassness(surface) < 1)
          at(
            ('platter', i),
            (f) => f.partsFor(tier).floating[i].bounds,
            () => _Platter(
              source: source,
              select: (f) => f.partsFor(tier).floating[i],
            ),
          ),
      if (content != null)
        _content(
          source,
          snapshot,
          lenses,
          lensed: lensed.isNotEmpty,
          content: content,
        ),
      for (final (i, surface) in floating.indexed)
        if (lifted(surface)) ...[
          if (content != null && surface.kind == MorphGlassKind.lens)
            fill(
              ('copy', i),
              ValueKey<(String, int)>(('copy', i)),
              () => MorphGlassContentCopy(
                frame: source.pick((f) {
                  final lens = f.partsFor(tier).floating[i];
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
              (f) => [f.partsFor(tier).floating[i]],
              read: GlassRead.lifted,
              shrink: shrinkOf,
              rim: optics(surface).rim,
            ),
          ),
        ],
    ],
  );
}

/// The control's content over its glass, outside the lifted [lenses]
/// ([lensed] while there are any), which show it themselves.
Widget _content(
  MorphGlassSource source,
  GlassContentSnapshot snapshot,
  List<RRect> Function(MorphGlassFrame f) lenses, {
  required bool lensed,
  required Widget content,
}) {
  final live = source.live;
  return Positioned.fill(
    key: const ValueKey<String>('content'),
    child: ClipPath(
      clipBehavior: lensed ? Clip.antiAlias : Clip.none,
      clipper: live == null
          ? _LensClip(lenses(source.frame), outside: true)
          : source.keep('lens clip', () {
              final picked = source.pick(lenses);
              return MorphLiveClipper<Path>(
                live: live,
                keyOf: () => _LensRects(picked.value),
                clipOf: (Size size) =>
                    _LensClip(picked.value, outside: true).getClip(size),
              );
            }),
      child: GlassContentSource(
        snapshot: snapshot,
        capture: lensed,
        live: live,
        child: content,
      ),
    ),
  );
}

/// The layer of a slotted frame ([morphGlassLayerSlots]): one layer of
/// a slot for every surface drawn as its own shape, then a body for every
/// fused group the surfaces can form, then the content, so a frame whose
/// surfaces fuse, part, appear or vanish fills slots instead of building.
/// The layers and keys are [morphLiquidLayer]'s, the separate shapes'
/// layer first under the key of a layer without fused bodies, so a change
/// that starts or ends at rest keeps its layers.
Widget _slottedLayer(
  GlassBuiltInPainter renderer,
  BuildContext context,
  MorphGlassSource source, {
  Widget? content,
}) {
  final tier = renderer.effectiveTier;
  final count = source.frame.surfaces.length;
  MorphGlassLayerParts partsOf(MorphGlassFrame f) => f.partsFor(tier);
  MorphGlassSurface anchor(MorphGlassFrame f) {
    final body = partsOf(f).body;
    return body.isEmpty ? f.surfaces.first : body.first;
  }

  final joined =
      MorphGlassContainerScope.maybeOf(context)?.holds(context) ?? false;
  Widget fill(Object slot, Key key, Widget Function() child) =>
      source.keep(slot, () => Positioned.fill(key: key, child: child()));
  return MorphLiveStack(
    live: source.live,
    children: [
      fill(
        'separate',
        const ValueKey<String>('body'),
        () => joined
            ? GlassRasterAnchor(
                child: _slotShapes(
                  renderer,
                  source,
                  (f) => partsOf(f).separate,
                  anchor,
                  count: count,
                ),
              )
            : _layer(
                renderer,
                source,
                (f) => partsOf(f).separate,
                slots: count,
                anchor: anchor,
              ),
      ),
      for (var i = 0; i < count ~/ 2; i++)
        fill(
          ('fused', i),
          ValueKey<(String, int)>(('fused', i)),
          () => _slotBody(
            renderer,
            source,
            (f) {
              final fused = partsOf(f).fused;
              return i < fused.length ? fused[i] : null;
            },
            anchor,
            count: count,
          ),
        ),
      if (content != null)
        _content(
          source,
          source.keep('snapshot', GlassContentSnapshot.new),
          (f) => const [],
          lensed: false,
          content: content,
        ),
    ],
  );
}

/// A resting lens, knob or thumb: an opaque platter, as UIKit draws one
/// until the finger lifts it into glass.
///
/// It fades by the alpha of its fill and shadow, not an opacity layer.
class _Platter extends StatelessWidget {
  const _Platter({required this.source, required this.select});

  final MorphGlassSource source;
  final MorphGlassSurface Function(MorphGlassFrame frame) select;

  @override
  Widget build(BuildContext context) => MorphLiveDecoratedBox(
    live: source.pick((f) {
      final surface = select(f);
      final shape = surface.localShape;
      final opacity = 1 - GlassBuiltInPainter.glassness(surface);
      return BoxDecoration(
        color: surface.color.withValues(alpha: surface.color.a * opacity),
        borderRadius: BorderRadius.only(
          topLeft: shape.tlRadius,
          topRight: shape.trRadius,
          bottomLeft: shape.blRadius,
          bottomRight: shape.brRadius,
        ),
        boxShadow: [
          for (final shadow in _shadows(surface))
            shadow.copyWith(
              color: shadow.color.withValues(alpha: shadow.color.a * opacity),
            ),
        ],
      );
    }),
  );
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
///
/// The copy's text is drawn as [MorphGlyphPolicy] decides from its screen
/// scale (render transform x [grow] x [magnification]): exact at rest,
/// on a grid of scales while a lift or set-down sweeps it.
@internal
class MorphGlassContentCopy extends StatefulWidget {
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

  /// Called for every item a copy draws, with the strip it is clipped to
  /// in the copy's own coordinates, the canvas transform at the start of
  /// the copy's paint and the one the item's content is replayed with: for
  /// tests that replay where the copy's glyphs land on screen.
  @visibleForTesting
  static void Function(
    Rect slot,
    Rect strip,
    Float64List base,
    Float64List item,
  )?
  debugOnItem;

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
  State<MorphGlassContentCopy> createState() => _ContentCopyState();
}

class _ContentCopyState extends State<MorphGlassContentCopy> {
  /// Ticks when the glyph policy asks for one more paint.
  final ValueNotifier<int> _settle = ValueNotifier<int>(0);

  late final MorphGlyphTracker _glyphs = MorphGlyphTracker(
    () => _settle.value++,
  );

  @override
  void dispose() {
    _glyphs.reset();
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.frame;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: MorphScreenScalePaint(
          repaint: frame is MorphFixed<MorphGlassCopyFrame>
              ? _settle
              : Listenable.merge([frame, _settle]),
          painter: _ContentCopyPainter(
            widget,
            _glyphs,
            MediaQuery.devicePixelRatioOf(context),
          ).paint,
        ),
      ),
    );
  }
}

class _ContentCopyPainter {
  _ContentCopyPainter(this.copy, this.glyphs, this.devicePixelRatio);

  final MorphGlassContentCopy copy;

  final MorphGlyphTracker glyphs;

  final double devicePixelRatio;

  /// The magnification the copy draws at, and whether its items that
  /// replay aligned glyphs are drawn aligned: whenever the recording holds
  /// any, as the copy exists only while its lens is lifted, and at the
  /// copy's first frame or while its own scale holds still the aligned
  /// items still move with the drawings they replay.
  (double, bool) _glyphMagnification(double screenScale) {
    final magnification = copy.magnification;
    final base = screenScale * devicePixelRatio * copy.grow;
    if (base <= 0) return (magnification, false);
    final screen = base * magnification;
    final aligned = copy.snapshot.aligned;
    // No raster: a live lens records its source again every frame, so a
    // raster of the copy would be taken again every frame.
    final mode = glyphs.observe(screen, canRaster: false, settle: !aligned);
    if (aligned) return (magnification, true);
    if (mode == MorphGlyphMode.live) return (magnification, false);
    return (
      MorphGlyphScale.snap(
            screen,
            devicePixelRatio,
            perOctave: glyphs.perOctave,
          ) /
          base,
      false,
    );
  }

  /// The aligned drawing of glyphs centered in [slot], if the recording
  /// holds one.
  GlassContentGlyphs? _alignedIn(Rect slot) {
    for (final drawn in copy.snapshot.glyphs) {
      if (!drawn.aligned) continue;
      final center = MatrixUtils.transformPoint(
        drawn.transform,
        drawn.size.center(Offset.zero),
      );
      if (slot.contains(center)) return drawn;
    }
    return null;
  }

  void paint(Canvas canvas, Size size, Matrix4 toRoot) {
    final (magnification, aligned) = _glyphMagnification(
      MorphGlyphScale.of(toRoot),
    );
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
    final grow = copy.grow;
    final onItem = MorphGlassContentCopy.debugOnItem;
    final base = onItem == null ? null : canvas.getTransform();
    final screen = toRoot.storage;
    // Aligning needs an axis-aligned transform to the screen.
    final aligns =
        aligned &&
        screen[1] == 0 &&
        screen[4] == 0 &&
        screen[3] == 0 &&
        screen[7] == 0 &&
        screen[0] > 0 &&
        screen[5] > 0;
    canvas.save();
    canvas.clipRRect(copy.surface.shape);
    for (final (strip, clip) in strips.indexed) {
      canvas.save();
      canvas.clipRect(clip);
      final (anchor, growX, growY) = axis == Offset.zero
          ? (center, grow, grow)
          : strip == 0
          ? (start, grow, grow)
          : strip == 2
          ? (end, grow, grow)
          : (center, axis.dx == 0 ? grow : 1.0, axis.dy == 0 ? grow : 1.0);
      _scaleAbout(canvas, anchor, growX, growY);
      for (final slot in slots) {
        if (!slot.overlaps(bounds)) continue;
        canvas.save();
        canvas.clipRRect(copy.surface.shape);
        canvas.clipRect(slot);
        final drawn = aligns ? _alignedIn(slot) : null;
        if (drawn == null) {
          _scaleAbout(canvas, slot.center, magnification, magnification);
        } else {
          _alignedItem(
            canvas,
            slot,
            drawn,
            screen,
            anchor,
            growX,
            growY,
            copy.magnification,
          );
        }
        onItem?.call(slot, clip, base!, canvas.getTransform());
        copy.snapshot.paint(canvas);
        canvas.restore();
      }
      canvas.restore();
    }
    canvas.restore();
  }

  /// Magnifies [slot] by about [magnification] about its center so that
  /// the glyphs of [drawn] land on grid scales with the drawing's origin
  /// on a whole device pixel across, under the strip's growth by
  /// ([growX], [growY]) about [anchor] and the box's transform [screen] to
  /// the root.
  ///
  /// The axes snap apart: a strip grown across only scales one axis more
  /// than the other, and the atlas keys the glyphs by the larger scale but
  /// places them by the scale across. The larger snaps on the copy's grid
  /// and the other keeps its ratio to it snapped on the same grid, so each
  /// grid scale meets few scales across while a lift sweeps the strip's
  /// growth, and the copy is at most half a step of that grid wider or
  /// taller than it is exactly besides the snap: 0.54 percent while the
  /// copy's scale moves slowly, 1.1 or 2.2 percent only while it moves fast
  /// ([MorphGlyphPolicy.gridFor]).
  void _alignedItem(
    Canvas canvas,
    Rect slot,
    GlassContentGlyphs drawn,
    Float64List screen,
    Offset anchor,
    double growX,
    double growY,
    double magnification,
  ) {
    final w = screen[15];
    final scaleX = screen[0] / w * devicePixelRatio;
    final scaleY = screen[5] / w * devicePixelRatio;
    final inner = drawn.transform.storage;
    final unmagnifiedX = scaleX * growX * inner[0];
    final unmagnifiedY = scaleY * growY * inner[5];
    if (unmagnifiedX <= 0 || unmagnifiedY <= 0) {
      _scaleAbout(canvas, slot.center, magnification, magnification);
      return;
    }
    final keyed = math.max(unmagnifiedX, unmagnifiedY);
    final key = MorphGlyphScale.snap(
      keyed * magnification,
      devicePixelRatio,
      perOctave: glyphs.perOctave,
    );
    double along(double unmagnified) =>
        key *
        MorphGlyphScale.snap(
          unmagnified / keyed,
          1,
          perOctave: glyphs.perOctave,
        ) /
        unmagnified;
    final magX = along(unmagnifiedX);
    final magY = along(unmagnifiedY);
    final c = slot.center.dx;
    final origin =
        growX * (magX * (inner[12] / inner[15] - c) + c - anchor.dx) +
        anchor.dx;
    final x = scaleX * origin + screen[12] / w * devicePixelRatio;
    _scaleAbout(canvas, slot.center, magX, magY);
    canvas.translate((x.roundToDouble() - x) / (scaleX * growX * magX), 0);
  }

  static final Float64List _matrix = Float64List(16);

  // The entries MorphGlassContentCopy._about composes, in the same double
  // arithmetic, without its three Matrix4 per call.
  static void _scaleAbout(Canvas canvas, Offset center, double sx, double sy) {
    final m = _matrix;
    m.fillRange(0, 16, 0);
    m[0] = sx;
    m[5] = sy;
    m[10] = 1;
    m[12] = sx * -center.dx + center.dx;
    m[13] = sy * -center.dy + center.dy;
    m[15] = 1;
    canvas.transform(m);
  }
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
