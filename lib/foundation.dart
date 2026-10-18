/// The engine under the widget layer: the tag registry ([MorphScope],
/// [MorphTag]), the spring vocabulary ([MorphSpring], [MorphMotion]) and
/// the vessel flight ([showMorph], [MorphFlight]) that carries the menus
/// until they become routes.
///
/// The widget layer is `package:morph/widgets.dart`; it depends on this
/// library, never the other way around.
///
/// Every engine symbol is canonical HERE, not in the widgets library
/// that re-exports it - the directives below pin dartdoc's choice.
/// {@canonicalFor flight.MorphContentBuilder}
/// {@canonicalFor flight.MorphFlight}
/// {@canonicalFor flight.MorphFlightEvent}
/// {@canonicalFor liquid_field.MorphMass}
/// {@canonicalFor liquid_field.MorphSkinStyle}
/// {@canonicalFor motion.MorphMotion}
/// {@canonicalFor presentation.MorphPresentationBoundary}
/// {@canonicalFor presentation.morphPresentationNavigatorOf}
/// {@canonicalFor presentation.morphPresentationOverlayOf}
/// {@canonicalFor scope.MorphScope}
/// {@canonicalFor scope.MorphScopeState}
/// {@canonicalFor scope.MorphSurfaceSpec}
/// {@canonicalFor scope.MorphTag}
/// {@canonicalFor scope.MorphTagState}
/// {@canonicalFor scrim.MorphScrimMotion}
/// {@canonicalFor show.showMorph}
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

export 'src/flight.dart'
    show MorphContentBuilder, MorphFlight, MorphFlightEvent;
export 'src/liquid_field.dart' show MorphMass, MorphSkinStyle;
export 'src/motion.dart';
export 'src/presentation.dart';
export 'src/scope.dart'
    show MorphScope, MorphScopeState, MorphSurfaceSpec, MorphTag, MorphTagState;
export 'src/scrim.dart' show MorphScrimMotion;
export 'src/show.dart';
export 'src/spring.dart';
export 'src/target.dart' hide morphTargetPaddingOf;
export 'src/theme.dart';
