/// The engine under the widget layer: the tag registry ([MorphScope],
/// [MorphTag]), the spring vocabulary ([MorphSpring], [MorphMotion]) and
/// the vessel flight ([showMorph], [MorphFlight]) that carries the menus.
///
/// The widget layer is `package:morph/widgets.dart`; it depends on this
/// library, never the other way around.
///
/// Every engine symbol is canonical HERE, not in the widgets library
/// that re-exports it - the directives below pin dartdoc's choice.
/// {@canonicalFor flight.MorphContentBuilder}
/// {@canonicalFor flight.MorphFlight}
/// {@canonicalFor flight.MorphFlightEvent}
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
library;

export 'src/flight.dart'
    show MorphContentBuilder, MorphFlight, MorphFlightEvent;
export 'src/motion.dart';
export 'src/presentation.dart';
export 'src/scope.dart'
    show
        MorphScope,
        MorphScopeState,
        MorphSource,
        MorphSourceLink,
        MorphSurfaceSpec,
        MorphTag,
        MorphTagState;
export 'src/scrim.dart' show MorphScrimMotion;
export 'src/show.dart';
export 'src/spring.dart';
export 'src/target.dart' hide morphTargetPaddingOf;
