import 'package:meta/meta.dart';
import 'package:morph/src/widgets/glass_tier.dart';

/// The web has no Flutter GPU to ask.
@internal
MorphGlassDeviceClass morphProbeGlassDeviceClass() =>
    MorphGlassDeviceClass.unknown;
