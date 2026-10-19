import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:morph/src/glass/renderer/glass_field.dart';
import 'package:morph/src/glass/renderer/internal/glass_defaults.dart';
import 'package:morph/src/glass/renderer/internal/glass_shadow_shader.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/theme/glass.dart';
import 'package:morph/src/widgets/flat_body_shader.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/src/widgets/glass_liquid.dart';
import 'package:morph/src/widgets/glass_outline.dart';

/// The two Liquid Glass materials an app picks per surface
/// (`UIGlassEffect.Style`, SwiftUI `Glass.regular` / `Glass.clear`).
enum MorphGlassStyle {
  /// The regular material: a light wash that keeps content on it legible
  /// over any backdrop.
  regular,

  /// The clear material, for glass over rich media (photos, video, maps):
  /// no wash and the full bevel on every shape. Content on it needs its own
  /// contrast, as UIKit advises.
  clear,
}

/// The iOS 27 glass materials the liquid tier is fitted to, a renderer's
/// preset for the surfaces that pick no [MorphGlassStyle] of their own.
enum MorphGlassMaterial {
  /// The regular material of `.glass` buttons and controls.
  regular,

  /// The toolbar material, with a stronger rim in dark mode.
  toolbar,

  /// The clear material: no wash, the full bevel on every shape.
  clear,
}

/// The package's glass renderer: draws the surfaces of every measured
/// control at a quality [tier].
///
/// A `MorphTheme` installs it at the tier its `MorphThemeData.glass`
/// chooses; a [MorphGlassScope] installs one with other settings. Only
/// surfaces that are glass in iOS 27 become glass: a plain surface
/// ([MorphGlassSurface.glass] false - the segmented, switch and slider
/// tracks, the stepper) is a flat fill on every tier.
///
/// The shapes are the package's, never the renderer's: a menu fused to its
/// button hands its silhouette as a [MorphGlassOutline], and the surfaces
/// of a glass container (a bar's capsules, [MorphGlassPainter.buildLayer]'s
/// `spacing`) are fused by the skin's merge law before any tier shades
/// them. The liquid tier shades a fused outline from its distance field,
/// so the neck between a menu and its button is liquid glass too.
///
/// On the liquid tier a control's glass body surfaces (bar, button, menu)
/// share a layer and a resting lens, knob or thumb is an opaque platter
/// under the control's content; lifted, it turns into clear glass in a
/// layer of its own above everything of the control, so it refracts what
/// lies under it - the bar's glass included. Lifted, a tab bar lens, a
/// segmented lens and a switch knob minify what lies beneath them and a
/// tab bar lens shows its items magnified, by the amounts measured on the
/// iPhone 16 Pro ([tabBarMagnification], [segmentedShrink] and their
/// kin). Frost is the dearest part of the liquid tier, so only bars,
/// menus and lifted lenses frost unless [frostControls] is on.
///
/// Until shaders are ready, or if they fail, liquid draws fake glass and
/// reports [MorphGlassTier.fake].
@immutable
class GlassBuiltInPainter extends MorphGlassPainter {
  /// Creates a renderer at [tier] with the liquid tier's settings.
  const GlassBuiltInPainter({
    this.tier = MorphGlassTier.liquid,
    this.material = MorphGlassMaterial.regular,
    this.blur = 1,
    this.refraction = 1,
    this.light = 1,
    this.tint = 0,
    this.frostControls = false,
  });

  /// The quality tier asked for; see [effectiveTier] for the one drawn.
  final MorphGlassTier tier;

  /// The material preset of the liquid tier for every surface without
  /// its own [MorphGlassSurface.style]; a surface that picks a
  /// [MorphGlassStyle] draws that material instead.
  final MorphGlassMaterial material;

  /// The factor on the preset's frost.
  final double blur;

  /// The factor on the preset's refraction.
  final double refraction;

  /// The factor on the preset's rim glint.
  final double light;

  /// The Liquid Glass slider of iOS Settings, 0 clear and 1 tinted.
  final double tint;

  /// Whether tracks and buttons frost what is behind them as bars and
  /// menus do, on the liquid tier.
  ///
  /// Off by default: a frosted surface blurs its backdrop again on every
  /// frame anything on screen moves, which costs about a millisecond of
  /// raster per surface on an iPhone 16 Pro, and at control size over a
  /// plain page the frost is rarely visible.
  final bool frostControls;

  /// Whether the runtime GPU context and liquid shaders are ready.
  ///
  /// False on the web, whose shader compiler cannot build the renderer's
  /// shaders; there [MorphGlassTier.liquid] draws [MorphGlassTier.fake].
  static bool get liquidAvailable => morphLiquidGlassAvailable;

  /// The reason liquid glass initialization failed on this runtime.
  ///
  /// Null until initialization fails, including while it is pending and
  /// after it succeeds. Await [precache] before reading a resolved result.
  /// Failures are cached for the isolate, shared by all renderer instances,
  /// and reported once through [FlutterError.reportError] in every build
  /// mode. The web reports that it has no liquid glass tier.
  static String? get liquidUnavailableReason =>
      morphLiquidGlassUnavailableReason;

  /// The best tier currently available on this runtime.
  static MorphGlassTier get bestTier =>
      liquidAvailable ? MorphGlassTier.liquid : MorphGlassTier.fake;

  /// The tier this renderer draws: [tier], or [bestTier] when the build
  /// cannot draw [tier].
  MorphGlassTier get effectiveTier =>
      tier == MorphGlassTier.liquid ? bestTier : tier;

  /// Loads the liquid tier's shaders and draws every glass pipeline once
  /// offscreen, so the first glass on screen is already the real one and
  /// compiles nothing.
  ///
  /// Await it before `runApp`: the warm-up takes about 0.35 to 0.45 s on a
  /// Pixel 6a (Vulkan) and moves that cost from the first glass frame to
  /// the launch. It holds the launch for at most one second; a GPU that is
  /// slower to start finishes the warm-up in the background, and glass
  /// drawn before the liquid tier is ready is fake glass.
  ///
  /// Unsupported runtimes and shader loading failures complete normally,
  /// report once through [FlutterError.reportError], and expose the cause
  /// through [liquidUnavailableReason].
  /// On Android, calling before `runApp` can wait for the engine's GPU
  /// context initialization; it does not wait for an application frame.
  /// With the flat tier's shader bodies enabled
  /// (`MORPH_FLAT_SHADER_BODIES`) it also loads their shader, and with
  /// shader shadows enabled (`MORPH_SHADER_SHADOWS`) the glass shadows'.
  static Future<void> precache() async {
    await Future.wait([
      morphPrecacheLiquidGlass(),
      if (MorphFlatBodyShader.enabled) MorphFlatBodyShader.precache(),
      if (MorphGlassShadowShader.enabled) MorphGlassShadowShader.precache(),
    ]);
  }

  /// The same renderer at [tier], or with any other setting replaced.
  GlassBuiltInPainter copyWith({
    MorphGlassTier? tier,
    MorphGlassMaterial? material,
    double? blur,
    double? refraction,
    double? light,
    double? tint,
    bool? frostControls,
  }) => GlassBuiltInPainter(
    tier: tier ?? this.tier,
    material: material ?? this.material,
    blur: blur ?? this.blur,
    refraction: refraction ?? this.refraction,
    light: light ?? this.light,
    tint: tint ?? this.tint,
    frostControls: frostControls ?? this.frostControls,
  );

  /// The growth of the tab bar items seen through a fully lifted lens.
  ///
  /// Measured on the iPhone 16 Pro tab bar references: the held item's
  /// icon and label show at 1.218 of their resting size while the
  /// swelling bar carries its other items at 1.052, so the lens adds
  /// 1.158 on top of the bar.
  static const double tabBarMagnification = 0.16;

  /// The growth of the segment labels seen through a fully lifted lens.
  ///
  /// None: the iPhone 16 Pro reference (`segmented-held-selected`) shows
  /// the held label at 0.996 of its resting size, in place.
  static const double segmentedMagnification = 0;

  /// The liquid tier's refraction per pixel of UIKit lens displacement.
  ///
  /// A lifted lens bends by `9 * 2 = 18`, under the bevel height of 20, so
  /// its rim compresses what lies just outside it - the edge of the bar
  /// or track it floats over - as UIKit's lens does, instead of mirroring
  /// the content inside it as the 60 of a glass button would.
  static const double lensRefraction = 2;

  /// The color separation along a lifted lens's rim.
  static const double lensDispersion = -0.25;

  /// How much smaller a fully lifted tab bar lens shows the bar glass.
  ///
  /// UIKit's lens minifies the glass beneath it and magnifies only the
  /// items: the iPhone 16 Pro reference (`tabbar3-held-other`) shows the
  /// swollen bar's edges 0.890 of its height apart inside the lens. The
  /// lens's own bevel pulls the backdrop inward near the rim, so it takes
  /// this shrink to put them there.
  static const double tabBarShrink = 0.16;

  /// How much smaller a fully lifted segmented lens shows the track.
  ///
  /// The reference (`segmented-held-selected`) shows the track's edges
  /// 0.8125 of its height apart inside the lens, and the track's end at
  /// 0.964 of its distance from the lens center: the shrink is about the
  /// lens's center line ([lensShrinkRim]), not its center.
  static const double segmentedShrink = 0.20;

  /// How much smaller a fully lifted switch knob shows the track.
  ///
  /// The reference (`switch-off-knob-held`) shows the track's edges 0.755
  /// of its height apart inside the knob. A slider thumb shows its track
  /// unchanged (`slider-thumb-held`), so a thumb does not shrink.
  static const double switchKnobShrink = 0.25;

  /// How far a lifted segmented lens or switch knob shrinks the backdrop
  /// about its center line instead of its center.
  ///
  /// UIKit's lens minifies by depth below its rim: across the straight
  /// part of the capsule and radially about the centers of its round
  /// ends. The references fit the full center line: the track's end
  /// inside a held end segment moves 7 px inward (0.962 of its distance
  /// from the lens center; about the center it moved 36, 0.800), and
  /// inside the switch knob 8 px (15 about the center).
  static const double lensShrinkRim = 1;

  /// The rim weight of a lifted tab bar lens's shrink.
  ///
  /// The swollen bar's end inside a lens held on the end item moves 11 px
  /// inward on the reference (`tabbar3-held-selected`); the full center
  /// line moves it 8 and the center 20, so three quarters of the line.
  static const double tabBarShrinkRim = 0.75;

  /// The lift below which a lens, knob or thumb is only its platter.
  static const double restingLift = 0.005;

  /// The growth of the content, the backdrop shrink and the shrink's rim
  /// weight a fully lifted floating surface of [kind] shows, over a bar
  /// when [overBar].
  ///
  /// A lens over a bar is a tab bar's, a lens over a plain track a
  /// segmented control's, a knob a switch's and a thumb a slider's.
  static ({double magnification, double shrink, double rim}) liftedOptics(
    MorphGlassKind kind, {
    required bool overBar,
  }) => switch (kind) {
    MorphGlassKind.lens =>
      overBar
          ? (
              magnification: tabBarMagnification,
              shrink: tabBarShrink,
              rim: tabBarShrinkRim,
            )
          : (
              magnification: segmentedMagnification,
              shrink: segmentedShrink,
              rim: lensShrinkRim,
            ),
    MorphGlassKind.knob => (
      magnification: 0.0,
      shrink: switchKnobShrink,
      rim: lensShrinkRim,
    ),
    MorphGlassKind.thumb ||
    MorphGlassKind.track ||
    MorphGlassKind.bar ||
    MorphGlassKind.button ||
    MorphGlassKind.menu => (magnification: 0.0, shrink: 0.0, rim: 0.0),
  };

  /// Whether a surface of [kind] floats over its control: a lens, knob or
  /// thumb, an opaque platter at rest and glass only while lifted.
  static bool floats(MorphGlassKind kind) => switch (kind) {
    MorphGlassKind.lens || MorphGlassKind.knob || MorphGlassKind.thumb => true,
    MorphGlassKind.track ||
    MorphGlassKind.bar ||
    MorphGlassKind.button ||
    MorphGlassKind.menu => false,
  };

  /// How far a floating surface has turned from its resting platter into
  /// glass, 0 to 1 over the first quarter of its lift; 1 for every other
  /// surface.
  ///
  /// A lift up to [restingLift] is still the platter, so the glass starts
  /// where the lifted look does and both flip in the same frame: a lift
  /// that has just begun when a frame samples it no longer rebuilds the
  /// surface twice. The glass it skips is at most 2 % of its blend
  /// (0.005 over the 0.25 span), for the first ~4 ms of a lift and the
  /// last frames of a landing: invisible, NEAR.
  static double glassness(MorphGlassSurface surface) {
    if (!floats(surface.kind)) return 1;
    if (surface.lift <= restingLift) return 0;
    return (surface.lift / MorphGlassDefaults.glassLiftSpan).clamp(0.0, 1.0);
  }

  bool get _exact => runtimeType == GlassBuiltInPainter;

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) =>
      _surface(
        context,
        MorphMorphFixedSource(MorphGlassFrame([surface])),
        (f) => f.surfaces.single,
      );

  @override
  Widget buildBody(
    BuildContext context,
    MorphGlassOutline outline,
    List<MorphGlassSurface> surfaces,
  ) => _body(
    context,
    MorphMorphFixedSource(MorphGlassFrame(surfaces, outline: outline)),
    (f) => (f.surfaces, f.outline!),
  );

  @override
  Widget buildLayer(
    BuildContext context,
    List<MorphGlassSurface> surfaces, {
    Widget? content,
    List<Rect> contentSlots = const [],
    double spacing = 0,
    MorphGlassOutline? outline,
  }) => _layer(
    context,
    MorphMorphFixedSource(
      MorphGlassFrame(
        surfaces,
        outline: outline,
        contentSlots: contentSlots,
        spacing: spacing,
      ),
    ),
    content: content,
  );

  /// What decides the widget tree of [mode] for [frame]: two frames with
  /// equal structures draw through the same render objects, so the second
  /// is pushed into the tree the first built.
  @internal
  Object structureOf(
    MorphGlassMode mode,
    MorphGlassFrame frame, {
    required bool content,
  }) {
    final tier = effectiveTier;
    return MorphListKey<Object?>(switch (mode) {
      MorphGlassMode.layer when morphGlassLayerSlots(frame) => [
        tier,
        content,
        'slots',
        frame.surfaces.length,
        frame.surfaces.first.brightness,
        if (tier == MorphGlassTier.flat) _flatMerged(frame),
      ],
      MorphGlassMode.layer => [
        tier,
        content,
        ..._layerStructure(tier, frame.partsFor(tier)),
      ],
      MorphGlassMode.surface => [
        tier,
        ..._surfaceStructure(tier, frame.surfaces.single),
      ],
      MorphGlassMode.fill => const [],
      MorphGlassMode.body => [
        tier,
        ..._bodyStructure(tier, frame.surfaces, frame.outline!),
      ],
    });
  }

  /// Builds the tree of [mode] whose render objects follow [source].
  @internal
  Widget buildFrom(
    BuildContext context,
    MorphGlassMode mode,
    MorphGlassSource source, {
    Widget? content,
  }) => switch (mode) {
    MorphGlassMode.layer => _layer(context, source, content: content),
    MorphGlassMode.surface => _surface(
      context,
      source,
      (f) => f.surfaces.single,
    ),
    MorphGlassMode.fill => liveFill(context, source, (f) => f.surfaces.single),
    MorphGlassMode.body => _body(
      context,
      source,
      (f) => (f.surfaces, f.outline!),
    ),
  };

  /// Whether the flat tier fills every fused body of [frame] by the merge
  /// law per pixel: each body's widget is chosen when the tree is built.
  static bool _flatMerged(MorphGlassFrame frame) =>
      MorphFlatBodyShader.enabled &&
      frame
          .partsFor(MorphGlassTier.flat)
          .fused
          .every((body) => body.$1.length <= MorphFlatBodyShader.maxBoxes);

  static List<Object?> _surfaceStructure(
    MorphGlassTier tier,
    MorphGlassSurface surface,
  ) => [
    surface.kind,
    surface.brightness,
    _visible(surface),
    surface.glass,
    glassness(surface) == 0,
  ];

  static List<Object?> _bodyStructure(
    MorphGlassTier tier,
    List<MorphGlassSurface> surfaces,
    MorphGlassOutline outline,
  ) => [
    surfaces.length,
    for (final s in surfaces) s.kind,
    surfaces.first.brightness,
    morphGlassOutlineField(outline) != null,
    morphGlassOutlineShapes(outline) != null,
    morphGlassOutlineMergedBoxes(outline) != null,
  ];

  static List<Object?> _layerStructure(
    MorphGlassTier tier,
    MorphGlassLayerParts parts,
  ) => [
    parts.fills.length,
    parts.separate.length,
    for (final s in parts.separate) ..._surfaceStructure(tier, s),
    parts.fused.length,
    for (final (surfaces, outline) in parts.fused)
      ..._bodyStructure(tier, surfaces, outline),
    parts.floating.length,
    for (final s in parts.floating) ...[
      ..._surfaceStructure(tier, s),
      glassness(s) < 1,
      s.lift > restingLift,
    ],
  ];

  /// The flat fill of the surface [select] picks, following [source]; the
  /// installed painter's own [buildFill] for a subclass.
  @internal
  Widget liveFill(
    BuildContext context,
    MorphGlassSource source,
    MorphGlassSurface Function(MorphGlassFrame frame) select,
  ) => _exact
      ? morphGlassLiveFill(source, select)
      : buildFill(context, select(source.frame));

  Widget _surface(
    BuildContext context,
    MorphGlassSource source,
    MorphGlassSurface Function(MorphGlassFrame frame) select,
  ) {
    final surface = select(source.frame);
    if (!_visible(surface)) return const SizedBox.expand();
    if (!surface.glass) return liveFill(context, source, select);
    return switch (effectiveTier) {
      MorphGlassTier.flat => liveFill(context, source, select),
      MorphGlassTier.fake || MorphGlassTier.liquid => morphLiquidSurface(
        this,
        context,
        source,
        select,
      ),
    };
  }

  Widget _body(
    BuildContext context,
    MorphGlassSource source,
    (List<MorphGlassSurface>, MorphGlassOutline) Function(MorphGlassFrame f)
    select,
  ) => switch (effectiveTier) {
    MorphGlassTier.flat => morphGlassLiveBody(source, select),
    MorphGlassTier.fake ||
    MorphGlassTier.liquid => morphLiquidBody(this, context, source, select),
  };

  Widget _layer(
    BuildContext context,
    MorphGlassSource source, {
    Widget? content,
  }) {
    if (effectiveTier != MorphGlassTier.flat) {
      return morphLiquidLayer(this, context, source, content: content);
    }
    if (_exact && source.live != null && morphGlassLayerSlots(source.frame)) {
      return _flatSlots(source, content: content);
    }
    MorphGlassLayerParts partsOf(MorphGlassFrame f) =>
        _exact ? f.partsFor(MorphGlassTier.flat) : f.parts;
    final parts = partsOf(source.frame);
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
    return MorphLiveStack(
      live: source.live,
      children: [
        for (var i = 0; i < parts.fills.length; i++)
          at(
            ('fill', i),
            (f) => partsOf(f).fills[i].bounds,
            () => liveFill(context, source, (f) => partsOf(f).fills[i]),
          ),
        for (var i = 0; i < parts.separate.length; i++)
          at(
            ('surface', i),
            (f) => partsOf(f).separate[i].bounds,
            () => _exact
                ? _surface(context, source, (f) => partsOf(f).separate[i])
                : buildSurface(context, parts.separate[i]),
          ),
        for (var i = 0; i < parts.fused.length; i++)
          source.keep(
            ('body', i),
            () => Positioned.fill(
              key: ValueKey<(String, int)>(('body', i)),
              child: _exact
                  ? _body(context, source, (f) => partsOf(f).fused[i])
                  : buildBody(context, parts.fused[i].$2, parts.fused[i].$1),
            ),
          ),
        for (var i = 0; i < parts.floating.length; i++)
          at(
            ('floating', i),
            (f) => partsOf(f).floating[i].bounds,
            () => _exact
                ? _surface(context, source, (f) => partsOf(f).floating[i])
                : buildSurface(context, parts.floating[i]),
          ),
        if (content != null)
          Positioned.fill(
            key: const ValueKey<String>('content'),
            child: content,
          ),
      ],
    );
  }

  /// The flat tier of a slotted layer ([morphGlassLayerSlots]): a fill for every
  /// surface drawn as its own shape and a body for every fused group the
  /// surfaces can form, each empty while the frame has nothing for it, in
  /// the unslotted layer's order and keys.
  Widget _flatSlots(MorphGlassSource source, {Widget? content}) {
    final count = source.frame.surfaces.length;
    final merged = _flatMerged(source.frame);
    MorphGlassLayerParts partsOf(MorphGlassFrame f) =>
        f.partsFor(MorphGlassTier.flat);
    MorphGlassSurface? separate(MorphGlassFrame f, int i) {
      final separate = partsOf(f).separate;
      return i < separate.length ? separate[i] : null;
    }

    (List<MorphGlassSurface>, MorphGlassOutline)? fused(
      MorphGlassFrame f,
      int i,
    ) {
      final fused = partsOf(f).fused;
      return i < fused.length ? fused[i] : null;
    }

    return MorphLiveStack(
      live: source.live,
      children: [
        for (var i = 0; i < count; i++)
          source.keep(
            ('surface', i),
            () => MorphLivePositioned(
              key: ValueKey<(String, int)>(('surface', i)),
              rect: source.pick((f) => separate(f, i)?.bounds ?? Rect.zero),
              child: morphGlassLiveFillSlot(source, (f) => separate(f, i)),
            ),
          ),
        for (var i = 0; i < count ~/ 2; i++)
          source.keep(
            ('body', i),
            () => Positioned.fill(
              key: ValueKey<(String, int)>(('body', i)),
              child: morphGlassLiveBodySlot(
                source,
                (f) => fused(f, i),
                merged: merged,
              ),
            ),
          ),
        if (content != null)
          Positioned.fill(
            key: const ValueKey<String>('content'),
            child: content,
          ),
      ],
    );
  }

  static bool _visible(MorphGlassSurface surface) =>
      surface.bounds.width >= 0.5 && surface.bounds.height >= 0.5;

  @override
  bool operator ==(Object other) =>
      other is GlassBuiltInPainter &&
      other.tier == tier &&
      other.material == material &&
      other.blur == blur &&
      other.refraction == refraction &&
      other.light == light &&
      other.tint == tint &&
      other.frostControls == frostControls;

  @override
  int get hashCode =>
      Object.hash(tier, material, blur, refraction, light, tint, frostControls);
}

/// Whether a layer host keeps one tree of slots for [frame]: a
/// [MorphGlassFrame.slotted] frame whose surfaces are all glass body
/// surfaces of a container ([MorphGlassFrame.spacing] above 0) that
/// neither float nor frost, so any of them may be drawn as its own shape
/// or as a member of any fused body without a change of tree.
@internal
bool morphGlassLayerSlots(MorphGlassFrame frame) =>
    frame.slotted &&
    frame.outline == null &&
    frame.spacing > 0 &&
    frame.surfaces.isNotEmpty &&
    frame.surfaces.every(
      (s) =>
          s.glass &&
          !GlassBuiltInPainter.floats(s.kind) &&
          s.kind != MorphGlassKind.bar &&
          s.kind != MorphGlassKind.menu,
    );

/// Whether [painter] draws a control's content only as it paints, never
/// recording it to copy it into a lens, so the content may hold repaint
/// boundaries of its own: no painter, or the package's renderer on the
/// flat tier.
@internal
bool morphGlassKeepsContentLive(MorphGlassPainter? painter) =>
    switch (painter) {
      null => true,
      final GlassBuiltInPainter renderer when renderer._exact =>
        renderer.effectiveTier == MorphGlassTier.flat,
      _ => false,
    };

/// Whether glass drawn with [painter] shows a touch glow
/// ([MorphGlassSurface.glow]): the package's renderer only on its liquid
/// tier, any other painter as far as the control can tell, no painter
/// never. A control whose glass shows none spends no frame on its glow.
@internal
bool morphGlassLightsGlow(MorphGlassPainter? painter) => switch (painter) {
  null => false,
  final GlassBuiltInPainter renderer when renderer._exact =>
    renderer.effectiveTier == MorphGlassTier.liquid,
  _ => true,
};

/// Whether a control drawing with [painter] needs the field of the
/// outlines it fuses, or their edge alone.
///
/// Only the package's own [GlassBuiltInPainter] on the flat tier, which
/// fills a fused body's path, and no painter at all, where the control
/// fills it itself, need the edge alone; any other painter may shade the
/// body from its field.
@internal
bool morphGlassShadesOutlines(MorphGlassPainter? painter) => switch (painter) {
  null => false,
  final GlassBuiltInPainter renderer when renderer._exact =>
    renderer.effectiveTier != MorphGlassTier.flat,
  _ => true,
};

/// The surfaces of one [MorphGlassPainter.buildLayer] call, sorted by how
/// a tier draws them, with the glass bodies the package fused.
@internal
@immutable
class MorphGlassLayerParts {
  const MorphGlassLayerParts._({
    required this.fills,
    required this.separate,
    required this.fused,
    required this.floating,
  });

  /// Sorts the visible [surfaces] of a layer: plain fills, glass body
  /// surfaces drawn as their own shapes, glass bodies fused into one
  /// outline - the control's [outline], or the groups a glass container
  /// with [spacing] fuses - and floating lenses, knobs and thumbs.
  /// With [withField] false, generated fused bodies carry their silhouette
  /// alone, or, with [MorphFlatBodyShader.enabled], those of at most
  /// [MorphFlatBodyShader.maxBoxes] surfaces their boxes for a flat fill
  /// that merges them per pixel ([morphGlassContainerMergedOutline]); with
  /// [boxes] true, those of at most [GlassBoxField.maxBoxes] surfaces carry
  /// their boxes for a liquid layer that merges them itself
  /// ([morphGlassContainerBoxOutline]). Supplied [outline] values are
  /// retained unchanged.
  factory MorphGlassLayerParts.of(
    List<MorphGlassSurface> surfaces, {
    double spacing = 0,
    MorphGlassOutline? outline,
    bool withField = true,
    bool boxes = false,
  }) {
    final visible = [
      for (final s in surfaces)
        if (GlassBuiltInPainter._visible(s)) s,
    ];
    final body = [
      for (final s in visible)
        if (s.glass && !GlassBuiltInPainter.floats(s.kind)) s,
    ];
    final separate = <MorphGlassSurface>[];
    final fused = <(List<MorphGlassSurface>, MorphGlassOutline)>[];
    if (outline != null && body.isNotEmpty) {
      fused.add((body, outline));
    } else {
      for (final group in morphGlassContainerGroups([
        for (final s in body) s.shape,
      ], spacing)) {
        if (group.length == 1) {
          separate.add(body[group.single]);
        } else {
          final members = [for (final i in group) body[i]];
          final shapes = [for (final s in members) s.shape];
          fused.add((
            members,
            switch (shapes.length) {
              _ when boxes => morphGlassContainerBoxOutline(shapes, spacing),
              <= MorphFlatBodyShader.maxBoxes
                  when !withField && MorphFlatBodyShader.enabled =>
                morphGlassContainerMergedOutline(shapes, spacing),
              _ => morphGlassContainerOutline(
                shapes,
                spacing,
                withField: withField,
              ),
            },
          ));
        }
      }
    }
    return MorphGlassLayerParts._(
      fills: [
        for (final s in visible)
          if (!s.glass) s,
      ],
      separate: separate,
      fused: fused,
      floating: [
        for (final s in visible)
          if (s.glass && GlassBuiltInPainter.floats(s.kind)) s,
      ],
    );
  }

  /// The plain surfaces, drawn flat on every tier.
  final List<MorphGlassSurface> fills;

  /// The glass body surfaces drawn as their own shapes.
  final List<MorphGlassSurface> separate;

  /// The glass bodies fused into one outline each, with their surfaces.
  final List<(List<MorphGlassSurface>, MorphGlassOutline)> fused;

  /// The lenses, knobs and thumbs.
  final List<MorphGlassSurface> floating;

  /// Every glass body surface, separate and fused.
  List<MorphGlassSurface> get body => [
    ...separate,
    for (final (surfaces, _) in fused) ...surfaces,
  ];
}
