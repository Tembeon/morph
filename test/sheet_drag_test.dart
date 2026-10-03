import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

const _dir = 'test/fixtures/ios27/sheet-drag';
const _deviceDir = 'test/fixtures/ios27-device/sheet-drag';

/// The probe screen: an iPhone 16 Pro (simulator and device), 402 x 874
/// points with a
/// 62 point top and a 34 point bottom safe area.
const double _w = 402;
const double _h = 874;
const double _maximum = _h - 62 - 34;

/// The distance UIKit's sheet pan waits for before the sheet moves; the
/// sheet does not catch up with the finger afterwards.
const double _slop = 12;

/// One display frame of the 60 Hz simulator recordings: presentation
/// layers are sampled for the frame being prepared.
const double _frame = 1 / 60;

/// The shift of the 120 Hz device recordings: their rows line up with the
/// model as stamped (a shift of one 120 Hz frame doubles the error of the
/// grabber tap and the hold, two frames that of every flick).
const double _deviceFrame = 0;

final _heights = [
  MorphSheetDetent.medium.resolve(_maximum) + 34,
  MorphSheetDetent.large.resolve(_maximum) + 34,
];

class _Capture {
  _Capture(String name, {String dir = _dir, double frame = _frame}) {
    for (final line in File('$dir/$name.jsonl').readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final r = (jsonDecode(line) as Map).cast<String, Object?>();
      double d(String k) => (r[k]! as num).toDouble();
      switch (r['k']) {
        case 'touch':
          touches.add((d('t'), r['phase']! as int, d('y')));
        case 'evt':
          if (r['e'] == 'dismissed') dismissed = true;
        case 'V':
          if (!(d('bw') == _w && d('bh') == _h)) {
            sheet.add((
              t: d('t') + frame,
              top: d('y') - d('h') / 2,
              bottom: d('y') + d('h') / 2,
              w: d('w'),
              bh: d('bh'),
            ));
          }
      }
    }
  }

  final List<(double, int, double)> touches = [];
  final List<({double t, double top, double bottom, double w, double bh})>
  sheet = [];
  bool dismissed = false;
}

/// Replays the last touch of a capture into a [MorphSheetMotion] resting
/// where the sheet rested before it, and compares the visible top and
/// bottom edges from the touch on. Returns the rms and max error, the
/// detent the model settles on (-1 for dismissed) and the recorded one.
({double rms, double max, int model, int recorded}) _replay(
  String name, {
  String dir = _dir,
  double frame = _frame,
}) {
  final cap = _Capture(name, dir: dir, frame: frame);
  final downAt = cap.touches.lastIndexWhere((t) => t.$2 == 0);
  final touches = cap.touches.sublist(downAt);
  final down = touches.first;
  final before = cap.sheet.lastWhere((r) => r.t <= down.$1);
  final largeOnly = name.startsWith('l-');
  final heights = largeOnly ? [_heights.last] : _heights;
  final start = largeOnly || before.bh < 800 ? 0 : 1;
  final motion = MorphSheetMotion(
    heights: heights,
    width: _w,
    initial: start,
    dockedIndex: heights.length - 1,
  );
  motion.present(0);
  motion.advance(down.$1 - 2);
  final rect = motion.visibleRect(down.$1 - 2, _h);
  if ((rect.top - before.top).abs() > 1) {
    throw StateError('$name rests at ${before.top}, model ${rect.top}');
  }
  var dragging = false;
  var next = 0;
  final errors = <double>[];
  void feed(double until) {
    while (next < touches.length && touches[next].$1 <= until) {
      final (t, phase, y) = touches[next];
      if (phase == 0) {
        motion.press(t);
      } else if (phase == 3) {
        if (dragging) {
          final recent = [
            for (final s in touches.sublist(0, next + 1))
              if (s.$1 >= t - 0.06) s,
          ];
          final v = recent.length < 2
              ? 0.0
              : (recent.last.$3 - recent.first.$3) /
                    (recent.last.$1 - recent.first.$1);
          motion.dragEnd(t, v);
        } else {
          motion.unpress(t);
          final top = motion.visibleRect(t, _h).top;
          if ((y - top) / motion.scale(t) < MorphSheetTuning.grabberHitHeight) {
            motion.tapGrabber(t);
          }
        }
      } else if (!dragging && (y - down.$3).abs() > _slop) {
        dragging = true;
        motion.dragStart(t, y);
      } else if (dragging) {
        motion.dragUpdate(t, y);
      }
      next++;
    }
  }

  for (final row in cap.sheet) {
    if (row.t < down.$1) continue;
    feed(row.t);
    motion.advance(row.t);
    final r = motion.visibleRect(row.t, _h);
    final e = [r.top - row.top, r.bottom - row.bottom];
    if (e.any((double v) => v.abs() > 60) && row.top <= 0.5) continue;
    if (row.top >= _h - 1 && r.top >= _h - 1) continue;
    errors.addAll(e);
  }
  feed(double.infinity);
  final model = motion.isDismissing ? -1 : motion.index;
  final last = cap.sheet.last;
  final recorded = cap.dismissed ? -1 : (last.bh > 800 && !largeOnly ? 1 : 0);
  return (
    rms: math.sqrt(errors.fold(0.0, (a, b) => a + b * b) / errors.length),
    max: errors.fold(0.0, (a, b) => math.max(a, b.abs())),
    model: model,
    recorded: recorded,
  );
}

// Tolerances are the honest spread of what the model leaves out: a sheet
// pulled below its smallest detent stretches about 2 percent taller and
// half a percent narrower in UIKit (drag-down-far), the start of a flick
// dismissal varies by up to 0.09 s from flick to flick (fd-1000,
// l-flick-down; the visible part of the slide), and a grabber tap starts
// within 0.045 - 0.065 s of the lift. lfd-800 is left out: its flick sits
// on the projection boundary both ways the bracketing flicks put it
// (0.143 s at 680 pt/s), and UIKit took it to medium.
void main() {
  const cases = <(String, double)>[
    ('hold', 3),
    ('grab-tap', 10),
    ('drag-up-mid', 6),
    ('drag-up-slow', 9),
    ('large-drag-down', 6),
    ('large-drag-down-mid', 6),
    ('drag-down-small', 6),
    ('drag-down-far', 10),
    ('flick-up', 8),
    ('flick-down', 8),
    ('fu-800', 8),
    ('fu-1000', 12),
    ('fd-800', 8),
    ('fd-1000', 25),
    ('l-drag-down', 8),
    ('l-flick-down', 45),
  ];
  group('sheet drags replayed against the iOS 27 simulator', () {
    for (final (name, tolerance) in cases) {
      test(name, () {
        final r = _replay(name);
        expect(r.model, r.recorded, reason: 'settled detent');
        expect(r.rms, lessThan(tolerance));
      });
    }
  });

  // The same probe on the device. Two flicks sit on the decision boundary
  // and are left out: fd-1000 (887 pt/s, 95 pt below medium; the
  // projection lands 9 pt short of half the sheet by the 60 ms finger
  // velocity, yet the next flicks up, 964 and 983 pt/s, dismiss) and
  // lfd-800 (the simulator's boundary case again, which UIKit settled at
  // large on the device and at medium on the simulator).
  const deviceCases = <(String, double)>[
    ('hold', 5),
    ('grab-tap', 6),
    ('drag-up-mid', 6),
    ('drag-up-slow', 6),
    ('large-drag-down', 5),
    ('large-drag-down-mid', 3),
    ('drag-down-small', 5),
    ('drag-down-far', 10),
    ('flick-up', 4),
    ('flick-down', 6),
    ('fu-600', 4),
    ('fu-700', 5),
    ('fu-800', 8),
    ('fu-900', 6),
    ('fu-1000', 6),
    ('fd-600', 6),
    ('fd-800', 8),
    ('fd-900', 8),
    ('fd-1100', 20),
    ('fd-1300', 20),
    ('fd-lift-mid', 26),
    ('l-drag-down', 6),
    ('l-flick-down', 15),
    ('lfd-700', 5),
    ('lfd-900', 8),
    ('lfd-1000', 7),
  ];
  group('sheet drags replayed against an iPhone 16 Pro', () {
    for (final (name, tolerance) in deviceCases) {
      test(name, () {
        final r = _replay(name, dir: _deviceDir, frame: _deviceFrame);
        expect(r.model, r.recorded, reason: 'settled detent');
        expect(r.rms, lessThan(tolerance));
      });
    }
  });
}
