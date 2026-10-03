import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/widgets/search_motion.dart';
import 'package:morph/src/widgets/spring_state.dart';
import 'package:morph/widgets.dart';

const _dir = 'test/fixtures/ios27/search';

/// The probe screen: the iOS 27 simulator's iPhone 18 Pro Max, 440 x 956
/// points, keyboard 347 points tall.
const double _w = 440;
const double _h = 956;
const double _keyboard = 347;
const double _frame = 1 / 60;

List<Map<String, Object?>> _rows(String file, {String dir = _dir}) => [
  for (final line in File('$dir/$file').readAsLinesSync())
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

double _d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();

double _script(List<Map<String, Object?>> rows, String action) =>
    _d(rows.firstWhere((r) => r['k'] == 'evt' && r['a'] == action), 't');

double _rms(List<double> e) =>
    math.sqrt(e.fold(0.0, (a, b) => a + b * b) / math.max(1, e.length));

Rect _rect(Map<String, Object?> r) => Rect.fromCenter(
  center: Offset(_d(r, 'x'), _d(r, 'y')),
  width: _d(r, 'w'),
  height: _d(r, 'h'),
);

/// Fits the call time of a transition: UIKit starts it some time after the
/// probe's call (the keyboard's bring-up on a focus). Returns the call time
/// within [window] after [call] whose transition fits [errors] best.
(double, double) _fit(
  double call,
  double window,
  List<double> Function(double) errors,
) {
  var best = call;
  var bestErr = double.infinity;
  for (var lag = 0.0; lag <= window; lag += 0.001) {
    final e = _rms(errors(call + lag));
    if (e < bestErr) {
      bestErr = e;
      best = call + lag;
    }
  }
  return (best, bestErr);
}

void main() {
  final rest = morphSearchBarLayout(
    width: _w,
    bottom: _h - MorphSearchTuning.restInset,
    focused: false,
  );
  final focused = morphSearchBarLayout(
    width: _w,
    bottom: _h - _keyboard - MorphSearchTuning.keyboardGap,
    focused: true,
  );

  group('search toolbar replays the simulator', () {
    test('rest and focused geometry', () {
      expect(rest.field, const Rect.fromLTWH(28, 880, 384, 48));
      expect(focused.field, const Rect.fromLTWH(8, 551, 364, 48));
      expect(focused.close, const Rect.fromLTWH(384, 551, 48, 48));
      final items = morphSearchBarLayout(
        width: _w,
        bottom: _h - 28,
        focused: false,
        leading: const [48],
        trailing: const [48],
      );
      expect(items.leading.single, const Rect.fromLTWH(28, 880, 48, 48));
      expect(items.field, const Rect.fromLTWH(88, 880, 264, 48));
      expect(items.trailing.single, const Rect.fromLTWH(364, 880, 48, 48));
    });

    for (final (source, dir, frame, size, keyboard) in [
      ('the simulator', _dir, _frame, const Size(_w, _h), _keyboard),
      (
        'an iPhone 16 Pro',
        'test/fixtures/ios27-device/search',
        1 / 120,
        const Size(402, 874),
        328.0,
      ),
    ]) {
      test('focus and cancel on $source: field, close button, one spring', () {
        final rest = morphSearchBarLayout(
          width: size.width,
          bottom: size.height - MorphSearchTuning.restInset,
          focused: false,
        );
        final focused = morphSearchBarLayout(
          width: size.width,
          bottom: size.height - keyboard - MorphSearchTuning.keyboardGap,
          focused: true,
        );
        final restWidth = rest.field.width;
        final rows = _rows('search-toolbar.jsonl', dir: dir);
        final focusCall = _script(rows, 'focus');
        final cancelCall = _script(rows, 'cancel');
        // UIKit moves the close button a few frames behind the field (two
        // on the simulator; its opacity and scale are on time; a layout
        // artifact morph does not reproduce), so its position is compared
        // at the best lag of up to four frames.
        final glass = [
          for (final r in rows)
            if (r['k'] == 'V' &&
                (r['cls']! as String).endsWith('GlassInteractionView'))
              r,
        ];
        final field = [
          for (final r in glass)
            if (_d(r, 'bw') > 200) r,
        ];
        final close = [
          for (final r in glass)
            if (_d(r, 'bw') == 48 && _d(r, 't') > focusCall) r,
        ];
        List<double> fieldErrors(
          MorphSearchMotion motion,
          double from,
          double to,
        ) => [
          for (final r in field)
            if (_d(r, 't') > from && _d(r, 't') < to)
              ...() {
                final t = _d(r, 't') + frame;
                final p = motion.progress(t);
                final model = Rect.lerp(rest.field, focused.field, p)!;
                final seen = _rect(r);
                return [
                  model.left - seen.left,
                  model.width - seen.width,
                  model.top - seen.top,
                ];
              }(),
        ];
        MorphSearchMotion focusAt(double call) {
          final motion = MorphSearchMotion(size: Size(restWidth, 48));
          motion.focus(call);
          motion.advance(call + 0.5);
          return motion;
        }

        final (focusFit, focusRms) = _fit(
          focusCall,
          0.6,
          (call) => fieldErrors(focusAt(call), focusCall, cancelCall),
        );
        // The field travels over 300 points; 2 points rms is 0.6 percent,
        // the gap between the read spring and the free fits.
        expect(focusRms, lessThan(2));
        final motion = focusAt(focusFit);
        List<double> closeErrors(int lagFrames) => [
          for (final r in close)
            if (_d(r, 't') < cancelCall && _d(r, 'ea') > 0)
              ...() {
                final t = _d(r, 't') + frame;
                final p = motion.progress(t);
                final lagged = motion.progress(t - lagFrames * frame);
                final model = Rect.lerp(rest.close, focused.close, lagged)!;
                return [
                  (MorphSearchMotion.appearScaleFor(p) - _d(r, 'w') / 48) * 48,
                  (p.clamp(0.0, 1.0) - _d(r, 'ea')) * 48,
                  model.center.dx - _d(r, 'x'),
                  model.center.dy - _d(r, 'y'),
                ];
              }(),
        ];
        final closeRms = [
          for (var lag = 0; lag <= 4; lag++) _rms(closeErrors(lag)),
        ].reduce(math.min);
        expect(closeRms, lessThan(2));
        List<double> cancelErrors(double call) {
          final m = MorphSearchMotion(size: Size(restWidth, 48));
          m.snap(0, focused: true);
          m.unfocus(call);
          m.advance(call + 0.5);
          return fieldErrors(m, cancelCall, double.infinity);
        }

        final (cancelFit, cancelRms) = _fit(
          cancelCall - 0.08,
          0.2,
          cancelErrors,
        );
        expect(cancelRms, lessThan(2));
        expect(cancelFit - cancelCall, closeTo(0, 0.04));
      });
    }

    test('the other toolbar items leave where they stand and come back', () {
      final rows = _rows('search-toolbar-items.jsonl');
      final focusCall = _script(rows, 'focus');
      final cancelCall = _script(rows, 'cancel');
      final items = morphSearchBarLayout(
        width: _w,
        bottom: _h - 28,
        focused: false,
        leading: const [48],
        trailing: const [48],
      );
      final virtual = morphSearchBarLayout(
        width: _w,
        bottom: _h - MorphSearchTuning.keyboardGap,
        focused: true,
        leading: const [48],
        trailing: const [48],
      );
      final glass = [
        for (final r in rows)
          if (r['k'] == 'V' &&
              (r['cls']! as String).endsWith('GlassInteractionView') &&
              _d(r, 'bw') == 48)
            r,
      ];
      final fieldRows = [
        for (final r in rows)
          if (r['k'] == 'V' &&
              (r['cls']! as String).endsWith('GlassInteractionView') &&
              _d(r, 'bw') > 200)
            r,
      ];
      final itemsFocused = morphSearchBarLayout(
        width: _w,
        bottom: _h - _keyboard - MorphSearchTuning.keyboardGap,
        focused: true,
        leading: const [48],
        trailing: const [48],
      );
      List<double> fieldErrors(double call) {
        final m = MorphSearchMotion(size: const Size(264, 48));
        m.focus(call);
        m.advance(call + 0.5);
        return [
          for (final r in fieldRows)
            if (_d(r, 't') > focusCall && _d(r, 't') < cancelCall)
              Rect.lerp(
                    items.field,
                    itemsFocused.field,
                    m.progress(_d(r, 't') + _frame),
                  )!.left -
                  _rect(r).left,
        ];
      }

      final (focusFit, fieldRms) = _fit(focusCall, 0.6, fieldErrors);
      expect(fieldRms, lessThan(1.5));
      final leaving = MorphSearchMotion(size: const Size(264, 48));
      leaving.focus(focusFit);
      leaving.advance(focusFit + 0.5);
      final firstSeen = <int, double>{};
      for (final r in glass) {
        if (_d(r, 't') > focusCall) {
          firstSeen.putIfAbsent(r['id']! as int, () => _d(r, 'ea'));
        }
      }
      final out = <double>[];
      for (final r in glass) {
        final t = _d(r, 't') + _frame;
        if (_d(r, 't') <= focusCall || _d(r, 't') >= cancelCall) continue;
        if ((firstSeen[r['id']! as int] ?? 0) < 0.5) continue;
        final seen = _rect(r);
        final isLead = seen.center.dx < _w / 2;
        if (seen.center.dy < 700) continue;
        final p = leaving.progress(t);
        final home = isLead ? items.leading.single : items.trailing.single;
        out.add(home.center.dx - seen.center.dx);
        out.add(home.center.dy - seen.center.dy);
        out.add(
          (MorphSearchMotion.appearScaleFor(1 - p) - seen.width / 48) * 48,
        );
        out.add((1 - p).clamp(0.0, 1.0) * 48 - _d(r, 'ea') * 48);
      }
      expect(_rms(out), lessThan(1.5));
      List<double> back(double call) {
        final m = MorphSearchMotion(size: const Size(264, 48));
        m.snap(0, focused: true);
        m.unfocus(call);
        m.advance(call + 0.5);
        return [
          for (final r in glass)
            if (_d(r, 't') > cancelCall && _rect(r).center.dy > 700)
              ...() {
                final seen = _rect(r);
                final isLead = seen.center.dx < _w / 2;
                final p = m.progress(_d(r, 't') + _frame);
                final from = isLead
                    ? virtual.leading.single
                    : virtual.trailing.single;
                final to = isLead
                    ? items.leading.single
                    : items.trailing.single;
                final model = Rect.lerp(from, to, 1 - p)!;
                return [
                  model.center.dx - seen.center.dx,
                  model.center.dy - seen.center.dy,
                  (1 - p).clamp(0.0, 1.0) * 48 - _d(r, 'ea') * 48,
                ];
              }(),
        ];
      }

      final (_, backRms) = _fit(cancelCall - 0.08, 0.2, back);
      expect(backRms, lessThan(1.5));
    });

    test('a held touch lifts the field like a glass button', () {
      final rows = _rows('search-hold.jsonl');
      final touches = [
        for (final r in rows)
          if (r['k'] == 'touch') r,
      ];
      final down = _d(touches.first, 't');
      final up = _d(touches.last, 't');
      final field = [
        for (final r in rows)
          if (r['k'] == 'V' &&
              (r['cls']! as String).endsWith('GlassInteractionView') &&
              _d(r, 'bw') == 384 &&
              _d(r, 't') < up)
            r,
      ];
      List<double> errors(double at) {
        final motion = MorphSearchMotion(size: const Size(384, 48));
        motion.pointerDown(at);
        final out = <double>[];
        for (final r in field) {
          final t = _d(r, 't') + _frame;
          motion.advance(t);
          out.add((motion.pressScale(t) - _d(r, 'w') / 384) * 384);
        }
        return out;
      }

      final (_, rms) = _fit(down - 0.02, 0.05, errors);
      expect(rms, lessThan(0.35));
    });
  });

  group('search toolbar touches replay an iPhone 16 Pro', () {
    const dir = 'test/fixtures/ios27-device/search';
    const size = Size(402, 874);
    const keyboard = 328.0;
    final rest = morphSearchBarLayout(
      width: size.width,
      bottom: size.height - MorphSearchTuning.restInset,
      focused: false,
    );
    final focused = morphSearchBarLayout(
      width: size.width,
      bottom: size.height - keyboard - MorphSearchTuning.keyboardGap,
      focused: true,
    );

    test('a tap focuses once the keyboard rises; the close button ends', () {
      final rows = _rows('search-tap.jsonl', dir: dir);
      final ups = [
        for (final r in rows)
          if (r['k'] == 'touch' && r['phase'] == 3) _d(r, 't'),
      ];
      final keyboardRise = _d(
        rows.firstWhere((r) => r['cls'] == 'keyboard' && _d(r, 't') > ups[0]),
        't',
      );
      final field = [
        for (final r in rows)
          if (r['cls'] == 'GlassInteractionView' && _d(r, 'bw') > 200) r,
      ];
      List<double> errors(MorphSearchMotion motion, double from, double to) => [
        for (final r in field)
          if (_d(r, 't') > from && _d(r, 't') < to)
            ...() {
              final p = motion.progress(_d(r, 't'));
              final model = Rect.lerp(rest.field, focused.field, p)!;
              return [model.top - _d(r, 'y') + 24];
            }(),
      ];
      MorphSearchMotion at(double start, {required bool focus}) {
        final motion = MorphSearchMotion(size: rest.field.size);
        if (!focus) motion.snap(0, focused: true);
        if (focus) {
          motion.focus(start, delay: 0);
        } else {
          motion.unfocus(start - MorphSearchTuning.transitionDelay);
        }
        motion.advance(start + 0.6);
        return motion;
      }

      final (focusStart, focusRms) = _fit(
        ups[0],
        0.4,
        (start) => errors(at(start, focus: true), ups[0], ups[1]),
      );
      expect(focusRms, lessThan(2));
      expect(
        focusStart - keyboardRise,
        closeTo(MorphSearchTuning.keyboardLag, 0.012),
      );
      final (closeStart, closeRms) = _fit(
        ups[1],
        0.2,
        (start) => errors(at(start, focus: false), ups[1], double.infinity),
      );
      expect(closeRms, lessThan(2));
      expect(
        closeStart - ups[1],
        closeTo(MorphSearchTuning.transitionDelay, 0.02),
      );
    });

    test('a held touch lifts the field like a glass button', () {
      final rows = _rows('search-hold.jsonl', dir: dir);
      final touches = [
        for (final r in rows)
          if (r['k'] == 'touch') r,
      ];
      final down = _d(touches.first, 't');
      final up = _d(touches.last, 't');
      final width = rest.field.width;
      final field = [
        for (final r in rows)
          if (r['cls'] == 'GlassInteractionView' &&
              _d(r, 'bw') == width &&
              _d(r, 't') < up)
            r,
      ];
      List<double> errors(double at) {
        final motion = MorphSearchMotion(size: Size(width, 48));
        motion.pointerDown(at);
        final out = <double>[];
        for (final r in field) {
          final t = _d(r, 't');
          motion.advance(t);
          out.add((motion.pressScale(t) - _d(r, 'w') / width) * width);
        }
        return out;
      }

      // The device rows are compared as stamped: the lift shows 0.034 s
      // after the contact, MorphSearchTuning.pressDelay less the one 60 Hz
      // frame the simulator rows are shifted by.
      final (at, rms) = _fit(down - 0.05, 0.1, errors);
      expect(rms, lessThan(0.4));
      expect(at - down, closeTo(-1 / 60, 0.01));
    });
  });

  test('a tab bar search takes the focus mid-morph and falls straight back '
      '(iPhone 16 Pro, screen-recording session)', () {
    final rows = _rows(
      'vid-tab.jsonl',
      dir: 'test/fixtures/ios27-device/search',
    );
    final ups = [
      for (final r in rows)
        if (r['k'] == 'touch' && r['phase'] == 3) _d(r, 't'),
    ];
    final field = [
      for (final r in rows)
        if (r['cls'] == 'UISearchBarTextField') r,
    ];
    // The field reads its focused place 0.159 s after the lift of the tap
    // on the search circle, long before the morph settles.
    final present = _d(
      rows.firstWhere((r) => r['e'] == 'willPresentSearch'),
      't',
    );
    expect(present - ups[0], lessThan(MorphSearchTuning.tabActivationDelay));
    // The close tap: the field falls from above the keyboard straight to
    // its place above the tab circle.
    final close = ups[1];
    const restY = 822.0;
    final focusedY = _d(field.lastWhere((r) => _d(r, 't') < close), 'y');
    var last = focusedY;
    for (final r in field) {
      final t = _d(r, 't');
      if (t <= close || t > close + 0.6) continue;
      expect(_d(r, 'y'), greaterThanOrEqualTo(last - 0.5));
      expect(_d(r, 'y'), lessThanOrEqualTo(restY + 0.5));
      last = _d(r, 'y');
    }
    final (fall, rms) = _fit(close, 0.12, (double start) {
      final motion = MorphSearchMotion(
        spring: MorphSearchTuning.tabFocusSpring,
      );
      motion.snap(0, focused: true);
      motion.unfocus(start, delay: 0);
      return [
        for (final r in field)
          if (_d(r, 't') > close && _d(r, 't') < close + 0.6)
            ...() {
              motion.advance(_d(r, 't'));
              final p = motion.progress(_d(r, 't'));
              return [restY + (focusedY - restY) * p - _d(r, 'y')];
            }(),
      ];
    });
    expect(rms, lessThan(1));
    // 0.064 s here, 0.038 s in tab-search-focus: tabUnfocusDelay is the
    // middle of the two.
    expect(fall - close, closeTo(MorphSearchTuning.tabUnfocusDelay, 0.016));
  });

  test('a tab bar search rises once the keyboard does (iPhone 16 Pro)', () {
    final rows = _rows(
      'tab-search-focus.jsonl',
      dir: 'test/fixtures/ios27-device/search',
    );
    final ups = [
      for (final r in rows)
        if (r['k'] == 'touch' && r['phase'] == 3) _d(r, 't'),
    ];
    final keyboardRise = _d(
      rows.firstWhere((r) => r['cls'] == 'keyboard' && _d(r, 't') > ups[0]),
      't',
    );
    final field = [
      for (final r in rows)
        if (r['cls'] == 'field') r,
    ];
    const restY = 822.0;
    final focusedY = _d(field.lastWhere((r) => _d(r, 't') < ups[1]), 'y');
    List<double> errors(double start, {required bool focus}) {
      final motion = MorphSearchMotion(
        spring: MorphSearchTuning.tabFocusSpring,
      );
      if (focus) {
        motion.focus(start, delay: 0);
      } else {
        motion.snap(0, focused: true);
        motion.unfocus(start, delay: 0);
      }
      final from = focus ? ups[0] : ups[1];
      final to = focus ? ups[1] : ups[1] + 0.6;
      return [
        for (final r in field)
          if (_d(r, 't') > from && _d(r, 't') < to)
            ...() {
              motion.advance(_d(r, 't'));
              final p = motion.progress(_d(r, 't'));
              return [restY + (focusedY - restY) * p - _d(r, 'y')];
            }(),
      ];
    }

    final (rise, riseRms) = _fit(
      keyboardRise,
      0.2,
      (start) => errors(start, focus: true),
    );
    expect(riseRms, lessThan(1.5));
    expect(
      rise - keyboardRise,
      closeTo(MorphSearchTuning.tabKeyboardLag, 0.015),
    );
    final (fall, fallRms) = _fit(
      ups[1],
      0.15,
      (start) => errors(start, focus: false),
    );
    expect(fallRms, lessThan(1.5));
    expect(fall - ups[1], closeTo(MorphSearchTuning.tabUnfocusDelay, 0.015));
  });

  group('MorphSearchMotion', () {
    test('the transition starts after the measured delay', () {
      final motion = MorphSearchMotion();
      motion.focus(0);
      motion.advance(MorphSearchTuning.transitionDelay - 0.001);
      expect(motion.progress(motion.time), 0);
      motion.advance(1);
      expect(motion.progress(1), closeTo(1, 1e-3));
      expect(motion.isSettled, isTrue);
    });

    test('a reversal mid-way keeps the velocity', () {
      final motion = MorphSearchMotion();
      motion.focus(0);
      motion.advance(0.15);
      final p = motion.progress(0.15);
      motion.unfocus(0.15);
      motion.advance(0.15 + MorphSearchTuning.transitionDelay);
      expect(
        motion.progress(0.15 + MorphSearchTuning.transitionDelay),
        greaterThan(p),
      );
      motion.advance(2);
      expect(motion.progress(2), closeTo(0, 1e-3));
    });

    test('a quick tap barely lifts; reduced motion never does', () {
      final motion = MorphSearchMotion(size: const Size(384, 48));
      motion.pointerDown(0);
      motion.advance(0.04);
      expect(motion.pressScale(0.04), 1);
      motion.pointerUp(0.04);
      motion.advance(1);
      expect(motion.pressScale(1), closeTo(1, 1e-4));
      final calm = MorphSearchMotion(size: const Size(384, 48));
      calm.reducedMotion = true;
      calm.pointerDown(0);
      calm.advance(0.5);
      expect(calm.pressScale(0.5), 1);
    });
  });

  group('MorphSearchField', () {
    Future<void> pump(
      WidgetTester tester,
      Widget child, {
      ThemeData? theme,
      TextDirection direction = TextDirection.ltr,
      double textScale = 1,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: Center(child: SizedBox(width: 346, child: child)),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('types, hides the placeholder, clears', (tester) async {
      final changes = <String>[];
      await pump(tester, MorphSearchField(onChanged: changes.add));
      expect(find.text('Search'), findsOneWidget);
      await tester.tap(find.byType(MorphSearchField));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'Item 1');
      await tester.pump();
      expect(find.text('Search'), findsNothing);
      expect(changes.last, 'Item 1');
      await tester.tap(find.bySemanticsLabel('Clear text'));
      await tester.pump();
      expect(changes.last, '');
      expect(find.text('Search'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('is 48 tall and lifts under a held touch', (tester) async {
      await pump(tester, const MorphSearchField());
      expect(tester.getSize(find.byType(MorphSearchField)).height, 48);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MorphSearchField)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final lifted = tester.getRect(find.byType(CustomPaint).first);
      expect(lifted.width, greaterThan(346));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a disabled field takes no focus', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pump(tester, MorphSearchField(enabled: false, focusNode: focus));
      await tester.tap(find.byType(MorphSearchField));
      await tester.pump();
      expect(focus.hasFocus, isFalse);
    });

    testWidgets('mirrors in right-to-left, dark, large text', (tester) async {
      await pump(
        tester,
        const MorphSearchField(),
        theme: ThemeData(brightness: Brightness.dark),
        direction: TextDirection.rtl,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      final field = tester.getRect(find.byType(MorphSearchField));
      final text = tester.getRect(find.text('Search'));
      expect(text.right, closeTo(field.right - 40.67, 1));
      final style = tester.widget<Text>(find.text('Search')).style!;
      expect(style.color, MorphSearchFieldStyle.dark.restingPlaceholderColor);
    });

    testWidgets('screen readers see a labelled text field', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, const MorphSearchField());
      expect(find.bySemanticsLabel('Search'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('MorphSearchToolbar', () {
    Future<void> pump(
      WidgetTester tester, {
      ValueChanged<bool>? onActive,
      List<MorphBarButton> leading = const [],
    }) async {
      await tester.binding.setSurfaceSize(const Size(_w, _h));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: MorphSearchToolbar(
                    leading: leading,
                    onActiveChanged: onActive,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('focus widens the field, the close button ends the search', (
      tester,
    ) async {
      final active = <bool>[];
      var filtered = 0;
      await pump(
        tester,
        onActive: active.add,
        leading: [
          MorphBarButton(
            id: 'filter',
            icon: const Icon(Icons.filter_list),
            semanticLabel: 'Filter',
            onPressed: () => filtered++,
          ),
        ],
      );
      final field = find.byType(MorphSearchField);
      expect(tester.getRect(field), const Rect.fromLTWH(88, 880, 324, 48));
      await tester.tap(find.bySemanticsLabel('Filter'));
      await tester.pumpAndSettle();
      expect(filtered, 1);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(active, [true]);
      expect(
        tester.getRect(field),
        rectMoreOrLessEquals(
          const Rect.fromLTWH(8, _h - 10 - 48, _w - 8 - 8 - 48 - 12, 48),
          epsilon: 0.05,
        ),
      );
      await tester.enterText(find.byType(EditableText), 'abc');
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(active, [true, false]);
      expect(
        tester.getRect(field),
        rectMoreOrLessEquals(
          const Rect.fromLTWH(88, 880, 324, 48),
          epsilon: 0.05,
        ),
      );
      expect(find.text('abc'), findsNothing);
      expect(find.bySemanticsLabel('Close'), findsNothing);
    });

    testWidgets('a held touch focuses the field when it lifts', (tester) async {
      final active = <bool>[];
      await pump(tester, onActive: active.add);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MorphSearchField)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(active, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(active, [true]);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('closing falls straight to rest while the keyboard drops', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(_w, _h));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final keyboard = ValueNotifier<double>(0);
      addTearDown(keyboard.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<double>(
            valueListenable: keyboard,
            builder: (BuildContext context, double inset, Widget? _) =>
                MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
                  child: const Scaffold(
                    resizeToAvoidBottomInset: false,
                    body: Stack(
                      children: [Positioned.fill(child: MorphSearchToolbar())],
                    ),
                  ),
                ),
          ),
        ),
      );
      final field = find.byType(MorphSearchField);
      await tester.tap(field);
      await tester.pump();
      keyboard.value = 336;
      await tester.pumpAndSettle();
      expect(tester.getRect(field).bottom, closeTo(_h - 336 - 10, 0.2));
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pump();
      keyboard.value = 0;
      var last = tester.getRect(field).bottom;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 1000 ~/ 60));
        final bottom = tester.getRect(field).bottom;
        expect(bottom, lessThanOrEqualTo(_h - 28 + 1));
        expect(bottom, greaterThanOrEqualTo(last - 1));
        last = bottom;
      }
      await tester.pumpAndSettle();
      expect(tester.getRect(field).bottom, closeTo(_h - 28, 0.2));
    });

    testWidgets('Escape ends the search', (tester) async {
      final active = <bool>[];
      await pump(tester, onActive: active.add);
      await tester.tap(find.byType(MorphSearchField));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(active, [true, false]);
    });
  });
  group('tab bar search replays the simulator', () {
    test('rest, searching and focused geometry', () {
      final g = morphSearchTabLayout(
        size: const Size(_w, _h),
        barWidth: 188,
        keyboard: _keyboard,
      );
      expect(g.bar, const Rect.fromLTWH(21, 873, 188, 62));
      expect(g.search, const Rect.fromLTWH(357, 873, 62, 62));
      expect(g.tab, const Rect.fromLTWH(28, 880, 48, 48));
      expect(g.field, const Rect.fromLTWH(88, 880, 324, 48));
      expect(g.focusedField, const Rect.fromLTWH(8, 553, 368, 48));
      expect(g.close, const Rect.fromLTWH(384, 553, 48, 48));
    });

    test('the bar and the search circle trade places on the tab spring', () {
      final data =
          (jsonDecode(File('$_dir/tab-search-video.json').readAsStringSync())
                  as Map)
              .cast<String, Object?>();
      final rows = (data['rows']! as List).cast<Map<String, Object?>>();
      final g = morphSearchTabLayout(size: const Size(_w, _h), barWidth: 188);
      // The video's dark-pixel runs on row 924 cross each capsule where
      // its rounded end meets the row; a capsule of height h centered at
      // cy is that far inside its box: r - sqrt(r^2 - (924 - cy)^2).
      double inset(Rect r) {
        final radius = r.height / 2;
        final dy = (924 - r.center.dy).abs();
        return radius - math.sqrt(math.max(0, radius * radius - dy * dy));
      }

      List<double> errors(double start) {
        final spring = MorphSpringState(MorphSearchTuning.tabSpring, 0);
        spring.retarget(start, 1);
        final out = <double>[];
        for (final row in rows) {
          final t = _d(row, 't');
          final runs = [
            for (final run in (row['runs']! as List).cast<List<Object?>>())
              if ((run[1]! as num) - (run[0]! as num) <= 3)
                (run[0]! as num).toDouble(),
          ];
          if (runs.length < 4 || t < start - 0.02) continue;
          final q = spring.value(t);
          final bar = Rect.lerp(g.bar, g.tab, q)!;
          final search = Rect.lerp(g.search, g.field, q)!;
          double nearest(double x) =>
              runs.reduce((a, b) => (a - x).abs() < (b - x).abs() ? a : b);
          final barEdge = bar.right - inset(bar);
          final searchEdge = search.left + inset(search);
          final a = barEdge - nearest(barEdge);
          final b = searchEdge - nearest(searchEdge);
          // One frame of the video catches the glass mid-redraw without
          // the tab circle's edge; frames that far off are skipped.
          if (a.abs() > 12 || b.abs() > 12) continue;
          out.add(a);
          out.add(b);
        }
        return out;
      }

      final firstT = _d(rows.first, 't');
      final (_, rms) = _fit(firstT, 0.4, errors);
      expect(rms, lessThan(3));
    });
  });

  group('MorphSearchTabBar', () {
    testWidgets('the search circle starts a search, the tab circle ends it', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(_w, _h));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var searching = false;
      final asked = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => Stack(
              children: [
                Positioned.fill(
                  child: MorphSearchTabBar(
                    items: const [
                      MorphTabItem(icon: Icons.home, label: 'Home'),
                      MorphTabItem(icon: Icons.book, label: 'Library'),
                    ],
                    selected: 0,
                    onChanged: (_) {},
                    searching: searching,
                    onSearchingChanged: (bool v) {
                      asked.add(v);
                      setState(() => searching = v);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MorphTabBar), findsOneWidget);
      await tester.tapAt(const Offset(388, 904));
      await tester.pumpAndSettle();
      expect(asked, [true]);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'MorphSearchTabBar',
      );
      expect(find.byType(MorphTabBar), findsNothing);
      expect(find.byType(MorphSearchField), findsOneWidget);
      expect(
        tester.getRect(find.byType(MorphSearchField)),
        rectMoreOrLessEquals(
          const Rect.fromLTWH(8, _h - 8 - 48, 368, 48),
          epsilon: 0.05,
        ),
      );
      await tester.tapAt(const Offset(_w - 8 - 24, _h - 8 - 24));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(MorphSearchField)),
        rectMoreOrLessEquals(
          const Rect.fromLTWH(88, 880, 324, 48),
          epsilon: 0.05,
        ),
      );
      await tester.tapAt(const Offset(52, 904));
      await tester.pumpAndSettle();
      expect(asked, [true, false]);
      expect(find.byType(MorphTabBar), findsOneWidget);
    });

    testWidgets('an activating search tab takes the focus mid-morph', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(_w, _h));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var searching = false;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => Stack(
              children: [
                Positioned.fill(
                  child: MorphSearchTabBar(
                    items: const [
                      MorphTabItem(icon: Icons.home, label: 'Home'),
                      MorphTabItem(icon: Icons.book, label: 'Library'),
                    ],
                    selected: 0,
                    onChanged: (_) {},
                    focusNode: focus,
                    searching: searching,
                    onSearchingChanged: (bool v) =>
                        setState(() => searching = v),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(388, 904));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(focus.hasFocus, isFalse);
      await tester.pump(const Duration(milliseconds: 40));
      expect(focus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(find.bySemanticsLabel('Search'), findsWidgets);
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
    });
  });
}
