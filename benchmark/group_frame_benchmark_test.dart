import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';

/// Full-pipeline frame cost of a MorphSkin while a flight animates:
/// build + layout + paint per pumped frame in the test binding. The
/// glacial motion keeps the spring ticking for the whole measured
/// window. Run explicitly:
///
/// ```bash
/// flutter test benchmark/group_frame_benchmark_test.dart
/// ```
///
/// JIT numbers - compare relatively on one machine.
void main() {
  testWidgets('frame cost during a glacial flight', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) =>
            MorphScope(child: child!),
        home: Scaffold(
          body: MorphSkin(
            blend: 24,
            color: const Color(0xFF2A2440),
            elevation: 5,
            pieces: <MorphPiece>[
              const MorphPiece(id: 'a', rect: .fromLTWH(40, 500, 140, 80)),
              const MorphPiece(id: 'b', rect: .fromLTWH(190, 520, 90, 50)),
              const MorphPiece(id: 'c', rect: .fromLTWH(700, 80, 120, 70)),
              const MorphPiece(id: 'd', rect: .fromLTWH(830, 110, 80, 46)),
              .morphable(
                id: 'hero',
                rect: const .fromLTWH(300, 510, 110, 50),
                child: Builder(
                  builder: (BuildContext context) => TextButton(
                    onPressed: () => showMorphDialog(
                      context,
                      from: 'hero',
                      width: 420,
                      height: 320,
                      motion: .glacial,
                      builder: (BuildContext context, MorphFlight flight) =>
                          const Text('dialog'),
                    ),
                    child: const Text('fly'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('fly'));
    await tester.pump(const Duration(milliseconds: 16));

    const int frames = 240;
    final Stopwatch watch = Stopwatch()..start();
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    watch.stop();
    final double msPerFrame = watch.elapsedMicroseconds / 1000 / frames;
    // ignore: avoid_print
    print(
      'flight frame cost: ${msPerFrame.toStringAsFixed(2)} ms/frame '
      '($frames frames)',
    );
    expect(tester.takeException(), isNull);
  });

  // App-driven geometry, the stress-orbit scene both ways: the OLD
  // path (a rebuild per frame feeding new piece lists through the
  // widget) against the piece geometry channel (writes straight into
  // the render object). Identical orbits, identical traced geometry -
  // the delta is pure pipeline overhead.
  testWidgets('app-driven orbits: rebuild-driven vs channel-driven', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const int count = 24;
    const int frames = 240;
    const double goldenAngle = 2.399963229728653;

    Rect base(int i) {
      return Rect.fromCenter(
        center: Offset(90.0 + (i % 6) * 160, 100.0 + (i ~/ 6) * 170),
        width: 46 + (i % 4) * 18,
        height: 34 + (i % 3) * 14,
      );
    }

    Offset orbit(int i, double t) {
      final double phase = i * goldenAngle;
      return Offset(
        math.sin(t * (0.5 + (i % 5) * 0.11) + phase) * 66,
        math.cos(t * (0.4 + (i % 3) * 0.17) + phase * 1.7) * 70,
      );
    }

    Widget skin(List<MorphPiece> pieces) {
      return MaterialApp(
        home: Scaffold(
          body: MorphSkin(
            blend: 24,
            color: const Color(0xFF2A2440),
            elevation: 5,
            pieces: pieces,
          ),
        ),
      );
    }

    final ValueNotifier<double> time = ValueNotifier<double>(0);
    addTearDown(time.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: time,
            builder: (BuildContext context, Widget? child) => MorphSkin(
              blend: 24,
              color: const Color(0xFF2A2440),
              elevation: 5,
              pieces: <MorphPiece>[
                for (int i = 0; i < count; i++)
                  MorphPiece(
                    id: i,
                    rect: base(i).shift(orbit(i, time.value)),
                    radius: 12 + (i % 3) * 6.0,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final Stopwatch rebuildWatch = Stopwatch()..start();
    for (int f = 0; f < frames; f++) {
      time.value = f * 0.016;
      await tester.pump();
    }
    rebuildWatch.stop();

    final List<MorphPieceChannel> channels = <MorphPieceChannel>[
      for (int i = 0; i < count; i++) MorphPieceChannel(),
    ];
    addTearDown(() {
      for (final MorphPieceChannel channel in channels) {
        channel.dispose();
      }
    });
    await tester.pumpWidget(
      skin(<MorphPiece>[
        for (int i = 0; i < count; i++)
          MorphPiece(
            id: i,
            rect: base(i),
            radius: 12 + (i % 3) * 6.0,
            channel: channels[i],
          ),
      ]),
    );
    final Stopwatch channelWatch = Stopwatch()..start();
    for (int f = 0; f < frames; f++) {
      final double t = f * 0.016;
      for (int i = 0; i < count; i++) {
        channels[i].update(offset: orbit(i, t));
      }
      await tester.pump();
    }
    channelWatch.stop();

    final double rebuildMs = rebuildWatch.elapsedMicroseconds / 1000 / frames;
    final double channelMs = channelWatch.elapsedMicroseconds / 1000 / frames;
    // ignore: avoid_print
    print(
      'orbit frame cost: rebuild ${rebuildMs.toStringAsFixed(2)} ms/frame, '
      'channel ${channelMs.toStringAsFixed(2)} ms/frame ($count pieces, '
      '$frames frames)',
    );
    expect(tester.takeException(), isNull);
  });
}
