import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

const _dir = 'test/fixtures/ios27/alert';

/// One display frame of the 60 Hz simulator recordings: the probe samples
/// each presentation layer for the frame being prepared.
const double _frame = 1 / 60;

const _deviceDir = 'test/fixtures/ios27-device/alert';

List<Map<String, Object?>> _rows(String file, {String dir = _dir}) => [
  for (final line in File('$dir/$file').readAsLinesSync())
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

double _d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();

double _event(List<Map<String, Object?>> rows, String name) => _d(
  rows.firstWhere((r) => r['k'] == 'evt' && (r['e'] == name || r['a'] == name)),
  't',
);

double _rms(List<double> e) =>
    math.sqrt(e.fold(0.0, (a, b) => a + b * b) / math.max(1, e.length));

/// Aligns the start of an animation to the recording: UIKit starts it a
/// frame or more after its call. Returns the best start within [maxLag]
/// of [call] and the rms error there.
(double, double) _align(
  double call,
  double maxLag,
  List<double> Function(double start) errors,
) {
  var best = call;
  var bestErr = double.infinity;
  for (var lag = 0.0; lag <= maxLag; lag += 0.001) {
    final e = _rms(errors(call + lag));
    if (e < bestErr) {
      bestErr = e;
      best = call + lag;
    }
  }
  return (best, bestErr);
}

void main() {
  for (final (source, dir, frame) in [
    ('the simulator', _dir, _frame),
    ('an iPhone 16 Pro', _deviceDir, 1 / 120),
  ]) {
    group('alert motion replays $source', () {
      final rows = _rows('alert-present-dismiss.jsonl', dir: dir);
      final present = _event(rows, 'present');
      final dismiss = _event(rows, 'dismiss');
      final alert = [
        for (final r in rows)
          if (r['cls'] == '_UIAlertControllerPhoneTVMacView' &&
              _d(r, 't') > present)
            r,
      ];
      final dim = [
        for (final r in rows)
          if (r['cls'] == 'UIView' && _d(r, 't') > present) r,
      ];

      test('present: the scale and the dimming on one spring', () {
        List<double> scaleErrors(double start) {
          final motion = MorphAlertMotion();
          motion.present(start);
          return [
            for (final r in alert)
              if (_d(r, 't') < dismiss)
                motion.scale(_d(r, 't') + frame) - _d(r, 'w') / _d(r, 'bw'),
          ];
        }

        final (start, scaleRms) = _align(present, 0.15, scaleErrors);
        final motion = MorphAlertMotion();
        motion.present(start);
        final dimErr = [
          for (final r in dim)
            if (_d(r, 't') < dismiss)
              motion.dimming(_d(r, 't') + frame) - _d(r, 'a'),
        ];
        expect(scaleRms, lessThan(0.0015));
        expect(_rms(dimErr), lessThan(0.012));
      });

      test(
        'dismiss: the dimming fades on the same spring, the scale stays',
        () {
          List<double> errors(double start) {
            final motion = MorphAlertMotion();
            motion.present(present);
            motion.dismiss(start);
            return [
              for (final r in dim)
                if (_d(r, 't') > dismiss)
                  motion.dimming(_d(r, 't') + frame) - _d(r, 'a'),
            ];
          }

          final (start, rms) = _align(dismiss, 0.15, errors);
          expect(rms, lessThan(0.012));
          final motion = MorphAlertMotion();
          motion.present(present);
          motion.dismiss(start);
          expect(motion.scale(start + 0.2), closeTo(1, 1e-3));
        },
      );
    });
  }

  group('alert presses replay the simulator', () {
    test('a touch lifts the whole platter like a glass button', () {
      for (final file in ['alert-press.jsonl', 'alert-tap.jsonl']) {
        final rows = _rows(file);
        final touches = [
          for (final r in rows)
            if (r['k'] == 'touch') r,
        ];
        final down = _d(touches.first, 't');
        final up = _d(touches.last, 't');
        final card = [
          for (final r in rows)
            if (r['cls'] == '_UIAlertControllerPhoneTVMacView' &&
                _d(r, 't') > down - 0.02 &&
                _d(r, 't') < up + 0.4)
              r,
        ];
        List<double> errors(double lag) {
          final motion = MorphGlassButtonMotion(size: const Size(320, 264));
          final out = <double>[];
          var pressed = false;
          var released = false;
          for (final r in card) {
            final t = _d(r, 't') + _frame;
            if (!pressed && t >= down + lag) {
              motion.pointerDown(down + lag, const Offset(160, 112));
              pressed = true;
            }
            if (!released && t >= up + lag) {
              motion.pointerUp(up + lag, const Offset(160, 112));
              released = true;
            }
            motion.advance(t);
            out.add((motion.scale - _d(r, 'w') / 320) * 320);
          }
          return out;
        }

        final (_, rms) = _align(0, 0.05, errors);
        expect(rms, lessThan(0.35), reason: file);
      }
    });
  });

  group('alert and action sheet touches replay an iPhone 16 Pro', () {
    test('a touch lifts the platter like a glass button', () {
      for (final file in ['alert-press.jsonl', 'alert-tap.jsonl']) {
        final rows = _rows(file, dir: _deviceDir);
        final touches = [
          for (final r in rows)
            if (r['k'] == 'touch') r,
        ];
        final down = _d(touches.first, 't');
        final up = _d(touches.last, 't');
        final card = [
          for (final r in rows)
            if (r['cls'] == '_UIAlertControllerPhoneTVMacView' &&
                _d(r, 't') > down - 0.02 &&
                _d(r, 't') < up + 0.4)
              r,
        ];
        List<double> errors(double lag) {
          final motion = MorphGlassButtonMotion(size: const Size(320, 264));
          final out = <double>[];
          var pressed = false;
          var released = false;
          for (final r in card) {
            final t = _d(r, 't');
            if (!pressed && t >= down + lag) {
              motion.pointerDown(down + lag, const Offset(160, 112));
              pressed = true;
            }
            if (!released && t >= up + lag) {
              motion.pointerUp(up + lag, const Offset(160, 112));
              released = true;
            }
            motion.advance(t);
            out.add((motion.scale - _d(r, 'w') / 320) * 320);
          }
          return out;
        }

        final (_, rms) = _align(0, 0.06, errors);
        expect(rms, lessThan(0.35), reason: file);
      }
    });

    test('a dragging finger pulls the platter a quarter as far', () {
      for (final file in ['alert-lean.jsonl', 'alert-slide.jsonl']) {
        final rows = _rows(file, dir: _deviceDir);
        final touches = [
          for (final r in rows)
            if (r['k'] == 'touch') r,
        ];
        final card = [
          for (final r in rows)
            if (r['cls'] == '_UIAlertControllerPhoneTVMacView') r,
        ];
        final down = _d(touches.first, 't');
        final rest = card.lastWhere((r) => _d(r, 't') < down);
        final center = Offset(_d(rest, 'x'), _d(rest, 'y'));
        Offset local(Map<String, Object?> r) =>
            Offset(_d(r, 'x'), _d(r, 'y')) - center + const Offset(160, 132);
        final motion = MorphGlassButtonMotion(size: const Size(320, 264));
        motion.pull = MorphAlertTuning.platterPull;
        motion.stretch = MorphAlertTuning.platterStretch;
        final lean = <double>[];
        final size = <double>[];
        var next = 0;
        for (final r in card) {
          final t = _d(r, 't');
          if (t < down) continue;
          while (next < touches.length && _d(touches[next], 't') <= t) {
            final touch = touches[next];
            final at = local(touch);
            switch (touch['phase']) {
              case 0:
                motion.pointerDown(_d(touch, 't') + 0.05, at);
              case 3:
                motion.pointerUp(_d(touch, 't'), at);
              case _:
                motion.pointerMove(_d(touch, 't'), at);
            }
            next++;
          }
          motion.advance(t);
          lean.add(motion.lean.dx - (_d(r, 'x') - center.dx));
          lean.add(motion.lean.dy - (_d(r, 'y') - center.dy));
          size.add((motion.scaleX - _d(r, 'w') / 320) * 320);
          size.add((motion.scaleY - _d(r, 'h') / 264) * 264);
        }
        expect(lean.length, greaterThan(200));
        expect(_rms(lean), lessThan(0.15), reason: '$file lean');
        expect(_rms(size), lessThan(0.35), reason: '$file size');
      }
    });

    test('an action sheet popover does not lift under a touch', () {
      final rows = _rows('ash-press.jsonl', dir: _deviceDir);
      final touches = [
        for (final r in rows)
          if (r['k'] == 'touch') r,
      ];
      final down = _d(touches.first, 't');
      final up = _d(touches.last, 't');
      final held = [
        for (final r in rows)
          if (r['cls'] == '_UIPopoverView' &&
              _d(r, 't') >= down &&
              _d(r, 't') <= up)
            _d(r, 'w'),
      ];
      expect(held, isNotEmpty);
      expect(
        held.every((w) => (w - MorphAlertTuning.popoverWidth).abs() < 0.01),
        isTrue,
      );
    });

    test('a tap outside dismisses on the dismiss spring', () {
      final rows = _rows('ash-tap-out.jsonl', dir: _deviceDir);
      final up = _d(rows.lastWhere((r) => r['k'] == 'touch'), 't');
      final popover = [
        for (final r in rows)
          if (r['cls'] == '_UIPopoverView' && _d(r, 't') > up) r,
      ];
      List<double> errors(double start) {
        final motion = MorphPopoverMotion();
        motion.present(start - 5);
        motion.dismiss(start);
        return [
          for (final r in popover) motion.scale(_d(r, 't')) - _d(r, 'sx'),
        ];
      }

      final (start, rms) = _align(up, 0.08, errors);
      expect(rms, lessThan(0.006));
      expect(start - up, lessThan(0.06));
    });
  });

  group('popover motion replays the simulator', () {
    for (final (source, dir, frame, size) in [
      ('the simulator', _dir, _frame, const Size(440, 956)),
      ('an iPhone 16 Pro', _deviceDir, 1 / 120, const Size(402, 874)),
    ]) {
      test('present and dismiss about the arrow tip on $source', () {
        final rows = _rows('actionsheet-present-dismiss.jsonl', dir: dir);
        final dismiss = _event(rows, 'dismiss');
        final popover = [
          for (final r in rows)
            if (r['cls'] == '_UIPopoverView') r,
        ];
        final first = popover.firstWhere((r) => _d(r, 'sx') < 1);
        final firstT = _d(first, 't');
        List<double> presentErrors(double start) {
          final motion = MorphPopoverMotion();
          motion.present(start);
          return [
            for (final r in popover)
              if (_d(r, 't') >= firstT && _d(r, 't') < dismiss)
                motion.scale(_d(r, 't') + frame) - _d(r, 'sx'),
          ];
        }

        final (start, rms) = _align(firstT - 0.05, 0.1, presentErrors);
        expect(rms, lessThan(0.007));
        List<double> dismissErrors(double end) {
          final motion = MorphPopoverMotion();
          motion.present(start);
          motion.dismiss(end);
          return [
            for (final r in popover)
              if (_d(r, 't') > dismiss + 0.01)
                motion.scale(_d(r, 't') + frame) - _d(r, 'sx'),
          ];
        }

        final (end, dismissRms) = _align(dismiss, 0.1, dismissErrors);
        expect(dismissRms, lessThan(0.006));
        final placement = morphPlacePopover(
          size: const Size(240, 208.33),
          source: Rect.fromLTWH(size.width / 2 - 60, 576, 120, 48),
          screen: size,
          padding: const EdgeInsets.only(top: 62, bottom: 34),
        );
        expect(placement.edge, MorphPopoverArrowEdge.bottom);
        final motion = MorphPopoverMotion();
        motion.present(start);
        final yErrors = [
          for (final r in popover)
            if (_d(r, 't') >= firstT && _d(r, 't') < dismiss)
              () {
                final s = motion.scale(_d(r, 't') + frame);
                final full = placement.bounds;
                final anchor = placement.anchor;
                return anchor.dy +
                    s * (full.center.dy - anchor.dy) -
                    _d(r, 'y');
              }(),
        ];
        expect(_rms(yErrors), lessThan(1.5));
        final shown = MorphPopoverMotion();
        shown.present(start);
        final leaving = MorphPopoverMotion();
        leaving.present(start);
        leaving.dismiss(end);
        final aErrors = [
          for (final r in popover)
            if (_d(r, 't') >= firstT)
              (_d(r, 't') + frame < end ? shown : leaving).progress(
                    _d(r, 't') + frame,
                  ) -
                  _d(r, 'a'),
        ];
        expect(_rms(aErrors), lessThan(0.01));
      });
    }

    test('a tap outside dismisses on the dismiss spring', () {
      final rows = _rows('actionsheet-tap-out.jsonl');
      final up = _d(rows.lastWhere((r) => r['k'] == 'touch'), 't');
      final popover = [
        for (final r in rows)
          if (r['cls'] == '_UIPopoverView' && _d(r, 't') > up) r,
      ];
      List<double> errors(double start) {
        final motion = MorphPopoverMotion();
        motion.present(start - 5);
        motion.dismiss(start);
        return [
          for (final r in popover)
            motion.scale(_d(r, 't') + _frame) - _d(r, 'sx'),
        ];
      }

      final (_, rms) = _align(up, 0.08, errors);
      expect(rms, lessThan(0.006));
    });

    test('placement matches UIKit for every captured source', () {
      final data =
          (jsonDecode(File('$_dir/placements.json').readAsStringSync()) as Map)
              .cast<String, Object?>();
      final cases = (data['cases']! as List).cast<Map<String, Object?>>();
      expect(cases.length, greaterThanOrEqualTo(15));
      for (final c in cases) {
        final s = (c['source']! as List).cast<num>();
        final m = (c['content']! as List).cast<num>();
        final placement = morphPlacePopover(
          size: Size(m[2].toDouble(), m[3].toDouble()),
          source: Rect.fromLTWH(
            s[0].toDouble(),
            s[1].toDouble(),
            s[2].toDouble(),
            s[3].toDouble(),
          ),
          screen: const Size(440, 956),
          padding: const EdgeInsets.only(top: 62, bottom: 34),
        );
        expect(
          placement.content.left,
          closeTo(m[0].toDouble(), 0.5),
          reason: '${c['name']}',
        );
        expect(
          placement.content.top,
          closeTo(m[1].toDouble(), 0.5),
          reason: '${c['name']}',
        );
      }
    });
  });

  group('MorphAlertMotion', () {
    test('presents from the measured scale, transparent', () {
      final motion = MorphAlertMotion();
      motion.present(0);
      expect(motion.scale(0), closeTo(MorphAlertTuning.presentScale, 1e-9));
      expect(motion.opacity(0), 0);
      motion.advance(2);
      expect(motion.isSettled, isTrue);
      expect(motion.scale(2), closeTo(1, 1e-4));
      expect(motion.opacity(2), closeTo(1, 1e-3));
    });

    test('a dismissal mid-present reverses with the velocity', () {
      final motion = MorphAlertMotion();
      motion.present(0);
      final before = motion.progress(0.05);
      motion.dismiss(0.05);
      expect(motion.progress(0.05), closeTo(before, 1e-9));
      expect(motion.progress(0.06), greaterThan(before));
      motion.advance(3);
      expect(motion.isDismissed, isTrue);
    });
  });

  group('showMorphAlert', () {
    Future<void> open(
      WidgetTester tester,
      Future<void> Function(BuildContext) show, {
      ThemeData? theme,
      TextDirection direction = TextDirection.ltr,
      double textScale = 1,
    }) async {
      await tester.binding.setSurfaceSize(const Size(440, 956));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Directionality(textDirection: direction, child: child!),
          ),
          home: Builder(
            builder: (BuildContext context) => Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => show(context),
                child: const SizedBox(
                  key: ValueKey('source'),
                  width: 120,
                  height: 48,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('source')));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the text and the buttons, cancel last in a column', (
      tester,
    ) async {
      await open(
        tester,
        (c) => showMorphAlert(
          c,
          title: 'Title',
          message: 'Message',
          actions: const [
            MorphAlertAction(title: 'Cancel', style: .cancel),
            MorphAlertAction(title: 'OK'),
            MorphAlertAction(title: 'Delete', style: .destructive),
          ],
        ),
      );
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      final ok = tester.getCenter(find.text('OK'));
      final delete = tester.getCenter(find.text('Delete'));
      final cancel = tester.getCenter(find.text('Cancel'));
      expect(ok.dy, lessThan(delete.dy));
      expect(delete.dy, lessThan(cancel.dy));
      expect(delete.dy - ok.dy, closeTo(56, 0.5));
    });

    testWidgets('two buttons sit side by side, cancel first', (tester) async {
      await open(
        tester,
        (c) => showMorphAlert(
          c,
          title: 'Title',
          actions: const [
            MorphAlertAction(title: 'OK'),
            MorphAlertAction(title: 'Cancel', style: .cancel),
          ],
        ),
      );
      final ok = tester.getCenter(find.text('OK'));
      final cancel = tester.getCenter(find.text('Cancel'));
      expect(ok.dy, closeTo(cancel.dy, 0.5));
      expect(cancel.dx, lessThan(ok.dx));
    });

    testWidgets('mirrors the row in right-to-left', (tester) async {
      await open(
        tester,
        (c) => showMorphAlert(
          c,
          title: 'Title',
          actions: const [
            MorphAlertAction(title: 'OK'),
            MorphAlertAction(title: 'Cancel', style: .cancel),
          ],
        ),
        direction: TextDirection.rtl,
      );
      final ok = tester.getCenter(find.text('OK'));
      final cancel = tester.getCenter(find.text('Cancel'));
      expect(cancel.dx, greaterThan(ok.dx));
    });

    testWidgets('a tap chooses, the handler runs once the alert is gone', (
      tester,
    ) async {
      var handled = 0;
      MorphAlertAction? result;
      await open(
        tester,
        (c) async => result = await showMorphAlert(
          c,
          title: 'Title',
          actions: [MorphAlertAction(title: 'OK', onPressed: () => handled++)],
        ),
      );
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(result?.title, 'OK');
      expect(handled, 0);
      await tester.pumpAndSettle();
      expect(handled, 1);
      expect(find.text('Title'), findsNothing);
    });

    testWidgets('sliding to another button chooses it, outside chooses none', (
      tester,
    ) async {
      MorphAlertAction? result;
      var done = false;
      await open(tester, (c) async {
        result = await showMorphAlert(
          c,
          title: 'Title',
          actions: const [
            MorphAlertAction(title: 'One'),
            MorphAlertAction(title: 'Two'),
            MorphAlertAction(title: 'Three'),
          ],
        );
        done = true;
      });
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('One')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(tester.getCenter(find.text('Two')));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(done, isFalse);
      final again = await tester.startGesture(
        tester.getCenter(find.text('One')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await again.moveTo(tester.getCenter(find.text('Three')));
      await tester.pump(const Duration(milliseconds: 100));
      await again.up();
      await tester.pumpAndSettle();
      expect(result?.title, 'Three');
    });

    testWidgets('a disabled action does not choose', (tester) async {
      var done = false;
      await open(tester, (c) async {
        await showMorphAlert(
          c,
          title: 'Title',
          actions: const [
            MorphAlertAction(title: 'Off', enabled: false),
            MorphAlertAction(title: 'Cancel', style: .cancel),
          ],
        );
        done = true;
      });
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      expect(done, isFalse);
    });

    testWidgets('Escape cancels and Return chooses the preferred action', (
      tester,
    ) async {
      MorphAlertAction? result;
      await open(
        tester,
        (c) async => result = await showMorphAlert(
          c,
          title: 'Title',
          actions: const [
            MorphAlertAction(title: 'Cancel', style: .cancel),
            MorphAlertAction(title: 'Save', isPreferred: true),
          ],
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(result?.title, 'Cancel');
      await tester.tap(find.byKey(const ValueKey('source')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result?.title, 'Save');
    });

    testWidgets('a tap outside an alert does nothing', (tester) async {
      var done = false;
      await open(tester, (c) async {
        await showMorphAlert(c, title: 'Title');
        done = true;
      });
      await tester.tapAt(const Offset(20, 100));
      await tester.pumpAndSettle();
      expect(done, isFalse);
      expect(find.text('Title'), findsOneWidget);
    });

    testWidgets('screen readers see a named route of buttons', (tester) async {
      final semantics = tester.ensureSemantics();
      await open(
        tester,
        (c) => showMorphAlert(
          c,
          title: 'Delete photo?',
          actions: const [
            MorphAlertAction(title: 'Delete', style: .destructive),
          ],
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Delete')),
        matchesSemantics(
          label: 'Delete',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(find.bySemanticsLabel('Delete photo?'), findsWidgets);
      semantics.dispose();
    });

    testWidgets('resolves dark colors and survives a large text scale', (
      tester,
    ) async {
      await open(
        tester,
        (c) => showMorphAlert(
          c,
          title: 'A title that is long enough to wrap at a large scale',
          message: 'And a message below it that wraps as well.',
          actions: const [
            MorphAlertAction(title: 'One'),
            MorphAlertAction(title: 'Two'),
            MorphAlertAction(title: 'Three'),
          ],
        ),
        theme: ThemeData(brightness: Brightness.dark),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(find.textContaining('A title'));
      expect(title.style?.color, MorphAlertStyle.dark.titleColor);
    });

    testWidgets('a text field takes input', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await open(
        tester,
        (c) => showMorphAlert(
          c,
          title: 'Rename',
          textFields: [
            MorphAlertTextField(placeholder: 'Name', controller: controller),
          ],
          actions: const [MorphAlertAction(title: 'OK')],
        ),
      );
      expect(find.text('Name'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'Kitten');
      await tester.pump();
      expect(controller.text, 'Kitten');
      expect(find.text('Name'), findsNothing);
    });
  });

  group('showMorphActionSheet', () {
    testWidgets('anchored: a popover without cancel; outside runs cancel', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(440, 956));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var cancelled = 0;
      MorphAlertAction? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Stack(
              children: [
                Positioned(
                  left: 160,
                  top: 576,
                  width: 120,
                  height: 48,
                  child: Builder(
                    builder: (BuildContext anchor) => GestureDetector(
                      key: const ValueKey('source'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () async => result = await showMorphActionSheet(
                        context,
                        anchor: anchor,
                        title: 'Title',
                        actions: [
                          const MorphAlertAction(title: 'OK'),
                          MorphAlertAction(
                            title: 'Cancel',
                            style: .cancel,
                            onPressed: () => cancelled++,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('source')));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      final ok = tester.getRect(find.text('OK'));
      expect(ok.center.dx, closeTo(220, 1));
      expect(ok.bottom, lessThan(576));
      await tester.tapAt(const Offset(220, 120));
      await tester.pump();
      expect(cancelled, 1);
      await tester.pumpAndSettle();
      expect(result?.title, 'Cancel');
      expect(cancelled, 1);
      expect(find.text('OK'), findsNothing);
    });

    testWidgets('without a source it is an alert with cancel at the bottom', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(440, 956));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => GestureDetector(
              key: const ValueKey('source'),
              behavior: HitTestBehavior.opaque,
              onTap: () => showMorphActionSheet(
                context,
                title: 'Title',
                actions: const [
                  MorphAlertAction(title: 'Cancel', style: .cancel),
                  MorphAlertAction(title: 'OK'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('source')));
      await tester.pumpAndSettle();
      final ok = tester.getCenter(find.text('OK'));
      final cancel = tester.getCenter(find.text('Cancel'));
      expect(cancel.dy, greaterThan(ok.dy));
      expect(ok.dx, closeTo(220, 0.5));
    });
  });
}
