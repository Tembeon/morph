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
export 'src/skin.dart' show MorphSkin, MorphLink, MorphPiece;
export 'src/liquid_field.dart'
    show LiquidBox, LiquidBridge, LiquidShape, MorphSkinStyle;
export 'src/reveal.dart';
export 'src/route.dart' show MorphPageRoute, showMorphRoute;
export 'src/shared.dart' show MorphSharedElement;
export 'src/scope.dart'
    show MorphScope, MorphScopeState, MorphSurfaceSpec, MorphTag, MorphTagState;
export 'src/show.dart';
export 'src/motion.dart';
export 'src/theme.dart';
export 'src/target.dart';
