import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/glass_painter.dart';
import 'package:morph/src/widgets/clock.dart';
import 'package:morph/morph.dart';

class _Glass extends MorphGlassPainter {
  final Map<MorphGlassKind, MorphGlassSurface> surfaces = {};

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    surfaces[surface.kind] = surface;
    return const SizedBox.expand();
  }
}

void main() {
  var frameStamp = Duration.zero;
  var frameWall = DateTime(2026);
  var listening = false;
  late Duration Function() savedNow;
  late Duration? Function() savedOffset;

  Duration now() =>
      frameStamp +
      TestWidgetsFlutterBinding.instance.clock.now().difference(frameWall);

  setUp(() {
    savedNow = morphClockNow;
    savedOffset = morphPointerClockOffset;
    if (!listening) {
      listening = true;
      SchedulerBinding.instance.addPersistentFrameCallback((Duration _) {
        frameStamp = SchedulerBinding.instance.currentSystemFrameTimeStamp;
        frameWall = TestWidgetsFlutterBinding.instance.clock.now();
      });
    }
    morphClockNow = now;
    morphPointerClockOffset = () => Duration.zero;
  });
  tearDown(() {
    morphClockNow = savedNow;
    morphPointerClockOffset = savedOffset;
  });

  // Touches stamped 5 - 35 ms before their delivery, as an iPhone delivers
  // them, land on the motion clock behind the frames already shown.
  for (var seed = 0; seed < 24; seed++) {
    testWidgets('a stepped slider driven on the device clock rests on its '
        'stop ($seed)', (tester) async {
      final rng = math.Random(seed);
      final glass = _Glass();
      var value = 0.5;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: MorphGlassScope(
                painter: glass,
                child: SizedBox(
                  width: 300,
                  child: StatefulBuilder(
                    builder: (context, setState) => MorphSlider(
                      value: value,
                      ticks: 5,
                      onChanged: (v) => setState(() => value = v),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(MorphSlider));
      for (var g = 0; g < 3; g++) {
        Duration lag() => Duration(microseconds: 5000 + rng.nextInt(30000));
        var x = box.left + 18.5 + value * 263;
        final gesture = await tester.createGesture();
        await gesture.down(Offset(x, box.center.dy), timeStamp: now() - lag());
        await tester.pump(const Duration(milliseconds: 8));
        final moves = 5 + rng.nextInt(30);
        final speed = rng.nextDouble() * 8 - 4;
        for (var i = 0; i < moves; i++) {
          x += speed + rng.nextDouble() - 0.5;
          await gesture.moveTo(
            Offset(x, box.center.dy),
            timeStamp: now() - lag(),
          );
          if (rng.nextInt(4) > 0) {
            await tester.pump(Duration(milliseconds: 4 + rng.nextInt(12)));
          }
        }
        for (var i = 0; i < rng.nextInt(20); i++) {
          await tester.pump(const Duration(milliseconds: 8));
        }
        await gesture.up(timeStamp: now() - lag());
        for (var i = 0; i < rng.nextInt(10); i++) {
          await tester.pump(const Duration(milliseconds: 8));
        }
      }
      for (var i = 0; i < 400; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      final center = glass.surfaces[MorphGlassKind.thumb]!.shape.center.dx;
      expect((value * 4).roundToDouble(), value * 4);
      expect(center, closeTo(18.5 + value * 263, 0.11), reason: 'v=$value');
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }
}
