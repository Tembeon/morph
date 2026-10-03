import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:morph_example/gallery/glass_settings.dart';

/// Plays the probe's `slvid-*` slider schedule on a morph slider for a
/// screen recording: a 300 pt slider centered 400 pt from the top of the
/// screen, at 0.3 without ticks and at 0 with five ticks, light then dark,
/// in the gallery's glass.
///
/// Build it as a profile app (`flutter build ios --profile -t
/// integration_test/slider_video_test.dart`), launch it with devicectl and
/// record the screen while it runs; it waits [_lead] before the first
/// gesture.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('slider video', (WidgetTester tester) async {
    await MorphGlassRenderer.precache();
    runApp(const GalleryApp());
    await tester.pump(const Duration(seconds: 2));
    final settings = GalleryGlassScope.of(
      tester.element(find.byType(Navigator)),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final clock = Stopwatch();
    clock.start();
    var pointer = 1;

    Future<void> wait(double seconds) =>
        tester.pump(Duration(microseconds: (seconds * 1e6).round()));

    Duration now() => clock.elapsed;

    Future<void> stroke(
      Offset from,
      List<(double dx, double seconds, double hold)> legs, {
      double press = 0.1,
    }) async {
      final gesture = await tester.createGesture(pointer: pointer++);
      await gesture.down(from, timeStamp: now());
      await wait(press);
      var at = from;
      for (final (dx, seconds, hold) in legs) {
        final start = at;
        final begin = now();
        var done = 0.0;
        while (done < 1) {
          await wait(1 / 120);
          final elapsed = (now() - begin).inMicroseconds / 1e6;
          done = (elapsed / seconds).clamp(0.0, 1.0);
          at = start + Offset(dx * done, 0);
          await gesture.moveTo(at, timeStamp: now());
        }
        if (hold > 0) await wait(hold);
      }
      await gesture.up(timeStamp: now());
    }

    Future<void> tap(Offset at, double hold) =>
        stroke(at, const [], press: hold);

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      settings.appearance = mode;
      for (final ticks in [0, 5]) {
        final value = ValueNotifier<double>(ticks == 0 ? 0.3 : 0);
        unawaited(
          navigator.push(
            PageRouteBuilder<void>(
              pageBuilder: (BuildContext context, _, _) =>
                  _Page(value: value, ticks: ticks),
            ),
          ),
        );
        await wait(1.5);
        final box = tester.getRect(find.byType(MorphSlider));
        Offset thumb() => Offset(
          box.left + 18.5 + value.value * (box.width - 37),
          box.center.dy,
        );
        await wait(_lead.inMilliseconds / 1000);
        if (ticks == 0) {
          await tap(thumb(), 0.09);
          await wait(1.5);
          await tap(thumb(), 0.8);
          await wait(1.5);
          await stroke(thumb(), const [(100, 1.0, 0.4)]);
          await wait(1.5);
          await stroke(thumb(), const [(-100, 0.4, 0)]);
          await wait(1.5);
          await tap(Offset(box.left + 270, box.center.dy), 0.09);
          await wait(1.5);
          var p = thumb();
          await stroke(p, [
            (box.right + 40 - p.dx, (box.right + 40 - p.dx) / 150, 0.6),
          ]);
          await wait(1.5);
          p = thumb();
          await stroke(p, [
            (box.left - 40 - p.dx, (p.dx - box.left + 40) / 150, 0.6),
          ]);
          await wait(1.5);
        } else {
          await tap(thumb(), 0.8);
          await wait(1.5);
          await stroke(thumb(), const [(200, 1.6, 0.4)]);
          await wait(1.5);
          await stroke(thumb(), const [(-45, 0.6, 0.4)]);
          await wait(1.5);
        }
        navigator.pop();
        await wait(1);
      }
    }
    await wait(2);
  });
}

const _lead = Duration(
  seconds: int.fromEnvironment('VIDEO_LEAD', defaultValue: 2),
);

class _Page extends StatelessWidget {
  const _Page({required this.value, required this.ticks});

  final ValueNotifier<double> value;
  final int ticks;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: galleryBackgroundColor(Theme.of(context).brightness),
      body: Stack(
        children: [
          Positioned(
            left: (width - 300) / 2,
            top: 400 - MorphSlider.height / 2,
            width: 300,
            height: MorphSlider.height,
            child: ValueListenableBuilder<double>(
              valueListenable: value,
              builder: (BuildContext context, double v, Widget? _) =>
                  MorphSlider(
                    value: v,
                    ticks: ticks,
                    onChanged: (double next) => value.value = next,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
