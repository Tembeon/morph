import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/liquid_glass.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/live.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/glass_painter.dart';
import 'package:morph/src/widgets/glass_renderer.dart';

/// The frame timing of [MorphFrameSync] and of a [MorphGlassHost] that
/// follows one: driven by tickers, the structure is read once per frame
/// after every ticker of the frame ran, a widget builds only when the
/// structure changes, and the value drawn in a frame is the motion's value
/// of that frame.
void main() {
  setUpAll(() => isLocalTest = true);
  tearDownAll(() => isLocalTest = false);

  final running = <AnimationController>[];

  AnimationController motion(WidgetTester tester) {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);
    running.add(controller);
    return controller;
  }

  setUp(running.clear);

  // The test ends with no ticker left running.
  void stop() {
    for (final controller in running) {
      controller.stop();
    }
    running.clear();
  }

  Future<void> frame(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 16));

  group('MorphFrameSync', () {
    testWidgets('reads the structure once per frame', (tester) async {
      final a = motion(tester);
      final b = motion(tester);
      var reads = 0;
      final sync = MorphFrameSync<int>(
        structure: () {
          reads++;
          return 0;
        },
        rebuild: (int _) {},
      );
      addTearDown(sync.dispose);
      sync.read();
      sync.follow(Listenable.merge([a, b]));
      a.forward();
      b.forward();
      reads = 0;
      for (var i = 0; i < 5; i++) {
        await frame(tester);
      }
      expect(reads, 5);
      stop();
    });

    testWidgets('rebuilds only when the structure changes', (tester) async {
      final a = motion(tester);
      final built = <bool>[];
      late final MorphFrameSync<bool> sync;
      sync = MorphFrameSync<bool>(
        structure: () => a.value >= 0.5,
        rebuild: (bool structure) {
          built.add(structure);
          sync.read();
        },
      );
      addTearDown(sync.dispose);
      sync.read();
      sync.follow(a);
      a.forward();
      for (var i = 0; i < 70; i++) {
        await frame(tester);
      }
      expect(built, [true]);
      stop();
    });

    for (final notifies in [false, true]) {
      testWidgets('listeners hear the frames that keep the structure'
          '${notifies ? ' and the rebuilding ones' : ''}', (tester) async {
        final a = motion(tester);
        final heard = <double>[];
        final rebuilt = <double>[];
        final sync = MorphFrameSync<bool>(
          structure: () => a.value >= 0.05,
          rebuild: (bool _) => rebuilt.add(a.value),
          notifiesOnRebuild: notifies,
        );
        addTearDown(sync.dispose);
        sync.addListener(() => heard.add(a.value));
        sync.read();
        sync.follow(a);
        a.forward();
        for (var i = 0; i < 6; i++) {
          await frame(tester);
        }
        expect(rebuilt, hasLength(1));
        expect(
          heard.contains(rebuilt.single),
          notifies,
          reason: 'heard $heard, rebuilt at ${rebuilt.single}',
        );
        expect(heard, hasLength(notifies ? 6 : 5));
        stop();
      });
    }

    testWidgets('a notification in the mid-frame microtasks reads at once', (
      tester,
    ) async {
      final source = ValueNotifier<int>(0);
      addTearDown(source.dispose);
      var reads = 0;
      final sync = MorphFrameSync<int>(
        structure: () {
          reads++;
          return 0;
        },
        rebuild: (int _) {},
      );
      addTearDown(sync.dispose);
      sync.read();
      sync.follow(source);
      reads = 0;
      SchedulerPhase? phase;
      int? readsAfter;
      tester.binding.scheduleFrameCallback((Duration _) {
        scheduleMicrotask(() {
          phase = SchedulerBinding.instance.schedulerPhase;
          source.value++;
          readsAfter = reads;
        });
      });
      await frame(tester);
      expect(phase, SchedulerPhase.midFrameMicrotasks);
      expect(readsAfter, 1);
      expect(reads, 1);
      stop();
    });

    testWidgets('a queued read is dropped by dispose', (tester) async {
      final a = motion(tester);
      var reads = 0;
      final sync = MorphFrameSync<int>(
        structure: () {
          reads++;
          return 0;
        },
        rebuild: (int _) {},
      );
      sync.follow(a);
      a.forward();
      await frame(tester);
      reads = 0;
      tester.binding.scheduleFrameCallback((Duration _) => sync.dispose());
      await frame(tester);
      await frame(tester);
      expect(reads, 0);
      stop();
    });

    testWidgets('a notification between frames asks for the frame that '
        'shows it', (tester) async {
      final source = ValueNotifier<int>(0);
      addTearDown(source.dispose);
      final sync = MorphFrameSync<int>(
        structure: () => source.value,
        rebuild: (int _) {},
      );
      addTearDown(sync.dispose);
      sync.read();
      sync.follow(source);
      await frame(tester);
      expect(tester.binding.hasScheduledFrame, isFalse);
      source.value++;
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump();
      expect(sync.read(), 1);
    });

    testWidgets('a disposed sync no longer follows its source', (tester) async {
      final source = ValueNotifier<int>(0);
      addTearDown(source.dispose);
      var reads = 0;
      final sync = MorphFrameSync<int>(
        structure: () {
          reads++;
          return 0;
        },
        rebuild: (int _) {},
      );
      sync.follow(source);
      sync.dispose();
      source.value++;
      tester.binding.scheduleFrameCallback((Duration _) => source.value++);
      await frame(tester);
      expect(reads, 0);
      stop();
    });

    testWidgets('reads the motion of the frame, not of the frame before', (
      tester,
    ) async {
      // The source ticks before the motion it reads: a read at the
      // source's notification would see the motion one frame late.
      final source = motion(tester);
      final moving = motion(tester);
      final read = <double>[];
      final sync = MorphFrameSync<int>(
        structure: () {
          read.add(moving.value);
          return 0;
        },
        rebuild: (int _) {},
      );
      addTearDown(sync.dispose);
      sync.read();
      sync.follow(source);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MorphLiveOpacity(
            live: sync,
            opacityOf: () => moving.value,
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      );
      source.forward();
      moving.forward();
      read.clear();
      for (var i = 0; i < 5; i++) {
        await frame(tester);
        expect(read.last, moving.value);
        expect(
          tester
              .renderObject<RenderOpacity>(find.byType(MorphLiveOpacity))
              .opacity,
          moving.value,
        );
      }
      expect(read, hasLength(5));
      stop();
    });
  });

  group('MorphGlassHost following a MorphFrameSync', () {
    MorphGlassSurface track() => const MorphGlassSurface(
      kind: MorphGlassKind.track,
      shape: RRect.fromLTRBXY(0, 0, 300, 60, 30, 30),
      color: Color(0xFFE5E5EA),
      brightness: Brightness.light,
      glass: false,
    );

    MorphGlassSurface lens(double left) => MorphGlassSurface(
      kind: MorphGlassKind.lens,
      shape: RRect.fromLTRBXY(left, 4, left + 100, 56, 26, 26),
      color: const Color(0xFFFFFFFF),
      brightness: Brightness.light,
      lift: 1,
      optics: MorphGlassOptics.large,
    );

    Future<
      ({
        AnimationController moving,
        AnimationController source,
        StateSetter update,
        int Function() reads,
        double Function() left,
      })
    >
    pumpHost(WidgetTester tester) async {
      final source = motion(tester);
      final moving = motion(tester);
      final sync = MorphFrameSync<int>(structure: () => 0, rebuild: (int _) {});
      addTearDown(sync.dispose);
      sync.read();
      sync.follow(source);
      var reads = 0;
      late StateSetter update;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 300,
              height: 60,
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
                  update = setState;
                  return MorphGlassHost(
                    painter: const GlassBuiltInPainter(),
                    mode: MorphGlassMode.layer,
                    frames: sync,
                    frame: () {
                      reads++;
                      return MorphGlassFrame([
                        track(),
                        lens(10 + 100 * moving.value),
                      ]);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
      source.forward();
      moving.forward();
      return (
        moving: moving,
        source: source,
        update: update,
        reads: () => reads,
        left: () =>
            tester.getRect(find.byType(LiquidGlass).last).left -
            tester.getRect(find.byType(MorphGlassHost)).left,
      );
    }

    testWidgets('builds nothing on a frame that keeps the structure and '
        'draws the motion of that frame', (tester) async {
      final host = await pumpHost(tester);
      final built = <Type>[];
      debugOnRebuildDirtyWidget = (Element element, bool _) {
        built.add(element.widget.runtimeType);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      final start = host.reads();
      for (var i = 1; i <= 5; i++) {
        await frame(tester);
        expect(host.left(), moreOrLessEquals(10 + 100 * host.moving.value));
        expect(host.reads() - start, i);
      }
      debugOnRebuildDirtyWidget = null;
      expect(built, isEmpty);
      stop();
    });

    testWidgets('builds once under a dirty ancestor', (tester) async {
      final host = await pumpHost(tester);
      await frame(tester);
      final built = <Type>[];
      debugOnRebuildDirtyWidget = (Element element, bool _) {
        built.add(element.widget.runtimeType);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      final start = host.reads();
      tester.binding.scheduleFrameCallback((Duration _) => host.update(() {}));
      await frame(tester);
      debugOnRebuildDirtyWidget = null;
      expect(built.where((Type t) => t == MorphGlassHost), hasLength(1));
      expect(host.reads() - start, 1);
      expect(host.left(), moreOrLessEquals(10 + 100 * host.moving.value));
      stop();
    });
  });
}
