import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/glass_page.dart';

/// Whether this build carries the liquid glass renderer.
const bool liquidGlassAvailable = false;

/// The iOS 27 glass materials of the liquid glass renderer, absent from
/// this build.
enum LiquidGlassMaterial {
  /// The regular material of `.glass` buttons and controls.
  regular,

  /// The toolbar material, with a stronger rim in dark mode.
  toolbar,

  /// The clear material: no wash, the full bevel on every shape.
  clear,
}

/// Completes at once: there are no glass shaders to load.
Future<void> precacheLiquidGlass() async {}

/// The [FrostedGlassPainter], standing in for the liquid glass this build
/// does not carry.
MorphGlassPainter liquidGlassPainter({
  required LiquidGlassMaterial material,
  required double blur,
  required double refraction,
  required double light,
  required double tint,
  required bool fake,
  required bool frostControls,
}) => const FrostedGlassPainter();
