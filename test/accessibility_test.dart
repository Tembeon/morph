import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';
import 'package:morph/src/widgets/switch_motion.dart';

Future<T> _resolve<T>(
  WidgetTester tester,
  T Function(BuildContext) resolve, {
  required bool highContrast,
  Brightness brightness = Brightness.light,
}) async {
  late T result;
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        highContrast: highContrast,
        platformBrightness: brightness,
      ),
      child: Builder(
        builder: (context) {
          result = resolve(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return result;
}

void main() {
  group('switch, Reduce Motion', () {
    test('a dragged knob stops at the ends and never lifts', () {
      final motion = MorphSwitchMotion(value: false);
      motion.reducedMotion = true;
      motion.pointerDown(0, 10);
      motion.pointerMove(0.3, 80);
      motion.advance(1);
      expect(motion.knob, closeTo(MorphSwitchMotion.travel, 1e-3));
      expect(motion.lens.progress(1), 0);
      expect(motion.lens.size(1), MorphSwitchMotion.knobSize);
    });

    test('without it the knob rubber-bands past the end', () {
      final motion = MorphSwitchMotion(value: false);
      motion.pointerDown(0, 10);
      motion.pointerMove(0.3, 80);
      motion.advance(1);
      expect(motion.knob, greaterThan(MorphSwitchMotion.travel + 1));
    });

    test('the shown state changes at each commit and toggling release', () {
      final shown = <bool>[];
      final motion = MorphSwitchMotion(value: false);
      motion.onDisplayedChanged = shown.add;
      motion.pointerDown(0, 10);
      motion.pointerMove(0.3, 60);
      motion.pointerMove(0.4, 0);
      motion.pointerMove(0.5, 60);
      motion.pointerUp(0.6, 60);
      expect(shown, [true, false, true]);
      motion.pointerDown(1, 10);
      motion.pointerUp(1.1, 10);
      expect(shown, [true, false, true, false]);
    });
  });

  group('Increase Contrast tables', () {
    testWidgets('switch', (tester) async {
      expect(
        await _resolve(
          tester,
          (c) => MorphSwitchAppearance.resolve(c, null),
          highContrast: true,
        ),
        same(MorphSwitchAppearance.lightHighContrast),
      );
      expect(
        await _resolve(
          tester,
          (c) => MorphSwitchAppearance.resolve(c, null),
          highContrast: true,
          brightness: Brightness.dark,
        ),
        same(MorphSwitchAppearance.darkHighContrast),
      );
      expect(
        await _resolve(
          tester,
          (c) => MorphSwitchAppearance.resolve(c, null),
          highContrast: false,
        ),
        same(MorphSwitchAppearance.light),
      );
    });
  });
}
