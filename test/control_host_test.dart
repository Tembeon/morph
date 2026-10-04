import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/widgets/control_focus.dart';
import 'package:morph/src/widgets/control_host.dart';
import 'package:morph/widgets.dart';

class _Probe extends StatefulWidget {
  const _Probe({this.enabled = true, this.stampUpdates = true});

  final bool enabled;
  final bool stampUpdates;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends MorphControlHost<_Probe> {
  final List<({String kind, double time})> events = [];
  final List<double> ticks = [];
  bool settled = true;
  bool accept = true;
  int activations = 0;

  @override
  bool get controlEnabled => widget.enabled;

  @override
  bool get stampPointerUpdates => widget.stampUpdates;

  @override
  bool acceptsControlPointer(PointerDownEvent event) => accept;

  @override
  void advanceMotion(double t) => ticks.add(t);

  @override
  bool get motionSettled => settled;

  @override
  void onControlDown(double t, PointerDownEvent event) {
    settled = false;
    events.add((kind: 'down', time: t));
  }

  @override
  void onControlMove(double t, PointerMoveEvent event) {
    events.add((kind: 'move', time: t));
  }

  @override
  void onControlUp(double t, PointerUpEvent event) {
    expect(ownsPointer(event), isFalse);
    settled = true;
    events.add((kind: 'up', time: t));
  }

  @override
  void onControlCancel(double t) {
    settled = true;
    events.add((kind: 'cancel', time: t));
  }

  @override
  void onControlLost(double t) {
    settled = true;
    events.add((kind: 'lost', time: t));
  }

  @override
  Widget build(BuildContext context) => MorphControlFocus(
    enabled: controlEnabled,
    onHighlight: highlightControlFocus,
    onActivate: () => activations++,
    child: MorphFocusRing(
      visible: controlFocused,
      child: const SizedBox(width: 100, height: 40),
    ),
  );
}

Widget _scene(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

Future<_ProbeState> _probe(
  WidgetTester tester, {
  bool stampUpdates = true,
}) async {
  await tester.pumpWidget(_scene(_Probe(stampUpdates: stampUpdates)));
  return tester.state<_ProbeState>(find.byType(_Probe));
}

void main() {
  testWidgets('host gates primary buttons and unrelated pointer events', (
    tester,
  ) async {
    final state = await _probe(tester);
    state.handleDown(
      const PointerDownEvent(pointer: 1, buttons: kSecondaryButton),
    );
    state.handleMove(const PointerMoveEvent(pointer: 1));
    state.handleUp(const PointerUpEvent(pointer: 1));
    state.handleCancel(const PointerCancelEvent(pointer: 1));
    expect(state.events, isEmpty);
    expect(tester.binding.transientCallbackCount, 0);

    state.handleDown(const PointerDownEvent(pointer: 1));
    state.handleDown(const PointerDownEvent(pointer: 2));
    state.handleMove(const PointerMoveEvent(pointer: 2));
    state.handleUp(const PointerUpEvent(pointer: 2));
    state.handleCancel(const PointerCancelEvent(pointer: 2));
    state.handleLost(const PointerCancelEvent(pointer: 2));
    expect(state.events.map((event) => event.kind), ['down']);
    expect(state.ownsPointer(const PointerMoveEvent(pointer: 1)), isTrue);
    state.handleMove(const PointerMoveEvent(pointer: 1));
    state.handleUp(const PointerUpEvent(pointer: 1));
    state.handleDown(const PointerDownEvent(pointer: 2));
    state.handleCancel(const PointerCancelEvent(pointer: 2));
    expect(state.events.map((event) => event.kind), [
      'down',
      'move',
      'up',
      'down',
      'cancel',
    ]);
    await tester.pumpAndSettle();
  });

  testWidgets('host does not capture or wake on a missed handle', (
    tester,
  ) async {
    final state = await _probe(tester);
    state.accept = false;
    state.handleDown(const PointerDownEvent(pointer: 1));
    expect(state.ownsPointer(const PointerUpEvent(pointer: 1)), isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    state.accept = true;
    state.handleDown(const PointerDownEvent(pointer: 2));
    state.handleUp(const PointerUpEvent(pointer: 2));
    expect(state.events.map((event) => event.kind), ['down', 'up']);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'host stamps preframe spacing under time dilation monotonically',
    (tester) async {
      final previous = timeDilation;
      addTearDown(() => timeDilation = previous);
      timeDilation = 2;
      final state = await _probe(tester);
      state.handleDown(
        const PointerDownEvent(pointer: 1, timeStamp: Duration(seconds: 1)),
      );
      state.handleMove(
        const PointerMoveEvent(
          pointer: 1,
          timeStamp: Duration(milliseconds: 1100),
        ),
      );
      state.handleMove(
        const PointerMoveEvent(
          pointer: 1,
          timeStamp: Duration(milliseconds: 1050),
        ),
      );
      state.handleUp(
        const PointerUpEvent(
          pointer: 1,
          timeStamp: Duration(milliseconds: 1200),
        ),
      );
      expect(state.events.map((event) => event.time), [0, 0.05, 0.05, 0.1]);
      await tester.pump();
      expect(state.clock, 0.1);
      expect(tester.binding.transientCallbackCount, 0);
      timeDilation = previous;
    },
  );

  testWidgets(
    'host stamps active events on the latest frame and sleeps at rest',
    (tester) async {
      final state = await _probe(tester);
      var frames = 0;
      state.frames.addListener(() => frames++);
      state.handleDown(const PointerDownEvent(pointer: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final current = state.clock;
      state.handleMove(
        const PointerMoveEvent(pointer: 1, timeStamp: Duration(seconds: 10)),
      );
      state.handleUp(
        const PointerUpEvent(pointer: 1, timeStamp: Duration(seconds: 11)),
      );
      expect(state.events.last.time, current);
      await tester.pump(const Duration(milliseconds: 10));
      final asleep = state.clock;
      final sleepingFrames = frames;
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 5));
      expect(state.clock, asleep);
      expect(frames, sleepingFrames);
      state.handleDown(
        const PointerDownEvent(pointer: 2, timeStamp: Duration(seconds: 20)),
      );
      expect(state.events.last.time, asleep);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(state.clock, asleep + 0.02);
      state.handleCancel(const PointerCancelEvent(pointer: 2));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('repeat host leaves moves and releases on the frame clock', (
    tester,
  ) async {
    final state = await _probe(tester, stampUpdates: false);
    state.handleDown(
      const PointerDownEvent(pointer: 1, timeStamp: Duration(seconds: 1)),
    );
    state.handleMove(
      const PointerMoveEvent(pointer: 1, timeStamp: Duration(seconds: 2)),
    );
    state.handleUp(
      const PointerUpEvent(pointer: 1, timeStamp: Duration(seconds: 3)),
    );
    expect(state.events.map((event) => event.time), [0, 0, 0]);
    await tester.pumpAndSettle();
  });

  testWidgets('host reports arena loss separately and releases ownership', (
    tester,
  ) async {
    final state = await _probe(tester);
    state.handleDown(const PointerDownEvent(pointer: 1));
    state.handleLost(const PointerCancelEvent(pointer: 1));
    state.handleUp(const PointerUpEvent(pointer: 1));
    state.handleDown(const PointerDownEvent(pointer: 2));
    state.handleCancel(const PointerCancelEvent(pointer: 2));
    expect(state.events.map((event) => event.kind), [
      'down',
      'lost',
      'down',
      'cancel',
    ]);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'host cancels once on disable and does not revive the held pointer',
    (tester) async {
      final state = await _probe(tester);
      state.handleDown(const PointerDownEvent(pointer: 1));
      await tester.pump();
      final disabledAt = state.clock;
      await tester.pumpWidget(_scene(const _Probe(enabled: false)));
      await tester.pumpWidget(_scene(const _Probe(enabled: false)));
      state.handleDown(const PointerDownEvent(pointer: 2));
      state.handleMove(const PointerMoveEvent(pointer: 1));
      state.handleUp(const PointerUpEvent(pointer: 1));
      expect(state.events.map((event) => event.kind), ['down', 'cancel']);
      expect(state.events.last.time, disabledAt);
      await tester.pumpWidget(_scene(const _Probe()));
      state.handleUp(const PointerUpEvent(pointer: 1));
      state.handleDown(const PointerDownEvent(pointer: 2));
      state.handleUp(const PointerUpEvent(pointer: 2));
      expect(state.events.map((event) => event.kind), [
        'down',
        'cancel',
        'down',
        'up',
      ]);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('host stores the focus highlight and disposes an active ticker', (
    tester,
  ) async {
    final state = await _probe(tester);
    final focus = tester.widget<MorphControlFocus>(
      find.byType(MorphControlFocus),
    );
    focus.onHighlight(true);
    await tester.pump();
    expect(state.controlFocused, isTrue);
    expect(
      tester.widget<MorphFocusRing>(find.byType(MorphFocusRing)).visible,
      isTrue,
    );
    focus.onHighlight(false);
    await tester.pump();
    expect(state.controlFocused, isFalse);
    state.handleDown(const PointerDownEvent(pointer: 1));
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  final controls =
      <String, Widget Function(VoidCallback, {required bool enabled})>{
        'segmented': (called, {required bool enabled}) => SizedBox(
          width: 240,
          child: MorphSegmentedControl(
            segments: const ['One', 'Two'],
            selected: 0,
            onChanged: enabled ? (_) => called() : null,
          ),
        ),
        'switch': (called, {required bool enabled}) => MorphSwitch(
          value: false,
          onChanged: enabled ? (_) => called() : null,
        ),
        'slider': (called, {required bool enabled}) => SizedBox(
          width: 240,
          child: MorphSlider(
            value: 0.5,
            onChanged: enabled ? (_) => called() : null,
          ),
        ),
        'stepper': (called, {required bool enabled}) =>
            MorphStepper(value: 5, onChanged: enabled ? (_) => called() : null),
        'button': (called, {required bool enabled}) => MorphGlassButton(
          onPressed: enabled ? called : null,
          child: const Text('Press'),
        ),
        'page': (called, {required bool enabled}) => MorphPageControl(
          count: 3,
          page: 0,
          onChanged: enabled ? (_) => called() : null,
        ),
      };
  for (final entry in controls.entries) {
    testWidgets(
      '${entry.key} uses host cancellation across disable and reenable',
      (tester) async {
        var enabled = true;
        var calls = 0;
        late StateSetter update;
        await tester.pumpWidget(
          _scene(
            StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return entry.value(() => calls++, enabled: enabled);
              },
            ),
          ),
        );
        final host = tester.state<MorphControlHost<StatefulWidget>>(
          find.byWidgetPredicate(
            (widget) =>
                widget is MorphSegmentedControl ||
                widget is MorphSwitch ||
                widget is MorphSlider ||
                widget is MorphStepper ||
                widget is MorphGlassButton ||
                widget is MorphPageControl,
          ),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byWidget(host.widget)),
          pointer: 1,
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(host.ownsPointer(const PointerMoveEvent(pointer: 1)), isTrue);
        update(() => enabled = false);
        await tester.pump();
        expect(host.ownsPointer(const PointerMoveEvent(pointer: 1)), isFalse);
        update(() => enabled = true);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(calls, 0);
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  testWidgets(
    'button second pointer cannot release or cancel the first press',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _scene(
          MorphGlassButton(
            onPressed: () => calls++,
            child: const Text('Press'),
          ),
        ),
      );
      final point = tester.getCenter(find.text('Press'));
      final first = await tester.startGesture(point, pointer: 1);
      await tester.pump(const Duration(milliseconds: 200));
      final second = await tester.startGesture(point, pointer: 2);
      await second.cancel();
      expect(calls, 0);
      await first.up();
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  testWidgets(
    'tab host accepts disabled tabs and cancels when all items disappear',
    (tester) async {
      var present = true;
      late StateSetter update;
      await tester.pumpWidget(
        _scene(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MorphTabBar(
                items: present
                    ? const [
                        MorphTabItem(
                          icon: IconData(0xe318),
                          label: 'One',
                          enabled: false,
                        ),
                      ]
                    : const [],
                selected: 0,
                onChanged: null,
              );
            },
          ),
        ),
      );
      final host = tester.state<MorphControlHost<MorphTabBar>>(
        find.byType(MorphTabBar),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(MorphTabBar)),
        pointer: 1,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(host.ownsPointer(const PointerMoveEvent(pointer: 1)), isTrue);
      update(() => present = false);
      await tester.pump();
      expect(host.ownsPointer(const PointerMoveEvent(pointer: 1)), isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
