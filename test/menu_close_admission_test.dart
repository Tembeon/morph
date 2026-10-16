import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/motion.dart';
import 'package:morph/src/widgets/menu_motion.dart'
    show morphMenuSetCloseAdmission;

const _button = Rect.fromLTWH(24, 80, 44, 44);
const _outside = Offset(350, 500);

MorphMenuMotion _motion() => MorphMenuMotion(
  button: _button,
  bounds: const Size(402, 874),
  itemCount: 3,
);

void main() {
  for (final input in ['outside', 'selection', 'early outside', 'early row']) {
    test('$input requests admission before changing any closing channel', () {
      final motion = _motion();
      final requests = <double>[];
      final selected = <int>[];
      motion.onSelected = selected.add;
      morphMenuSetCloseAdmission(motion, (time) {
        expect(motion.isOpen, isTrue);
        expect(motion.isClosing, isFalse);
        requests.add(time);
        return false;
      });
      final early = input.startsWith('early');
      if (early) {
        motion.pointerDown(0, _button.center);
        motion.pointerUp(0.01, _button.center);
        motion.pointerDown(0.02, _outside);
        motion.pointerUp(
          0.03,
          input == 'early row' ? const Offset(60, 110) : _outside,
        );
      } else {
        motion.open(0);
        motion.advance(1);
        final position = input == 'selection'
            ? motion.menuBlob.rrect.outerRect.center
            : _outside;
        motion.pointerDown(1.01, position);
        motion.pointerUp(1.02, position);
      }
      final due = early
          ? 0.01 + motion.tuning.tapOpenDelay + motion.tuning.earlyCloseDelay
          : 1.02 + motion.tuning.dismissDelay;
      motion.advance(due);
      expect(requests, hasLength(1));
      expect(requests.single, closeTo(due, 1e-12));
      expect(selected, switch (input) {
        'selection' => [1],
        'early row' => [0],
        _ => isEmpty,
      });
      expect(motion.isClosing, isFalse);
      motion.advance(3);
      expect(motion.isOpen, isTrue);
      expect(motion.progress, closeTo(1, 1e-3));
      expect(motion.menuKick, closeTo(0, 0.01));
      expect(motion.buttonKick, closeTo(0, 0.01));
      expect(motion.fusionRadius, 0);

      morphMenuSetCloseAdmission(motion, (time) {
        expect(motion.isOpen, isTrue);
        requests.add(time);
        return true;
      });
      motion.pointerDown(3.01, _outside);
      motion.pointerUp(3.02, _outside);
      final retry = 3.02 + motion.tuning.dismissDelay;
      motion.advance(retry);
      expect(requests.last, closeTo(retry, 1e-12));
      expect(motion.isClosing, isTrue);
      motion.advance(5);
      expect(motion.isPresented, isFalse);
    });
  }

  test('explicit close bypasses admission and preserves its command time', () {
    final motion = _motion();
    morphMenuSetCloseAdmission(
      motion,
      (_) => fail('Explicit close is a command'),
    );
    motion.open(0);
    motion.advance(1);
    motion.close(1.1);
    expect(motion.time, 1.1);
    expect(motion.isClosing, isTrue);
    motion.advance(3);
    expect(motion.isPresented, isFalse);
  });

  test('removing admission restores autonomous dismissal', () {
    final motion = _motion();
    morphMenuSetCloseAdmission(motion, (_) => false);
    morphMenuSetCloseAdmission(motion, null);
    motion.open(0);
    motion.advance(1);
    motion.pointerDown(1.01, _outside);
    motion.pointerUp(1.02, _outside);
    motion.advance(1.2);
    expect(motion.isClosing, isTrue);
  });
}

// ignore_for_file: invalid_use_of_internal_member
