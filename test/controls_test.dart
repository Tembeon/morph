import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

import 'support/trace.dart';

const _dir = 'test/fixtures/ios27/controls';

/// The window-space center of every recorded control.
const double _controlX = 220;

const _deviceDir = 'test/fixtures/ios27-device/controls';

/// The window-space center of every control recorded on the device.
const double _deviceControlX = 201;

/// Root-mean-square of [errors].
double _rms(Iterable<double> errors) {
  var sum = 0.0;
  var n = 0;
  for (final e in errors) {
    sum += e * e;
    n++;
  }
  return n == 0 ? double.nan : math.sqrt(sum / n);
}

/// Feeds the touches of [trace] up to time [t] into [feed], once each.
class _Touches {
  _Touches(this.trace);

  final Trace trace;
  int _next = 0;

  void until(double t, void Function(TraceTouch touch) feed) {
    while (_next < trace.touches.length && trace.touches[_next].t <= t) {
      feed(trace.touches[_next]);
      _next++;
    }
  }
}

({MorphSliderMotion motion, double left, Trace trace, _Touches touches})
_slider(
  String file, {
  double width = 300,
  double value = 0.3,
  bool device = false,
}) {
  final trace = Trace.load('${device ? _deviceDir : _dir}/$file');
  final motion = MorphSliderMotion(width: width, value: value, frameRate: 60);
  motion.advance(trace.touches.first.t - 1);
  return (
    motion: motion,
    left: (device ? _deviceControlX : _controlX) - width / 2,
    trace: trace,
    touches: _Touches(trace),
  );
}

void Function(TraceTouch) _feedSlider(MorphSliderMotion m, double left) {
  return (TraceTouch touch) {
    final x = touch.x - left;
    switch (touch.phase) {
      case 0:
        m.pointerDown(touch.t, x);
      case 3:
        m.pointerUp(touch.t, x);
      case _:
        m.pointerMove(touch.t, x);
    }
  };
}

/// The model's value at every recorded valueChanged event during the
/// drag, as errors in pixels of thumb travel.
({double drag, int n}) _sliderValues(
  String file, {
  double width = 300,
  double value = 0.3,
  bool device = false,
}) {
  final s = _slider(file, width: width, value: value, device: device);
  final feed = _feedSlider(s.motion, s.left);
  final up = s.trace.touches.lastWhere((t) => t.phase == 3).t;
  final drag = <double>[];
  for (final e in s.trace.events) {
    if (e['e'] != 'valueChanged') continue;
    final t = (e['t']! as num).toDouble();
    if (t >= up) break;
    s.touches.until(t - 0.002, feed);
    s.motion.advance(t);
    drag.add((s.motion.value - (e['v']! as num).toDouble()) * width);
  }
  return (drag: _rms(drag), n: drag.length);
}

/// The time after a step's start at which [value] of the step is first
/// reached, found by bisection over the first [span] seconds.
double _solveStart(
  double Function(double dt) value,
  double target,
  double span,
) {
  var lo = 0.0;
  var hi = span;
  final rising = value(span) > value(0);
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if ((value(mid) < target) == rising) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// The lens of [file] against the small lens model: lift progress and
/// size, with the lift and landing starts solved from the first moving
/// frames because the simulator delivers touches 16 to 45 ms late.
({double progress, double width, double height}) _liftReplay(String file) {
  final trace = Trace.load('$_dir/$file');
  final frames = trace.track('_UILiquidLensView');
  final lifting = frames.indexWhere((f) => f.opt('lpp')! > 0.5);
  final first = frames[lifting];
  final liftDt = _solveStart(
    (dt) {
      final lens = _lens();
      lens.lift(0);
      return lens.progress(dt);
    },
    first.opt('lpp')!,
    0.1,
  );
  final liftAt = first.t - liftDt;
  final landing = frames.indexWhere(
    (f) => f.t > liftAt + 0.5 && f.opt('lpp')! < 0.999,
  );
  final drop = frames[landing];
  final landDt = _solveStart(
    (dt) {
      final lens = _lens();
      lens.lift(-5);
      lens.unlift(0);
      lens.advance(dt);
      return lens.progress(dt);
    },
    drop.opt('lpp')!,
    0.1,
  );
  final landAt = drop.t - landDt;
  final lens = _lens();
  lens.lift(liftAt);
  var landed = false;
  final progress = <double>[];
  final width = <double>[];
  final height = <double>[];
  double? previous;
  for (final f in frames.skip(lifting)) {
    if (!landed && f.t >= landAt) {
      lens.unlift(landAt);
      landed = true;
    }
    final lpp = f.opt('lpp')!;
    final stale = lpp == previous && lpp != 0 && lpp != 1;
    previous = lpp;
    if (stale) continue;
    lens.advance(f.t);
    progress.add(lens.progress(f.t) - f.opt('lpp')!);
    final size = lens.size(f.t);
    width.add(size.width - f.bw);
    height.add(size.height - f.bh);
  }
  return (progress: _rms(progress), width: _rms(width), height: _rms(height));
}

MorphSmallLens _lens() => MorphSmallLens(
  restSize: MorphSliderMotion.thumbSize,
  liftedSize: MorphSliderMotion.liftedThumbSize,
  frameRate: 60,
);

/// The lift scale of the button in [file] against the model, with the
/// press and release starts solved from the first moving frames because
/// the simulator delivers touches 16 to 45 ms late.
({double press, double release, double peak, double releaseLag}) _buttonReplay(
  String file,
  Size size,
) {
  final trace = Trace.load('$_dir/$file');
  final rows = trace.layer('0.0');
  final up = trace.touches.lastWhere((t) => t.phase == 3).t;
  final center = Offset(size.width / 2, size.height / 2);
  final moving = rows.indexWhere(
    (f) => f.t > trace.touches.first.t - 0.02 && f.sx > 1.0005,
  );
  final first = rows[moving];
  final pressDt = _solveStart(
    (dt) {
      final m = MorphGlassButtonMotion(size: size);
      m.pointerDown(0, center);
      m.advance(dt);
      return m.scale;
    },
    first.sx,
    0.1,
  );
  final plateau = rows.lastWhere((f) => f.t < up - 0.005).sx;
  final dropping = rows.indexWhere(
    (f) => f.t > up - 0.03 && f.sx < plateau - 0.002,
  );
  final drop = rows[dropping];
  final releaseDt = _solveStart(
    (dt) {
      final m = MorphGlassButtonMotion(size: size);
      m.pointerDown(-5, center);
      m.pointerUp(0, center);
      m.advance(dt);
      return m.scale;
    },
    drop.sx,
    0.1,
  );
  final releaseAt = drop.t - releaseDt;
  final m = MorphGlassButtonMotion(size: size);
  m.advance(first.t - pressDt - 0.1);
  m.pointerDown(first.t - pressDt, center);
  final press = <double>[];
  final release = <double>[];
  var released = false;
  for (final f in rows.skip(moving)) {
    if (!released && f.t >= releaseAt) {
      m.pointerUp(releaseAt, center);
      released = true;
    }
    if (f.t > releaseAt + 1.2) break;
    m.advance(f.t);
    (released ? release : press).add(m.scale - f.sx);
  }
  return (
    press: _rms(press),
    release: _rms(release),
    peak: m.liftedScale - plateau,
    releaseLag: releaseAt - up,
  );
}

/// The lean of the 120 x 44 button while a finger drags 150 pixels off
/// and back, against the model fed the recorded touches.
({double lean, double stretch}) _leanReplay() {
  final trace = Trace.load('$_dir/button-glass-120x44-drag-off-back.jsonl');
  const size = Size(120, 44);
  const origin = Offset(_controlX - 60, 400 - 22);
  final m = MorphGlassButtonMotion(size: size);
  m.advance(trace.touches.first.t - 1);
  final touches = _Touches(trace);
  final up = trace.touches.lastWhere((t) => t.phase == 3).t;
  final lean = <double>[];
  final stretch = <double>[];
  for (final f in trace.layer('0.0')) {
    if (f.t < trace.touches.first.t + 0.3 || f.t > up) continue;
    touches.until(f.t, (touch) {
      final p = Offset(touch.x, touch.y) - origin;
      switch (touch.phase) {
        case 0:
          m.pointerDown(touch.t, p);
        case 3:
          m.pointerUp(touch.t, p);
        case _:
          m.pointerMove(touch.t, p);
      }
    });
    m.advance(f.t);
    lean.add(m.lean.dx - f.tx);
    stretch.add((m.scaleX - m.scaleY) - (f.sx - f.sy));
  }
  return (lean: _rms(lean), stretch: _rms(stretch));
}

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: SizedBox(width: 300, child: child)),
);

/// The track ends and height of the slider in [file] against the model.
({double left, double right, double height, int n}) _stretchReplay(
  String file, {
  double width = 300,
  double value = 0.3,
  bool device = false,
}) {
  final s = _slider(file, width: width, value: value, device: device);
  final feed = _feedSlider(s.motion, s.left);
  final left = <double>[];
  final right = <double>[];
  final height = <double>[];
  for (final f in s.trace.layer('0.0.0')) {
    if (f.t < s.trace.touches.first.t) continue;
    s.touches.until(f.t, feed);
    s.motion.advance(f.t);
    final ends = s.motion.trackEnds;
    left.add(s.left + ends.left - (f.x - f.w / 2));
    right.add(s.left + ends.right - (f.x + f.w / 2));
    height.add(s.motion.currentTrackHeight - f.h);
  }
  return (
    left: _rms(left),
    right: _rms(right),
    height: _rms(height),
    n: left.length,
  );
}

/// The thumb center of the device slider in [file] against the model
/// while the finger is down, and the finger's lead over the recorded and
/// the modelled thumb when the value first reaches an end.
({double thumb, double lead, double modelLead, int n}) _thumbReplay(
  String file, {
  required double width,
  required double value,
}) {
  final s = _slider(file, width: width, value: value, device: true);
  final up = s.trace.touches.lastWhere((t) => t.phase == 3).t;
  final atEnd = s.trace.events.where((e) {
    final v = (e['v']! as num).toDouble();
    return e['e'] == 'valueChanged' && (v == 0 || v == 1);
  }).firstOrNull;
  final endTime = (atEnd?['t'] as num?)?.toDouble() ?? double.infinity;
  final thumb = <double>[];
  var finger = s.trace.touches.first.x;
  var lead = double.nan;
  var modelLead = double.nan;
  for (final f in s.trace.layer('0.0.1')) {
    if (f.t < s.trace.touches.first.t || f.t > up) continue;
    s.touches.until(f.t, (touch) {
      finger = touch.x;
      _feedSlider(s.motion, s.left)(touch);
    });
    s.motion.advance(f.t);
    final model = s.left + s.motion.thumbCenter;
    thumb.add(model - f.x);
    if (lead.isNaN && f.t >= endTime) {
      lead = (finger - f.x).abs();
      modelLead = (finger - model).abs();
    }
  }
  return (
    thumb: _rms(thumb),
    lead: lead,
    modelLead: modelLead,
    n: thumb.length,
  );
}

/// The glide of a device slider capture after a moving release: the
/// travel since the release, recorded against modelled, as the rms
/// error in pixels of thumb travel and the error of the final value, with the release speed measured
/// by Flutter's [VelocityTracker] as the widget measures it; the tracker
/// reads the test binding's clock, so this runs inside a widget test.
///
/// With [tracked] false the release speed is the motion's own: the speed
/// of the last moves however long ago, as UIKit's pan reports it.
({double glide, double end}) _glideReplay(String file, {bool tracked = true}) {
  final width = file.contains('w200') ? 200.0 : 300.0;
  final trace = Trace.load('test/fixtures/ios27-device/controls/$file');
  final left = 201 - width / 2;
  final values = [
    for (final row in trace.states)
      if (row['v'] != null)
        (t: (row['t']! as num).toDouble(), v: (row['v']! as num).toDouble()),
  ];
  final motion = MorphSliderMotion(width: width, value: values.first.v);
  final travel = motion.travel;
  final tracker = VelocityTracker.withKind(PointerDeviceKind.touch);
  final origin = trace.touches.first.t;
  var next = 0;
  void feed(double until) {
    while (next < trace.touches.length && trace.touches[next].t <= until) {
      final touch = trace.touches[next++];
      final x = touch.x - left;
      tracker.addPosition(
        Duration(microseconds: ((touch.t - origin) * 1e6).round()),
        Offset(x, 0),
      );
      switch (touch.phase) {
        case 0:
          motion.pointerDown(touch.t, x);
        case 3:
          motion.pointerUp(
            touch.t,
            x,
            velocity: tracked ? tracker.getVelocity().pixelsPerSecond.dx : null,
          );
        case _:
          motion.pointerMove(touch.t, x);
      }
    }
  }

  motion.advance(origin - 0.5);
  final up = trace.touches.lastWhere((t) => t.phase == 3).t;
  final glide = <double>[];
  var model = motion.value;
  var recorded = values.first.v;
  for (final (:t, :v) in values) {
    if (t < origin || t > up + 0.6) continue;
    feed(t);
    motion.advance(t);
    if (t <= up) {
      model = motion.value;
      recorded = v;
    } else {
      glide.add((motion.value - model - (v - recorded)) * travel);
    }
  }
  motion.advance(up + 2);
  return (
    glide: _rms(glide),
    end: (motion.value - model - (values.last.v - recorded)) * travel,
  );
}

void main() {
  group('replays of the native recordings', () {
    testWidgets('a released slider glides on like the device', (
      WidgetTester tester,
    ) async {
      final all = <double>[];
      for (final file in const [
        'slider-w300-glide-v150.jsonl',
        'slider-w300-glide-v250.jsonl',
        'slider-w300-glide-v400.jsonl',
        'slider-w200-glide-v150.jsonl',
        'slider-w200-glide-v250.jsonl',
        'slider-w200-glide-v400.jsonl',
      ]) {
        final e = _glideReplay(file);
        expect(e.glide, lessThan(3.5), reason: '$file glide');
        expect(e.end.abs(), lessThan(4.5), reason: '$file end');
        all.add(e.glide);
      }
      expect(_rms(all), lessThan(2.2));
      final stale = _glideReplay('slider-w300-drag-slow.jsonl', tracked: false);
      expect(stale.glide, lessThan(3), reason: 'a release after a stop');
      expect(stale.end.abs(), lessThan(3), reason: 'a release after a stop');
    });

    test('the slider thumb lifts and lands like the recorded lens', () {
      final hold = _liftReplay('slider-w300-hold800-thumb.jsonl');
      expect(hold.progress, lessThan(0.002));
      expect(hold.width, lessThan(0.25));
      expect(hold.height, lessThan(0.16));
      final drag = _liftReplay('slider-w300-drag-slow.jsonl');
      expect(drag.progress, lessThan(0.025));
      expect(drag.width, lessThan(0.35));
      expect(drag.height, lessThan(0.25));
    });

    test('glass buttons lift and land by their size', () {
      for (final (file, size) in [
        ('button-glass-44x44-hold800.jsonl', const Size(44, 44)),
        ('button-glass-60x44-hold800.jsonl', const Size(60, 44)),
        ('button-glass-120x44-hold800.jsonl', const Size(120, 44)),
        ('button-glass-200x44-hold800.jsonl', const Size(200, 44)),
        ('button-glass-300x44-hold800.jsonl', const Size(300, 44)),
        ('button-glass-200x100-hold800.jsonl', const Size(200, 100)),
        ('button-prominent-120x44-hold800.jsonl', const Size(120, 44)),
      ]) {
        final e = _buttonReplay(file, size);
        expect(e.press, lessThan(3e-4), reason: '$file press');
        expect(e.release, lessThan(3e-4), reason: '$file release');
        expect(e.peak.abs(), lessThan(1e-4), reason: '$file lifted scale');
        expect(e.releaseLag.abs(), lessThan(0.02), reason: '$file release');
      }
    });

    test('a glass button leans after a finger that drags off', () {
      final e = _leanReplay();
      expect(e.lean, lessThan(0.25));
      expect(e.stretch, lessThan(0.004));
    });

    test('a slider drag maps the finger by the full track width', () {
      for (final (file, width, value, limit) in [
        ('slider-w300-drag-slow.jsonl', 300.0, 0.3, 4.2),
        ('slider-w200-drag-slow.jsonl', 200.0, 0.3, 4.7),
        ('slider-w300-glide-v150.jsonl', 300.0, 0.1, 0.9),
        ('slider-w300-glide-v250.jsonl', 300.0, 0.1, 1.8),
        ('slider-w300-glide-v400.jsonl', 300.0, 0.1, 6.8),
        ('slider-w200-glide-v150.jsonl', 200.0, 0.1, 0.6),
        ('slider-w200-glide-v250.jsonl', 200.0, 0.1, 0.8),
        ('slider-w200-glide-v400.jsonl', 200.0, 0.1, 3.5),
        ('slider-w200-end-max-slow.jsonl', 200.0, 0.5, 2.0),
        ('slider-w200-end-min-slow.jsonl', 200.0, 0.5, 2.0),
        ('slider-w200-sweep.jsonl', 200.0, 0.0, 2.4),
        ('slider-w260-sweep.jsonl', 260.0, 0.0, 2.2),
        ('slider-w200-nearend-max.jsonl', 200.0, 0.9, 2.2),
        ('slider-w200-offgrab-max.jsonl', 200.0, 0.5, 1.0),
        ('slider-w200-fast-max.jsonl', 200.0, 0.5, 1.4),
        ('slider-w200-fast-min.jsonl', 200.0, 0.5, 1.4),
        ('slider-w200-fling-max.jsonl', 200.0, 0.5, 1.3),
      ]) {
        final e = _sliderValues(file, width: width, value: value, device: true);
        expect(e.n, greaterThan(15), reason: file);
        expect(e.drag, lessThan(limit), reason: '$file drag');
      }
      for (final file in [
        'slider-w300-drag-pastend.jsonl',
        'slider-w300-drag-pastend-small.jsonl',
      ]) {
        final e = _sliderValues(file);
        expect(e.n, greaterThan(15), reason: file);
        expect(e.drag, lessThan(0.01), reason: '$file drag');
      }
    });

    test('a device slider thumb stays behind the finger at its ends', () {
      for (final (file, width, value, limit, leadTolerance) in [
        ('slider-w200-end-max-slow.jsonl', 200.0, 0.5, 1.6, 1.0),
        ('slider-w200-end-min-slow.jsonl', 200.0, 0.5, 1.6, 1.0),
        ('slider-w200-sweep.jsonl', 200.0, 0.0, 2.1, 1.0),
        ('slider-w260-sweep.jsonl', 260.0, 0.0, 2.1, 1.0),
        ('slider-w200-nearend-max.jsonl', 200.0, 0.9, 1.3, 1.0),
        ('slider-w200-atend-max.jsonl', 200.0, 1.0, 2.0, double.nan),
        ('slider-w200-offgrab-max.jsonl', 200.0, 0.5, 0.6, 1.0),
        ('slider-w200-fast-max.jsonl', 200.0, 0.5, 3.7, 6.5),
        ('slider-w200-fast-min.jsonl', 200.0, 0.5, 3.7, 6.5),
      ]) {
        final e = _thumbReplay(file, width: width, value: value);
        expect(e.n, greaterThan(70), reason: file);
        expect(e.thumb, lessThan(limit), reason: '$file thumb');
        if (!leadTolerance.isNaN) {
          expect(e.lead, greaterThan(14), reason: '$file lead');
          expect(
            (e.lead - e.modelLead).abs(),
            lessThan(leadTolerance),
            reason: '$file lead against the model',
          );
        }
        final st = _stretchReplay(
          file,
          width: width,
          value: value,
          device: true,
        );
        expect(st.n, greaterThan(70), reason: file);
        expect(st.left, lessThan(0.7), reason: '$file left end');
        expect(st.right, lessThan(0.7), reason: '$file right end');
        expect(st.height, lessThan(0.25), reason: '$file height');
      }
    });

    test('a slider dragged past an end stretches the track', () {
      for (final (file, limit) in [
        ('slider-w300-drag-pastend.jsonl', 0.25),
        ('slider-w300-drag-paststart.jsonl', 0.6),
        ('slider-w300-drag-pastend-far.jsonl', 1.3),
        ('slider-w300-drag-pastend-small.jsonl', 2.1),
      ]) {
        final e = _stretchReplay(file);
        expect(e.n, greaterThan(20), reason: file);
        expect(e.left, lessThan(limit), reason: '$file left end');
        expect(e.right, lessThan(limit), reason: '$file right end');
        expect(e.height, lessThan(limit / 2), reason: '$file height');
      }
    });
  });

  group('widgets', () {
    testWidgets('a slider moves only from its thumb and settles', (
      tester,
    ) async {
      var value = 0.3;
      double? ended;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => MorphSlider(
              value: value,
              onChanged: (v) => setState(() => value = v),
              onChangeEnd: (v) => ended = v,
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(MorphSlider));
      expect(box.width, 300);
      final thumb = Offset(box.left + 18.5 + 0.3 * 263, box.center.dy);

      await tester.tapAt(Offset(box.left + 250, box.center.dy));
      await tester.pumpAndSettle();
      expect(value, 0.3, reason: 'a tap on the track does nothing');

      final gesture = await tester.startGesture(thumb);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(14, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(value, 0.3, reason: 'the pan begins at the slop');
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(value, moreOrLessEquals(0.5, epsilon: 1e-9));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(value, moreOrLessEquals(0.5, epsilon: 1e-9));
      expect(ended, value);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a flung slider glides on and stops at its end', (
      tester,
    ) async {
      var value = 0.3;
      double? ended;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => MorphSlider(
              value: value,
              onChanged: (v) => setState(() => value = v),
              onChangeEnd: (v) => ended = v,
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(MorphSlider));
      final thumb = Offset(box.left + 18.5 + 0.3 * 263, box.center.dy);
      await tester.flingFrom(thumb, const Offset(90, 0), 1000);
      final atRelease = value;
      await tester.pumpAndSettle();
      expect(value, greaterThan(atRelease + 0.1));
      expect(ended, value);
      await tester.flingFrom(
        Offset(box.left + 18.5 + value * 263, box.center.dy),
        const Offset(150, 0),
        3000,
      );
      await tester.pumpAndSettle();
      expect(value, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a glass button lifts, fires inside and settles', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          Center(
            child: SizedBox(
              width: 120,
              height: 44,
              child: MorphGlassButton(
                padding: EdgeInsets.zero,
                onPressed: () => taps++,
                child: const Text('Glass'),
              ),
            ),
          ),
        ),
      );
      final surface = find.descendant(
        of: find.byType(MorphGlassButton),
        matching: find.byType(CustomPaint),
      );
      final rest = tester.getRect(surface.first);
      final gesture = await tester.startGesture(rest.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final lifted = tester.getRect(surface.first);
      expect(lifted.width, moreOrLessEquals(136, epsilon: 0.5));
      expect(lifted.center.dx, moreOrLessEquals(rest.center.dx, epsilon: 1e-6));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(
        tester.getRect(surface.first),
        rectMoreOrLessEquals(rest, epsilon: 0.01),
      );
      expect(tester.binding.hasScheduledFrame, isFalse);

      final off = await tester.startGesture(rest.center);
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 10; i++) {
        await off.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      final leaning = tester.getRect(surface.first);
      expect(leaning.center.dx, greaterThan(rest.center.dx + 2));
      expect(leaning.width, greaterThan(lifted.width));
      await off.up();
      await tester.pumpAndSettle();
      expect(taps, 1, reason: 'a release far outside does not fire');
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a stepper commits on release and repeats while held', (
      tester,
    ) async {
      var value = 5.0;
      await tester.pumpWidget(
        _host(
          Center(
            child: StatefulBuilder(
              builder: (context, setState) => MorphStepper(
                value: value,
                max: 8,
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(MorphStepper));
      final minus = box.centerLeft + const Offset(23.5, 0);
      final plus = box.centerRight - const Offset(23.5, 0);

      final tap = await tester.startGesture(plus);
      await tester.pump(const Duration(milliseconds: 90));
      expect(value, 5, reason: 'a tap commits on release');
      await tap.up();
      await tester.pump();
      expect(value, 6);

      final hold = await tester.startGesture(plus);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 499));
      expect(value, 6);
      await tester.pump(const Duration(milliseconds: 2));
      expect(value, 7, reason: 'the first repeat comes after 0.5 s');
      await tester.pump(const Duration(milliseconds: 500));
      expect(value, 8);
      await tester.pump(const Duration(milliseconds: 500));
      expect(value, 8, reason: 'the stepper stops at its maximum');
      await hold.up();
      await tester.pump();
      expect(value, 8, reason: 'a release after repeats does not step');

      final slide = await tester.startGesture(plus);
      await tester.pump(const Duration(milliseconds: 100));
      await slide.moveTo(minus);
      await tester.pump(const Duration(milliseconds: 100));
      await slide.up();
      await tester.pump();
      expect(value, 7, reason: 'sliding moves the press to the other half');

      final leave = await tester.startGesture(minus);
      await tester.pump(const Duration(milliseconds: 100));
      await leave.moveTo(box.centerRight + const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 600));
      await leave.up();
      await tester.pump();
      expect(value, 7, reason: 'leaving the control cancels');
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
