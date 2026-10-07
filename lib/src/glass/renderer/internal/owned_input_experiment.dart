import 'dart:ui' as ui;

/// An experimental owned input for the isolated same-frame laboratory.
class OwnedGlassInput {
  /// Describes a ready blur of the covered source region.
  const OwnedGlassInput(this.image, this.region, this.shift, this.halfOffset);

  /// The ready Gaussian or reduced Dual output.
  final ui.Image image;

  /// The source-space coverage, in logical pixels.
  final ui.Rect region;

  /// The current source translation, in logical pixels.
  final ui.Offset shift;

  /// Final Dual upsample offsets in output texture UVs; zero for Gaussian.
  final ui.Offset halfOffset;
}

/// Laboratory-only input seam; not a general widget backdrop service.
class OwnedGlassExperiment {
  /// A separately compiled final shader with unchanged production optics.
  static ui.FragmentProgram? program;

  /// Produces the exact current source before the glass draw is recorded.
  static OwnedGlassInput Function()? read;
}
