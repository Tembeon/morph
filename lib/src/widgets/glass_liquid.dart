/// The liquid tier of the glass renderer where the build can draw it:
/// Impeller with Flutter GPU (iOS, macOS, Android).
///
/// The web gets a stub capability that never touches Flutter GPU: its
/// shader compiler cannot build the liquid shaders, so there the renderer
/// draws the same layers as fake glass.
library;

export 'package:morph/src/widgets/glass_liquid_web.dart'
    if (dart.library.io) 'package:morph/src/widgets/glass_liquid_native.dart';
