import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/liquid_glass_painter.dart';

export 'package:morph_example/gallery/liquid_glass_painter.dart'
    show LiquidGlassMaterial;

/// Whether this build carries the liquid glass renderer.
const bool liquidGlassAvailable = true;

/// Loads the glass shaders, so the first glass on screen is already the
/// real one.
Future<void> precacheLiquidGlass() => LiquidGlass.precache();

/// The liquid glass painter for the gallery's settings.
MorphGlassPainter liquidGlassPainter({
  required LiquidGlassMaterial material,
  required double blur,
  required double refraction,
  required double light,
  required double tint,
  required bool fake,
  required bool frostControls,
}) => LiquidGlassRendererPainter(
  material: material,
  blur: blur,
  refraction: refraction,
  light: light,
  tint: tint,
  fake: fake,
  frostControls: frostControls,
);
