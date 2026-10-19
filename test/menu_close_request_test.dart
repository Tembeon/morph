import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/menu_motion.dart';

const _button = Rect.fromLTWH(24, 80, 44, 44);
const _outside = Offset(350, 500);

MorphMenuMotion _motion({MorphMenuTuning tuning = MorphMenuTuning.standard}) =>
    MorphMenuMotion(
      button: _button,
      bounds: const Size(402, 874),
      itemCount: 3,
      tuning: tuning,
    );

/// Opens [motion] by a tap at 0 and feeds the release that requests the
/// close: [input] is outside, on a row, or one of them before the menu
/// appeared. Returns the time the close comes due.
double _request(MorphMenuMotion motion, String input) {
  if (input.startsWith('early')) {
    motion.pointerDown(0, _button.center);
    motion.pointerUp(0.01, _button.center);
    motion.pointerDown(0.02, _outside);
    motion.pointerUp(
      0.03,
      input == 'early row' ? const Offset(60, 110) : _outside,
    );
    return 0.01 + motion.tuning.tapOpenDelay + motion.tuning.earlyCloseDelay;
  }
  motion.open(0);
  motion.advance(1);
  final position = input == 'selection'
      ? motion.menuBlob.rrect.outerRect.center
      : _outside;
  motion.pointerDown(1.01, position);
  motion.pointerUp(1.02, position);
  return 1.02 + motion.tuning.dismissDelay;
}

({
  double progress,
  double menuKick,
  double buttonKick,
  double fusion,
  Rect blob,
})
_sample(MorphMenuMotion motion) => (
  progress: motion.progress,
  menuKick: motion.menuKick,
  buttonKick: motion.buttonKick,
  fusion: motion.fusionRadius,
  blob: motion.menuBlob.rect,
);

void _expectSame(MorphMenuMotion a, MorphMenuMotion b, String reason) {
  final x = _sample(a);
  final y = _sample(b);
  expect(x.progress, closeTo(y.progress, 1e-12), reason: reason);
  expect(x.menuKick, closeTo(y.menuKick, 1e-12), reason: reason);
  expect(x.buttonKick, closeTo(y.buttonKick, 1e-12), reason: reason);
  expect(x.fusion, closeTo(y.fusion, 1e-12), reason: reason);
  for (final (u, v) in [
    (x.blob.left, y.blob.left),
    (x.blob.top, y.blob.top),
    (x.blob.right, y.blob.right),
    (x.blob.bottom, y.blob.bottom),
  ]) {
    expect(u, closeTo(v, 1e-9), reason: reason);
  }
}

void main() {
  for (final input in ['outside', 'selection', 'early outside', 'early row']) {
    test('$input stops at its deadline before any closing channel changes, '
        'and a refusal keeps the menu open', () {
      final motion = _motion();
      final due = _request(motion, input);
      motion.drainEvents();
      expect(motion.advanceToRequest(due + 0.5), isFalse);
      expect(motion.time, closeTo(due, 1e-12));
      expect(motion.isOpen, isTrue);
      expect(motion.isClosing, isFalse);
      final events = motion.drainEvents();
      final request = events.last as MorphMenuCloseRequested;
      expect(request.time, closeTo(due, 1e-12));
      expect(
        [
          for (final e in events)
            if (e case MorphMenuActivated(:final index)) index,
        ],
        switch (input) {
          'selection' => [1],
          'early row' => [0],
          _ => isEmpty,
        },
      );

      expect(motion.advanceToRequest(3), isTrue);
      expect(motion.admitClose(request), isFalse);
      expect(motion.drainEvents(), isEmpty);
      expect(motion.isOpen, isTrue);
      expect(motion.progress, closeTo(1, 1e-3));
      expect(motion.menuKick, closeTo(0, 0.01));
      expect(motion.buttonKick, closeTo(0, 0.01));
      expect(motion.fusionRadius, 0);

      motion.pointerDown(3.01, _outside);
      motion.pointerUp(3.02, _outside);
      final retry = 3.02 + motion.tuning.dismissDelay;
      motion.drainEvents();
      expect(motion.advanceToRequest(4), isFalse);
      final again = motion.drainEvents().single as MorphMenuCloseRequested;
      expect(again.time, closeTo(retry, 1e-12));
      expect(motion.admitClose(again), isTrue);
      expect(motion.admitClose(again), isFalse);
      expect(motion.isClosing, isTrue);
      expect(motion.advanceToRequest(5), isTrue);
      expect(motion.isPresented, isFalse);
    });

    test('$input admitted where it stopped closes exactly as an unhosted '
        'motion closes on its own', () {
      final hosted = _motion();
      final alone = _motion();
      final due = _request(hosted, input);
      _request(alone, input);
      var stops = 0;
      for (var t = due - 0.05; t < due + 1.5; t += 1 / 60) {
        while (!hosted.advanceToRequest(t)) {
          final request = hosted.drainEvents().last as MorphMenuCloseRequested;
          expect(hosted.admitClose(request), isTrue);
          stops++;
        }
        alone.advance(t);
        expect(hosted.time, alone.time);
        _expectSame(hosted, alone, '$input at $t');
      }
      expect(stops, 1);
      expect([
        for (final e in alone.drainEvents())
          if (e is MorphMenuCloseRequested) e,
      ], isEmpty);
    });
  }

  test('a close approved later starts from the current state, never at the '
      'requested time', () {
    final motion = _motion();
    final due = _request(motion, 'outside');
    final waiting = _motion(tuning: const MorphMenuTuning(dismissDelay: 100));
    _request(waiting, 'outside');
    expect(motion.advanceToRequest(due + 0.2), isFalse);
    final request = motion.drainEvents().last as MorphMenuCloseRequested;
    var t = due;
    for (; t < due + 0.5; t += 1 / 60) {
      motion.advanceToRequest(t);
      waiting.advance(t);
    }
    expect(motion.isOpen, isTrue);
    expect(motion.admitClose(request), isFalse);
    final approved = motion.time;
    expect(approved, greaterThan(request.time));
    motion.close(approved);
    waiting.close(approved);
    expect(motion.time, approved);
    for (var s = approved; s < approved + 1.5; s += 1 / 60) {
      motion.advanceToRequest(s);
      waiting.advance(s);
      _expectSame(motion, waiting, 'approved at $approved, frame $s');
    }
    expect(motion.isPresented, isFalse);
  });

  test('explicit close is a command at its own time and requests nothing', () {
    final motion = _motion();
    motion.open(0);
    motion.advance(1);
    motion.close(1.1);
    expect(motion.time, 1.1);
    expect(motion.isClosing, isTrue);
    expect(motion.advanceToRequest(3), isTrue);
    expect([
      for (final e in motion.drainEvents())
        if (e is MorphMenuCloseRequested) e,
    ], isEmpty);
    expect(motion.isPresented, isFalse);
  });

  test('a command that goes on past a stop refuses its request', () {
    final motion = _motion();
    final due = _request(motion, 'outside');
    expect(motion.advanceToRequest(due + 0.1), isFalse);
    final request = motion.drainEvents().last as MorphMenuCloseRequested;
    motion.highlight(due + 0.05, 0);
    expect(motion.admitClose(request), isFalse);
    expect(motion.isOpen, isTrue);
    expect(motion.time, due + 0.05);
  });
}
