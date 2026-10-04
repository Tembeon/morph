import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/glass.dart';
import 'package:morph/src/glass/renderer/internal/glass_defaults.dart';
import 'package:morph/src/widgets/glass_liquid.dart';
import 'package:morph/src/widgets/glass_outline.dart';

/// The quality tiers of [MorphGlassRenderer], cheapest first.
///
/// Every tier draws the same shapes: the package computes each surface's
/// outline, the fused silhouettes of a menu and its button or of a bar's
/// capsules, the lens deformation and the content placement once, and a
/// tier only decides how the outline is shaded. A device that cannot keep
/// up steps down a tier ([MorphAdaptiveGlass]) and the controls keep their
/// geometry, their motion and their fusion.
enum MorphGlassTier {
  /// A flat fill of each outline in the surface's color, no backdrop
  /// sampling: the cheapest tier, for weak devices.
  flat,

  /// Frosted glass: the backdrop blurred inside each outline and tinted by
  /// the surface's color, with a thin rim; a resting lens, knob or thumb
  /// stays its opaque platter. No shader, so it runs wherever Flutter
  /// runs, the web included.
  frosted,

  /// Liquid glass: refraction at the rim, magnification and the measured
  /// lens optics, frost and rim light, rendered on the GPU by the package's
  /// glass renderer. Needs Impeller with Flutter GPU (iOS, macOS,
  /// Android); elsewhere the renderer draws [frosted] in its place.
  liquid,
}

/// The iOS 27 glass materials the liquid tier is fitted to.
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
/// Install it with [MorphGlass], or with [MorphAdaptiveGlass], which picks
/// the tier from the frame timings the device achieves. Only surfaces that
/// are glass in iOS 27 become glass: a plain surface
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
/// Enable Flutter GPU with `FLTEnableFlutterGPU` in the Apple app's
/// Info.plist or `io.flutter.embedding.android.EnableFlutterGPU` in the
/// Android manifest, and use Impeller. Call [precache] before installing
/// a fixed renderer; [MorphAdaptiveGlass] follows initialization itself.
/// Until shaders are ready, or if they fail, liquid draws frosted and
/// reports [MorphGlassTier.frosted]. A failure logs once in debug builds.
/// Native builds need Flutter's data asset support enabled to package the GPU
/// bundle (`flutter config --enable-dart-data-assets` on toolchains with
/// the feature flag). Toolchains without data assets keep the frosted fallback.
/// Wrap a fixed renderer's controls in [BackdropGroup] to share backdrop
/// copies; overlapping glass that samples other glass needs its own group.
@immutable
class MorphGlassRenderer extends MorphGlassPainter {
  /// Creates a renderer at [tier] with the liquid tier's settings.
  const MorphGlassRenderer({
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

  /// The material preset of the liquid tier.
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
  /// shaders; there [MorphGlassTier.liquid] draws [MorphGlassTier.frosted].
  static bool get liquidAvailable => morphLiquidGlassAvailable;

  /// The best tier currently available on this runtime.
  static MorphGlassTier get bestTier =>
      liquidAvailable ? MorphGlassTier.liquid : MorphGlassTier.frosted;

  /// The tier this renderer draws: [tier], or [bestTier] when the build
  /// cannot draw [tier].
  MorphGlassTier get effectiveTier =>
      tier.index <= bestTier.index ? tier : bestTier;

  /// Loads the liquid tier's shaders, so the first glass on screen is
  /// already the real one; completes at once where there is no liquid tier.
  /// On Android, calling before `runApp` can wait for the engine's GPU
  /// context initialization; it does not wait for an application frame.
  static Future<void> precache() => morphPrecacheLiquidGlass();

  /// The same renderer at [tier], or with any other setting replaced.
  MorphGlassRenderer copyWith({
    MorphGlassTier? tier,
    MorphGlassMaterial? material,
    double? blur,
    double? refraction,
    double? light,
    double? tint,
    bool? frostControls,
  }) => MorphGlassRenderer(
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
  static double glassness(MorphGlassSurface surface) => floats(surface.kind)
      ? (surface.lift / MorphGlassDefaults.glassLiftSpan).clamp(0.0, 1.0)
      : 1.0;

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    if (!_visible(surface)) return const SizedBox.expand();
    if (!surface.glass) return buildFill(context, surface);
    return switch (effectiveTier) {
      MorphGlassTier.flat => buildFill(context, surface),
      MorphGlassTier.frosted when glassness(surface) == 0 => buildFill(
        context,
        surface,
      ),
      MorphGlassTier.frosted => _FrostedSurface(surface: surface),
      MorphGlassTier.liquid => morphLiquidSurface(this, context, surface),
    };
  }

  @override
  Widget buildBody(
    BuildContext context,
    MorphGlassOutline outline,
    List<MorphGlassSurface> surfaces,
  ) => switch (effectiveTier) {
    MorphGlassTier.flat => super.buildBody(context, outline, surfaces),
    MorphGlassTier.frosted => _FrostedBody(
      outline: outline,
      surface: surfaces.first,
    ),
    MorphGlassTier.liquid => morphLiquidBody(this, context, outline, surfaces),
  };

  @override
  Widget buildLayer(
    BuildContext context,
    List<MorphGlassSurface> surfaces, {
    Widget? content,
    List<Rect> contentSlots = const [],
    double spacing = 0,
    MorphGlassOutline? outline,
  }) {
    final parts = MorphGlassLayerParts.of(
      surfaces,
      spacing: spacing,
      outline: outline,
    );
    if (effectiveTier == MorphGlassTier.liquid) {
      return morphLiquidLayer(
        this,
        context,
        parts,
        content: content,
        contentSlots: contentSlots,
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final (i, surface) in parts.fills.indexed)
          Positioned.fromRect(
            key: ValueKey<(String, int)>(('fill', i)),
            rect: surface.bounds,
            child: buildFill(context, surface),
          ),
        for (final (i, surface) in parts.separate.indexed)
          Positioned.fromRect(
            key: ValueKey<(String, int)>(('surface', i)),
            rect: surface.bounds,
            child: buildSurface(context, surface),
          ),
        for (final (i, (bodySurfaces, bodyOutline)) in parts.fused.indexed)
          Positioned.fill(
            key: ValueKey<(String, int)>(('body', i)),
            child: buildBody(context, bodyOutline, bodySurfaces),
          ),
        for (final (i, surface) in parts.body.indexed)
          if (surface.glow != null)
            Positioned.fromRect(
              key: ValueKey<(String, int)>(('glow', i)),
              rect: surface.bounds,
              child: buildGlow(context, surface),
            ),
        for (final (i, surface) in parts.floating.indexed)
          Positioned.fromRect(
            key: ValueKey<(String, int)>(('floating', i)),
            rect: surface.bounds,
            child: buildSurface(context, surface),
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
      other is MorphGlassRenderer &&
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
  factory MorphGlassLayerParts.of(
    List<MorphGlassSurface> surfaces, {
    double spacing = 0,
    MorphGlassOutline? outline,
  }) {
    final visible = [
      for (final s in surfaces)
        if (MorphGlassRenderer._visible(s)) s,
    ];
    final body = [
      for (final s in visible)
        if (s.glass && !MorphGlassRenderer.floats(s.kind)) s,
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
          fused.add((
            members,
            morphGlassContainerOutline([
              for (final s in members) s.shape,
            ], spacing),
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
          if (s.glass && MorphGlassRenderer.floats(s.kind)) s,
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

/// The frosted tier's blur of [surface]'s backdrop, in logical pixels.
double _frostSigma(MorphGlassSurface surface) =>
    switch (surface.kind) {
      MorphGlassKind.bar ||
      MorphGlassKind.menu => MorphGlassDefaults.chromeFrost,
      MorphGlassKind.button => MorphGlassDefaults.buttonFrost,
      MorphGlassKind.track => MorphGlassDefaults.trackFrost,
      MorphGlassKind.lens || MorphGlassKind.knob || MorphGlassKind.thumb =>
        MorphGlassDefaults.floatingFrost +
            (surface.optics?.blurRadiusAt(surface.lift) ?? 0),
    } *
    surface.opacity.clamp(0.0, 1.0);

Color _faded(Color color, double opacity) =>
    color.withValues(alpha: color.a * opacity.clamp(0.0, 1.0));

/// One frosted surface: the backdrop blurred inside its shape, tinted by
/// its color, with a rim and a highlight that grows with its lift.
class _FrostedSurface extends StatelessWidget {
  const _FrostedSurface({required this.surface});

  final MorphGlassSurface surface;

  @override
  Widget build(BuildContext context) {
    final shape = surface.localShape;
    final radius = BorderRadius.only(
      topLeft: shape.tlRadius,
      topRight: shape.trRadius,
      bottomLeft: shape.blRadius,
      bottomRight: shape.brRadius,
    );
    final dark = surface.brightness == Brightness.dark;
    final sigma = _frostSigma(surface);
    final opacity = surface.opacity;
    final highlight =
        MorphGlassDefaults.frostHighlight +
        MorphGlassDefaults.frostLiftHighlight * surface.lift;
    const white = Color(0xFFFFFFFF);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        backdropGroupKey: BackdropGroup.of(context)?.backdropKey,
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: DecoratedBox(
          decoration: BoxDecoration(color: _faded(surface.color, opacity)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                width: MorphGlassDefaults.frostRimWidth,
                color: _faded(
                  white.withValues(
                    alpha: dark
                        ? MorphGlassDefaults.darkFrostRim
                        : MorphGlassDefaults.lightFrostRim,
                  ),
                  opacity,
                ),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _faded(white.withValues(alpha: highlight), opacity),
                  white.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A frosted fused body: the backdrop blurred inside its outline, tinted
/// by the color of its first surface, with a rim along the outline.
class _FrostedBody extends StatelessWidget {
  const _FrostedBody({required this.outline, required this.surface});

  final MorphGlassOutline outline;
  final MorphGlassSurface surface;

  @override
  Widget build(BuildContext context) {
    final sigma = _frostSigma(surface);
    final dark = surface.brightness == Brightness.dark;
    return ClipPath(
      clipper: MorphGlassOutlineClip(outline.path),
      child: BackdropFilter(
        backdropGroupKey: BackdropGroup.of(context)?.backdropKey,
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: CustomPaint(
          painter: _RimPainter(
            outline.path,
            _faded(surface.color, surface.opacity),
            _faded(
              dark
                  ? MorphGlassDefaults.darkBodyRim
                  : MorphGlassDefaults.lightBodyRim,
              surface.opacity,
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _RimPainter extends CustomPainter {
  const _RimPainter(this.path, this.color, this.rim);

  final Path path;
  final Color color;
  final Color rim;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    fill.color = color;
    canvas.drawPath(path, fill);
    final stroke = Paint();
    stroke.style = PaintingStyle.stroke;
    stroke.strokeWidth = MorphGlassDefaults.bodyRimWidth;
    stroke.color = rim;
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_RimPainter oldDelegate) =>
      oldDelegate.path != path ||
      oldDelegate.color != color ||
      oldDelegate.rim != rim;
}
