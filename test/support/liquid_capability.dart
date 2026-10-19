import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_liquid.dart';

/// Holds the liquid tier unavailable for the rest of the test, as on a
/// device whose liquid shaders are still loading, and returns the
/// capability the test sets to true when they are ready.
///
/// The host's own load fails and reports once; the report is dropped. The
/// capability is unavailable again after the test.
ValueNotifier<bool> pendingLiquidGlass() {
  final capability = morphLiquidGlassCapability as ValueNotifier<bool>;
  final previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.library != 'morph glass') previous?.call(details);
  };
  final local = isLocalTest;
  isLocalTest = false;
  capability.value = false;
  addTearDown(() {
    capability.value = false;
    isLocalTest = local;
    FlutterError.onError = previous;
  });
  return capability;
}
