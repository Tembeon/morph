import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

const _progress = 'test/fixtures/ios27/progress';
const _pages = 'test/fixtures/ios27/page_control';

List<Map<String, Object?>> _rows(String path) => [
  for (final line in File(path).readAsLinesSync())
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

double _d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();

/// Replays a scripted progress capture: the fill of a 300 point
/// UIProgressView starting at [initial], each `progress:` script action
/// aligned to the recording within two frames of its call. Returns the
/// rms errors of the fill width and opacity.
({double width, double opacity}) _replayProgress(String file, double initial) {
  final rows = _rows('$_progress/$file');
  final actions = [
    for (final r in rows)
      if (r['k'] == 'evt' &&
          (r['a'] as String?)?.startsWith('progress:') == true)
        (double.parse((r['a']! as String).substring(9)), _d(r, 't')),
  ];
  final fill = [
    for (final r in rows)
      if (r['k'] == 'V') r,
  ];
  final frame = 1 / 60;
  List<double> run(List<double> starts, double until, {bool opacity = false}) {
    final motion = MorphProgressMotion(value: initial);
    final errors = <double>[];
    var next = 0;
    for (final r in fill) {
      final t = _d(r, 't') + frame;
      if (t < starts.first - 0.05 || t >= until) continue;
      while (next < starts.length && starts[next] <= t) {
        motion.setValue(starts[next], actions[next].$1);
        next++;
      }
      motion.advance(t);
      errors.add(
        opacity
            ? motion.fillOpacity(t) - _d(r, 'a')
            : motion.fillWidth(t, 300) - _d(r, 'bw'),
      );
    }
    return errors;
  }

  double sq(List<double> e) => e.fold(0.0, (a, b) => a + b * b);
  final starts = <double>[];
  for (var k = 0; k < actions.length; k++) {
    final until = k + 1 < actions.length ? actions[k + 1].$2 : double.infinity;
    var best = actions[k].$2;
    var bestErr = double.infinity;
    for (var lag = -0.034; lag <= 0.034; lag += 0.001) {
      final e = sq(run([...starts, actions[k].$2 + lag], until));
      if (e < bestErr) {
        bestErr = e;
        best = actions[k].$2 + lag;
      }
    }
    starts.add(best);
  }
  double rms(List<double> e) => math.sqrt(sq(e) / e.length);
  return (
    width: rms(run(starts, double.infinity)),
    opacity: rms(run(starts, double.infinity, opacity: true)),
  );
}

void main() {
  group('MorphProgressMotion', () {
    test('runs one second per unit of progress, linearly', () {
      final m = MorphProgressMotion(value: 0.2);
      m.setValue(0, 0.8);
      m.advance(0.3);
      expect(m.fillWidth(0.3, 300), closeTo(150, 1e-9));
      m.advance(0.6);
      expect(m.fillWidth(0.6, 300), closeTo(240, 1e-6));
      m.advance(0.61);
      expect(m.isSettled, isTrue);
    });

    test('hides an empty fill, fading over at least 0.2 s', () {
      final m = MorphProgressMotion(value: 0);
      expect(m.fillOpacity(0), 0);
      m.setValue(0, 0.05);
      m.advance(0.1);
      expect(m.fillOpacity(0.1), closeTo(0.5, 1e-9));
      expect(m.fillWidth(0.1, 300), closeTo(11.5, 1e-9));
      m.advance(0.2);
      expect(m.fillOpacity(0.2), 1);
    });

    test('a change during a change adds on top without a jump', () {
      final m = MorphProgressMotion(value: 0);
      m.setValue(0, 1);
      m.advance(0.5);
      final before = m.fillWidth(0.5, 300);
      m.setValue(0.5, 0.2);
      expect(m.fillWidth(0.5, 300), closeTo(before, 1e-9));
    });

    test('replays the simulator: 0.2 -> 0.3 -> 1 -> 0 -> 0.05', () {
      final r = _replayProgress('progress2.jsonl', 0.2);
      expect(r.width, lessThan(0.6));
      expect(r.opacity, lessThan(0.02));
    });

    test('replays the simulator: 0.5 -> 0.52 -> 0 -> 0.5', () {
      final r = _replayProgress('progress3.jsonl', 0.5);
      expect(r.width, lessThan(0.6));
      expect(r.opacity, lessThan(0.02));
    });
  });

  group('MorphActivityIndicatorFrames', () {
    test('sixteen images per 0.8 s turn, head moving clockwise', () {
      expect(MorphActivityIndicatorFrames.frameAt(0), 0);
      expect(MorphActivityIndicatorFrames.frameAt(0.05), 1);
      expect(MorphActivityIndicatorFrames.frameAt(0.8), 0);
      expect(MorphActivityIndicatorFrames.strength(0, 0), 0.843);
      expect(MorphActivityIndicatorFrames.strength(1, 2), 0.843);
      expect(
        MorphActivityIndicatorFrames.strength(7, 0),
        greaterThan(MorphActivityIndicatorFrames.strength(6, 0)),
      );
      expect(
        MorphActivityIndicatorFrames.strength(1, 0),
        MorphActivityIndicatorFrames.restStrength,
      );
    });

    test('a half step averages the two spokes it lies between', () {
      final s = MorphActivityIndicatorFrames.strength(0, 1);
      final a = MorphActivityIndicatorFrames.strength(0, 0);
      final b = MorphActivityIndicatorFrames.strength(0, 2);
      expect(s, closeTo((a + b) / 2, 1e-9));
    });
  });

  group('MorphPageControlMotion', () {
    test('replays the simulator: a timer page advance', () {
      final rows = _rows('$_pages/pc-timer.jsonl');
      final indicators = <int, List<Map<String, Object?>>>{};
      final fill = <Map<String, Object?>>[];
      for (final r in rows) {
        if (r['k'] != 'V') continue;
        if (r['cls'] == '_UIPageIndicatorView') {
          (indicators[r['id']! as int] ??= []).add(r);
        } else {
          fill.add(r);
        }
      }
      final ids = indicators.keys.toList()..sort();
      final first = indicators[ids[0]]!;
      final leave = first.firstWhere((r) => _d(r, 'w') < 27.2);
      double score(double start, {required bool report}) {
        final m = MorphPageControlMotion(
          count: 5,
          page: 0,
          showsProgress: true,
        );
        m.setPage(start, 1);
        final e = <double>[];
        for (final id in ids.take(2)) {
          final i = ids.indexOf(id);
          for (final r in indicators[id]!) {
            final t = _d(r, 't') + 1 / 60;
            if (t < start - 0.1) continue;
            m.advance(t);
            e.add(m.width(i, t) - _d(r, 'w'));
          }
        }
        return math.sqrt(e.fold(0.0, (a, b) => a + b * b) / e.length);
      }

      var best = double.infinity;
      for (var lag = -0.08; lag <= 0.02; lag += 0.002) {
        best = math.min(best, score(_d(leave, 't') + lag, report: false));
      }
      expect(best, lessThan(0.25));
      expect(fill, isNotEmpty);
    });
  });

  // The platter timing is the device's (120 Hz rows resolve its 25 ms
  // fades); on the 60 Hz simulator it lands within a frame, which is up to
  // 0.3 of opacity on the two or three samples of each fade.
  for (final (source, dir, shift, holdTolerance, scrubTolerance) in [
    ('the simulator', _pages, 1 / 60, 0.12, 0.18),
    (
      'an iPhone 16 Pro',
      'test/fixtures/ios27-device/page_control',
      1 / 120,
      0.03,
      0.03,
    ),
  ]) {
    group('MorphPageControlMotion touches, replayed against $source', () {
      /// The first dot's center in the probe's window, and the control's
      /// width (5 pages).
      const firstDot = 166.0;
      const width = 5 * 9.67 + 4 * 8 + 28;

      ({List<int> model, List<int> recorded, double platter}) replay(
        String name,
      ) {
        final rows = _rows('$dir/$name.jsonl');
        final motion = MorphPageControlMotion(count: 5, page: 0);
        final model = <int>[];
        motion.onChanged = model.add;
        final recorded = [
          for (final r in rows)
            if (r['k'] == 'evt' && r['e'] == 'valueChanged') r['v']! as int,
        ];
        final events = [
          for (final r in rows)
            if (r['k'] == 'touch' ||
                (r['k'] == 'V' && r['cls'] == 'UIVisualEffectView'))
              r,
        ];
        final errors = <double>[];
        for (final r in events) {
          final t = _d(r, 't');
          if (r['k'] == 'touch') {
            final x = _d(r, 'x') - firstDot + 9.67 / 2;
            switch (r['phase']) {
              case 0:
                motion.pointerDown(t, x);
              case 3:
                motion.pointerUp(t, x, width: width);
              default:
                motion.pointerMove(t, x);
            }
          } else if (t > _d(events.first, 't') + 1) {
            final shown = t + shift;
            motion.advance(shown);
            errors.add(motion.platter(shown) - _d(r, 'a'));
          }
        }
        return (
          model: model,
          recorded: recorded,
          platter: errors.isEmpty
              ? 0
              : math.sqrt(
                  errors.fold(0.0, (a, b) => a + b * b) / errors.length,
                ),
        );
      }

      test('taps step to the side they land on', () {
        final r = replay('pc-tap-right');
        expect(r.model, r.recorded);
      });

      test(
        'a held touch shows the platter after 0.2 s and hides it on lift',
        () {
          final r = replay('pc-hold');
          expect(r.model, isEmpty);
          expect(r.platter, lessThan(holdTolerance));
        },
      );

      test('a scrub follows the nearest dot both ways', () {
        final r = replay('pc-scrub');
        expect(r.model, r.recorded);
        expect(r.platter, lessThan(scrubTolerance));
      });
    });
  }

  testWidgets('progress view: semantics value and RTL fill from the right', (
    WidgetTester tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: SizedBox(
            width: 300,
            child: MorphProgressView(value: 0.5, semanticLabel: 'Upload'),
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.byType(MorphProgressView)),
      matchesSemantics(label: 'Upload', value: '50%'),
    );
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: SizedBox(width: 300, child: MorphProgressView(value: 0.9)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    handle.dispose();
  });

  testWidgets('activity indicator turns, hides when stopped, has a label', (
    WidgetTester tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Center(
          child: MorphActivityIndicator(size: MorphActivityIndicatorSize.large),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      tester.getSize(find.byType(MorphActivityIndicator)),
      const Size(37, 37),
    );
    expect(find.bySemanticsLabel('In progress'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Center(child: MorphActivityIndicator(animating: false)),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(MorphActivityIndicator),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.hasRunningAnimations, isFalse);
    handle.dispose();
  });

  testWidgets('page control: taps on either half step, arrows step too', (
    WidgetTester tester,
  ) async {
    var page = 2;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => Center(
            child: MorphPageControl(
              count: 5,
              page: page,
              semanticLabel: 'Pages',
              onChanged: (int p) => setState(() => page = p),
            ),
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byType(MorphPageControl));
    expect(box.width, closeTo(5 * 9.67 + 4 * 8 + 28, 0.01));
    expect(box.height, closeTo(25.67, 0.01));
    await tester.tapAt(box.centerRight - const Offset(10, 0));
    await tester.pump();
    expect(page, 3);
    await tester.tapAt(box.centerLeft + const Offset(10, 0));
    await tester.pump();
    expect(page, 2);
    final handle = tester.ensureSemantics();
    final node = tester.semantics.find(find.bySemanticsLabel('Pages'));
    final data = node.getSemanticsData();
    expect(data.value, 'page 3 of 5');
    expect(data.increasedValue, 'page 4 of 5');
    expect(data.decreasedValue, 'page 2 of 5');
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);
    handle.dispose();
  });

  testWidgets('page control in RTL steps the other way; disabled ignores', (
    WidgetTester tester,
  ) async {
    var page = 2;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: MorphPageControl(
            count: 5,
            page: page,
            onChanged: (int p) => page = p,
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byType(MorphPageControl));
    await tester.tapAt(box.centerLeft + const Offset(10, 0));
    expect(page, 3);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: MorphPageControl(count: 5, page: 2, onChanged: null),
        ),
      ),
    );
    await tester.tapAt(
      tester.getRect(find.byType(MorphPageControl)).centerRight,
    );
    expect(page, 3);
  });
}
