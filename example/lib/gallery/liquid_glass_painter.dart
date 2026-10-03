import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:morph/widgets.dart';

/// The iOS 27 glass materials the renderer is fitted to.
enum LiquidGlassMaterial {
  /// The regular material of `.glass` buttons and controls.
  regular,

  /// The toolbar material, with a stronger rim in dark mode.
  toolbar,

  /// The clear material: no wash, the full bevel on every shape.
  clear,
}

/// Renders the measured controls with the liquid glass renderer.
///
/// A control's body surfaces (track, bar, button, menu) share a layer,
/// and fuse in a blend group when there are several, as a menu does with
/// its button. A resting lens, knob or thumb is an opaque platter under
/// the control's content; lifted, it turns into glass in a layer of its
/// own above the body and the content, so it refracts both. A lifted lens
/// shows the content behind it magnified by `1 + 0.16 * lift`, the growth
/// the UIKit tab bar shows through its lifted lens: the renderer never
/// enlarges its backdrop, so the content is drawn once more inside the
/// lens at that scale and cut out of the plane below.
///
/// Every backdrop copy is a full-screen readback, so body glass reads the
/// one copy of the nearest [BackdropGroup] and only lifted glass, which
/// must refract the glass and content under it, and chrome that floats
/// over content (a bar, a menu) pay for their own. Frost is the dearest
/// part of a layer, so only bars, menus and lifted lenses frost unless
/// [frostControls] is on.
/// Glass in one group does not see what paints between its members: give
/// a section painted over the page (a card) a group of its own.
///
/// Lift drives the optics of a lens the way [MorphGlassOptics] describes
/// UIKit's: refraction grows from the resting to the lifted displacement
/// and frost falls from the resting blur to none.
class LiquidGlassRendererPainter extends MorphGlassPainter {
  /// Creates the painter from the gallery's glass settings.
  const LiquidGlassRendererPainter({
    this.material = LiquidGlassMaterial.regular,
    this.blur = 1,
    this.refraction = 1,
    this.light = 1,
    this.tint = 0,
    this.fake = false,
    this.frostControls = false,
  });

  /// The material preset.
  final LiquidGlassMaterial material;

  /// The factor on the preset's frost.
  final double blur;

  /// The factor on the preset's refraction.
  final double refraction;

  /// The factor on the preset's rim glint.
  final double light;

  /// The Liquid Glass slider position, 0 clear and 1 tinted.
  final double tint;

  /// Whether to draw the renderer's fallback glass without refraction.
  final bool fake;

  /// Whether tracks and buttons frost what is behind them as bars and
  /// menus do.
  ///
  /// Off by default: a frosted surface blurs its backdrop again on every
  /// frame anything on screen moves, which costs about a millisecond of
  /// raster per surface on an iPhone 16 Pro, and at control size over a
  /// plain page the frost is rarely visible.
  final bool frostControls;

  /// The growth of the content seen through a fully lifted lens.
  static const double lensMagnification = 0.16;

  /// The lift below which a lens, knob or thumb is only its platter.
  static const double restingLift = 0.005;

  /// The distance within which the body surfaces of one control fuse.
  static const double blend = 18;

  static bool _floats(MorphGlassKind kind) => switch (kind) {
    MorphGlassKind.lens || MorphGlassKind.knob || MorphGlassKind.thumb => true,
    MorphGlassKind.track ||
    MorphGlassKind.bar ||
    MorphGlassKind.button ||
    MorphGlassKind.menu => false,
  };

  LiquidGlassSettings _preset(Brightness brightness) => switch (material) {
    LiquidGlassMaterial.regular => LiquidGlassSettings(
      frost: LiquidGlassSettings.ios27RegularFrost(tint),
      tintAmount: tint,
    ),
    LiquidGlassMaterial.toolbar => LiquidGlassSettings.ios27Toolbar(
      brightness: brightness,
      tintAmount: tint,
    ),
    LiquidGlassMaterial.clear => LiquidGlassSettings.ios27Clear(
      tintAmount: tint,
    ),
  };

  /// The renderer settings for [surface]: the preset scaled by the
  /// gallery's factors, with a lens's optics interpolated by its lift.
  LiquidGlassSettings settingsFor(MorphGlassSurface surface) {
    final preset = _preset(surface.brightness);
    final optics = surface.optics;
    final lift = surface.lift.clamp(0.0, 1.0);
    final frosted =
        frostControls ||
        surface.kind == MorphGlassKind.bar ||
        surface.kind == MorphGlassKind.menu;
    final frost = optics != null
        ? optics.blurRadiusAt(lift)
        : frosted
        ? preset.frost
        : 0.0;
    final bend = optics == null
        ? 1.0
        : (optics.displacementAt(lift) / optics.liftedDisplacement).clamp(
            0.0,
            2.0,
          );
    return preset.copyWith(
      frost: frost * blur,
      refractionAmount: preset.refractionAmount * refraction * bend,
      highlight: preset.highlight * light * (1 + 0.5 * lift),
    );
  }

  /// The renderer appearance for [surface], tinted by its flat color.
  LiquidGlassAppearance appearanceFor(MorphGlassSurface surface) =>
      switch (material) {
        LiquidGlassMaterial.regular => LiquidGlassAppearance.ios27Regular(
          brightness: surface.brightness,
          tint: surface.color,
        ),
        LiquidGlassMaterial.toolbar => LiquidGlassAppearance.ios27Toolbar(
          brightness: surface.brightness,
          tint: surface.color,
        ),
        LiquidGlassMaterial.clear => LiquidGlassAppearance.ios27Clear(
          tint: surface.color,
        ),
      };

  static LiquidShape _shape(RRect shape) {
    final side = math.min(shape.width, shape.height);
    final radius = math.min(shape.tlRadiusX, side / 2);
    if (shape.width == shape.height && radius >= side / 2) {
      return const LiquidOval();
    }
    return LiquidRoundedSuperellipse(borderRadius: radius);
  }

  static List<BoxShadow> _shadows(MorphGlassSurface surface) =>
      switch (surface.kind) {
        MorphGlassKind.track || MorphGlassKind.bar => const [],
        MorphGlassKind.button || MorphGlassKind.menu => const [
          BoxShadow(
            color: Color(0x14000000),
            offset: Offset(0, 4),
            blurRadius: 16,
          ),
        ],
        MorphGlassKind.lens || MorphGlassKind.knob || MorphGlassKind.thumb => [
          BoxShadow(
            color: const Color(0x1A000000),
            offset: Offset(0, 1.5 + 2 * surface.lift),
            blurRadius: 3 + 6 * surface.lift,
          ),
        ],
      };

  /// How far a floating surface has turned from its resting platter into
  /// glass, 0 to 1 over the first quarter of its lift.
  static double glassness(MorphGlassSurface surface) =>
      _floats(surface.kind) ? (surface.lift / 0.25).clamp(0.0, 1.0) : 1.0;

  Widget _glass(MorphGlassSurface surface, {required bool grouped}) {
    final shape = _shape(surface.localShape);
    final base = appearanceFor(surface);
    final appearance = base.copyWith(
      visibility: base.visibility * glassness(surface),
    );
    final shadows = _shadows(surface);
    const child = SizedBox.expand();
    return grouped
        ? LiquidGlass.grouped(
            shape: shape,
            appearance: appearance,
            shadows: shadows,
            child: child,
          )
        : LiquidGlass(
            shape: shape,
            appearance: appearance,
            shadows: shadows,
            child: child,
          );
  }

  Widget _layer(List<MorphGlassSurface> surfaces, {bool shared = true}) {
    final grouped = surfaces.length > 1;
    Widget shapes = Stack(
      clipBehavior: Clip.none,
      children: [
        for (final surface in surfaces)
          Positioned.fromRect(
            rect: surface.bounds,
            child: _glass(surface, grouped: grouped),
          ),
      ],
    );
    if (grouped) {
      shapes = LiquidGlassBlendGroup(blend: blend, child: shapes);
    }
    return ClipRect(
      clipper: const _Reach(),
      child: LiquidGlassLayer(
        settings: settingsFor(surfaces.first),
        fake: fake,
        useBackdropGroup: shared,
        child: shapes,
      ),
    );
  }

  static bool _visible(MorphGlassSurface surface) =>
      surface.bounds.width >= 0.5 && surface.bounds.height >= 0.5;

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    if (!_visible(surface)) return const SizedBox.expand();
    final local = MorphGlassSurface(
      kind: surface.kind,
      shape: surface.localShape,
      color: surface.color,
      brightness: surface.brightness,
      lift: surface.lift,
      scaleX: surface.scaleX,
      scaleY: surface.scaleY,
      optics: surface.optics,
      enabled: surface.enabled,
    );
    return _layer([local]);
  }

  @override
  Widget buildLayer(
    BuildContext context,
    List<MorphGlassSurface> surfaces, {
    Widget? content,
  }) {
    final visible = surfaces.where(_visible).toList();
    final body = [
      for (final s in visible)
        if (!_floats(s.kind)) s,
    ];
    final floating = [
      for (final s in visible)
        if (_floats(s.kind)) s,
    ];
    final chrome = body.any(
      (MorphGlassSurface s) =>
          s.kind == MorphGlassKind.bar || s.kind == MorphGlassKind.menu,
    );
    bool lifted(MorphGlassSurface s) => s.lift > restingLift;
    final lenses = [
      for (final s in floating)
        if (s.kind == MorphGlassKind.lens && lifted(s)) s.shape,
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (body.isNotEmpty)
          Positioned.fill(
            key: const ValueKey<String>('body'),
            child: _layer(body, shared: !chrome),
          ),
        for (var i = 0; i < floating.length; i++)
          if (glassness(floating[i]) < 1)
            Positioned.fromRect(
              key: ValueKey<(String, int)>(('platter', i)),
              rect: floating[i].bounds,
              child: _Platter(
                surface: floating[i],
                opacity: 1 - glassness(floating[i]),
              ),
            ),
        if (content != null)
          Positioned.fill(
            key: const ValueKey<String>('content'),
            child: ClipPath(
              clipper: _LensClip(lenses, outside: true),
              child: content,
            ),
          ),
        for (var i = 0; i < floating.length; i++)
          if (lifted(floating[i])) ...[
            Positioned.fill(
              key: ValueKey<(String, int)>(('glass', i)),
              child: _layer([floating[i]], shared: false),
            ),
            if (content != null && floating[i].kind == MorphGlassKind.lens)
              Positioned.fill(
                key: ValueKey<(String, int)>(('copy', i)),
                child: _Magnified(surface: floating[i], child: content),
              ),
          ],
      ],
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
          boxShadow: LiquidGlassRendererPainter._shadows(surface),
        ),
      ),
    );
  }
}

/// The content seen through a lens: clipped to it and scaled about its
/// center by the lens's lift.
class _Magnified extends StatelessWidget {
  const _Magnified({required this.surface, required this.child});

  final MorphGlassSurface surface;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final center = surface.bounds.center;
    final scale =
        1 +
        LiquidGlassRendererPainter.lensMagnification *
            surface.lift.clamp(0.0, 1.0);
    final transform = Matrix4.translationValues(center.dx, center.dy, 0);
    transform.multiply(Matrix4.diagonal3Values(scale, scale, 1));
    transform.multiply(Matrix4.translationValues(-center.dx, -center.dy, 0));
    return IgnorePointer(
      child: ExcludeSemantics(
        child: ClipPath(
          clipper: _LensClip([surface.shape], outside: false),
          child: Transform(transform: transform, child: child),
        ),
      ),
    );
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
