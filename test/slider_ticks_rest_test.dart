import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:morph/glass_painter.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/widgets/slider_motion.dart';

class _Glass extends MorphGlassPainter {
  final Map<MorphGlassKind, MorphGlassSurface> surfaces = {};

  @override
  Widget buildSurface(BuildContext context, MorphGlassSurface surface) {
    surfaces[surface.kind] = surface;
    return const SizedBox.expand();
  }
}

const double _width = 300;
const double _travel = _width - 37;
const _stops = [0.0, 0.25, 0.5, 0.75, 1.0];

class _Scene {
  _Scene(this.tester);

  final WidgetTester tester;
  final _Glass glass = _Glass();
  double value = 0.5;
  bool enabled = true;
  final List<double> ended = [];
  late StateSetter update;
  double Function(double)? accept;

  Future<void> pump({double initial = 0.5, bool list = false}) async {
    value = initial;
    Widget wrap(Widget child) => list
        ? ListView(
            children: [
              const SizedBox(height: 300),
              Center(child: child),
              const SizedBox(height: 900),
            ],
          )
        : Center(child: child);
    await tester.pumpWidget(
      MaterialApp(
        home: wrap(
          MorphGlassScope(
            painter: glass,
            child: SizedBox(
              width: _width,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return MorphSlider(
                    value: value,
                    ticks: 5,
                    onChanged: enabled
                        ? (v) => setState(() => value = accept?.call(v) ?? v)
                        : null,
                    onChangeEnd: ended.add,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect get box => tester.getRect(find.byType(MorphSlider));

  double get thumbCenter =>
      glass.surfaces[MorphGlassKind.thumb]!.shape.outerRect.center.dx;

  Offset thumbAt(double v) =>
      Offset(box.left + 18.5 + v * _travel, box.center.dy);

  void expectAtRest(String reason) {
    expect(_stops, contains(value), reason: '$reason: the value is a stop');
    expect(
      thumbCenter,
      closeTo(18.5 + value * _travel, 0.11),
      reason: '$reason: the thumb rests on its stop',
    );
    expect(tester.binding.hasScheduledFrame, isFalse, reason: reason);
  }
}

void main() {
  group('a stepped slider rests on its stop', () {
    for (final offset in [20.0, 30.0, 45.0, 60.0, 80.0, -25.0, -50.0]) {
      testWidgets('after a drag of $offset released still', (tester) async {
        final s = _Scene(tester);
        await s.pump();
        final gesture = await tester.startGesture(s.thumbAt(0.5));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(Offset(12 * offset.sign, 0));
        await tester.pump(const Duration(milliseconds: 16));
        const steps = 6;
        for (var i = 0; i < steps; i++) {
          await gesture.moveBy(Offset(offset / steps, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 300));
        final held = s.thumbCenter - (18.5 + s.value * _travel);
        expect(
          held.abs(),
          lessThanOrEqualTo(_travel / 8 + 0.01),
          reason: 'a held finger never leans the thumb past the midpoint',
        );
        await gesture.up();
        await tester.pumpAndSettle();
        s.expectAtRest('drag $offset');
      });

      testWidgets('after a drag of $offset released moving', (tester) async {
        final s = _Scene(tester);
        await s.pump();
        final gesture = await tester.startGesture(s.thumbAt(0.5));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(Offset(12 * offset.sign, 0));
        await tester.pump(const Duration(milliseconds: 16));
        const steps = 3;
        for (var i = 0; i < steps; i++) {
          await gesture.moveBy(Offset(offset / steps, 0));
          await tester.pump(const Duration(milliseconds: 8));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        s.expectAtRest('moving drag $offset');
      });
    }

    testWidgets('after a tap on the thumb or the track', (tester) async {
      final s = _Scene(tester);
      await s.pump();
      await tester.tapAt(s.thumbAt(0.5) + const Offset(6, 0));
      await tester.pumpAndSettle();
      s.expectAtRest('thumb tap');
      await tester.tapAt(s.thumbAt(0.9));
      await tester.pumpAndSettle();
      s.expectAtRest('track tap');
    });

    testWidgets('after a fast fling', (tester) async {
      final s = _Scene(tester);
      await s.pump();
      await tester.flingFrom(s.thumbAt(0.5), const Offset(70, 0), 3000);
      await tester.pumpAndSettle();
      s.expectAtRest('fling');
      expect(s.ended.last, s.value);
    });

    testWidgets('after a cancelled drag', (tester) async {
      final s = _Scene(tester);
      await s.pump();
      final gesture = await tester.startGesture(s.thumbAt(0.5));
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.cancel();
      await tester.pumpAndSettle();
      s.expectAtRest('cancel');
    });

    testWidgets('after the parent moves it mid-settle', (tester) async {
      final s = _Scene(tester);
      await s.pump();
      final gesture = await tester.startGesture(s.thumbAt(0.5));
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      s.update(() => s.value = 0.25);
      await tester.pump(const Duration(milliseconds: 16));
      s.update(() => s.value = 1);
      await tester.pump(const Duration(milliseconds: 40));
      s.update(() => s.value = 0.75);
      await tester.pumpAndSettle();
      expect(s.value, 0.75);
      s.expectAtRest('parent');
    });

    testWidgets('when the parent rejects the drag', (tester) async {
      final s = _Scene(tester);
      s.accept = (_) => 0.5;
      await s.pump();
      final gesture = await tester.startGesture(s.thumbAt(0.5));
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(s.value, 0.5);
      s.expectAtRest('rejected');
    });

    testWidgets('after keyboard steps', (tester) async {
      final s = _Scene(tester);
      await s.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 20));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(s.value, 1);
      s.expectAtRest('keyboard');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(s.value, 0.75);
      s.expectAtRest('keyboard back');
    });

    testWidgets('after a keyboard step from a value between stops', (
      tester,
    ) async {
      final s = _Scene(tester);
      await s.pump(initial: 0.3);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(s.value, 0.5);
      s.expectAtRest('keyboard up from 0.3');
      s.update(() => s.value = 0.3);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(s.value, 0.25);
      s.expectAtRest('keyboard down from 0.3');
      s.update(() => s.value = 0.75 - 1e-9);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(s.value, 1, reason: 'a stop off by a rounding counts as it');
    });

    testWidgets('when disabled mid-drag', (tester) async {
      final s = _Scene(tester);
      await s.pump();
      final gesture = await tester.startGesture(s.thumbAt(0.5));
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      s.update(() => s.enabled = false);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();
      s.expectAtRest('disabled');
    });

    testWidgets('when re-enabled after a drag cut by disabling', (
      tester,
    ) async {
      final s = _Scene(tester);
      await s.pump();
      final gesture = await tester.startGesture(s.thumbAt(0.5));
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      s.update(() => s.enabled = false);
      await tester.pumpAndSettle();
      s.expectAtRest('disabled, finger down');
      await gesture.up();
      s.update(() => s.enabled = true);
      await tester.pumpAndSettle();
      s.expectAtRest('re-enabled');
      await tester.flingFrom(s.thumbAt(s.value), const Offset(-40, 0), 500);
      await tester.pumpAndSettle();
      s.expectAtRest('next drag');
    });

    testWidgets('after a drag past the end', (tester) async {
      final s = _Scene(tester);
      await s.pump(initial: 0.75);
      final gesture = await tester.startGesture(s.thumbAt(0.75));
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(15, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(s.value, 1);
      s.expectAtRest('past the end');
    });

    testWidgets('after a press-release within the release delay', (
      tester,
    ) async {
      final s = _Scene(tester);
      await s.pump();
      final gesture = await tester.startGesture(s.thumbAt(0.5));
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 8));
      final again = await tester.startGesture(s.thumbAt(s.value));
      await tester.pump(const Duration(milliseconds: 8));
      await again.up();
      await tester.pumpAndSettle();
      s.expectAtRest('re-press');
    });
  });

  group('a stepped slider in a list rests on its stop', () {
    for (final (dx, dy) in [
      (6.0, 6.0),
      (6.0, 2.0),
      (2.0, 6.0),
      (8.0, -3.0),
      (3.0, 9.0),
    ]) {
      for (final early in [1, 3, 6]) {
        testWidgets('after a diagonal drag ($dx, $dy) x $early', (
          tester,
        ) async {
          final s = _Scene(tester);
          await s.pump(list: true);
          final gesture = await tester.startGesture(s.thumbAt(0.5));
          await tester.pump(const Duration(milliseconds: 8));
          for (var i = 0; i < early; i++) {
            await gesture.moveBy(Offset(dx, dy));
            await tester.pump(const Duration(milliseconds: 8));
          }
          for (var i = 0; i < 6; i++) {
            await gesture.moveBy(Offset(dx, dy * 2));
            await tester.pump(const Duration(milliseconds: 8));
          }
          await tester.pump(const Duration(milliseconds: 200));
          await gesture.up();
          await tester.pumpAndSettle();
          s.expectAtRest('diagonal');
        });
      }
    }
  });

  group('MorphSliderMotion with ticks', () {
    void expectOnStop(MorphSliderMotion m, String reason) {
      expect(_stops, contains(m.value), reason: reason);
      expect(m.position, closeTo(m.value, 1e-3), reason: reason);
      expect(m.isSettled, isTrue, reason: reason);
    }

    MorphSliderMotion run(void Function(MorphSliderMotion, double) gesture) {
      final m = MorphSliderMotion(width: _width, value: 0.5, ticks: 5);
      gesture(m, 18.5 + 0.5 * _travel);
      for (var t = 1.0; t < 3; t += 1 / 120) {
        m.advance(t);
        if (m.isSettled) break;
      }
      m.settle();
      return m;
    }

    test('settles on the stop after a release anywhere', () {
      for (var d = -130.0; d <= 130; d += 3.7) {
        final m = run((m, x) {
          m.pointerDown(0, x);
          m.pointerMove(0.1, x + 12 * d.sign);
          m.pointerMove(0.2, x + d);
          m.pointerMove(0.5, x + d);
          m.pointerUp(0.5, x + d);
        });
        expectOnStop(m, 'drag $d');
      }
    });

    test('a held finger leans the thumb by the detent curve', () {
      for (var d = -130.0; d <= 130; d += 3.7) {
        final m = MorphSliderMotion(width: _width, value: 0.5, ticks: 5);
        final x = 18.5 + 0.5 * _travel;
        m.pointerDown(0, x);
        m.pointerMove(0.1, x + MorphSliderMotion.panSlop * d.sign);
        m.pointerMove(0.2, x + MorphSliderMotion.panSlop * d.sign + d);
        final p = (0.5 + d / _width).clamp(0.0, 1.0);
        final u = ((p - m.value) * 8).clamp(-1.0, 1.0);
        expect(
          m.position,
          closeTo(m.value + u * u * u * u * u / 8, 1e-9),
          reason: 'drag $d',
        );
      }
    });

    test('settles on the stop after a cancel', () {
      final m = run((m, x) {
        m.pointerDown(0, x);
        m.pointerMove(0.1, x + 12);
        m.pointerMove(0.2, x + 40);
        m.pointerCancel(0.3);
      });
      expectOnStop(m, 'cancel');
    });
  });
}
