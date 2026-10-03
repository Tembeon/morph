import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/flex_integrator.dart';
import 'package:morph/src/widgets/timeline.dart';

void main() {
  group('MorphTimeline', () {
    test('runs due actions in time order, each at its own time', () {
      final timeline = MorphTimeline(now: 0);
      final log = <String>[];
      timeline.insert(0.3, (t) => log.add('c@$t'));
      timeline.insert(0.1, (t) => log.add('a@$t'));
      timeline.insert(0.2, (t) => log.add('b@$t'));
      expect(timeline.isEmpty, isFalse);
      timeline.runDue(0.25);
      expect(log, ['a@0.1', 'b@0.2']);
      expect(timeline.now, 0.25);
      timeline.runDue(1);
      expect(log, ['a@0.1', 'b@0.2', 'c@0.3']);
      expect(timeline.isEmpty, isTrue);
    });

    test('keeps insertion order for equal times', () {
      final timeline = MorphTimeline();
      final log = <int>[];
      for (var i = 0; i < 5; i++) {
        timeline.insert(0.5, (t) => log.add(i));
      }
      timeline.insert(0.4, (t) => log.add(-1));
      timeline.runDue(0.5);
      expect(log, [-1, 0, 1, 2, 3, 4]);
    });

    test('an action sees its own time and may schedule relative to it', () {
      final timeline = MorphTimeline(now: 0);
      final log = <(String, double, double)>[];
      timeline.insert(0.1, (t) {
        log.add(('first', t, timeline.now));
        timeline.at(t + 0.05, (s) => log.add(('chained', s, timeline.now)));
        timeline.at(t, (s) => log.add(('immediate', s, timeline.now)));
      });
      timeline.runDue(0.2);
      expect(log, [
        ('first', 0.1, 0.1),
        ('immediate', 0.1, 0.1),
        ('chained', 0.15000000000000002, 0.15000000000000002),
      ]);
      expect(timeline.now, 0.2);
    });

    test('at runs an action that is already due right away at now', () {
      final timeline = MorphTimeline(now: 1);
      final log = <double>[];
      timeline.at(0.5, log.add);
      expect(log, [1]);
      expect(timeline.isEmpty, isTrue);
    });

    test('runDue never moves now backwards', () {
      final timeline = MorphTimeline(now: 1);
      timeline.runDue(0.5);
      expect(timeline.now, 1);
    });

    test('flush runs everything at the given time and clear drops it', () {
      final timeline = MorphTimeline(now: 0);
      final log = <double>[];
      timeline.insert(2, log.add);
      timeline.insert(3, log.add);
      timeline.flush(1);
      expect(log, [1, 1]);
      timeline.insert(4, log.add);
      timeline.clear();
      timeline.runDue(10);
      expect(log, [1, 1]);
    });
  });

  group('MorphSubClock', () {
    test('reports every frame boundary crossed, once', () {
      final clock = MorphSubClock(60);
      final frames = <double>[];
      clock.start(0);
      clock.run(0.05, frames.add);
      clock.run(0.05, frames.add);
      clock.run(1 / 15, frames.add);
      expect(frames, [1 / 60, 2 / 60, 3 / 60, 4 / 60]);
    });

    test('does not depend on how the time is split', () {
      List<double> collect(List<double> steps) {
        final clock = MorphSubClock(120);
        final frames = <double>[];
        clock.start(0.003);
        for (final t in steps) {
          clock.run(t, frames.add);
        }
        return frames;
      }

      final coarse = collect([0.5]);
      final fine = collect([for (var i = 1; i <= 50; i++) i / 100]);
      expect(fine, coarse);
      expect(coarse.length, 60);
    });
  });

  group('MorphFlexIntegrator', () {
    test('filters the rate of change of speed with weight 0.3', () {
      final flex = MorphFlexIntegrator();
      flex.reset(0);
      final af = flex.step(10, 0.5);
      expect(flex.pf, 3);
      expect(flex.vf, closeTo(1.8, 1e-12));
      expect(af, closeTo(1.08, 1e-12));
      expect(flex.af, af);
    });

    test('an unprimed filter starts at rest on the first position', () {
      final flex = MorphFlexIntegrator();
      expect(flex.step(5, 1 / 60), 0);
      expect(flex.pf, 5);
      expect(flex.vf, 0);
    });
  });
}
