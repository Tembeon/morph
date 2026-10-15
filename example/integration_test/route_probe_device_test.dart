import 'dart:convert';
import 'dart:developer' show Timeline;
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:morph_example/proto/route_probe.dart';

/// Exercises the P1 routes on a physical display and writes raw frame timings.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'P1 device lifecycle and frame timings',
    semanticsEnabled: false,
    (tester) async {
      final out = Directory('${Directory.systemTemp.path}/foundation-p1');
      out.createSync(recursive: true);
      final timings = <Map<String, int>>[];
      final phases = <Map<String, Object?>>[];
      final checks = <String, Object?>{};
      var complete = false;
      void onTimings(List<FrameTiming> frames) {
        for (final frame in frames) {
          timings.add({
            'vsync_us': frame.timestampInMicroseconds(FramePhase.vsyncStart),
            'build_us': frame.buildDuration.inMicroseconds,
            'raster_us': frame.rasterDuration.inMicroseconds,
            'total_us': frame.totalSpan.inMicroseconds,
          });
        }
      }

      SchedulerBinding.instance.addTimingsCallback(onTimings);
      try {
        final nav = GlobalKey<NavigatorState>();
        var rootTaps = 0;
        await tester.pumpWidget(
          WidgetsApp(
            color: const Color(0xFFF0F0F0),
            navigatorKey: nav,
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              pageBuilder: (_, _, _) => GestureDetector(
                behavior: .opaque,
                onTap: () => rootTaps++,
                child: const ColoredBox(
                  color: Color(0xFFF0F0F0),
                  child: Center(child: Text('P1 route probe')),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        for (final driver in ProbeRouteDriver.values) {
          final focus = FocusNode();
          final editor = TextEditingController(text: 'P1 editor survives');
          final editorKey = GlobalKey<EditableTextState>();
          final route = ProbeSheetRoute<void>(
            driver: driver,
            builder: (_) => ColoredBox(
              color: const Color(0xFFE0E8F0),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: EditableText(
                  key: editorKey,
                  controller: editor,
                  focusNode: focus,
                  autofocus: true,
                  style: const TextStyle(
                    fontSize: 20,
                    color: Color(0xFF101010),
                  ),
                  cursorColor: const Color(0xFF007AFF),
                  backgroundCursorColor: const Color(0xFFFFFFFF),
                ),
              ),
            ),
          );
          nav.currentState!.push<void>(route);
          await _rest(tester, route);
          final state = editorKey.currentState;
          expect(state, isNotNull);
          expect(focus.hasFocus, isTrue);
          checks['${driver.name}_keyboard_inset'] =
              tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
          await _shot(binding, out, '${driver.name}-editor');
          final cover = RawDialogRoute<void>(
            transitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => const Center(child: Text('P1 cover')),
          );
          nav.currentState!.push<void>(cover);
          await tester.pump(const Duration(milliseconds: 150));
          nav.currentState!.pop();
          await tester.pump(const Duration(milliseconds: 200));
          expect(editorKey.currentState, same(state));
          expect(editor.text, 'P1 editor survives');
          expect(focus.hasFocus, isTrue);
          nav.currentState!.pop();
          await tester.pump();
          expect(focus.hasFocus, isFalse);
          expect(route.disposed, isFalse);
          final before = rootTaps;
          await tester.tapAt(const Offset(10, 120));
          expect(rootTaps, before + 1);
          await _rest(tester, route, closing: true);
          checks['${driver.name}_editor_state_focus_and_input'] = true;
          focus.dispose();
          editor.dispose();
        }

        const order = [
          ProbeRouteDriver.projected,
          ProbeRouteDriver.sdkController,
          ProbeRouteDriver.sdkController,
          ProbeRouteDriver.projected,
          ProbeRouteDriver.projected,
          ProbeRouteDriver.sdkController,
          ProbeRouteDriver.sdkController,
          ProbeRouteDriver.projected,
        ];
        for (var phase = 0; phase < order.length; phase++) {
          final driver = order[phase];
          final begin = Timeline.now;
          final runs = <Map<String, Object?>>[];
          for (var cycle = 0; cycle < 2; cycle++) {
            final route = ProbeSheetRoute<int>(
              driver: driver,
              builder: (_) => ColoredBox(
                color: const Color(0xFFBBD8EF),
                child: Center(child: Text('${driver.name} / $phase / $cycle')),
              ),
            );
            final result = nav.currentState!.push<int>(route);
            await _rest(tester, route);
            expect(route.animation!.status, AnimationStatus.completed);
            final idleStart = route.motionFrames;
            await tester.pump(const Duration(milliseconds: 120));
            expect(route.motionFrames, idleStart);
            final pageBuilds = route.pageBuilds;
            nav.currentState!.pop(42);
            await tester.pump();
            expect(await result, 42);
            expect(route.animation!.status, AnimationStatus.reverse);
            expect(route.disposed, isFalse);
            await _rest(tester, route, closing: true);
            runs.add({
              'motion_frames': route.motionFrames,
              'page_builds_open': pageBuilds,
              'page_builds_total': route.pageBuilds,
              'idle_motion_frames': 0,
              'disposed': route.disposed,
            });
          }
          phases.add({
            'phase': phase,
            'driver': driver.name,
            'begin_timeline_us': begin,
            'end_timeline_us': Timeline.now,
            'cycles': runs,
          });
          await tester.pump(const Duration(milliseconds: 300));
        }
        await tester.pump(const Duration(seconds: 2));
        complete = true;
      } finally {
        SchedulerBinding.instance.removeTimingsCallback(onTimings);
        File('${out.path}/report.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'complete': complete,
            'display_hz': tester.view.display.refreshRate,
            'physical_size': [
              tester.view.physicalSize.width,
              tester.view.physicalSize.height,
            ],
            'dpr': tester.view.devicePixelRatio,
            'checks': checks,
            'phases': phases,
            'timings': timings,
          }),
        );
      }
    },
  );
}

Future<void> _rest(
  WidgetTester tester,
  ProbeSheetRoute<Object?> route, {
  bool closing = false,
}) async {
  await tester.pump();
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (closing ? !route.disposed : !route.motionSettled) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('P1 route did not settle: ${route.driver.name}');
    }
    await tester.pump(const Duration(milliseconds: 8));
  }
}

Future<void> _shot(
  IntegrationTestWidgetsFlutterBinding binding,
  Directory out,
  String name,
) async {
  final data = await binding.callbackManager.takeScreenshot(name);
  final bytes = (data['bytes']! as List<Object?>).cast<int>();
  File('${out.path}/$name.png').writeAsBytesSync(bytes);
}
