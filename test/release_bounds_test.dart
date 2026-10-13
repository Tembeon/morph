import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/lens_driver.dart';
import 'package:morph/widgets.dart';

const _fixture = 'test/fixtures/ios27-device/tracking/release-outside.jsonl';

/// One recorded touch: window-space samples from contact to lift, and
/// what the lab's controls reported after it.
class _Trial {
  final List<({double t, Offset p})> samples = [];
  final List<String> events = [];

  Offset get down => samples.first.p;

  Offset get up => samples.last.p;
}

List<_Trial> _trials() {
  final trials = <_Trial>[];
  for (final line in File(_fixture).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final row = (jsonDecode(line) as Map).cast<String, Object?>();
    switch (row['k']) {
      case 'touch':
        if (row['phase'] == 0) trials.add(_Trial());
        trials.last.samples.add((
          t: (row['t']! as num).toDouble(),
          p: Offset(
            (row['x']! as num).toDouble(),
            (row['y']! as num).toDouble(),
          ),
        ));
      case 'lab_event':
        trials.last.events.add(_event(row['id']! as String, row['value']));
    }
  }
  return trials;
}

String _event(String id, Object? value) =>
    value == null ? id : '$id=${(value as num).toInt()}';

/// The lab scene of the fixture at the device's window coordinates:
/// glass button 141,200 120x44, switch centered on 176,420 51x31,
/// segmented control 51,600 300x32.
class _Scene extends StatefulWidget {
  const _Scene(this.events);

  final List<String> events;

  @override
  State<_Scene> createState() => _SceneState();
}

class _SceneState extends State<_Scene> {
  bool _on = false;
  int _segment = 0;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      children: [
        Positioned(
          left: 141,
          top: 200,
          width: 120,
          height: 44,
          child: MorphGlassButton(
            onPressed: () => widget.events.add('glass'),
            child: const Text('Glass'),
          ),
        ),
        Positioned(
          left: 176,
          top: 420,
          width: 51,
          height: 31,
          child: Center(
            child: MorphSwitch(
              value: _on,
              onChanged: (bool value) {
                widget.events.add(_event('toggle', value ? 1 : 0));
                setState(() => _on = value);
              },
            ),
          ),
        ),
        Positioned(
          left: 51,
          top: 600,
          width: 300,
          child: MorphSegmentedControl(
            segments: const ['A', 'B', 'C'],
            selected: _segment,
            onChanged: (int index) {
              widget.events.add(_event('seg', index));
              setState(() => _segment = index);
            },
          ),
        ),
      ],
    ),
  );
}

void main() {
  final trials = _trials();

  test('the fixture holds the measured release bounds', () {
    String at(Offset down, Offset up) => trials
        .firstWhere((trial) => trial.down == down && trial.up == up)
        .events
        .join(',');
    const button = Offset(201, 222);
    expect(at(button, const Offset(201, 130)), 'glass');
    expect(at(button, const Offset(201, 120)), '');
    expect(at(button, const Offset(321, 222)), 'glass');
    expect(at(button, const Offset(331, 222)), '');
    const segment = Offset(300, 616);
    expect(at(segment, const Offset(300, 692)), 'seg=2');
    expect(at(segment, const Offset(300, 702)), '');
    final toggles = [
      for (final trial in trials)
        if (trial.down.dy == 434) trial,
    ];
    expect(toggles, hasLength(7));
    expect(toggles.last.up.dy - 451, greaterThan(128));
    for (final trial in toggles) {
      expect(trial.events.single, startsWith('toggle='));
    }
  });

  testWidgets('every recorded release does on morph what it did on the '
      'iPhone', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final events = <String>[];
    await tester.pumpWidget(_Scene(events));
    await tester.pump(const Duration(seconds: 1));
    for (final trial in trials) {
      events.clear();
      final samples = trial.samples;
      final gesture = await tester.startGesture(samples.first.p);
      for (var i = 1; i < samples.length; i++) {
        final dt = samples[i].t - samples[i - 1].t;
        await tester.pump(Duration(microseconds: (dt * 1e6).round()));
        if (samples[i].p != samples[i - 1].p) {
          await gesture.moveTo(samples[i].p);
        }
        if (i == samples.length - 1) await gesture.up();
      }
      if (samples.length == 1) await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(
        events,
        trial.events,
        reason: 'press at ${trial.down}, release at ${trial.up}',
      );
    }
  });

  testWidgets('a segmented release beyond the bound drops the lens back', (
    WidgetTester tester,
  ) async {
    final picked = <int>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: MorphSegmentedControl(
              segments: const ['A', 'B', 'C'],
              selected: 0,
              onChanged: picked.add,
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(50, 16));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveTo(const Offset(250, 16));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveTo(
      const Offset(250, 32 + MorphSegmentedControl.releaseSlop + 10),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(picked, isEmpty);
  });

  testWidgets('a release beyond the bound restores the selected lens width', (
    WidgetTester tester,
  ) async {
    final picked = <int>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: MorphSegmentedControl(
              sizeByContent: true,
              segments: const ['A', 'Long label', 'B'],
              selected: 0,
              onChanged: picked.add,
            ),
          ),
        ),
      ),
    );
    final motion =
        (tester.state(find.byType(MorphSegmentedControl))
                as MorphLensDriver<MorphSegmentedControl>)
            .motion;
    final selected = motion.slots[0];
    final wide = motion.slots[1];
    expect(wide.width - selected.width, greaterThan(20));
    final gesture = await tester.startGesture(Offset(selected.center, 16));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveTo(Offset(wide.center, 16));
    await tester.pump(const Duration(milliseconds: 400));
    expect(motion.slotAt(motion.travelCenter), 1);
    await gesture.moveTo(
      Offset(wide.center, 32 + MorphSegmentedControl.releaseSlop + 10),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
    expect(motion.isSettled, isTrue);
    expect(motion.selected, 0);
    expect(motion.center, closeTo(selected.center, 0.01));
    expect(motion.size.width, closeTo(selected.width, 0.01));
  });
}
