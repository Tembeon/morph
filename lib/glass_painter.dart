/// The seam between the measured controls and the glass they are drawn
/// with: what a [MorphGlassPainter] receives for each surface.
///
/// The controls describe every piece of glass as a [MorphGlassSurface]
/// (its outline, [MorphGlassKind], [MorphGlassOptics], touch
/// [MorphGlassGlow] and [MorphGlassOutline]); the package's own
/// `MorphGlassRenderer` and any custom painter installed with
/// `MorphGlassScope` shade those descriptions. An app that uses the
/// built-in renderer needs nothing from this library.
library;

export 'src/widgets/glass.dart'
    show MorphGlassKind, MorphGlassOptics, MorphGlassPainter, MorphGlassSurface;
export 'src/widgets/glass_glow.dart' show MorphGlassGlow;
export 'src/widgets/glass_outline.dart' show MorphGlassOutline;
