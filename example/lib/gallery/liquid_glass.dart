/// The liquid glass renderer where the platform has it: Impeller with
/// Flutter GPU on macOS, iOS and Android.
///
/// The web build gets the stub instead, which never imports the renderer
/// package, so the web example builds with that package removed.
library;

export 'package:morph_example/gallery/liquid_glass_web.dart'
    if (dart.library.io) 'package:morph_example/gallery/liquid_glass_native.dart';
