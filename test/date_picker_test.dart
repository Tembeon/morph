import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';

const _dir = 'test/fixtures/ios27/date_picker';
const double _frame = 1 / 60;

List<Map<String, Object?>> _rows(String file) => [
  for (final line in File('$_dir/$file').readAsLinesSync())
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

double _d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();

double _rms(List<double> e) =>
    math.sqrt(e.fold(0.0, (a, b) => a + b * b) / math.max(1, e.length));

(double, double) _fit(
  double from,
  double window,
  List<double> Function(double) errors,
) {
  var best = from;
  var bestErr = double.infinity;
  for (var lag = 0.0; lag <= window; lag += 0.001) {
    final e = _rms(errors(from + lag));
    if (e < bestErr) {
      bestErr = e;
      best = from + lag;
    }
  }
  return (best, bestErr);
}

Rect _box(List<Object?> v) {
  final n = v.cast<num>();
  return Rect.fromLTWH(
    n[0].toDouble(),
    n[1].toDouble(),
    n[2].toDouble(),
    n[3].toDouble(),
  );
}

void main() {
  group('compact date picker replays the simulator', () {
    test('the overlay opens and closes about its anchor', () {
      final rows = _rows('date-open.jsonl');
      final touches = [
        for (final r in rows)
          if (r['k'] == 'touch') r,
      ];
      final openUp = _d(touches[1], 't');
      final closeUp = _d(touches[3], 't');
      // The first frame of the close reads the platter's hidden state for
      // one frame (a presentation-layer artifact); it is skipped.
      final platter = [
        for (final r in rows)
          if (r['cls'] == '_UIDatePickerOverlayPlatterView' &&
              !(_d(r, 't') > closeUp &&
                  _d(r, 't') < closeUp + 0.03 &&
                  _d(r, 'a') == 0))
            r,
      ];
      List<double> errors(MorphDatePickerMotion m, double from, double to) => [
        for (final r in platter)
          if (_d(r, 't') >= from && _d(r, 't') < to)
            ...() {
              final t = _d(r, 't') + _frame;
              return [
                m.scale(t) - _d(r, 'sx'),
                m.opacity(t) - _d(r, 'a').clamp(0.0, 1.0),
                (m.height(t, 332) - _d(r, 'bh')) / 332,
              ];
            }(),
      ];
      final (open, openRms) = _fit(openUp, 0.25, (start) {
        final m = MorphDatePickerMotion();
        m.open(start);
        return errors(m, openUp, closeUp);
      });
      expect(openRms, lessThan(0.006));
      final (_, closeRms) = _fit(closeUp, 0.1, (start) {
        final m = MorphDatePickerMotion();
        m.open(open);
        m.close(start);
        return errors(m, closeUp, double.infinity);
      });
      expect(closeRms, lessThan(0.006));
      final placement = morphPlaceDatePicker(
        size: const Size(320, 332),
        label: const Rect.fromLTWH(162.67, 283, 115, 34.33),
        screen: const Size(440, 956),
        padding: const EdgeInsets.only(top: 62, bottom: 34),
      );
      final m = MorphDatePickerMotion();
      m.open(open);
      final anchorErrors = [
        for (final r in platter)
          if (_d(r, 't') >= openUp && _d(r, 't') < closeUp)
            ...() {
              final t = _d(r, 't') + _frame;
              final s = m.scale(t);
              final a = placement.anchor;
              final left = a.dx + s * (placement.rect.left - a.dx);
              final top = a.dy + s * (placement.rect.top - a.dy);
              return [
                left - (_d(r, 'x') - _d(r, 'w') / 2),
                top - (_d(r, 'y') - _d(r, 'h') / 2),
              ];
            }(),
      ];
      expect(_rms(anchorErrors), lessThan(1.5));
    });

    test('above its label the overlay is anchored at its bottom', () {
      final rows = _rows('date-low.jsonl');
      final first = rows.firstWhere(
        (r) => r['cls'] == '_UIDatePickerOverlayPlatterView',
      );
      final placement = morphPlaceDatePicker(
        size: const Size(320, 332),
        label: const Rect.fromLTWH(162.67, 743, 115, 34.33),
        screen: const Size(440, 956),
        padding: const EdgeInsets.only(top: 62, bottom: 34),
      );
      expect(placement.below, isFalse);
      expect(
        _d(first, 'y') + _d(first, 'h') / 2,
        closeTo(placement.anchor.dy, 0.5),
      );
    });

    test('placement matches UIKit for every captured label', () {
      final data =
          (jsonDecode(File('$_dir/placements.json').readAsStringSync()) as Map)
              .cast<String, Object?>();
      for (final c in (data['cases']! as List).cast<Map<String, Object?>>()) {
        final overlay = _box(c['overlay']! as List);
        final hidden = _box(c['hidden']! as List);
        final placement = morphPlaceDatePicker(
          size: overlay.size,
          label: _box(c['label']! as List),
          screen: const Size(440, 956),
          padding: const EdgeInsets.only(top: 62, bottom: 34),
        );
        expect(
          placement.rect.left,
          closeTo(overlay.left, 0.5),
          reason: '${c['name']}',
        );
        expect(
          placement.rect.top,
          closeTo(overlay.top, 0.5),
          reason: '${c['name']}',
        );
        const s = MorphDatePickerTuning.hiddenScale;
        final a = placement.anchor;
        expect(
          a.dx + s * (placement.rect.left - a.dx),
          closeTo(hidden.left, 0.5),
          reason: '${c['name']} hidden',
        );
      }
    });

    test('a month turns on a sine ease over 0.3 s', () {
      final rows = _rows('date-page.jsonl');
      final touches = [
        for (final r in rows)
          if (r['k'] == 'touch') r,
      ];
      final up = _d(touches.last, 't');
      final first = rows.firstWhere(
        (r) => r['text'] == '15' && _d(r, 't') > up,
      );
      final day = [
        for (final r in rows)
          if (r['text'] == '15' && r['id'] == first['id'] && _d(r, 't') > up) r,
      ];
      final (_, rms) = _fit(up - 0.03, 0.08, (start) {
        final m = MorphDatePickerMotion();
        m.turnPage(start, 1);
        return [
          for (final r in day)
            (222.33 - 320 * m.page(_d(r, 't') + _frame)) - _d(r, 'x'),
        ];
      });
      expect(rms, lessThan(2.5));
    });

    test('the label dims under the finger', () {
      final rows = _rows('date-open.jsonl');
      final touches = [
        for (final r in rows)
          if (r['k'] == 'touch') r,
      ];
      final down = _d(touches[0], 't');
      final up = _d(touches[1], 't');
      final label = [
        for (final r in rows)
          if (r['cls'] == '_UIDatePickerLinkedLabel' &&
              _d(r, 't') < down + 0.7 &&
              _d(r, 't') >= down)
            r,
      ];
      final (_, rms) = _fit(down - 0.02, 0.04, (at) {
        final m = MorphDatePickerMotion();
        m.press(at);
        m.release(at + up - down);
        return [
          for (final r in label) m.highlight(_d(r, 't') + _frame) - _d(r, 'a'),
        ];
      });
      expect(rms, lessThan(0.03));
    });
  });

  group('compact date picker replays an iPhone 16 Pro', () {
    const device = 'test/fixtures/ios27-device/date_picker';
    List<Map<String, Object?>> load(String file) => [
      for (final line in File('$device/$file').readAsLinesSync())
        if (line.trim().isNotEmpty)
          (jsonDecode(line) as Map).cast<String, Object?>(),
    ];
    List<double> ups(List<Map<String, Object?>> rows) => [
      for (final r in rows)
        if (r['k'] == 'touch' && r['phase'] == 3) _d(r, 't'),
    ];

    test(
      'the overlay opens 0.14 s after the lift and closes 0.055 s after',
      () {
        final rows = load('vid-date.jsonl');
        final platter = [
          for (final r in rows)
            if (r['cls'] == '_UIDatePickerOverlayPlatterView') r,
        ];
        final lifts = ups(rows);
        // The press on the label lifts first and opens the overlay; the tap
        // outside at y 754 closes it.
        final openUp = lifts.first;
        final closeUp = [
          for (final r in rows)
            if (r['k'] == 'touch' && r['phase'] == 3 && _d(r, 'y') > 700)
              _d(r, 't'),
        ].first;
        final m = MorphDatePickerMotion();
        m.open(openUp);
        m.close(closeUp);
        final open = <double>[];
        final close = <double>[];
        for (final r in platter) {
          final t = _d(r, 't');
          // Before the animation's first frame the view reads its final
          // layout, and the close's first frame its hidden one (one row
          // each); the springs are compared from their start on.
          if (t < openUp + MorphDatePickerTuning.openDelay ||
              t > closeUp + 0.8 ||
              (t > closeUp && _d(r, 'a') == 0)) {
            continue;
          }
          final e = m.scale(t) - _d(r, 'sx');
          if (t < closeUp) {
            open.add(e);
          } else {
            close.add(e);
          }
        }
        expect(open.length, greaterThan(40));
        expect(close.length, greaterThan(30));
        // Without the delays the same springs miss by 0.27 (open) and 0.16
        // (close); 0.03 s either way already costs 0.07.
        expect(_rms(open), lessThan(0.015));
        expect(_rms(close), lessThan(0.015));
      },
    );

    test('the other label turns the overlay on a 0.25 s spring', () {
      final rows = load('vid-both.jsonl');
      final lifts = ups(rows);
      final up = lifts[1];
      const from = Size(320, 332);
      const to = MorphDatePickerTuning.timeSize;
      expect(MorphDatePickerTuning.switchSpring.dampingRatio, 1);
      double p(double t) {
        final dt = t - up - MorphDatePickerTuning.switchDelay;
        if (dt <= 0) return 0;
        final w = 2 * math.pi / MorphDatePickerTuning.switchSpring.response;
        return 1 - math.exp(-w * dt) * (1 + w * dt);
      }

      final size = <double>[];
      final fade = <double>[];
      for (final r in rows) {
        final t = _d(r, 't');
        if (t < up || t > up + 0.6) continue;
        if (r['cls'] == '_UIDatePickerOverlayPlatterView') {
          size.add(_d(r, 'w') - (from.width + (to.width - from.width) * p(t)));
          size.add(
            _d(r, 'h') - (from.height + (to.height - from.height) * p(t)),
          );
        } else if (r['cls'] == '_UIDatePickerCalendarView') {
          fade.add(_d(r, 'ea') - (1 - p(t)));
        }
      }
      expect(size.length, greaterThan(40));
      expect(_rms(size), lessThan(0.6));
      expect(_rms(fade), lessThan(0.02));
    });
  });

  group('MorphDatePicker', () {
    Future<void> pump(
      WidgetTester tester, {
      DateTime? value,
      ValueChanged<DateTime>? onChanged,
      MorphDatePickerMode mode = MorphDatePickerMode.date,
      ThemeData? theme,
      TextDirection direction = TextDirection.ltr,
      double textScale = 1,
      bool use24 = true,
      Alignment alignment = const Alignment(0, -0.4),
    }) async {
      await tester.binding.setSurfaceSize(const Size(440, 956));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var current = value ?? DateTime(2026, 10, 3, 9, 41);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: Directionality(textDirection: direction, child: child!),
          ),
          home: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => Align(
              alignment: alignment,
              child: MorphDatePicker(
                value: current,
                mode: mode,
                use24HourFormat: use24,
                today: DateTime(2026, 10, 3),
                semanticLabel: 'Date',
                onChanged: onChanged == null
                    ? null
                    : (DateTime v) {
                        onChanged(v);
                        setState(() => current = v);
                      },
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('opens the calendar, picks a day, stays open, closes', (
      tester,
    ) async {
      final picked = <DateTime>[];
      await pump(tester, onChanged: picked.add);
      expect(find.text('Oct 3, 2026'), findsOneWidget);
      await tester.tap(find.text('Oct 3, 2026'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      final label = tester.widget<Text>(find.text('Oct 3, 2026'));
      expect(label.style?.color, MorphDatePickerStyle.light.accentColor);
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      expect(picked.single, DateTime(2026, 10, 15, 9, 41));
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('Oct 15, 2026'), findsOneWidget);
      await tester.tapAt(const Offset(220, 900));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsNothing);
    });

    testWidgets('the overlay hangs below and extends to the leading side', (
      tester,
    ) async {
      await pump(tester, onChanged: (_) {});
      final label = tester.getRect(find.byType(MorphDatePicker));
      await tester.tap(find.byType(MorphDatePicker));
      await tester.pumpAndSettle();
      final title = tester.getRect(find.text('October 2026'));
      expect(title.top, greaterThan(label.center.dy));
      expect(title.left, closeTo(20 + 20.33, 1));
    });

    testWidgets('in right-to-left the overlay extends to the right', (
      tester,
    ) async {
      await pump(
        tester,
        onChanged: (_) {},
        direction: TextDirection.rtl,
        alignment: const Alignment(-0.6, -0.4),
      );
      final label = tester.getRect(find.byType(MorphDatePicker));
      await tester.tap(find.byType(MorphDatePicker));
      await tester.pumpAndSettle();
      final title = tester.getRect(find.text('October 2026'));
      expect(title.right, greaterThan(label.center.dx));
    });

    testWidgets('the chevrons turn the month', (tester) async {
      await pump(tester, onChanged: (_) {});
      await tester.tap(find.byType(MorphDatePicker));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Next month'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('November 2026'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
    });

    testWidgets('Escape closes the overlay', (tester) async {
      await pump(tester, onChanged: (_) {});
      await tester.tap(find.byType(MorphDatePicker));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsNothing);
    });

    testWidgets('time mode opens the wheels', (tester) async {
      final picked = <DateTime>[];
      await pump(tester, mode: MorphDatePickerMode.time, onChanged: picked.add);
      expect(find.text('09:41'), findsOneWidget);
      await tester.tap(find.text('09:41'));
      await tester.pumpAndSettle();
      expect(find.byType(ListWheelScrollView), findsNWidgets(2));
      // The probe's drag on an iPhone 16 Pro (rec-vid-time): 64 points up
      // in 0.375 s turns UIKit's wheel by exactly two rows.
      await tester.timedDrag(
        find.byType(ListWheelScrollView).last,
        const Offset(0, -64),
        const Duration(milliseconds: 375),
      );
      await tester.pumpAndSettle();
      expect(picked.last.minute, 43);
    });

    testWidgets('formats twelve-hour times and both labels', (tester) async {
      await pump(
        tester,
        mode: MorphDatePickerMode.dateAndTime,
        use24: false,
        onChanged: (_) {},
      );
      expect(find.text('Oct 3, 2026'), findsOneWidget);
      expect(find.text('9:41 AM'), findsOneWidget);
    });

    testWidgets('a disabled picker does not open', (tester) async {
      await pump(tester);
      await tester.tap(find.byType(MorphDatePicker));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsNothing);
    });

    testWidgets('screen readers see a button that expands', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, onChanged: (_) {});
      expect(find.bySemanticsLabel('Date, Oct 3, 2026'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('dark colors and a large text scale', (tester) async {
      await pump(
        tester,
        onChanged: (_) {},
        theme: ThemeData(brightness: Brightness.dark),
        textScale: 2,
      );
      final label = tester.widget<Text>(find.text('Oct 3, 2026'));
      expect(label.style?.color, MorphDatePickerStyle.dark.labelColor);
      await tester.tap(find.byType(MorphDatePicker));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('MorphDatePicker on an iPhone 16 Pro', () {
    Future<void> pump(
      WidgetTester tester,
      MorphDatePickerMode mode, {
      DateTime? start,
    }) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var value = start ?? DateTime(2026, 10, 3, 7, 41);
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => Align(
              alignment: const Alignment(0, -0.3135),
              child: MorphDatePicker(
                value: value,
                mode: mode,
                use24HourFormat: true,
                today: DateTime(2026, 10, 3),
                onChanged: (DateTime v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('the calendar keeps 16 points from the side, title whole', (
      tester,
    ) async {
      await pump(
        tester,
        MorphDatePickerMode.date,
        start: DateTime(2026, 5, 3, 7, 41),
      );
      await tester.tap(find.text('May 3, 2026'));
      await tester.pumpAndSettle();
      final title = find.text('May 2026');
      expect(
        tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse,
      );
      // The screen recording: the platter's left edge at 16, the title's
      // ink at 37.
      expect(tester.getRect(title).left, closeTo(16 + 20.33, 0.5));
    });

    testWidgets('a chosen day that is not today sits on a label disc', (
      tester,
    ) async {
      await pump(tester, MorphDatePickerMode.date);
      await tester.tap(find.text('Oct 3, 2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      BoxDecoration? disc(String day) =>
          tester
                  .widget<Container>(
                    find
                        .ancestor(
                          of: find.text(day),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration?;
      expect(
        disc('15')?.color,
        MorphDatePickerStyle.light.selectedDayFillColor,
      );
      expect(disc('3')?.color, MorphDatePickerStyle.light.todayFillColor);
      final text = tester.widget<Text>(find.text('15'));
      expect(
        text.style?.color,
        MorphDatePickerStyle.light.selectedDayTextColor,
      );
    });

    testWidgets('the overlay opens 0.14 s after the lift', (tester) async {
      await pump(tester, MorphDatePickerMode.date);
      await tester.tap(find.text('Oct 3, 2026'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text('October 2026'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 0);
      await tester.pump(const Duration(milliseconds: 100));
      final later = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text('October 2026'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(later.opacity, greaterThan(0.1));
    });

    testWidgets('the other label turns the open overlay into its picker', (
      tester,
    ) async {
      await pump(tester, MorphDatePickerMode.dateAndTime);
      await tester.tap(find.text('Oct 3, 2026'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      await tester.tap(find.text('07:41').first, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.byType(ListWheelScrollView), findsNWidgets(2));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsNothing);
      expect(find.byType(ListWheelScrollView), findsNWidgets(2));
      final label = tester.widget<Text>(find.text('07:41').first);
      expect(label.style?.color, MorphDatePickerStyle.light.accentColor);
      final date = tester.widget<Text>(find.text('Oct 3, 2026'));
      expect(date.style?.color, MorphDatePickerStyle.light.labelColor);
      await tester.tapAt(const Offset(201, 800));
      await tester.pumpAndSettle();
      expect(find.byType(ListWheelScrollView), findsNothing);
    });
  });

  group('MorphDatePicker time wheels', () {
    testWidgets('rows sit on UIKit\'s cylinder', (tester) async {
      await tester.binding.setSurfaceSize(const Size(402, 874));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: const Alignment(0, -0.3135),
            child: MorphDatePicker(
              value: DateTime(2026, 10, 3, 7, 41),
              mode: MorphDatePickerMode.time,
              use24HourFormat: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byType(MorphDatePicker));
      await tester.pumpAndSettle();
      final center = tester.getRect(find.text('07').last);
      // UIKit's labels on an iPhone 16 Pro (rec-vid-time): neighbours 31.3
      // and 56.7 points from the selected row, 0.905 and 0.647 of its
      // height; the hour column 73.5 and the minute column 148.5 points
      // from the platter's leading edge (16 on this screen).
      for (final (text, dy, h) in [
        ('06', -31.3, 0.905),
        ('08', 31.3, 0.905),
        ('05', -56.9, 0.647),
        ('09', 56.6, 0.647),
      ]) {
        final r = tester.getRect(find.text(text).last);
        expect(r.center.dy - center.center.dy, closeTo(dy, 0.6), reason: text);
        expect(r.height / center.height, closeTo(h, 0.03), reason: text);
        expect(r.center.dx, closeTo(16 + 73.5, 0.5), reason: text);
      }
      expect(
        tester.getRect(find.text('41').last).center.dx,
        closeTo(16 + 148.5, 0.5),
      );
    });
  });

  group('MorphDatePickerMotion', () {
    test('opens from a fifth of its size and its 50 point box', () {
      final m = MorphDatePickerMotion();
      m.open(0);
      expect(m.scale(0), MorphDatePickerTuning.hiddenScale);
      expect(m.height(0, 332), 50);
      m.advance(2);
      expect(m.scale(2), closeTo(1, 1e-3));
      expect(m.height(2, 332), closeTo(332, 0.5));
      m.close(2);
      m.advance(4);
      expect(m.isClosed, isTrue);
    });
  });
}
