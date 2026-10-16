import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/motion.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph_example/proto/menu_route_probe.dart';

const _button = Rect.fromLTWH(24, 80, 44, 44);
const _size = Size(402, 320);
const _scale = 3.0;

MorphMenuMotion _motion() => MorphMenuMotion(
  button: _button,
  bounds: const Size(402, 874),
  itemCount: 3,
);

Future<ui.Image> _referenceImage(MorphMenuMotion motion, RRect neighbor) async {
  final bar = morphGlassContainerOutline(
    [neighbor, motion.buttonBlob.rrect],
    12,
    withField: false,
  ).path;
  final menu = motion.silhouetteFor(withField: false);
  final path = menu == null ? bar : Path.combine(.union, bar, menu.path);
  final viewport = Offset.zero & _size;
  expect(viewport.contains(path.getBounds().topLeft), isTrue);
  expect(viewport.contains(path.getBounds().bottomRight), isTrue);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFFFFFFF), .src);
  canvas.scale(_scale);
  final paint = Paint();
  paint.color = const Color(0xFF8888AA);
  canvas.drawPath(path, paint);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (_size.width * _scale).toInt(),
    (_size.height * _scale).toInt(),
  );
  picture.dispose();
  return image;
}

Future<int> _changedPixels(ui.Image actual, ui.Image expected) async {
  expect(actual.width, expected.width);
  expect(actual.height, expected.height);
  final a = (await actual.toByteData(format: .rawRgba))!.buffer.asUint32List();
  final b = (await expected.toByteData(
    format: .rawRgba,
  ))!.buffer.asUint32List();
  var changed = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) changed++;
  }
  return changed;
}

void main() {
  for (final rate in [60, 120]) {
    for (final gap in [0.0, 8.0, 12.0]) {
      testWidgets(
        'actual flat scene keeps its landing contour: $rate Hz, gap=$gap',
        (tester) async {
          tester.view.devicePixelRatio = _scale;
          tester.view.physicalSize = _size * _scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final step = Duration(microseconds: (1e6 / rate).round());
          final nav = GlobalKey<NavigatorState>();
          final source = GlobalKey<ProbeMenuSourceState>();
          final scene = GlobalKey();
          final reference = _motion();
          final neighbor = RRect.fromRectAndRadius(
            Rect.fromLTWH(68 + gap, 80, 44, 44),
            const Radius.circular(22),
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: scene,
              child: ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: WidgetsApp(
                  color: const Color(0xFFFFFFFF),
                  debugShowCheckedModeBanner: false,
                  navigatorKey: nav,
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    transitionDuration: Duration.zero,
                    pageBuilder: (_, _, _) => ProbeMenuSource(
                      key: source,
                      neighbors: [neighbor],
                      createMotion: _motion,
                      now: () => Duration(
                        microseconds: tester.binding.clock
                            .now()
                            .microsecondsSinceEpoch,
                      ),
                      onSample: (sample) {
                        switch (sample.kind) {
                          case .open:
                            reference.open(sample.time);
                          case .close:
                            reference.close(sample.time);
                          case .frame:
                            reference.advance(sample.time);
                          case .pointer:
                          case .ignoredPointer:
                            fail(
                              'Command-mode scene receives no pointer input',
                            );
                        }
                      },
                      menuBuilder: (_) => const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          );
          final state = source.currentState!;
          final route = state.open();
          for (var i = 0; i < 240 && !route.animation!.isCompleted; i++) {
            await tester.pump(step);
          }
          expect(route.animation!.isCompleted, isTrue);
          nav.currentState!.pop();
          var routeFrames = 0;
          var sourceFrames = 0;
          var disposedDuringTail = false;
          var sampled = 0;
          for (var i = 0; i < 240; i++) {
            await tester.pump(step);
            if (state.ownsMotion) {
              sourceFrames++;
              disposedDuringTail |= route.disposed && !state.motionSettled;
            } else {
              routeFrames++;
            }
            final boundary =
                scene.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final changed = await tester.runAsync(() async {
              final actual = await boundary.toImage(pixelRatio: _scale);
              final expected = await _referenceImage(reference, neighbor);
              try {
                final difference = await _changedPixels(actual, expected);
                const output = String.fromEnvironment('P2_SCENE_OUTPUT');
                final label = difference != 0
                    ? 'difference'
                    : (i == 0
                          ? 'close'
                          : (sourceFrames == 1
                                ? 'hand-back'
                                : (state.motionSettled ? 'rest' : null)));
                if (label != null && output.isNotEmpty) {
                  await Directory(output).create(recursive: true);
                  for (final (name, image) in [
                    ('actual', actual),
                    ('expected', expected),
                  ]) {
                    final png = (await image.toByteData(format: .png))!;
                    await File(
                      '$output/$rate-${gap.toInt()}-$label-$name.png',
                    ).writeAsBytes(png.buffer.asUint8List());
                  }
                }
                return difference;
              } finally {
                actual.dispose();
                expected.dispose();
              }
            });
            expect(
              changed,
              0,
              reason:
                  'Frame $i, time ${state.frame.time}, source=${state.ownsMotion}',
            );
            sampled++;
            if (state.motionSettled && route.disposed) break;
          }
          expect(state.motionSettled, isTrue);
          expect(route.handBack!.before, route.handBack!.after);
          expect(routeFrames, greaterThan(0));
          expect(sourceFrames, greaterThan(1));
          expect(disposedDuringTail, isTrue);
          final restFrames = state.motionFrames;
          await tester.pump(const Duration(seconds: 10));
          expect(state.motionFrames, restFrames);
          expect(tester.binding.transientCallbackCount, 0);
          // ignore: avoid_print
          print(
            'P2_SCENE ${jsonEncode({'rate': rate, 'gap': gap, 'frames': sampled, 'routeFrames': routeFrames, 'sourceFrames': sourceFrames, 'scale': _scale, 'changedPixels': 0})}',
          );
        },
      );
    }
  }
}

// ignore_for_file: implementation_imports, invalid_use_of_internal_member
