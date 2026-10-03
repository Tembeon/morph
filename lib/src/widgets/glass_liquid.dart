/// The liquid tier of the glass renderer where the build can draw it:
/// Impeller with Flutter GPU (iOS, macOS, Android).
///
/// The web gets a stub that never imports the renderer: its shader
/// compiler cannot build the renderer's shaders, and there the renderer
/// draws the frosted tier instead.
library;

export 'package:morph/src/widgets/glass_liquid_web.dart'
    if (dart.library.io) 'package:morph/src/widgets/glass_liquid_native.dart';
