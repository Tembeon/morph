import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
      expect(title.left, closeTo(20 + 16, 1));
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
      await tester.drag(
        find.byType(ListWheelScrollView).last,
        const Offset(0, -32),
      );
      await tester.pumpAndSettle();
      expect(picked.last.minute, 42);
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
