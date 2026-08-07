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
}
