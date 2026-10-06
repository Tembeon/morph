import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:morph/src/widgets/glass_outline.dart';

/// The fusion worker where there are no isolates to run it on: it never
/// runs, and every fusion is computed where it is needed.
@internal
abstract final class MorphFusionWorker {
  /// Whether this platform can run the worker.
  static const bool supported = false;

  /// Does nothing.
  static void request(Float64List inputs) {}

  /// Always null.
  static MorphGlassOutlineParts? take(Float64List inputs, double tolerance) =>
      null;

  /// Always null.
  @internal
  static Float64List? get debugReadyInputs => null;

  /// Always false.
  @visibleForTesting
  static bool get debugHasReady => false;

  /// Does nothing.
  static void reset() {}
}
