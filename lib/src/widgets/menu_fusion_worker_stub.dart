import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:morph/src/widgets/glass_outline.dart';

/// The fusion worker where there are no isolates to run it on: it never
/// runs, and every fusion is computed where it is needed.
@internal
abstract final class MorphFusionWorker {
  /// Whether this platform can run the worker.
  static final bool supported = false;

  /// Does nothing.
  static void request(Float64List inputs, {Object? owner}) {}

  /// Always null.
  static MorphGlassOutlineParts? take(Float64List inputs, double tolerance) =>
      null;

  /// Always null.
  @internal
  static Float64List? get debugReadyInputs => null;

  /// Always null.
  @internal
  static Float64List? get debugTakenInputs => null;

  /// Always 0.
  @internal
  static int get debugDropped => 0;

  /// Always empty.
  @internal
  static const List<int> debugLatencyUs = [];

  /// Always false.
  @visibleForTesting
  static bool get debugHasReady => false;

  /// Does nothing.
  static void reset({Object? owner}) {}
}
