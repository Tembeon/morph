import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

import 'glass_density_test.dart' show DensityPage;

/// The number of liquid glass buttons on the probe's page, from the
/// `PROBE_BUTTONS` environment variable; 0 (the default) launches the
/// gallery itself.
final int buttons = int.parse(Platform.environment['PROBE_BUTTONS'] ?? '0');

/// Launches the gallery, or a density page of [buttons] liquid glass
/// buttons, the way the example's main does, prints `PROBE` lines to
/// stdout (precache and first rasterized frame, in ms since main) and
/// exits after 4 s.
///
/// A desktop release build of this target is the launch-hang probe of
/// spec/glass-renderer.md ("Startup and queue bounds"):
/// `flutter build macos --release -t integration_test/launch_probe.dart`,
/// then run the binary with `PROBE_BUTTONS=72` and treat a missing
/// `PROBE first_frame` line after 15 s as a hang (`sample <pid>`).
Future<void> main() async {
  final clock = Stopwatch();
  clock.start();
  WidgetsFlutterBinding.ensureInitialized();
  await MorphGlassRenderer.precache();
  stdout.writeln('PROBE precache ${clock.elapsedMilliseconds} ms');
  var frames = 0;
  SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
    if (frames == 0) {
      stdout.writeln('PROBE first_frame ${clock.elapsedMilliseconds} ms');
    }
    frames += timings.length;
  });
  var errors = 0;
  FlutterError.onError = (FlutterErrorDetails details) {
    errors++;
    stdout.writeln('PROBE EXCEPTION ${details.exception}');
  };
  runApp(
    buttons == 0
        ? GalleryApp(navigatorKey: GlobalKey<NavigatorState>())
        : DensityPage(count: buttons, tier: MorphGlassTier.liquid),
  );
  await Future<void>.delayed(const Duration(seconds: 4));
  stdout.writeln('PROBE done frames $frames errors $errors');
  await stdout.flush();
  exit(0);
}
