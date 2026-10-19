import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';
import 'package:morph/src/widgets/activity_indicator.dart';
import 'package:morph/src/widgets/page_control.dart';
import 'package:morph/src/widgets/progress.dart';

const _progress = 'test/fixtures/ios27/progress';
const _deviceProgress = 'test/fixtures/ios27-device/progress';
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
/// rms errors of the fill width and opacity. Device captures log several
/// views; [id] picks the fill's rows there.
({double width, double opacity}) _replayProgress(
  String file,
  double initial, {
  String dir = _progress,
  int? id,
  double frame = 1 / 60,
}) {
  final rows = _rows('$dir/$file');
  final actions = [
    for (final r in rows)
      if (r['k'] == 'evt' &&
          (r['a'] as String?)?.startsWith('progress:') == true)
        (double.parse((r['a']! as String).substring(9)), _d(r, 't')),
  ];
  final fill = [
    for (final r in rows)
      if (r['k'] == 'V' && (id == null || r['id'] == id)) r,
  ];
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
            ? motion.fillOpacity - _d(r, 'a')
            : motion.fillWidth(300) - _d(r, 'bw'),
      );
    }
    return errors;
  }

  double sq(List<double> e) => e.fold(0.0, (a, b) => a + b * b);
  final starts = <double>[];
  var k = 0;
  while (k < actions.length) {
    var end = k + 1;
    while (end < actions.length && actions[end].$2 - actions[k].$2 < 0.01) {
      end++;
    }
    final until = end < actions.length ? actions[end].$2 : double.infinity;
    var bestLag = 0.0;
    var bestErr = double.infinity;
    for (var lag = -0.034; lag <= 0.034; lag += 0.001) {
      final e = sq(
        run([
          ...starts,
          for (var j = k; j < end; j++) actions[j].$2 + lag,
        ], until),
      );
      if (e < bestErr) {
        bestErr = e;
        bestLag = lag;
      }
    }
    for (var j = k; j < end; j++) {
      starts.add(actions[j].$2 + bestLag);
    }
    k = end;
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
      expect(m.fillWidth(300), closeTo(150, 1e-9));
      m.advance(0.6);
      expect(m.fillWidth(300), closeTo(240, 1e-6));
      m.advance(0.61);
      expect(m.isSettled, isTrue);
    });

    test('hides an empty fill, fading over at least 0.2 s', () {
      final m = MorphProgressMotion(value: 0);
      expect(m.fillOpacity, 0);
      m.setValue(0, 0.05);
      m.advance(0.1);
      expect(m.fillOpacity, closeTo(0.5, 1e-9));
      expect(m.fillWidth(300), closeTo(11.5, 1e-9));
      m.advance(0.2);
      expect(m.fillOpacity, 1);
    });

    test('a change during a change adds on top without a jump', () {
      final m = MorphProgressMotion(value: 0);
      m.setValue(0, 1);
      m.advance(0.5);
      final before = m.fillWidth(300);
      m.setValue(0.5, 0.2);
      expect(m.fillWidth(300), closeTo(before, 1e-9));
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

    // Each capture runs a standard bar (fill rows 4) and a bar-style one
    // (fill rows 8) side by side, each from its own starting progress.
    for (final (file, standard, bar) in [
      ('progress2.jsonl', 0.2, 0.2),
      ('progress3.jsonl', 0.5, 0.2),
      ('progress-additive.jsonl', 0.2, 0.2),
    ]) {
      for (final (style, id, initial) in [
        ('standard', 4, standard),
        ('bar', 8, bar),
      ]) {
        test('replays the device: $file, $style style', () {
          final r = _replayProgress(
            file,
            initial,
            dir: _deviceProgress,
            id: id,
            frame: 1 / 120,
          );
          expect(r.width, lessThan(0.6));
          expect(r.opacity, lessThan(0.02));
        });
      }
    }
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
      double rms(List<double> e) =>
          math.sqrt(e.fold(0.0, (a, b) => a + b * b) / e.length);
      ({double widths, double fade}) score(double start) {
        MorphPageControlMotion started() {
          final m = MorphPageControlMotion(
            count: 5,
            page: 0,
            showsProgress: true,
          );
          m.setPage(start, 1);
          return m;
        }

        final e = <double>[];
        for (final id in ids.take(2)) {
          final i = ids.indexOf(id);
          final m = started();
          for (final r in indicators[id]!) {
            final t = _d(r, 't') + 1 / 60;
            if (t < start - 0.1) continue;
            m.advance(t);
            e.add(m.width(i) - _d(r, 'w'));
          }
        }
        final f = started();
        final fade = <double>[];
        for (final r in fill) {
          final t = _d(r, 't') + 1 / 60;
          if (t < start - 0.1) continue;
          f.advance(t);
          fade.add(f.fillOpacity(0) - _d(r, 'a'));
        }
        return (widths: rms(e), fade: rms(fade));
      }

      ({double widths, double fade})? best;
      for (var lag = -0.08; lag <= 0.02; lag += 0.002) {
        final s = score(_d(leave, 't') + lag);
        if (best == null || s.widths < best.widths) best = s;
      }
      expect(best!.widths, lessThan(0.25));
      // The fill of the page it leaves fades out at the same moment.
      expect(best.fade, lessThan(0.02));
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
        void collect() {
          for (final event in motion.drainEvents()) {
            if (event is MorphPageControlPicked) model.add(event.page);
          }
        }

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
            errors.add(motion.platter - _d(r, 'a'));
          }
          collect();
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

  testWidgets('a spinning activity indicator asks for one frame per image', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: MorphActivityIndicator()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    var frames = 0;
    var counting = true;
    tester.binding.addPersistentFrameCallback((_) {
      if (counting) frames++;
    });
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    counting = false;
    // 0.96 s of a 16-image, 0.8 s turn: 19.2 images. The doze used to end
    // half a frame early and take a frame that drew nothing new (31).
    expect(frames, lessThanOrEqualTo(21));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('activity indicator: stopped and started again, it turns on '
      'from the image it stopped on, as the device does', (
    WidgetTester tester,
  ) async {
    final rows = _rows('$_deviceProgress/activity-startstop.jsonl');
    final address = RegExp('CGImage (0x[0-9a-f]+)');
    List<String> images(Map<String, Object?> anim) => [
      for (final v in anim['vals']! as List<Object?>)
        address.firstMatch(v! as String)!.group(1)!,
    ];
    final anims = [
      for (final r in rows)
        if (r['k'] == 'anim' && r['id'] == 10 && r['key'] == 'contents') r,
    ];
    // Every startAnimating hands the layer the sixteen images reordered to
    // begin at the one it turns on from.
    final order = images(anims.first);
    final recorded = [for (final a in anims) order.indexOf(images(a).first)];
    expect(recorded, [0, 10, 4]);
    final begin = _d(anims.first, 'begin');
    final actions = [
      for (final r in rows)
        if (r['k'] == 'evt' &&
            r['e'] == 'script' &&
            _d(r, 't') > begin &&
            !(r['a']! as String).startsWith('dump'))
          (_d(r, 't') - begin, r['a']! as String),
    ];
    expect(
      [for (final (_, a) in actions) a],
      ['stop', 'start', 'hide:0', 'stop', 'start'],
    );

    var animating = true;
    var hides = true;
    Widget indicator() => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: MorphActivityIndicator(
          animating: animating,
          hidesWhenStopped: hides,
          color: const Color(0xFF000000),
        ),
      ),
    );
    int? shownImage() {
      final paint = find.descendant(
        of: find.byType(MorphActivityIndicator),
        matching: find.byType(CustomPaint),
      );
      if (paint.evaluate().isEmpty) return null;
      final render = tester.renderObject<RenderCustomPaint>(paint.first);
      final canvas = TestRecordingCanvas();
      render.painter!.paint(canvas, render.size);
      final strengths = [
        for (final call in canvas.invocations)
          if (call.invocation.memberName == #drawLine)
            (call.invocation.positionalArguments[2] as Paint).color.a,
      ];
      bool shows(int image) => [
        for (var i = 0; i < strengths.length; i++)
          (strengths[i] - MorphActivityIndicatorFrames.strength(i, image))
                  .abs() <
              1e-3,
      ].every((bool same) => same);
      return List<int>.generate(
        MorphActivityIndicatorFrames.frameCount,
        (int image) => image,
      ).firstWhere(shows);
    }

    const frame = Duration(microseconds: 8333);
    await tester.pumpWidget(indicator());
    final started = [shownImage()];
    final stops = <(int?, int?)>[];
    var now = 0.0;
    for (final (at, action) in actions) {
      while (now + 1 / 120 <= at) {
        await tester.pump(frame);
        now += 1 / 120;
      }
      final before = shownImage();
      switch (action) {
        case 'stop':
          animating = false;
        case 'start':
          animating = true;
        case 'hide:0':
          hides = false;
      }
      await tester.pumpWidget(indicator(), duration: frame);
      now += 1 / 120;
      if (action == 'start') started.add(shownImage());
      if (action == 'stop') stops.add((before, shownImage()));
    }
    expect(started, recorded);
    expect(stops.first.$2, isNull, reason: 'hidden when stopped');
    expect(
      stops.last.$2,
      stops.last.$1,
      reason: 'with hidesWhenStopped off, it keeps the image it stopped on',
    );
    await tester.pumpWidget(const SizedBox());
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

  testWidgets('page control: a resting finger lets the ticker sleep, a '
      'scrub wakes it', (WidgetTester tester) async {
    var page = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => Center(
            child: MorphPageControl(
              count: 5,
              page: page,
              onChanged: (int p) => setState(() => page = p),
            ),
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byType(MorphPageControl));
    final first = box.centerLeft + const Offset(14 + 9.67 / 2, 0);
    final touch = await tester.startGesture(first);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.hasRunningAnimations, isFalse);
    for (var i = 0; i < 4; i++) {
      await touch.moveBy(const Offset(12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(page, greaterThan(0));
    await touch.up();
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
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
