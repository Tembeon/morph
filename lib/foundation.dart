/// Morph System: "Hero for overlays, on springs".
///
/// Identity-based, spring-driven, interruptible morph animations from an
/// inline widget to an overlay, with no Navigator coupling.
///
/// Layers:
///  - geometry and identity: [MorphScope], [MorphTag];
///  - physics: [MorphController], [MorphMotion] (pairs of Motions from
///    the motor package, the default measured from UIKit's liquid morph),
///    [MorphSpring] (UIKit's response / damping-ratio vocabulary),
///    [MorphPhase]; the system invariant - every
///    visual property is a pure symmetric function of a single spring
///    value, which yields interruption continuity by construction;
///  - the shuttle: [showMorph], [showMorphSheet], [showMorphDialog],
///    declarative [MorphAnchor]; [showMorphRoute] - the destination as
///    a real Navigator route with the flight as its transition (the
///    second latch reparents live content into the page at settle);
///  - liquid fusion: [MorphSkin] - pieces sharing one "skin" via an
///    SDF smooth-union traced by marching squares into a vector Path;
///    a single knob k spans crisp concave joints to gooey necks.
///
/// This is the ENGINE layer; the widget layer (controls measured from
/// UIKit's Liquid Glass, the context menu) is
/// `package:morph/widgets.dart` and depends on this one, never the
/// other way around.
///
/// Every engine symbol is canonical HERE, not in the widgets library
/// that re-exports it - the directives below pin dartdoc's choice.
/// {@canonicalFor anchor.MorphAnchor}
/// {@canonicalFor controller.MorphController}
/// {@canonicalFor controller.MorphPhase}
/// {@canonicalFor flight.MorphContentBuilder}
/// {@canonicalFor flight.MorphFlight}
/// {@canonicalFor flight.MorphFlightEvent}
/// {@canonicalFor flight.MorphFlightScope}
/// {@canonicalFor frame.MorphFrame}
/// {@canonicalFor frame.computeMorphFrame}
/// {@canonicalFor frame.uniformMorphRadius}
/// {@canonicalFor gesture.morphDragArm}
/// {@canonicalFor gesture.morphDragCommitDistance}
/// {@canonicalFor gesture.morphDragCommitVelocity}
/// {@canonicalFor gesture.morphDragRecede}
/// {@canonicalFor gesture.morphDragScale}
/// {@canonicalFor gesture.morphDragScrimFactor}
/// {@canonicalFor gesture.morphProjectValue}
/// {@canonicalFor gesture.morphRubberband}
/// {@canonicalFor liquid_field.MorphMass}
/// {@canonicalFor liquid_field.MorphSkinStyle}
/// {@canonicalFor motion.MorphMotion}
/// {@canonicalFor route.MorphPageRoute}
/// {@canonicalFor route.showMorphRoute}
/// {@canonicalFor scope.MorphScope}
/// {@canonicalFor scope.MorphScopeState}
/// {@canonicalFor scope.MorphSurfaceSpec}
/// {@canonicalFor scope.MorphTag}
/// {@canonicalFor scope.MorphTagState}
/// {@canonicalFor scrim.MorphScrimMotion}
/// {@canonicalFor shared.MorphSharedElement}
/// {@canonicalFor shared.MorphSharedFade}
/// {@canonicalFor show.showMorph}
/// {@canonicalFor show.showMorphDialog}
/// {@canonicalFor show.showMorphSheet}
/// {@canonicalFor skin.MorphLink}
/// {@canonicalFor skin.MorphPiece}
/// {@canonicalFor skin.MorphPieceChannel}
/// {@canonicalFor skin.MorphSkin}
/// {@canonicalFor skin.MorphStroke}
/// {@canonicalFor spring.MorphSpring}
/// {@canonicalFor target.MorphTargetSpec}
/// {@canonicalFor target.morphAnchorRect}
/// {@canonicalFor target.maybeMorphAnchorRect}
/// {@canonicalFor theme.MorphTheme}
library;

// The motion vocabulary a custom MorphMotion is built from: re-exported
// so apps do not need a direct motor dependency for the common cases.
export 'package:motor/motor.dart'
    show CupertinoMotion, CurvedMotion, MaterialSpringMotion, Motion;

export 'src/anchor.dart';
export 'src/controller.dart' show MorphController, MorphPhase;
export 'src/flight.dart'
    show MorphContentBuilder, MorphFlight, MorphFlightEvent, MorphFlightScope;
export 'src/frame.dart' show MorphFrame, computeMorphFrame, uniformMorphRadius;
export 'src/gesture.dart';
export 'src/skin.dart'
    show MorphLink, MorphPiece, MorphPieceChannel, MorphSkin, MorphStroke;
export 'src/liquid_field.dart' show MorphMass, MorphSkinStyle;
export 'src/route.dart' show MorphPageRoute, showMorphRoute;
export 'src/scrim.dart' show MorphScrimMotion;
export 'src/shared.dart' show MorphSharedElement, MorphSharedFade;
export 'src/spring.dart';
export 'src/scope.dart'
    show MorphScope, MorphScopeState, MorphSurfaceSpec, MorphTag, MorphTagState;
export 'src/show.dart';
export 'src/motion.dart';
export 'src/theme.dart';
export 'src/target.dart'
    hide morphContentViewInsets, morphOverlayViewInsetsOf, morphTargetPaddingOf;
