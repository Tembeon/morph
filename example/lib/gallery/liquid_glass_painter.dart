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
/// Only surfaces that are glass in iOS 27 become glass: a plain surface
/// (`MorphGlassSurface.glass` false - the segmented, switch and slider
/// tracks, the stepper) is a flat fill. A control's glass body surfaces
/// (bar, button, menu) share a layer, and a menu fuses with its button in
/// a blend group; the capsules of a bar form a blend group of the bar's
/// container spacing (12, so resting groups 12 apart stay separate and
/// only capsules passing closer during an item change fuse). A resting lens,
/// knob or thumb is an opaque platter under the control's content;
/// lifted, it turns into glass in a layer of its own above everything of
/// the control, with its own backdrop copy, so it refracts what lies
/// under it - the bar's glass included (glass on glass). Lifted, a tab
/// bar lens, a segmented lens and a switch knob minify what lies beneath
/// them, and a tab bar lens shows its items magnified by
/// `1 + 0.16 * lift` while a segmented lens shows its labels at their own
/// size, as UIKit's do ([liftedOptics]): the renderer never enlarges its
/// backdrop, so the content is drawn once more inside the lens's outline,
/// grown against the shrink, cut out of the plane, and BELOW the lens
/// glass, which then bends it and the rim of what it floats over at its
/// bevel as UIKit's lens does.
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

  /// The renderer refraction per pixel of UIKit lens displacement.
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
  /// about its center line instead of its center
  /// (`LiquidGlassSettings.backdropShrinkRim`).
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

  /// Half the center line a lens with [bounds] shrinks the backdrop about
  /// at rim weight [rim], from the lens center along its longer side.
  static Offset shrinkAxis(Rect bounds, double rim) {
    final half = rim * (bounds.longestSide - bounds.shortestSide) / 2;
    return bounds.width >= bounds.height ? Offset(half, 0) : Offset(0, half);
  }

  /// How far from its center [surface]'s glass reads the backdrop for a
  /// point on its face when its layer shrinks the backdrop by [shrink].
  ///
  /// The renderer fades the shrink in with the glass's visibility, so a
  /// lens still turning from platter into glass shrinks less.
  static double backdropScale(MorphGlassSurface surface, double shrink) =>
      1 +
      (1 / (1 - shrink) - 1) *
          glassness(surface) *
          surface.opacity.clamp(0.0, 1.0);

  /// The lift below which a lens, knob or thumb is only its platter.
  static const double restingLift = 0.005;

  /// The distance within which a menu fuses with its button.
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
    final amount = optics == null
        ? preset.refractionAmount
        : optics.displacementAt(lift) * lensRefraction;
    return preset.copyWith(
      frost: frost * blur,
      refractionAmount: amount * refraction,
      dispersion: optics == null ? preset.dispersion : lensDispersion * lift,
      highlight: preset.highlight * light * (1 + 0.5 * lift),
    );
  }

  /// The renderer appearance for [surface], tinted by its flat color.
  ///
  /// A lifted lens, knob or thumb is clear glass: no wash and no tint, so
  /// what lies under it - a track, a bar's glass - shows through at its own
  /// brightness, as through UIKit's lifted lens.
  LiquidGlassAppearance appearanceFor(MorphGlassSurface surface) =>
      _floats(surface.kind)
      ? const LiquidGlassAppearance()
      : switch (material) {
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
      visibility:
          base.visibility *
          glassness(surface) *
          surface.opacity.clamp(0.0, 1.0),
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

  Widget _layer(
    List<MorphGlassSurface> surfaces, {
    bool shared = true,
    double shrink = 0,
    double rim = 0,
    double spacing = 0,
  }) {
    final menu = surfaces.any(
      (MorphGlassSurface s) => s.kind == MorphGlassKind.menu,
    );
    final grouped = surfaces.length > 1 && (menu || spacing > 0);
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
      shapes = LiquidGlassBlendGroup(
        blend: spacing > 0 ? spacing : blend,
        child: shapes,
      );
    }
    return ClipRect(
      clipper: const _Reach(),
      child: LiquidGlassLayer(
        settings: shrink == 0
            ? settingsFor(surfaces.first)
            : settingsFor(
                surfaces.first,
              ).copyWith(backdropShrink: shrink, backdropShrinkRim: rim),
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
    if (!surface.glass) return buildFill(context, surface);
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
      glass: surface.glass,
      opacity: surface.opacity,
    );
    return _layer([local]);
  }

  @override
  Widget buildLayer(
    BuildContext context,
    List<MorphGlassSurface> surfaces, {
    Widget? content,
    List<Rect> contentSlots = const [],
    double spacing = 0,
  }) {
    final visible = surfaces.where(_visible).toList();
    final fills = [
      for (final s in visible)
        if (!s.glass) s,
    ];
    final body = [
      for (final s in visible)
        if (s.glass && !_floats(s.kind)) s,
    ];
    final floating = [
      for (final s in visible)
        if (s.glass && _floats(s.kind)) s,
    ];
    final chrome = body.any(
      (MorphGlassSurface s) =>
          s.kind == MorphGlassKind.bar || s.kind == MorphGlassKind.menu,
    );
    bool lifted(MorphGlassSurface s) => s.lift > restingLift;
    final overBar = body.any(
      (MorphGlassSurface s) => s.kind == MorphGlassKind.bar,
    );
    double shrinkOf(MorphGlassSurface s) =>
        liftedOptics(s.kind, overBar: overBar).shrink * s.lift.clamp(0.0, 1.0);
    final lenses = [
      for (final s in floating)
        if (s.kind == MorphGlassKind.lens && lifted(s)) s.shape,
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < fills.length; i++)
          Positioned.fromRect(
            key: ValueKey<(String, int)>(('fill', i)),
            rect: fills[i].bounds,
            child: buildFill(context, fills[i]),
          ),
        if (body.isNotEmpty)
          Positioned.fill(
            key: const ValueKey<String>('body'),
            child: _layer(body, shared: !chrome, spacing: spacing),
          ),
        for (var i = 0; i < body.length; i++)
          if (body[i].glow != null)
            Positioned.fromRect(
              key: ValueKey<(String, int)>(('glow', i)),
              rect: body[i].bounds,
              child: buildGlow(context, body[i]),
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
            if (content != null && floating[i].kind == MorphGlassKind.lens)
              Positioned.fill(
                key: ValueKey<(String, int)>(('copy', i)),
                child: _Magnified(
                  surface: floating[i],
                  slots: contentSlots,
                  magnification:
                      1 +
                      liftedOptics(
                            floating[i].kind,
                            overBar: overBar,
                          ).magnification *
                          floating[i].lift.clamp(0.0, 1.0),
                  grow: backdropScale(floating[i], shrinkOf(floating[i])),
                  axis: shrinkAxis(
                    floating[i].bounds,
                    liftedOptics(floating[i].kind, overBar: overBar).rim,
                  ),
                  child: content,
                ),
              ),
            Positioned.fill(
              key: ValueKey<(String, int)>(('glass', i)),
              child: _layer(
                [floating[i]],
                shared: false,
                shrink: shrinkOf(floating[i]),
                rim: liftedOptics(floating[i].kind, overBar: overBar).rim,
              ),
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
class _Magnified extends StatelessWidget {
  const _Magnified({
    required this.surface,
    required this.slots,
    required this.magnification,
    required this.grow,
    required this.axis,
    required this.child,
  });

  final MorphGlassSurface surface;
  final List<Rect> slots;
  final double magnification;
  final double grow;
  final Offset axis;
  final Widget child;

  static Matrix4 _across(Offset center, Offset axis, double scale) {
    final transform = Matrix4.translationValues(center.dx, center.dy, 0);
    transform.multiply(
      Matrix4.diagonal3Values(
        axis.dx == 0 ? scale : 1,
        axis.dy == 0 ? scale : 1,
        1,
      ),
    );
    transform.multiply(Matrix4.translationValues(-center.dx, -center.dy, 0));
    return transform;
  }

  Widget _grown(Widget items) {
    final center = surface.bounds.center;
    if (axis == Offset.zero) {
      return Transform(transform: _about(center, grow), child: items);
    }
    final start = center - axis;
    final end = center + axis;
    final reach = surface.bounds.inflate(surface.bounds.longestSide * grow);
    final alongX = axis.dy == 0;
    return Stack(
      fit: .expand,
      clipBehavior: Clip.none,
      children: [
        ClipRect(
          key: const ValueKey<String>('start'),
          clipper: _Strip(
            alongX
                ? Rect.fromLTRB(reach.left, reach.top, start.dx, reach.bottom)
                : Rect.fromLTRB(reach.left, reach.top, reach.right, start.dy),
          ),
          child: Transform(transform: _about(start, grow), child: items),
        ),
        ClipRect(
          key: const ValueKey<String>('band'),
          clipper: _Strip(
            alongX
                ? Rect.fromLTRB(start.dx, reach.top, end.dx, reach.bottom)
                : Rect.fromLTRB(reach.left, start.dy, reach.right, end.dy),
          ),
          child: Transform(
            transform: _across(center, axis, grow),
            child: items,
          ),
        ),
        ClipRect(
          key: const ValueKey<String>('end'),
          clipper: _Strip(
            alongX
                ? Rect.fromLTRB(end.dx, reach.top, reach.right, reach.bottom)
                : Rect.fromLTRB(reach.left, end.dy, reach.right, reach.bottom),
          ),
          child: Transform(transform: _about(end, grow), child: items),
        ),
      ],
    );
  }

  static Matrix4 _about(Offset center, double scale) {
    final transform = Matrix4.translationValues(center.dx, center.dy, 0);
    transform.multiply(Matrix4.diagonal3Values(scale, scale, 1));
    transform.multiply(Matrix4.translationValues(-center.dx, -center.dy, 0));
    return transform;
  }

  @override
  Widget build(BuildContext context) {
    Widget items = slots.isEmpty
        ? LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                _slot(Offset.zero & constraints.biggest),
          )
        : Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < slots.length; i++)
                if (slots[i].overlaps(surface.bounds))
                  Positioned.fill(
                    key: ValueKey<int>(i),
                    child: _slot(slots[i]),
                  ),
            ],
          );
    if (grow != 1) {
      items = ClipPath(
        clipper: _LensClip([surface.shape], outside: false),
        child: _grown(items),
      );
    }
    return IgnorePointer(child: ExcludeSemantics(child: items));
  }

  Widget _slot(Rect slot) => ClipPath(
    clipper: _SlotLensClip(surface.shape, slot),
    child: Transform(
      transform: _about(slot.center, magnification),
      child: child,
    ),
  );
}

class _SlotLensClip extends CustomClipper<Path> {
  const _SlotLensClip(this.lens, this.slot);

  final RRect lens;
  final Rect slot;

  @override
  Path getClip(Size size) {
    final path = Path();
    path.addRRect(lens);
    final box = Path();
    box.addRect(slot);
    return Path.combine(PathOperation.intersect, path, box);
  }

  @override
  bool shouldReclip(_SlotLensClip oldClipper) =>
      oldClipper.lens != lens || oldClipper.slot != slot;
}

class _Strip extends CustomClipper<Rect> {
  const _Strip(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_Strip oldClipper) => oldClipper.rect != rect;
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
