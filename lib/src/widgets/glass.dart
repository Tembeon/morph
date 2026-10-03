import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The role a glass surface plays in a control.
enum MorphGlassKind {
  /// The track of a segmented control, switch, slider or stepper.
  track,

  /// The selection lens of a segmented control or tab bar.
  lens,

  /// The knob of a switch.
  knob,

  /// The thumb of a slider.
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

/// One glass surface of a control in one frame, handed to a
/// [MorphGlassPainter].
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
/// one surface may call [buildSurface] directly. The widget
/// [buildSurface] returns is placed exactly at [MorphGlassSurface.bounds],
/// so it can sample the backdrop with a `BackdropFilter`, run a shader or
/// paint anything else.
abstract class MorphGlassPainter {
  /// Creates a painter.
  const MorphGlassPainter();

  /// Builds the widget that draws [surface], sized to its bounds.
  Widget buildSurface(BuildContext context, MorphGlassSurface surface);

  /// Builds one glass layer of a control: its [surfaces], back to front,
  /// in a box that fills the layer, with the control's [content] over
  /// them.
  ///
  /// The surfaces of one call belong to one control and move together, so
  /// a painter can render them as a unit: share one backdrop sample, fuse
  /// neighbors, or show [content] through a lens. The default places each
  /// surface from [buildSurface] at its bounds and [content] over them.
  Widget buildLayer(
    BuildContext context,
    List<MorphGlassSurface> surfaces, {
    Widget? content,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final surface in surfaces)
          Positioned.fromRect(
            rect: surface.bounds,
            child: buildSurface(context, surface),
          ),
        if (content != null) Positioned.fill(child: content),
      ],
    );
  }
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

  @override
  Widget build(BuildContext context) {
    return MetaData(
      behavior: HitTestBehavior.opaque,
      child: ListenableBuilder(
        listenable: frames,
        builder: (BuildContext context, Widget? child) =>
            painter.buildLayer(context, surfaces(), content: child),
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
