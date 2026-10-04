import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

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
/// The glass shaders load before the first frame, so the first glass on
/// screen is already the real one.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kBenchMode) {
    runApp(const ReleaseBenchApp());
    return;
  }
  await MorphGlassRenderer.precache();
  final navigatorKey = GlobalKey<NavigatorState>();
  runApp(GalleryApp(navigatorKey: navigatorKey));
  if (kAutoDemo) {
    WidgetsBinding.instance.addPostFrameCallback(
      (Duration _) => runAutodemo(navigatorKey),
    );
  }
}
