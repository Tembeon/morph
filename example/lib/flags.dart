import 'package:flutter/foundation.dart';

/// Autodemo mode: drives the scripted flight sequence for the
/// exception-scan gate (see CLAUDE.md verification workflow).
const bool kAutoDemo = .fromEnvironment('MORPH_AUTODEMO');

/// Release benchmark mode: runs the shared tracing scenes AOT plus a
/// frame-timing pass, prints BENCH lines and exits (see
/// example/lib/perf/release_bench.dart).
const bool kBenchMode = .fromEnvironment('MORPH_BENCH');

/// App-wide reduced-motion override, toggled from the Playground and
/// applied via MediaQuery.disableAnimations at the app root.
final ValueNotifier<bool> appReducedMotion = ValueNotifier<bool>(false);
