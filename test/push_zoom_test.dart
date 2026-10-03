import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

Rect _rect(List<Object?> v) => Rect.fromLTRB(
  (v[0]! as num).toDouble(),
  (v[1]! as num).toDouble(),
  (v[2]! as num).toDouble(),
  (v[3]! as num).toDouble(),
);

Map<String, Object?> _fixture() => jsonDecode(
  File('test/fixtures/ios27-device/push_zoom/push_zoom.json')
      .readAsStringSync(),
) as Map<String, Object?>;

List<Map<String, Object?>> _list(Object? v) =>
    (v! as List<Object?>).cast<Map<String, Object?>>();

double _edgeRms(Iterable<(Rect, Rect)> pairs) {
  var sum = 0.0;
  var n = 0;
  for (final (a, b) in pairs) {
    for (final d in [
      a.left - b.left,
      a.top - b.top,
      a.right - b.right,
      a.bottom - b.bottom,
    ]) {
      sum += d * d;
      n++;
    }
  }
  return n == 0 ? 0 : math.sqrt(sum / n);
}

const _page = Rect.fromLTWH(0, 0, 402, 874);

const _rowsTrail = 1 / 60;

const _velocityWindow = 0.05;

const _dragLimits = {
  'pd-down-150': (3.0, 2.5),
  'pd-down-110': (3.0, 2.0),
  'pd-down-125': (4.5, 7.5),
  'pd-down-140': (3.0, 2.5),
  'pd-flick-100': (15.0, 45.0),
  'pd-flick': (8.0, 10.0),
  'push-zoom-swipe-down': (3.0, 6.0),
  'push-zoom-swipe-cancel': (3.5, 1.5),
  'pd-right-mid': (6.0, 0.5),
  'push-zoom-edge': (10.0, 9.0),
};
const _card = Rect.fromLTWH(121.33, 250, 160, 100);

void main() {
  group('device replay', () {
    for (final segment in _list(_fixture()['segments'])) {
      final name = segment['name']! as String;
      final way = segment['way']! as String;
      test('$name follows the recording', () {
        final from = _rect(segment['from']! as List<Object?>);
        final to = _rect(segment['to']! as List<Object?>);
        final motion = MorphPushZoomMotion();
        if (way == 'open') {
          motion.open(0, from, to);
        } else {
          motion.open(-10, to, from);
          motion.advance(0);
          motion.close(0, to);
        }
        final pairs = <(Rect, Rect)>[];
        var fadeError = 0.0;
        for (final f in _list(segment['frames'])) {
          final t = (f['t']! as num).toDouble();
          if (t < 0) continue;
          motion.advance(t);
          pairs.add((motion.rect(t), _rect(f['rect']! as List<Object?>)));
          final fade = f['fade'] as num?;
          if (fade != null) {
            fadeError = math.max(
              fadeError,
              (motion.fade(t) - fade.toDouble()).abs(),
            );
          }
        }
        expect(_edgeRms(pairs), lessThan(way == 'open' ? 1.6 : 1.0));
        expect(fadeError, lessThan(0.12));
      });
    }
  });

  group('device drags', () {
    for (final drag in _list(_fixture()['drags'])) {
      final name = drag['name']! as String;
      test('$name follows the finger and ends as UIKit did', () {
        final touches = [
          for (final v in (drag['touches']! as List<Object?>))
            [for (final x in (v! as List<Object?>)) (x! as num).toDouble()],
        ];
        final lift = (drag['lift']! as num).toDouble() - _rowsTrail;
        final motion = MorphPushZoomMotion();
        motion.open(-10, _card, _page);
        motion.advance(0);
        motion.dragStart(0, Offset(touches.first[1], touches.first[2]));
        var next = 1;
        bool? dismissed;
        var dragSum = 0.0;
        var dragN = 0;
        var endSum = 0.0;
        var endN = 0;
        for (final f in _list(drag['frames'])) {
          final t = (f['t']! as num).toDouble();
          while (next < touches.length && touches[next][0] <= t) {
            final p = touches[next];
            if (p[0] < lift) {
              motion.dragUpdate(p[0], Offset(p[1], p[2]));
            }
            next++;
          }
          if (dismissed == null && t >= lift) {
            final last = touches.last;
            final before = touches.firstWhere(
              (p) => p[0] >= last[0] - _velocityWindow,
            );
            final dt = math.max(1e-3, last[0] - before[0]);
            final velocity = Offset(
              (last[1] - before[1]) / dt,
              (last[2] - before[2]) / dt,
            );
            motion.dragUpdate(lift, Offset(last[1], last[2]));
            dismissed = motion.dragEnd(lift, velocity);
            if (dismissed) motion.close(lift, _card);
          }
          motion.advance(t);
          final r = motion.rect(t);
          final want = f['rect']! as List<Object?>;
          final got = [r.left, r.top, r.right, r.bottom];
          for (var i = 0; i < 4; i++) {
            final w = want[i] as num?;
            if (w == null) continue;
            final d = got[i] - w.toDouble();
            if (t < lift) {
              dragSum += d * d;
              dragN++;
            } else {
              endSum += d * d;
              endN++;
            }
          }
        }
        final dragRms = math.sqrt(dragSum / math.max(1, dragN));
        final endRms = math.sqrt(endSum / math.max(1, endN));
        final (dragLimit, endLimit) = _dragLimits[name]!;
        expect(dismissed, drag['outcome'] == 'dismiss');
        expect(dragRms, lessThan(dragLimit));
        expect(endRms, lessThan(endLimit));
      });
    }
  });

  group('motion', () {
    test('a pop mid-open turns around with the velocity it had', () {
      final motion = MorphPushZoomMotion();
      motion.open(0, _card, _page);
      motion.advance(0.08);
      final before = motion.rect(0.08);
      final ahead = motion.rect(0.081);
      motion.close(0.08, _card);
      expect(motion.rect(0.08), before);
      final after = motion.rect(0.081);
      expect((after.width - ahead.width).abs(), lessThan(0.5));
    });

    test('the corner radius runs from the source to the display', () {
      final motion = MorphPushZoomMotion();
      motion.open(0, _card, _page);
      expect(motion.radius(0, 16, 62), closeTo(16, 1e-9));
      motion.advance(3);
      expect(motion.radius(3, 16, 62), closeTo(62, 0.1));
      expect(motion.isOpen, isTrue);
    });

    test('a close rests on the source', () {
      final motion = MorphPushZoomMotion();
      motion.open(0, _card, _page);
      motion.advance(2);
      motion.close(2, _card);
      motion.advance(4);
      expect(motion.isClosed, isTrue);
      final r = motion.rect(4);
      expect(r.left, closeTo(_card.left, 0.1));
      expect(r.height, closeTo(_card.height, 0.1));
    });
  });

  group('in a navigation stack', () {
    Future<BuildContext> pumpStack(WidgetTester tester) async {
      tester.view.physicalSize = const Size(402, 874) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      late BuildContext home;
      await tester.pumpWidget(
        MaterialApp(
          home: MorphScope(
            child: MorphNavigationStack(
              home: Builder(
                builder: (BuildContext context) {
                  home = context;
                  return Stack(
                    children: [
                      const Positioned.fill(
                        child: ColoredBox(color: Color(0xFF808080)),
                      ),
                      Positioned.fromRect(
                        rect: _card,
                        child: const MorphTag(
                          id: 'card',
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                          ),
                          child: ColoredBox(
                            key: ValueKey<String>('card'),
                            color: Color(0xFFFF00FF),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return home;
    }

    Widget detail(BuildContext context) => const ColoredBox(
      key: ValueKey<String>('detail'),
      color: Color(0xFF00C800),
    );

    Future<void> pushDetail(WidgetTester tester, BuildContext home) async {
      unawaited(pushMorphZoom<void>(home, builder: detail, from: 'card'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('the page grows out of the card and fills the screen', (
      WidgetTester tester,
    ) async {
      final home = await pumpStack(tester);
      await pushDetail(tester, home);
      final mid = tester.getRect(find.byKey(const ValueKey<String>('detail')));
      expect(mid.width, lessThan(402));
      expect(mid.width, greaterThan(160));
      await tester.pumpAndSettle();
      final full = tester.getRect(find.byKey(const ValueKey<String>('detail')));
      expect(full, const Rect.fromLTWH(0, 0, 402, 874));
    });

    testWidgets('a pop zooms back into the card, which shows again', (
      WidgetTester tester,
    ) async {
      final home = await pumpStack(tester);
      await pushDetail(tester, home);
      await tester.pumpAndSettle();
      Navigator.of(home).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final mid = tester.getRect(find.byKey(const ValueKey<String>('detail')));
      expect(mid.width, lessThan(402));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('detail')), findsNothing);
      final card = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(const ValueKey<String>('card')),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(card.opacity, 1);
    });

    testWidgets('a drag down past the threshold dismisses, a short one '
        'returns, a drag up does nothing', (WidgetTester tester) async {
      final home = await pumpStack(tester);
      await pushDetail(tester, home);
      await tester.pumpAndSettle();
      final page = find.byKey(const ValueKey<String>('detail'));

      final up = await tester.startGesture(const Offset(201, 600));
      for (var i = 0; i < 10; i++) {
        await up.moveBy(const Offset(0, -15));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getRect(page), const Rect.fromLTWH(0, 0, 402, 874));
      await up.up();
      await tester.pumpAndSettle();

      final short = await tester.startGesture(const Offset(201, 400));
      for (var i = 0; i < 10; i++) {
        await short.moveBy(const Offset(0, 9));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final held = tester.getRect(page);
      expect(held.width, lessThan(402));
      expect(held.top, greaterThan(50));
      await tester.pump(const Duration(milliseconds: 300));
      await short.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(page), const Rect.fromLTWH(0, 0, 402, 874));

      final long = await tester.startGesture(const Offset(201, 400));
      for (var i = 0; i < 20; i++) {
        await long.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await long.up();
      await tester.pumpAndSettle();
      expect(page, findsNothing);
    });
  });
}
