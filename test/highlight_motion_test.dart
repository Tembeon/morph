import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/widgets/highlight_motion.dart';

void main() {
  group('list row', () {
    test('waits the touch delay, then fades after the tap', () {
      final motion = MorphListRowHighlightMotion();
      motion.touch(0);
      expect(motion.isSettled(0.1), isFalse);
      motion.press(0, 0.1);
      expect(motion.opacity(0.149), 0);
      expect(motion.opacity(0.15), 1);
      motion.release(0.6);
      expect(motion.opacity(0.6), 1);
      expect(motion.opacity(0.85), closeTo(0.5, 1e-9));
      expect(motion.opacity(1.1), 0);
      expect(motion.isSettled(1.1), isTrue);
    });

    test('a tap released before the delay shows at the release', () {
      final motion = MorphListRowHighlightMotion();
      motion.touch(0);
      motion.press(0, 0.067);
      motion.release(0.067);
      expect(motion.opacity(0.067), 1);
      expect(motion.opacity(0.2), greaterThan(0.8));
    });

    test('a scroll removes it at once', () {
      final motion = MorphListRowHighlightMotion();
      motion.touch(0);
      motion.press(0, 0.1);
      expect(motion.opacity(0.2), 1);
      motion.cancel();
      expect(motion.opacity(0.2), 0);
      expect(motion.isSettled(0.2), isTrue);
    });

    test('an undecided touch keeps time only for the delay', () {
      final motion = MorphListRowHighlightMotion();
      motion.touch(0);
      expect(motion.wakeTime(0), 0.15);
      expect(motion.isSettled(0.15), isTrue);
    });
  });

  group('segment title', () {
    test('dims on the measured curve and returns faster', () {
      final motion = MorphSegmentHighlightMotion();
      motion.press(0, 1);
      expect(motion.opacity(0, 1), 1);
      expect(motion.opacity(0, 0), 1);
      expect(motion.opacity(0.47, 1), closeTo(0.2, 1e-9));
      expect(motion.isSettled(0.47), isTrue);
      motion.release(1);
      expect(motion.opacity(1, 1), closeTo(0.2, 1e-9));
      expect(motion.opacity(1.2, 1), closeTo(1, 1e-6));
      motion.advance(1.2);
      expect(motion.index, isNull);
      expect(motion.isSettled(1.2), isTrue);
    });

    test('a quick tap returns from where the dimming reached', () {
      final motion = MorphSegmentHighlightMotion();
      motion.press(0, 2);
      final reached = motion.opacity(0.067, 2);
      expect(reached, lessThan(1));
      expect(reached, greaterThan(0.85));
      motion.release(0.067);
      expect(motion.opacity(0.067, 2), closeTo(reached, 1e-9));
    });
  });

  testWidgets('a pressed unselected segment dims its title', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              child: MorphSegmentedControl(
                segments: const [
                  MorphSegment('One'),
                  MorphSegment('Two'),
                  MorphSegment('Three'),
                ],
                selectedIndex: 0,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    double opacityOf(String text) {
      RenderObject? node = tester.renderObject(find.text(text));
      while (node != null &&
          node.runtimeType.toString() != '_RenderPressedTitle') {
        node = node.parent;
      }
      final layer = node?.debugLayer;
      return layer is OpacityLayer ? layer.alpha! / 255 : 1;
    }

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Three')),
    );
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(opacityOf('Three'), closeTo(0.2, 0.01));
    expect(opacityOf('Two'), 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(opacityOf('Three'), 1);
  });
}
