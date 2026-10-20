import 'package:flutter/widgets.dart';

import 'package:morph_example/autodemo.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/perf/release_bench.dart';

/// Autodemo mode: walks every gallery page with synthetic gestures and
/// exits, the exception-scan gate of the verification workflow.
const bool kAutoDemo = .fromEnvironment('MORPH_AUTODEMO');

/// Release benchmark mode: runs the shared tracing scenes AOT plus a
/// frame-timing pass, prints BENCH lines and exits.
const bool kBenchMode = .fromEnvironment('MORPH_BENCH');

/// Runs the example: the widgets gallery, or the release bench under
/// `--dart-define=MORPH_BENCH=true`.
///
/// The gallery's theme loads the glass shaders and holds the first frame
/// until they are ready, so the first glass on screen is already the real
/// one without `MorphTheme.precacheGlass`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kBenchMode) {
    runApp(const ReleaseBenchApp());
    return;
  }
  final navigatorKey = GlobalKey<NavigatorState>();
  runApp(GalleryApp(navigatorKey: navigatorKey));
  if (kAutoDemo) {
    WidgetsBinding.instance.addPostFrameCallback(
      (Duration _) => runAutodemo(navigatorKey),
    );
  }
}
