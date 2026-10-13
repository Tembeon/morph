import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/press.dart';

/// One step of a replayed press: a contact, a move, a lift or a loss.
sealed class _Step {
  const _Step(this.pointer);

  final int pointer;
}

class _Down extends _Step {
  const _Down(super.pointer, this.at, {this.buttons = kPrimaryButton});

  final Offset at;
  final int buttons;
}

class _Move extends _Step {
  const _Move(super.pointer, this.at);

  final Offset at;
}

class _Up extends _Step {
  const _Up(super.pointer, this.at);

  final Offset at;
}

class _Cancel extends _Step {
  const _Cancel(super.pointer, this.why);

  final MorphPressLoss why;
}

const _box = Size(100, 40);

/// Replays [steps] on a fresh tracker and returns what each one reported.
List<Object?> _replay(List<_Step> steps, {double slop = 70}) {
  final tracker = MorphPressTracker(slop: slop);
  return [
    for (final step in steps)
      switch (step) {
        _Down(:final pointer, :final at, :final buttons) => tracker.down(
          pointer,
          buttons,
          at,
          size: _box,
        ),
        _Move(:final pointer, :final at) => tracker.move(pointer, at),
        _Up(:final pointer, :final at) => tracker.up(pointer, at),
        _Cancel(:final pointer, :final why) => tracker.cancel(pointer, why),
      },
  ];
}

void main() {
  test('a press released on the control ends inside', () {
    expect(
      _replay(const [
        _Down(1, Offset(50, 20)),
        _Move(1, Offset(60, 25)),
        _Up(1, Offset(60, 25)),
      ]),
      [true, null, MorphPressEnd.inside],
    );
  });

  test('the extended bounds reach slop past every edge', () {
    expect(
      _replay(const [
        _Down(1, Offset(50, 20)),
        _Move(1, Offset(169, 20)),
        _Move(1, Offset(170, 20)),
        _Move(1, Offset(-70, 20)),
        _Move(1, Offset(-71, 20)),
        _Move(1, Offset(50, 109)),
        _Move(1, Offset(50, -71)),
        _Up(1, Offset(50, -71)),
      ]),
      [
        true,
        null,
        MorphPressEdge.exit,
        MorphPressEdge.enter,
        MorphPressEdge.exit,
        MorphPressEdge.enter,
        MorphPressEdge.exit,
        MorphPressEnd.outside,
      ],
    );
  });

  test('sliding back in re-enters and releases inside', () {
    expect(
      _replay(const [
        _Down(1, Offset(10, 10)),
        _Move(1, Offset(10, 200)),
        _Move(1, Offset(10, 90)),
        _Up(1, Offset(10, 90)),
      ]),
      [true, MorphPressEdge.exit, MorphPressEdge.enter, MorphPressEnd.inside],
    );
  });

  test('a release outside without a move still ends outside', () {
    expect(_replay(const [_Down(1, Offset(10, 10)), _Up(1, Offset(400, 10))]), [
      true,
      MorphPressEnd.outside,
    ]);
  });

  test('a zero slop tracks the exact box', () {
    expect(
      _replay(slop: 0, const [
        _Down(1, Offset(10, 10)),
        _Move(1, Offset(100, 10)),
        _Move(1, Offset(99, 10)),
        _Up(1, Offset(99, 40)),
      ]),
      [true, MorphPressEdge.exit, MorphPressEdge.enter, MorphPressEnd.outside],
    );
  });

  test('an infinite slop never leaves', () {
    expect(
      _replay(slop: double.infinity, const [
        _Down(1, Offset(10, 10)),
        _Move(1, Offset(1e6, -1e6)),
        _Up(1, Offset(-1e6, 1e6)),
      ]),
      [true, null, MorphPressEnd.inside],
    );
  });

  test('one pointer at a time; the others are ignored until it ends', () {
    expect(
      _replay(const [
        _Down(1, Offset(10, 10)),
        _Down(2, Offset(20, 10)),
        _Move(2, Offset(500, 10)),
        _Up(2, Offset(500, 10)),
        _Cancel(2, MorphPressLoss.platform),
        _Move(1, Offset(500, 10)),
        _Up(1, Offset(20, 10)),
        _Down(2, Offset(20, 10)),
        _Up(2, Offset(20, 10)),
      ]),
      [
        true,
        false,
        null,
        null,
        null,
        MorphPressEdge.exit,
        MorphPressEnd.inside,
        true,
        MorphPressEnd.inside,
      ],
    );
  });

  test('only the primary button alone starts a press', () {
    expect(
      _replay(const [
        _Down(1, Offset(10, 10), buttons: kSecondaryButton),
        _Down(2, Offset(10, 10), buttons: kPrimaryButton | kSecondaryButton),
        _Up(1, Offset(10, 10)),
        _Down(3, Offset(10, 10)),
      ]),
      [false, false, null, true],
    );
  });

  test('a cancel reports its reason and frees the tracker', () {
    final tracker = MorphPressTracker(slop: 70);
    expect(tracker.down(1, kPrimaryButton, Offset.zero, size: _box), isTrue);
    expect(tracker.inside, isTrue);
    expect(tracker.cancel(2, MorphPressLoss.scroll), isNull);
    expect(tracker.cancel(1, MorphPressLoss.scroll), MorphPressLoss.scroll);
    expect(tracker.loss, MorphPressLoss.scroll);
    expect(tracker.isTracking, isFalse);
    expect(tracker.inside, isFalse);
    expect(tracker.up(1, Offset.zero), isNull);
    expect(tracker.down(4, kPrimaryButton, Offset.zero, size: _box), isTrue);
    expect(tracker.loss, isNull, reason: 'a new press clears the old loss');
    expect(
      tracker.cancelActive(MorphPressLoss.disabled),
      MorphPressLoss.disabled,
    );
    expect(tracker.cancelActive(MorphPressLoss.disabled), isNull);
  });

  test('release forgets the press without a loss', () {
    final tracker = MorphPressTracker();
    tracker.down(1, kPrimaryButton, Offset.zero);
    tracker.release();
    expect(tracker.isTracking, isFalse);
    expect(tracker.loss, isNull);
    expect(tracker.owns(1), isFalse);
    expect(tracker.move(1, Offset.zero), isNull);
  });
}
