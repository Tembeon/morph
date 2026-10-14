import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph/src/widgets/alert_motion.dart';
import 'package:morph/src/widgets/lens_motion.dart';
import 'package:morph/src/widgets/menu_motion.dart';
import 'package:morph/src/widgets/slider_motion.dart';
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

  group('lens, Reduce Motion', () {
    const slots = <MorphLensSlot>[
      (center: 50, width: 100),
      (center: 150, width: 100),
      (center: 250, width: 100),
    ];

    MorphLensMotion lens(MorphLensTuning tuning) {
      final motion = MorphLensMotion(
        tuning: tuning,
        slots: slots,
        selected: 0,
        height: 28,
      );
      motion.reducedMotion = true;
      return motion;
    }

    test('the segmented selection appears on the new segment', () {
      final motion = lens(MorphLensTuning.segmented);
      motion.pointerDown(0, 250);
      motion.pointerUp(0.1, 250);
      motion.advance(0.1 + motion.startDelay);
      expect(motion.center, 250);
      expect(motion.lift, 0);
      motion.advance(2);
      expect(motion.center, 250);
    });

    test('a press on the selected segment neither lifts nor drags it', () {
      final motion = lens(MorphLensTuning.segmented);
      motion.pointerDown(0, 50);
      motion.pointerMove(0.2, 160);
      motion.advance(0.4);
      expect(motion.center, 50);
      expect(motion.lift, 0);
      motion.pointerUp(0.5, 160);
      motion.advance(0.5 + motion.startDelay);
      expect(motion.center, 150);
    });

    test('the tab bar selection travels on 0.9 over 0.2, unlifted', () {
      final reduced = lens(MorphLensTuning.tabBar);
      final normal = MorphLensMotion(
        tuning: MorphLensTuning.tabBar,
        slots: slots,
        selected: 0,
        height: 28,
      );
      for (final motion in [reduced, normal]) {
        motion.pointerDown(0, 250);
        motion.pointerUp(0.05, 250);
      }
      final t = 0.15 + reduced.startDelay;
      reduced.advance(t);
      normal.advance(t);
      expect(reduced.lift, 0);
      expect(normal.lift, greaterThan(0.5));
      final reducedLeft = (reduced.travelCenter - 250).abs();
      final normalLeft = (normal.travelCenter - 250).abs();
      expect(reducedLeft, lessThan(normalLeft / 2));
    });
  });

  group('alert and popover, Reduce Motion', () {
    test('the alert fades in at its size on the same spring', () {
      final reduced = MorphAlertMotion();
      reduced.reducedMotion = true;
      final normal = MorphAlertMotion();
      reduced.present(0);
      normal.present(0);
      expect(reduced.scale(0), 1);
      expect(normal.scale(0), MorphAlertTuning.presentScale);
      expect(reduced.opacity(0.1), normal.opacity(0.1));
    });

    test('the popover keeps its size', () {
      final popover = MorphPopoverMotion();
      popover.reducedMotion = true;
      popover.present(0);
      expect(popover.scale(0), 1);
      expect(popover.opacity(0), 0);
    });
  });

  test('a finger moving the menu highlight to another row is reported', () {
    final motion = MorphMenuMotion(
      button: const Rect.fromLTWH(179, 300, 44, 44),
      itemCount: 4,
      bounds: const Size(402, 874),
    );
    var tracked = 0;
    motion.onTrackedHighlight = () => tracked++;
    motion.advance(-4);
    motion.open(-3);
    motion.advance(0);
    final menu = motion.menuRect;
    final rows = [
      for (var i = 0; i < 4; i++)
        Offset(menu.center.dx, menu.top + menu.height * (i + 0.5) / 4),
    ];
    motion.pointerDown(0, rows[0]);
    motion.pointerMove(0.05, rows[0].translate(0, 2));
    motion.pointerMove(0.1, rows[1]);
    motion.pointerMove(0.15, rows[2]);
    expect(tracked, 3);
    motion.highlight(0.2, 0);
    expect(tracked, 3);
  });

  testWidgets('a held context menu hero keeps its size under Reduce Motion', (
    tester,
  ) async {
    const box = ValueKey<String>('box');
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: MorphScope(child: child!),
        ),
        home: Center(
          child: MorphContextMenuRegion(
            below: MorphSatellite(
              height: 40,
              builder: (BuildContext context, MorphFlight flight) =>
                  const Text('action'),
            ),
            child: Container(
              key: box,
              width: 120,
              height: 48,
              color: const Color(0xFF334455),
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(box)),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getRect(find.byKey(box)).width, 120);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  test('a dragged slider reports its ends and inner stops', () {
    final feels = <bool>[];
    final plain = MorphSliderMotion(width: 300, value: 0.5);
    plain.onFeel = feels.add;
    final x = plain.thumbCenter;
    plain.pointerDown(0, x);
    plain.pointerMove(0.02, x + 20);
    plain.pointerMove(0.04, x + 400);
    plain.pointerMove(0.06, x + 420);
    expect(feels, [false]);
    final stepped = MorphSliderMotion(width: 300, value: 0, ticks: 5);
    final stops = <bool>[];
    stepped.onFeel = stops.add;
    final y = stepped.thumbCenter;
    stepped.pointerDown(0, y);
    stepped.pointerMove(0.02, y + 20);
    for (var i = 1; i <= 30; i++) {
      stepped.pointerMove(0.02 + i * 0.01, y + 20 + i * 10);
    }
    expect(stops, [true, true, true, false]);
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

    testWidgets('alert', (tester) async {
      expect(
        await _resolve(
          tester,
          (c) => MorphAlertAppearance.resolve(c, null),
          highContrast: true,
          brightness: Brightness.dark,
        ),
        same(MorphAlertAppearance.darkHighContrast),
      );
    });

    testWidgets('slider, progress, segmented, page control, date picker', (
      tester,
    ) async {
      Future<Object> light(Object Function(BuildContext) resolve) =>
          _resolve(tester, resolve, highContrast: true);
      expect(
        await light((c) => MorphSliderAppearance.resolve(c, null)),
        same(MorphSliderAppearance.lightHighContrast),
      );
      expect(
        await light((c) => MorphProgressViewAppearance.resolve(c, null)),
        same(MorphProgressViewAppearance.lightHighContrast),
      );
      expect(
        await light((c) => MorphSegmentedControlAppearance.resolve(c, null)),
        same(MorphSegmentedControlAppearance.lightHighContrast),
      );
      expect(
        await light((c) => MorphPageControlAppearance.resolve(c, null)),
        same(MorphPageControlAppearance.lightHighContrast),
      );
      expect(
        await light((c) => MorphDatePickerAppearance.resolve(c, null)),
        same(MorphDatePickerAppearance.lightHighContrast),
      );
    });

    testWidgets('an explicit appearance stays the app\'s', (tester) async {
      const own = MorphSwitchAppearance(activeTrackColor: Color(0xFF123456));
      expect(
        await _resolve(
          tester,
          (c) => MorphSwitchAppearance.resolve(c, own),
          highContrast: true,
        ),
        same(own),
      );
    });
  });
}
