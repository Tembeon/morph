import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:morph/src/glass/renderer/internal/liquid_capability.dart';

export 'package:morph/src/widgets/glass_liquid_draw.dart';

/// Whether this build carries the liquid tier: not on the web.
@internal
bool get morphLiquidGlassAvailable {
  unawaited(_capability.precache());
  return false;
}

/// The cached web capability failure, or null before initialization.
@internal
String? get morphLiquidGlassUnavailableReason => _capability.unavailableReason;

/// The web's permanently unavailable liquid capability.
@internal
ValueListenable<bool> get morphLiquidGlassCapability => _capability;

final LiquidCapability _capability = LiquidCapability(
  load: () async {
    throw UnsupportedError('The web has no liquid glass tier.');
  },
);

/// Reports the unavailable web tier once and caches its reason.
@internal
Future<void> morphPrecacheLiquidGlass() => _capability.precache();
