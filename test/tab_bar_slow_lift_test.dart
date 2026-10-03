import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dir = 'test/fixtures/ios27-device/lens';

/// One tap of a device tab bar capture: its slots and whether the lens
/// size lagged the lift progress.
typedef _Tap = ({int from, int to, int count, bool slow});

List<_Tap> _taps(String name) {
  final rows = [
    for (final line in File('$_dir/$name').readAsLinesSync())
      if (line.trim().isNotEmpty)
        (jsonDecode(line) as Map).cast<String, Object?>(),
  ];
  double n(Map<String, Object?> row, String key) =>
      (row[key]! as num).toDouble();
  final frames = [
    for (final row in rows)
      if (row['k'] == 'frame' && n(row, 'y') > 100) row,
  ];
  final downs = [
    for (final row in rows)
      if (row['k'] == 'touch' && row['phase'] == 0) row,
  ];
  final slots = {for (final d in downs) n(d, 'x').roundToDouble()}.toList();
  slots.sort();
  int slotOf(double x) {
    var best = 0;
    for (var i = 1; i < slots.length; i++) {
      if ((slots[i] - x).abs() < (slots[best] - x).abs()) best = i;
    }
    return best;
  }

  final rest = n(frames.first, 'bh');
  final taps = <_Tap>[];
  for (final down in downs) {
    final t = n(down, 't');
    final before = frames.lastWhere((f) => n(f, 't') < t);
    final mid = frames.firstWhere(
      (f) => n(f, 't') > t && (f['lpp'] as num? ?? 0) >= 0.45,
    );
    final ratio = (n(mid, 'bh') - rest) / (16 * n(mid, 'lpp'));
    taps.add((
      from: slotOf(n(before, 'x')),
      to: slotOf(n(down, 'x')),
      count: slots.length,
      slow: ratio < 0.6,
    ));
  }
  return taps;
}

void main() {
  test('the slow lift is the third slot of the four-tab bar', () {
    var slow = 0;
    var total = 0;
    for (final name in const [
      'tabbar2-taps.jsonl',
      'tabbar3-taps.jsonl',
      'tabbar3-pairs.jsonl',
      'tabbar4-taps.jsonl',
      'tabbar4-pairs.jsonl',
      'tabbar4-radio-first.jsonl',
      'tabbar4-no-radio.jsonl',
      'tabbar5-taps.jsonl',
      'tabbar5-many.jsonl',
    ]) {
      for (final tap in _taps(name)) {
        if (tap.from == tap.to) continue;
        total++;
        if (tap.slow) slow++;
        expect(
          tap.slow,
          tap.count == 4 && (tap.from == 2 || tap.to == 2),
          reason: '$name ${tap.from} -> ${tap.to}',
        );
      }
    }
    expect(total, greaterThan(70));
    expect(slow, greaterThan(15));
  });
}
