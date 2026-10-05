/// The Flutter GPU probe behind [morphProbeGlassDeviceClass] where the
/// build has Flutter GPU; the web gets a stub that reports
/// `MorphGlassDeviceClass.unknown`.
library;

export 'package:morph/src/widgets/glass_device_web.dart'
    if (dart.library.io) 'package:morph/src/widgets/glass_device_native.dart';
