/// The opinionated widget layer: interesting, correct uses of the
/// morph engine, shipped as ready recipes - press springs, liquid
/// selection, glass tethers. Everything here is built strictly ON
/// `package:morph/foundation.dart` and motor; the engine never depends
/// on this layer, and taste knobs here are expected to move with the
/// owner's app.
///
/// This layer is about USING morph well, not about reproducing a
/// platform's look: there is no glass shader here and none is planned -
/// surface shading of that kind is the platform's business, not this
/// package's.
library;

export 'foundation.dart';
export 'src/widgets/chase_spring.dart' show ChaseSpring;
export 'src/widgets/morph_menu.dart' show MorphMenuItem, showMorphMenu;
export 'src/widgets/morph_surface.dart' show MorphSurface, MorphTapTarget;
export 'src/widgets/spring_button.dart' show SpringButton;
export 'src/widgets/tug.dart' show Tug;
