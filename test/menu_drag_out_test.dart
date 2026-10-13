import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/menu_motion.dart';

const _fixture = 'test/fixtures/ios27-device/menu/drag-out.jsonl';

/// The standard tuning with this phone's 250 pt tall four-row menu (82 +
/// 42 per row: menu/manifest.json), so the finger crosses the recorded
/// menu's edges where it did on the device.
const _device = MorphMenuTuning(verticalPadding: 41);

/// One recorded gesture: its touches and the list view's frames, times
/// from its touch-down.
typedef _Gesture = ({
  String name,
  List<({double t, int phase, Offset at})> touches,
  List<({double t, Rect frame})> frames,
});

List<_Gesture> _load() {
  final rows = [
    for (final line in File(_fixture).readAsLinesSync())
      if (line.trim().isNotEmpty)
        (jsonDecode(line) as Map).cast<String, Object?>(),
  ];
  double n(Map<String, Object?> row, String key) =>
      (row[key]! as num).toDouble();
  final touches = [
    for (final row in rows)
      if (row['k'] == 'touch')
        (
          t: n(row, 't'),
          phase: row['phase']! as int,
          at: Offset(n(row, 'x'), n(row, 'y')),
        ),
  ];
  final frames = [
    for (final row in rows)
      if (row['k'] == 'frame' && row['cls'] == '_UIContextMenuListView')
        (
          t: n(row, 't'),
          frame: Rect.fromCenter(
            center: Offset(n(row, 'x'), n(row, 'y')),
            width: n(row, 'w'),
            height: n(row, 'h'),
          ),
        ),
  ];
  final gestures = <_Gesture>[];
  const names = ['up', 'down', 'left', 'right'];
  for (var i = 0; i < touches.length; i++) {
    final down = touches[i];
    if (down.phase != 0 || (down.at.dy - 365.5).abs() > 5) continue;
    var j = i;
    while (touches[j].phase != 3) {
      j++;
    }
    final start = down.t;
    final end = touches[j].t + 1;
    gestures.add((
      name: names[gestures.length],
      touches: [
        for (final touch in touches.sublist(i, j + 1))
          (t: touch.t - start, phase: touch.phase, at: touch.at),
      ],
      frames: [
        for (final frame in frames)
          if (frame.t >= start && frame.t <= end)
            (t: frame.t - start, frame: frame.frame),
      ],
    ));
  }
  return gestures;
}

/// The rms error, in points, of the four frame edges [MorphMenuMotion]
/// flexes against the recorded ones, each relative to its rest frame.
double _replay(_Gesture gesture) {
  final motion = MorphMenuMotion(
    button: const Rect.fromLTWH(179, 300, 44, 44),
    itemCount: 4,
    bounds: const Size(402, 874),
    padding: const EdgeInsets.only(top: 62, bottom: 34),
    tuning: _device,
  );
  motion.advance(-4);
  motion.open(-3);
  motion.advance(-0.5);
  final rest = motion.menuRect;
  final native = gesture.frames.first.frame;
  final offset = rest.center - native.center;
  var touch = 0;
  var sum = 0.0;
  var count = 0;
  for (final frame in gesture.frames) {
    while (touch < gesture.touches.length &&
        gesture.touches[touch].t <= frame.t) {
      final event = gesture.touches[touch];
      final at = event.at + offset;
      switch (event.phase) {
        case 0:
          motion.pointerDown(event.t, at);
        case 3:
          motion.pointerUp(event.t, at);
        default:
          motion.pointerMove(event.t, at);
      }
      touch++;
    }
    motion.advance(frame.t);
    final flexed = motion.flexedMenuRect;
    final base = motion.menuRect;
    final edges = [
      (flexed.left - base.left) - (frame.frame.left - native.left),
      (flexed.right - base.right) - (frame.frame.right - native.right),
      (flexed.top - base.top) - (frame.frame.top - native.top),
      (flexed.bottom - base.bottom) - (frame.frame.bottom - native.bottom),
    ];
    for (final e in edges) {
      sum += e * e;
      count++;
    }
  }
  return math.sqrt(sum / count);
}

void main() {
  final gestures = _load();

  test('the fixture holds four drags off the menu', () {
    expect(gestures.map((g) => g.name), ['up', 'down', 'left', 'right']);
  });

  // The replay's errors (MorphMenuTuning.flexInsideGain): up 0.40, down
  // 0.36, left 0.17, right 0.17 pt rms.
  const bounds = {'up': 0.42, 'down': 0.39, 'left': 0.19, 'right': 0.19};
  for (final gesture in gestures) {
    test('a finger dragged ${gesture.name} off the menu flexes it as UIKit '
        'does', () {
      expect(_replay(gesture), lessThan(bounds[gesture.name]!));
    });
  }

  test('a finger resting where it touched down leaves the menu still', () {
    final motion = MorphMenuMotion(
      button: const Rect.fromLTWH(179, 300, 44, 44),
      itemCount: 4,
      bounds: const Size(402, 874),
    );
    motion.advance(-4);
    motion.open(-3);
    motion.advance(0);
    final rest = motion.menuRect;
    final at = rest.center.translate(0, -50);
    motion.pointerDown(0, at);
    motion.pointerMove(0.1, at);
    motion.advance(2);
    expect(motion.flexedMenuRect, rest);
    expect(motion.isSettled, isTrue);
  });
}
