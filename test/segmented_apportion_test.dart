import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/segmented_control.dart';

/// The slots the device's content rows rest the lens in: each resting lens
/// frame (center x, width) plus the 2 point inset on either side.
Map<String, List<double>> _deviceSlots() {
  final seen = <String, Set<(double, double)>>{};
  final file = File(
    'test/fixtures/ios27-device/lens/'
    'segmented-narrow-content-content4-taps.jsonl',
  );
  for (final line in file.readAsLinesSync()) {
    final row = jsonDecode(line) as Map<String, Object?>;
    final control = row['ctl'];
    if (row['k'] != 'frame' || control is! String) continue;
    if (row['lifted'] != 0 || row['sx'] != 1) continue;
    final frame = (
      (row['x']! as num).toDouble(),
      (row['w']! as num).toDouble(),
    );
    (seen[control] ??= {}).add(frame);
  }
  // Slots have whole point edges, so a resting lens centers on the half
  // point grid; a frame off it is the lens passing on its way.
  final slots = <String, List<double>>{};
  for (final MapEntry(:key, :value) in seen.entries) {
    final rests = [
      for (final frame in value)
        if ((frame.$1 * 2).roundToDouble() == frame.$1 * 2) frame,
    ];
    rests.sort((a, b) => a.$1.compareTo(b.$1));
    slots[key] = [for (final (_, w) in rests) w + 4];
  }
  return slots;
}

void main() {
  // The labels in UIKit's medium segment font at 13 points, measured with
  // CoreText on the Mac; morph's segment typography matches them within
  // its 1 point parity gate.
  const contentLabels = [15.787, 111.094, 20.919];
  const content4Labels = [8.963, 120.325, 8.640, 50.957];
  const appearance = MorphSegmentedControlAppearance.light;

  test('segments sized by content share the room as the device rows do', () {
    final device = _deviceSlots();
    expect(device['segContent'], [60, 231, 70]);
    expect(device['segContent4'], [42, 184, 42, 92]);
    List<double> apportion(List<double> labels) => morphApportionSegments(
      width: 362,
      labels: labels,
      fixed: List<double?>.filled(labels.length, null),
      padding: appearance.contentPadding,
      minimum: appearance.height,
    );
    expect(apportion(contentLabels), device['segContent']);
    expect(apportion(content4Labels), device['segContent4']);
  });

  test('a segment with a width keeps it and the others share the rest', () {
    expect(
      morphApportionSegments(
        width: 300,
        labels: const [20, 20, 60],
        fixed: const [100, null, null],
        padding: 9,
        minimum: 32,
      ),
      [100, 65, 134],
    );
  });
}
