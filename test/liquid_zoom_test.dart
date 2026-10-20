import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/zoom_motion.dart';

/// One device transition of the liquid zoom: the call's kind and the
/// frames sampled after it.
typedef _Transition = ({String kind, List<Map<String, Object?>> frames});

List<_Transition> _load() {
  final json =
      jsonDecode(
            File(
              'test/fixtures/ios27-device/zoom/liquid.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  return [
    for (final t in (json['transitions']! as List).cast<Map<String, Object?>>())
      (
        kind: t['kind']! as String,
        frames: (t['frames']! as List).cast<Map<String, Object?>>(),
      ),
  ];
}

Rect _rect(Object? box) {
  final b = (box! as List).cast<num>();
  return Rect.fromCenter(
    center: Offset(b[0].toDouble(), b[1].toDouble()),
    width: b[2].toDouble(),
    height: b[3].toDouble(),
  );
}

double _rms(List<double> errors) => errors.isEmpty
    ? 0
    : math.sqrt(errors.fold(0.0, (sum, e) => sum + e * e) / errors.length);

void main() {
  const source = Rect.fromLTWH(131, 276, 140, 48);

  for (final (index, transition) in _load().indexed) {
    test('liquid zoom ${transition.kind} #$index replays the device', () {
      final frames = transition.frames
          .where((f) => f['container'] != null && f['source'] != null)
          .toList();
      final opening = transition.kind == 'present';
      final sheet = _rect((opening ? frames.last : frames.first)['container']);
      // The morph starts 0.002 - 0.006 s after the frame sampled first.
      final start = (frames.first['t']! as num).toDouble() + 0.004;
      final motion = MorphLiquidZoomMotion();
      if (!opening) {
        motion.open(-10);
        motion.advance(-5);
      }
      if (opening) {
        motion.open(start);
      } else {
        motion.close(start);
      }
      final container = <double>[];
      final glass = <double>[];
      final corners = <double>[];
      final look = <double>[];
      for (final frame in frames) {
        final t = (frame['t']! as num).toDouble();
        motion.advance(t);
        final want = _rect(frame['container']);
        final got = motion.container(source, sheet);
        container.addAll([
          got.left - want.left,
          got.top - want.top,
          got.right - want.right,
          got.bottom - want.bottom,
        ]);
        final wantGlass = _rect(frame['source']);
        final gotGlass = motion.sourceGlass(source, sheet);
        glass.addAll([
          gotGlass.center.dy - wantGlass.center.dy,
          gotGlass.width - wantGlass.width,
          gotGlass.height - wantGlass.height,
        ]);
        if (frame['radii'] case final List<Object?> radii) {
          final rest = opening ? (sheet.width > 0 ? 54.0 : 0.0) : 52.7;
          corners.add(
            math.min(201, motion.corner(rest)) - (radii[0]! as num).toDouble(),
          );
        }
        if (frame['look'] case final num opacity) {
          look.add((1 - motion.fade) - opacity.toDouble());
        }
      }
      final large = !opening && sheet.height > 600;
      // Device: 2.5 - 3.4 points over the medium detent. From the large
      // detent UIKit shrinks the sheet's height faster (fit 0.38 / 0.88)
      // into a smaller circle (11.9 points), one sample: the tuning keeps
      // the medium detent's springs, 16 points rms off there (NEAR).
      expect(_rms(container), lessThan(large ? 16.5 : 3.5), reason: 'sheet');
      // From the large detent the source's glass rests deeper in the
      // sheet than a third of the way (342 against 355).
      expect(_rms(glass), lessThan(large ? 3.0 : 1.0), reason: 'source glass');
      expect(_rms(corners), lessThan(2.0), reason: 'corners');
      expect(_rms(look), lessThan(0.015), reason: 'crossfade');
    });
  }
}
