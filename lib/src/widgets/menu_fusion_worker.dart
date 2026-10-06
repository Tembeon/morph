/// The menu fusion worker: a background isolate where the platform has
/// isolates, a stub that never runs on the web.
library;

export 'package:morph/src/widgets/menu_fusion_worker_stub.dart'
    if (dart.library.io) 'package:morph/src/widgets/menu_fusion_worker_io.dart';
