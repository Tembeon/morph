import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'support/glass_button_replay.dart';
import 'support/onset.dart';
import 'support/trace.dart';

/// Glass button, switch and segmented control inside a UIScrollView with
/// the default delaysContentTouches (iPhone 16 Pro, lab scenario
/// `scroll-delay`); `lift` samples the glass button's scale.
const _file = 'test/fixtures/ios27-device/tracking/scroll-delay.jsonl';

/// The 120 x 44 glass button, its center at (201, 384) in the window.
const _size = Size(120, 44);
const _center = Offset(201, 384);

// glass_button_device_replay_test.dart holds the glass button's lift to
// this rms, as controls_test.dart holds the simulator's.
const double _scaleTolerance = 3e-4;

/// The glass button's scale rows, a row only where the scale changed.
List<TraceFrame> _lift() {
  final rows = <TraceFrame>[];
  for (final line in File(_file).readAsLinesSync()) {
    final row = (jsonDecode(line) as Map).cast<String, Object?>();
    if (row['k'] != 'lab_sample' || row['id'] != 'lift') continue;
    final values = (row['values']! as Map).cast<String, Object?>();
    final frame = TraceFrame({
      't': row['t'],
      'sx': values['scaleX'],
      'sy': values['scaleY'],
    });
    if (rows.isNotEmpty &&
        rows.last.sx == frame.sx &&
        rows.last.sy == frame.sy) {
      continue;
    }
    rows.add(frame);
  }
  return rows;
}

/// The touches of each gesture on the glass button, in the button's own
/// space.
List<List<GlassTouch>> _gestures(Trace trace) {
  final gestures = <List<GlassTouch>>[];
  List<GlassTouch>? current;
  for (final touch in trace.touches) {
    if (touch.phase == 0) {
      current = touch.y == _center.dy ? [] : null;
      if (current != null) gestures.add(current);
    }
    final at = Offset(touch.x, touch.y) - _center + _size.center(Offset.zero);
    current?.add((t: touch.t, phase: touch.phase, at: at));
  }
  return gestures;
}

void main() {
  test(
    'a glass button in a scroll view lifts at contact, as outside one',
    () {
      // The scroll view holds nothing back: three still holds, a tap and a
      // swipe the scroll takes all lift within UIKit's delivery spread of
      // the model fed the touch at its stamp, as the button does outside a
      // scroll view (glass_button_device_replay_test.dart).
      final gestures = _gestures(Trace.load(_file));
      expect(gestures, hasLength(5));
      final rows = _lift();
      final lags = [
        for (final g in gestures) glassPressLag(rows, _size, g.first.t),
      ];
      for (final lag in lags) {
        expect(lag.abs(), lessThan(deliverySpread));
      }
      expect(median(lags).abs(), lessThan(deviceFrame / 2));
    },
    skip:
        'the five touches in the scroll view lift 24.4 - 27.5 ms after their '
        'stamps, as outside one; morph flexes at the stamp until the glass '
        'button touchDelay (26 ms, held for the owner) lands',
  );

  test('a still glass button in a scroll view lifts and returns like the '
      'device once it starts', () {
    // As glass_button_device_replay_test.dart replays the holds: press
    // and release start where the recorded ones do.
    final rows = _lift();
    final holds = [
      for (final g in _gestures(Trace.load(_file)))
        if (g.length == 2) g,
    ];
    expect(holds, hasLength(3));
    for (final g in holds) {
      final down = g.first;
      final up = g.last;
      final errors = glassErrors(rows, _size, [
        (t: down.t + glassPressLag(rows, _size, down.t), phase: 0, at: down.at),
        (t: up.t + glassReleaseLag(rows, _size, up.t), phase: 3, at: up.at),
      ], up.t + 1);
      final press = [
        for (final e in errors)
          if (e.pressed) e.error,
      ];
      final release = [
        for (final e in errors)
          if (!e.pressed) e.error,
      ];
      expect(rms(press), lessThan(_scaleTolerance), reason: '${down.t} press');
      expect(
        rms(release),
        lessThan(_scaleTolerance),
        reason: '${down.t} release',
      );
    }
  });
}
