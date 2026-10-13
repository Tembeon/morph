import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/internal/ancestor_clip.dart';
import 'package:morph/widgets.dart';

const _contentKey = Key('content');

/// The touches of a device recording: time in seconds, phase (0 down,
/// 1 moved, 3 up) and y in points.
List<(double, int, double)> _touches(String name) => [
  for (final line in File(
    'test/fixtures/ios27-device/sheet-drag/$name.jsonl',
  ).readAsLinesSync())
    if (line.trim().isNotEmpty)
      if ((jsonDecode(line) as Map).cast<String, Object?>() case {
        'k': 'touch',
        't': final num t,
        'phase': final int phase,
        'y': final num y,
      })
        (t.toDouble(), phase, y.toDouble()),
];

void main() {
  // Glass bounds its backdrop samples by the clips above it
  // (localPaintClipAbove, screenClipAbove), read through
  // describeApproximatePaintClip. The sheet clips its body inside its
  // moving, stretching transform: that clip has to reach the glass where
  // the body is, or the frost ends at a line that slides the other way.
  testWidgets('the clip glass reads covers the body on every frame of a '
      'replayed drag up', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showMorphSheet<void>(
                  context,
                  detents: const [
                    MorphSheetDetent.medium,
                    MorphSheetDetent.large,
                  ],
                  builder: (BuildContext context) =>
                      const SizedBox.expand(key: _contentKey),
                ),
                child: const Text('present'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('present'));
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final rest = tester.getRect(find.byKey(_contentKey));
    var stretched = false;
    var frames = 0;
    void check() {
      final content = tester.renderObject<RenderBox>(find.byKey(_contentKey));
      final toScreen = content.getTransformTo(null);
      final painted = MatrixUtils.transformRect(
        toScreen,
        Offset.zero & content.size,
      );
      final local = localPaintClipAbove(content);
      expect(local, isNotNull);
      final clip = MatrixUtils.transformRect(toScreen, local!);
      expect(
        clip,
        rectMoreOrLessEquals(painted, epsilon: 1e-6),
        reason: 'frame $frames: the clip glass reads matches the body',
      );
      expect(
        screenClipAbove(content),
        rectMoreOrLessEquals(
          painted.intersect(const Rect.fromLTWH(0, 0, 402, 874)),
          epsilon: 1e-6,
        ),
      );
      final ratio =
          (painted.height / rest.height) / (painted.width / rest.width);
      if (ratio > 1.005) stretched = true;
      frames++;
    }

    final touches = _touches('drag-up-slow');
    final start = touches.first;
    // The recording's touches are in the probe's window, which this view
    // matches; the finger lands where it landed on the device.
    final gesture = await tester.startGesture(Offset(201, start.$3));
    var clock = start.$1;
    for (final (t, phase, y) in touches.skip(1)) {
      await tester.pump(Duration(microseconds: ((t - clock) * 1e6).round()));
      check();
      clock = t;
      if (phase == 3) {
        await gesture.up();
        break;
      }
      await gesture.moveTo(Offset(201, y));
    }
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      check();
    }
    expect(stretched, isTrue, reason: 'the replay stretches the sheet');
    expect(frames, greaterThan(60));
  });
}
