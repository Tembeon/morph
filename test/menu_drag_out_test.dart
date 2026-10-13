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

MorphMenuMotion _openMenu() {
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
  return motion;
}

/// Plays [gesture]'s touches on [motion] up to each recorded frame and
/// hands the frame to [onFrame] once the motion stands at its time.
void _play(
  MorphMenuMotion motion,
  _Gesture gesture,
  void Function(({double t, Rect frame}) frame, Offset offset) onFrame,
) {
  final rest = motion.menuRect;
  final native = gesture.frames.first.frame;
  final offset = rest.center - native.center;
  var touch = 0;
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
    onFrame(frame, offset);
  }
}

/// The rms error, in points, of the four frame edges [MorphMenuMotion]
/// flexes against the recorded ones, each relative to its rest frame.
double _replay(_Gesture gesture) {
  final motion = _openMenu();
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

  for (final gesture in gestures) {
    test('the content rides the menu flexed ${gesture.name} on every '
        'recorded frame', () {
      final motion = _openMenu();
      var largest = 0.0;
      _play(motion, gesture, (frame, offset) {
        if (!motion.isOpen) return;
        final shape = motion.menuBlob.rect;
        final content = motion.contentRect;
        final reason = '${gesture.name} at ${frame.t}';
        expect(content.left, closeTo(shape.left, 0.5), reason: reason);
        expect(content.top, closeTo(shape.top, 0.5), reason: reason);
        expect(content.right, closeTo(shape.right, 0.5), reason: reason);
        expect(content.bottom, closeTo(shape.bottom, 0.5), reason: reason);
        final stretch = motion.contentStretch;
        final scale = motion.contentScale;
        final rest = motion.menuRect.size;
        expect(
          rest.width * scale * stretch.dx,
          closeTo(content.width, 1e-6),
          reason: reason,
        );
        expect(
          rest.height * scale * stretch.dy,
          closeTo(content.height, 1e-6),
          reason: reason,
        );
        final rect = motion.flexedMenuRect;
        largest = [
          largest,
          (rect.left - motion.menuRect.left).abs(),
          (rect.top - motion.menuRect.top).abs(),
          (rect.right - motion.menuRect.right).abs(),
          (rect.bottom - motion.menuRect.bottom).abs(),
        ].reduce(math.max);
      });
      expect(largest, greaterThan(4), reason: 'the replay flexes the menu');
    });
  }

  test('a row is hit where the flexed menu shows it', () {
    final gesture = gestures.firstWhere((g) => g.name == 'down');
    final motion = _openMenu();
    final rest = motion.menuRect;
    final spans = [
      for (var i = 0; i < 4; i++)
        Rect.fromLTWH(rest.left, rest.top + 41 + 42.0 * i, rest.width, 42),
    ];
    final rows = [for (final span in spans) motion.rowAt(span.center)];
    expect(rows.toSet(), hasLength(4));
    var checked = 0;
    var moved = 0;
    _play(motion, gesture, (frame, offset) {
      final shown = motion.flexedMenuRect;
      if (!motion.isOpen || shown.bottom - rest.bottom < 6 || checked > 0) {
        return;
      }
      checked++;
      double y(double at) =>
          shown.top + (at - rest.top) * shown.height / rest.height;
      for (var i = 0; i < spans.length; i++) {
        for (final at in [y(spans[i].top) + 1, y(spans[i].bottom) - 1]) {
          final point = Offset(shown.center.dx, at);
          expect(motion.rowAt(point), rows[i], reason: 'row $i at $at');
          if (!spans[i].contains(point)) moved++;
        }
      }
    });
    expect(checked, 1, reason: 'the drag down stretches the menu by 6 pt');
    expect(moved, greaterThan(0), reason: 'some rows show off their rest');
  });

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
