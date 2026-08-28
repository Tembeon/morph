/// Morph System: "Hero for overlays, on springs".
///
/// Identity-based, spring-driven, interruptible morph animations from an
/// inline widget to an overlay, with no Navigator coupling.
///
/// Layers:
///  - geometry and identity: [MorphScope], [MorphTag];
///  - physics: [MorphController], [MorphMotion] (pairs of Motions from
///    the motor package), [MorphPhase]; the system invariant - every
///    visual property is a pure symmetric function of a single spring
///    value, which yields interruption continuity by construction;
///  - the shuttle: [showMorph], [showMorphSheet], [showMorphDialog],
///    declarative [MorphAnchor]; [showMorphRoute] - the destination as
///    a real Navigator route with the flight as its transition (the
///    second latch reparents live content into the page at settle);
///  - content choreography: [MorphReveal] - a cascade of content blocks
///    unfolding on sub-ranges of the same spring;
///  - liquid fusion: [MorphSkin] - pieces sharing one "skin" via an
///    SDF smooth-union traced by marching squares into a vector Path;
///    a single knob k spans crisp concave joints to gooey necks.
///
/// This is the ENGINE layer; the opinionated widget layer (press
/// springs, liquid selection, glass tethers) is
/// `package:morph/widgets.dart` and depends on this one, never the
/// other way around.
///
/// Every engine symbol is canonical HERE, not in the widgets library
/// that re-exports it - the directives below pin dartdoc's choice.
/// {@canonicalFor anchor.MorphAnchor}
/// {@canonicalFor controller.MorphController}
/// {@canonicalFor controller.MorphDirection}
/// {@canonicalFor controller.MorphPhase}
/// {@canonicalFor flight.MorphContentBuilder}
/// {@canonicalFor flight.MorphFlight}
/// {@canonicalFor flight.MorphFlightScope}
/// {@canonicalFor frame.MorphFrame}
/// {@canonicalFor frame.computeMorphFrame}
/// {@canonicalFor frame.morphBumpedRect}
/// {@canonicalFor frame.morphLandingBump}
/// {@canonicalFor frame.uniformMorphRadius}
/// {@canonicalFor gesture.morphCloseHintScale}
/// {@canonicalFor gesture.morphDragArm}
/// {@canonicalFor gesture.morphDragRecede}
/// {@canonicalFor gesture.morphDragScale}
/// {@canonicalFor gesture.morphDragScrimFactor}
/// {@canonicalFor gesture.morphProjectValue}
/// {@canonicalFor gesture.morphRubberband}
/// {@canonicalFor liquid_field.MorphMass}
/// {@canonicalFor liquid_field.MorphSkinStyle}
/// {@canonicalFor motion.MorphMotion}
/// {@canonicalFor reveal.MorphReveal}
/// {@canonicalFor route.MorphPageRoute}
/// {@canonicalFor route.showMorphRoute}
/// {@canonicalFor scope.MorphScope}
/// {@canonicalFor scope.MorphScopeState}
/// {@canonicalFor scope.MorphSurfaceSpec}
/// {@canonicalFor scope.MorphTag}
/// {@canonicalFor scope.MorphTagState}
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
export 'src/controller.dart' show MorphController, MorphDirection, MorphPhase;
export 'src/flight.dart'
    show MorphContentBuilder, MorphFlight, MorphFlightScope;
export 'src/frame.dart'
    show
        MorphFrame,
        computeMorphFrame,
        morphBumpedRect,
        morphLandingBump,
        uniformMorphRadius;
export 'src/gesture.dart';
export 'src/skin.dart'
    show MorphLink, MorphPiece, MorphPieceChannel, MorphSkin, MorphStroke;
export 'src/liquid_field.dart' show MorphMass, MorphSkinStyle;
export 'src/reveal.dart';
export 'src/route.dart' show MorphPageRoute, showMorphRoute;
export 'src/shared.dart' show MorphSharedElement, MorphSharedFade;
export 'src/scope.dart'
    show MorphScope, MorphScopeState, MorphSurfaceSpec, MorphTag, MorphTagState;
export 'src/show.dart';
export 'src/motion.dart';
export 'src/theme.dart';
export 'src/target.dart';
