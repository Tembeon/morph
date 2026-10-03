import 'package:morph/widgets.dart';

/// Loads the liquid glass shaders, so the first glass on screen is already
/// the real one; completes at once where the build has no liquid tier.
Future<void> precacheLiquidGlass() => MorphGlassRenderer.precache();
