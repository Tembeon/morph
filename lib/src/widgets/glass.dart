import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:morph/src/widgets/glass_glow.dart';

/// The role a surface plays in a control.
///
/// The kind names the part; whether the part is Liquid Glass is
/// [MorphGlassSurface.glass] and, for a lens, knob or thumb, its lift.
enum MorphGlassKind {
  /// The track of a segmented control, switch, slider or stepper: a plain
  /// fill in iOS 27, handed over with [MorphGlassSurface.glass] false.
  track,

  /// The selection lens of a segmented control or tab bar: an opaque
  /// platter at rest, glass only while lifted.
  lens,

  /// The knob of a switch: an opaque platter at rest, glass only while
  /// lifted.
  knob,

  /// The thumb of a slider: an opaque platter at rest, glass only while
  /// lifted.
  thumb,

  /// The body of a glass button.
  button,

  /// The floating body of a tab bar.
  bar,

  /// The platter of a menu grown out of its button, or of a sheet
  /// floating below its large detent.
  menu,
}

/// The refraction tuning UIKit gives a liquid lens.
///
/// A resting lens bends what is behind it by [unliftedDisplacement] and
/// blurs it by [unliftedBlurRadius]; a lifted one bends by
/// [liftedDisplacement] without blur. The values are UIKit's own, read
/// from its lens configuration; a [MorphGlassPainter] that refracts can
/// interpolate them by lift with [displacementAt] and [blurRadiusAt].
@immutable
class MorphGlassOptics {
  /// Creates optics from explicit values.
  const MorphGlassOptics({
    this.liftedDisplacement = 9,
    this.unliftedDisplacement = 0,
    this.unliftedBlurRadius = 0,
    this.contentWrapperDisplacement = -17.5,
    this.innerShadowRadius = 3,
    this.innerShadowOpacity = 0.06,
    this.innerShadowOffsetY = 7,
  });

  /// The refraction displacement of the lifted lens, in pixels.
  final double liftedDisplacement;

  /// The refraction displacement of the resting lens, in pixels.
  final double unliftedDisplacement;

  /// The blur radius of the resting lens, in pixels.
  final double unliftedBlurRadius;

  /// The displacement of the content seen through the lens, in pixels.
  final double contentWrapperDisplacement;

  /// The blur radius of the lens's inner shadow, in pixels.
  final double innerShadowRadius;

  /// The opacity of the lens's inner shadow.
  final double innerShadowOpacity;

  /// The vertical offset of the lens's inner shadow, in pixels.
  final double innerShadowOffsetY;

  /// The optics of the small lens, which rests frosted.
  static const small = MorphGlassOptics(
    unliftedDisplacement: 50,
    unliftedBlurRadius: 6,
  );

  /// The optics of the large lens, which rests clear.
  static const large = MorphGlassOptics();

  /// The refraction displacement at [lift], 0 resting and 1 lifted.
  double displacementAt(double lift) =>
      lerpDouble(unliftedDisplacement, liftedDisplacement, lift.clamp(0, 1))!;

  /// The blur radius at [lift], 0 resting and 1 lifted.
  double blurRadiusAt(double lift) =>
      lerpDouble(unliftedBlurRadius, 0, lift.clamp(0, 1))!;
}

/// One surface of a control in one frame, handed to a
/// [MorphGlassPainter].
///
/// Only some surfaces are Liquid Glass in iOS 27: bars, glass buttons,
/// menus, popovers, alerts, floating sheets and the search capsule. The
/// tracks of the segmented control, switch and slider and the stepper are
/// plain fills and come with [glass] false; a painter draws them flat. A
/// lens, knob or thumb is glass only while the finger lifts it: at
/// [lift] 0 it is an opaque platter of [color], and a painter turns it
/// into glass as [lift] grows.
@immutable
class MorphGlassSurface {
  /// Creates a surface description.
  const MorphGlassSurface({
    required this.kind,
    required this.shape,
    required this.color,
    required this.brightness,
    this.lift = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.optics,
    this.enabled = true,
    this.glass = true,
    this.opacity = 1,
    this.glow,
  });

  /// The role of the surface.
  final MorphGlassKind kind;

  /// The outline of the surface in the control's local coordinates,
  /// deformation included.
  final RRect shape;

  /// The flat fill the control would paint without a painter; a painter
  /// uses it as the tint of its glass.
  final Color color;

  /// The brightness the control resolved its colors for.
  final Brightness brightness;

  /// The lift progress, 0 resting and 1 fully lifted.
  final double lift;

  /// The deformation along the track already applied to [shape].
  final double scaleX;

  /// The deformation across the track already applied to [shape].
  final double scaleY;

  /// The refraction tuning of a lens surface, or null for a surface that
  /// does not refract.
  final MorphGlassOptics? optics;

  /// Whether the control accepts input.
  final bool enabled;

  /// Whether the surface is Liquid Glass natively.
  ///
  /// False for a plain fill, which every painter draws flat: [color] in
  /// [shape], nothing sampled from the backdrop.
  final bool glass;

  /// How much of the surface shows, 0 to 1: a surface fading in or out,
  /// such as a popover's platter while it opens.
  ///
  /// A control fades its glass through this value rather than an
  /// `Opacity` above the painter's widget: an opacity layer hands a
  /// backdrop-sampling surface the empty layer instead of what lies
  /// behind it. A painter fades everything it draws by it, the flat fill
  /// of [MorphGlassPainter.buildFill] included.
  final double opacity;

  /// The glow a finger raises on the surface, or null when it is not
  /// lit; a painter draws it with [MorphGlassPainter.buildGlow] over the
  /// surface and under the control's content.
  final MorphGlassGlow? glow;

  /// The box the surface occupies in the control's local coordinates.
  Rect get bounds => shape.outerRect;

  /// The [shape] relative to [bounds], for drawing inside a box placed
  /// at [bounds].
  RRect get localShape => shape.shift(-bounds.topLeft);
}

/// Renders the glass surfaces of the measured controls.
///
/// Without a painter the controls draw flat fills. Install one with
/// [MorphGlass] and every control below it builds its surfaces from the
/// painter instead, every frame, behind its content. A control with
/// several surfaces hands them to [buildLayer] together; a control with
/// one surface calls [buildSurface] for a glass surface and [buildFill]
/// for a plain one. The widget either returns is placed exactly at
/// [MorphGlassSurface.bounds], so [buildSurface] can sample the backdrop
/// with a `BackdropFilter`, run a shader or paint anything else.
///
/// A surface whose [MorphGlassSurface.glass] is false is not glass in
/// iOS 27 and must be drawn flat; [buildLayer] implementations route it
/// to [buildFill].
abstract class MorphGlassPainter {
  /// Creates a painter.
  const MorphGlassPainter();

  /// Builds the widget that draws the glass [surface], sized to its
  /// bounds.
  Widget buildSurface(BuildContext context, MorphGlassSurface surface);

  /// Builds the widget that draws the plain [surface] flat, sized to its
  /// bounds.
  ///
  /// The default fills [MorphGlassSurface.localShape] with
  /// [MorphGlassSurface.color], as the control does without a painter.
  Widget buildFill(BuildContext context, MorphGlassSurface surface) =>
      CustomPaint(
        painter: _FillPainter(
          surface.localShape,
          surface.color.withValues(
            alpha: surface.color.a * surface.opacity.clamp(0.0, 1.0),
          ),
        ),
      );

  /// Builds the widget that draws the [MorphGlassSurface.glow] of
  /// [surface], sized to its bounds and placed over the surface.
  ///
  /// The default applies the glow's wash and spot to what is already
  /// painted, inside [MorphGlassSurface.localShape]. A painter that
  /// renders [buildLayer] itself places this over each lit surface.
  Widget buildGlow(BuildContext context, MorphGlassSurface surface) {
    final glow = surface.glow;
    if (glow == null) return const SizedBox.expand();
    return CustomPaint(
      painter: MorphGlassGlowPainter(
        surface.localShape,
        MorphGlassGlow(
          wash: glow.wash,
          center: glow.center - surface.bounds.topLeft,
          radius: glow.radius,
          gain: glow.gain,
        ),
      ),
    );
  }

  /// Builds one glass layer of a control: its [surfaces], back to front,
  /// in a box that fills the layer, with the control's [content] over
  /// them.
  ///
  /// The surfaces of one call belong to one control and move together, so
  /// a painter can render them as a unit: share one backdrop sample, fuse
  /// neighbors, or show [content] through a lens. The default places each
  /// surface at its bounds, from [buildSurface] when it is glass and from
  /// [buildFill] when it is not, and [content] over them.
  ///
  /// [contentSlots] are the boxes of the items of [content] - the segments
  /// of a segmented control, the tabs of a tab bar - in the layer's local
  /// coordinates, each item centered in its box. They stay put while a
  /// lens moves over them. A painter that magnifies the content seen
  /// through a lens scales each item about the center of its own slot and
  /// clips it to that slot, so a label under a moving lens grows in place
  /// and never slides; only the lens window moves. Empty means the content
  /// is one item that fills the layer.
  ///
  /// A positive [spacing] makes the glass surfaces one glass container
  /// with that spacing, as UIKit's `UIGlassContainerEffect` and SwiftUI's
  /// `GlassEffectContainer` do: two surfaces closer than [spacing] lean
  /// toward each other and fuse once they are within half of it, by the
  /// merge law of the skin (`MorphSkin`, whose blend width the spacing
  /// is, 1:1); surfaces [spacing] or more apart do not touch. Zero keeps
  /// every surface separate. The bars pass 12, the spacing UIKit gives the
  /// glass container of a navigation bar and of a toolbar, which is also
  /// the gap between two groups of one bar: resting groups never fuse,
  /// moving ones fuse while they pass closer.
  Widget buildLayer(
    BuildContext context,
    List<MorphGlassSurface> surfaces, {
    Widget? content,
    List<Rect> contentSlots = const [],
    double spacing = 0,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final surface in surfaces) ...[
          Positioned.fromRect(
            rect: surface.bounds,
            child: surface.glass
                ? buildSurface(context, surface)
                : buildFill(context, surface),
          ),
          if (surface.glow != null)
            Positioned.fromRect(
              rect: surface.bounds,
              child: buildGlow(context, surface),
            ),
        ],
        if (content != null) Positioned.fill(child: content),
      ],
    );
  }
}

class _FillPainter extends CustomPainter {
  const _FillPainter(this.shape, this.color);

  final RRect shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    canvas.drawRRect(shape, paint);
  }

  @override
  bool shouldRepaint(_FillPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.color != color;
}

/// Installs a [MorphGlassPainter] for the measured controls below it.
class MorphGlass extends InheritedWidget {
  /// Installs [painter] for [child].
  const MorphGlass({required this.painter, required super.child, super.key});

  /// The painter the controls below use.
  final MorphGlassPainter painter;

  /// The nearest painter above [context], or null when none is installed.
  static MorphGlassPainter? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MorphGlass>()?.painter;

  @override
  bool updateShouldNotify(MorphGlass oldWidget) => oldWidget.painter != painter;
}

/// Builds the surfaces a control hands to [painter] through
/// [MorphGlassPainter.buildLayer], with [content] over them, rebuilt on
/// every notification of [frames].
///
/// The layer takes hits across its whole box, as the flat fills do,
/// whatever the painter builds.
@internal
class MorphGlassLayer extends StatelessWidget {
  /// Creates a layer.
  const MorphGlassLayer({
    required this.painter,
    required this.frames,
    required this.surfaces,
    this.content,
    this.contentSlots = const [],
    this.spacing = 0,
    super.key,
  });

  /// The painter that builds each surface.
  final MorphGlassPainter painter;

  /// Notifies when the surfaces change.
  final Listenable frames;

  /// Returns the surfaces of the current frame, back to front.
  final List<MorphGlassSurface> Function() surfaces;

  /// The control's content, drawn over the surfaces.
  final Widget? content;

  /// The boxes of the items of [content] in the layer's local coordinates,
  /// handed to [MorphGlassPainter.buildLayer].
  final List<Rect> contentSlots;

  /// The glass container spacing handed to [MorphGlassPainter.buildLayer].
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return MetaData(
      behavior: HitTestBehavior.opaque,
      child: ListenableBuilder(
        listenable: frames,
        builder: (BuildContext context, Widget? child) => painter.buildLayer(
          context,
          surfaces(),
          content: child,
          contentSlots: contentSlots,
          spacing: spacing,
        ),
        child: content,
      ),
    );
  }
}

/// Mirrors [shape] across the vertical center line of a box [width] wide.
@internal
RRect morphMirror(RRect shape, double width) => RRect.fromLTRBAndCorners(
  width - shape.right,
  shape.top,
  width - shape.left,
  shape.bottom,
  topLeft: shape.trRadius,
  topRight: shape.tlRadius,
  bottomLeft: shape.brRadius,
  bottomRight: shape.blRadius,
);
