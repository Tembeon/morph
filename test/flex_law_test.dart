import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/flex_interaction.dart';
import 'package:morph/src/widgets/flex_spec.dart';
import 'package:morph/src/widgets/slider_motion.dart';

import 'support/trace.dart';

/// The flex movement law against the targets UIKit recorded on an iPhone
/// 16 Pro (iOS 27.0.1): every lens, knob and thumb frame that logs UIKit's
/// own filtered motion (`vi_ax` rate of change of speed, `vi_vx`
/// velocity) and the flex targets it set (`f_scaleX`, `f_scaleY`,
/// `f_driftX`) is fed to [MorphFlexInteraction.withMovement] with
/// [MorphFlexSpec.loupeForSize] of the lens.

const _device = 'test/fixtures/ios27-device';

double _rms(List<double> e) =>
    math.sqrt(e.fold(0.0, (a, b) => a + b * b) / e.length);

double _d(Map<String, Object?> r, String key) => (r[key]! as num).toDouble();

Iterable<Map<String, Object?>> _frames(String file) sync* {
  for (final line in File(file).readAsLinesSync()) {
    final row = jsonDecode(line) as Map<String, Object?>;
    if (row['k'] != 'frame') continue;
    if (!row.containsKey('vi_ax') || !row.containsKey('vi_vx')) continue;
    final sx = row['f_scaleX'] as num?;
    if (sx == null || sx == 0) continue;
    yield row;
  }
}

MorphFlexValues _law(Size size, Map<String, Object?> r) =>
    MorphFlexInteraction.withMovement(
      MorphFlexInteraction.rest,
      spec: MorphFlexSpec.loupeForSize(size),
      size: size,
      acceleration: Offset(_d(r, 'vi_ax'), 0),
      velocity: Offset(_d(r, 'vi_vx'), 0),
    );

void main() {
  test('the selection lens targets follow the law at the lens size', () {
    final errors = <String, (List<double>, List<double>)>{};
    final files = Directory(
      '$_device/lens',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl'));
    for (final file in files) {
      for (final r in _frames(file.path)) {
        final tab = (r['ctl']! as String).startsWith('tab');
        final restHeight = tab ? 54.0 : 28.0;
        final liftWidth = tab ? 16.0 : 24.0;
        const liftHeight = 16.0;
        final lifted = r['lifted'] == 1;
        final Size size;
        if (lifted) {
          final progress = (_d(r, 'bh') - restHeight) / liftHeight;
          final width = _d(r, 'bw') - progress * liftWidth;
          size = Size(width + liftWidth, restHeight + liftHeight);
        } else {
          size = Size(_d(r, 'bw'), restHeight);
        }
        final v = _law(size, r);
        final key = '${tab ? 'tab bar' : 'segmented'} lifted $lifted';
        final (sx, dx) = errors.putIfAbsent(key, () => (<double>[], []));
        sx.add(v.scaleX - _d(r, 'f_scaleX'));
        dx.add(v.driftX - _d(r, 'f_driftX'));
      }
    }
    const limits = {
      'segmented lifted false': (0.006, 0.6),
      'segmented lifted true': (0.001, 1.1),
      'tab bar lifted false': (0.0035, 0.3),
      'tab bar lifted true': (0.0002, 0.002),
    };
    expect(errors.keys.toSet(), limits.keys.toSet());
    for (final MapEntry(key: key, value: (sx, dx)) in errors.entries) {
      final (sxLimit, dxLimit) = limits[key]!;
      expect(sx.length, greaterThan(1000), reason: key);
      expect(_rms(sx), lessThan(sxLimit), reason: '$key scale x');
      expect(_rms(dx), lessThan(dxLimit), reason: '$key drift');
    }
  });

  test('the knob and thumb targets follow the law at their size', () {
    final files = Directory(
      '$_device/controls',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl'));
    var checked = 0;
    for (final file in files) {
      final sx = <double>[];
      final sy = <double>[];
      final dx = <double>[];
      for (final r in _frames(file.path)) {
        if (!r.containsKey('f_scaleY')) continue;
        final v = _law(Size(_d(r, 'bw'), _d(r, 'bh')), r);
        sx.add(v.scaleX - _d(r, 'f_scaleX'));
        sy.add(v.scaleY - _d(r, 'f_scaleY'));
        dx.add(v.driftX - _d(r, 'f_driftX'));
      }
      if (sx.length < 50) continue;
      checked++;
      final name = file.uri.pathSegments.last;
      expect(_rms(sx), lessThan(0.004), reason: '$name scale x');
      expect(_rms(sy), lessThan(0.004), reason: '$name scale y');
      expect(_rms(dx), lessThan(0.35), reason: '$name drift');
    }
    expect(checked, greaterThan(30));
  });

  test('a dragged slider thumb deforms and lags like the device', () {
    const files = [
      ('slider-w300-drag-slow.jsonl', 300.0, 0.3),
      ('slider-w300-drag-pastend.jsonl', 300.0, 0.3),
      ('slider-w300-drag-pastend-far.jsonl', 300.0, 0.3),
      ('slider-w300-drag-paststart.jsonl', 300.0, 0.3),
      ('slider-w300-glide-v150.jsonl', 300.0, 0.1),
      ('slider-w300-glide-v250.jsonl', 300.0, 0.1),
      ('slider-w300-glide-v400.jsonl', 300.0, 0.1),
      ('slider-w200-glide-v250.jsonl', 200.0, 0.1),
      ('slider-w300-fling-slow.jsonl', 300.0, 0.3),
    ];
    final sx = <double>[];
    final sy = <double>[];
    final shift = <double>[];
    for (final (file, width, value) in files) {
      final trace = Trace.load('$_device/controls/$file');
      final motion = MorphSliderMotion(
        width: width,
        value: value,
        frameRate: 120,
      );
      final left = 201 - width / 2;
      motion.advance(trace.touches.first.t - 1);
      var next = 0;
      for (final f in trace.frames) {
        if (f.t < trace.touches.first.t) continue;
        while (next < trace.touches.length && trace.touches[next].t <= f.t) {
          final touch = trace.touches[next++];
          final x = touch.x - left;
          switch (touch.phase) {
            case 0:
              motion.pointerDown(touch.t, x);
            case 3:
              motion.pointerUp(touch.t, x);
            case _:
              motion.pointerMove(touch.t, x);
          }
        }
        motion.advance(f.t);
        if (f.raw['lifted'] != 1) continue;
        sx.add(motion.lens.scaleX(f.t) - f.sx);
        sy.add(motion.lens.scaleY(f.t) - f.sy);
        shift.add(motion.lens.shift(f.t) - f.tx);
      }
    }
    expect(sx.length, greaterThan(800));
    expect(_rms(sx), lessThan(0.021));
    expect(_rms(sy), lessThan(0.021));
    expect(_rms(shift), lessThan(0.65));
  });
}
