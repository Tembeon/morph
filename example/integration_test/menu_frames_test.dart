// The harness reads the menu fusion's counters, package internals by design.
// ignore_for_file: invalid_use_of_internal_member, implementation_imports, invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:morph/src/widgets/menu_fusion.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart';

/// The menu scene of the glass audit frame by frame: every FrameTiming of
/// every timed run, the timeline of that run (the framework's BUILD,
/// LAYOUT, PAINT, COMPOSITING, SEMANTICS blocks, the GC stream and the
/// engine's frame slices) and the run's marks (each tap's down and up, and
/// every flight event of the menu), written to `<AUDIT_OUT>/report.json`.
/// tool/ios_reference/perf/menu_frames.py joins them into one row per
/// frame.
///
/// The scene is glass_audit_test's `menu`, step for step: the gallery's
/// Menu page in dark, the rich menu (the second MorphMenuButton) opened
/// and closed twice per run, semantics off. Build and run it through
/// audit_android.sh / audit.sh with
/// `AUDIT_TARGET=integration_test/menu_frames_test.dart
/// AUDIT_REPORT=menu_frames`; `GALLERY_GLASS` and `AUDIT_RUNS` as there.
/// `--dart-define=FRAMES_DETAIL=true` also profiles every widget build,
/// layout and paint (debugProfileBuildsEnabled and friends), which
/// attributes a heavy frame to widgets but inflates every frame.
/// `--dart-define=FUSION_PREFETCH=false` (or true) overrides whether the
/// menu fuses its next frame's silhouette ahead on the fusion worker; the
/// report counts the outlines served ahead and fused in the frame.
/// `--dart-define=FRAMES_CPU=true` adds the Dart CPU samples of the UI
/// thread inside each frame's build window: per run the functions of the
/// heaviest builds, and the functions of every frame whose build is over
/// a third of the budget, by inclusive and by self samples.
/// `--dart-define=FRAMES_SCENE=controls` profiles the glass audit's switch
/// and slider gestures with the same phase and CPU collection.
const String _scene = String.fromEnvironment(
  'FRAMES_SCENE',
  defaultValue: 'menu',
);

const int _runs = int.fromEnvironment('AUDIT_RUNS', defaultValue: 1);

const bool _detail = bool.fromEnvironment('FRAMES_DETAIL');

final List<List<double>> _fuses = [];

const bool _cpu = bool.fromEnvironment('FRAMES_CPU');

const Set<String> _phases = {
  'BUILD',
  'LAYOUT',
  'UPDATING COMPOSITING BITS',
  'PAINT',
  'COMPOSITING',
  'SEMANTICS',
  'FINALIZE TREE',
  'Animate',
  'POST_FRAME',
  'Frame',
};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('$_scene frames', semanticsEnabled: false, (
    WidgetTester tester,
  ) async {
    MorphMenuFusion.debugOnFuse = (frame, ready, {required served}) =>
        _fuses.add([...frame, ...?ready, if (served) 1 else 0]);
    if (const bool.hasEnvironment('FUSION_PREFETCH')) {
      MorphMenuFusion.debugPrefetch = const bool.fromEnvironment(
        'FUSION_PREFETCH',
      );
    }
    final out = Directory(
      const String.fromEnvironment('AUDIT_OUT').isEmpty
          ? '${Directory.systemTemp.path}/menu_frames'
          : const String.fromEnvironment('AUDIT_OUT'),
    );
    if (out.existsSync()) out.deleteSync(recursive: true);
    final frames = _Frames(binding, tester);
    binding.platformDispatcher.platformBrightnessTestValue = .dark;
    SchedulerBinding.instance.addTimingsCallback(frames.timings.addAll);
    await frames.run();
    out.createSync(recursive: true);
    File(
      '${out.path}/report.json',
    ).writeAsStringSync(jsonEncode(frames.report()));
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
  });
}

class _Frames {
  _Frames(this.binding, this.tester);

  final IntegrationTestWidgetsFlutterBinding binding;
  final WidgetTester tester;
  final List<ui.FrameTiming> timings = [];
  final List<Map<String, Object?>> _runsOut = [];
  List<List<Object>> _marks = [];
  final List<StreamSubscription<MorphFlightEvent>> _subscriptions = [];
  int _pointer = 300;
  bool _vmTrace = true;

  void _mark(String what) => _marks.add([developer.Timeline.now, what]);

  Future<void> settle(int ms) => tester.pump(Duration(milliseconds: ms));

  Future<void> tap(Offset at, String what) async {
    final gesture = await tester.createGesture(pointer: _pointer++);
    _mark('$what down');
    await gesture.down(at);
    await tester.pump(const Duration(milliseconds: 60));
    _mark('$what up');
    await gesture.up();
    await tester.pump();
  }

  void _listen() {
    for (final element in find.byType(MorphScope).evaluate()) {
      final scope = (element as StatefulElement).state as MorphScopeState;
      scope.lastFlight.addListener(() {
        final flight = scope.lastFlight.value;
        if (flight == null) return;
        _mark('flight launch-call');
        _subscriptions.add(
          flight.events.listen((MorphFlightEvent e) => _mark('flight $e')),
        );
      });
    }
  }

  Future<void> run() async {
    await MorphGlassRenderer.precache();
    runApp(const GalleryApp());
    await settle(1500);
    await settle(300);
    await tester.tap(find.text(_scene == 'controls' ? 'Controls' : 'Menu'));
    await settle(800);
    Future<void> Function() gesture;
    if (_scene == 'controls') {
      gesture = _controls;
      await gesture();
      await settle(1500);
    } else {
      _listen();
      final at = tester.getCenter(find.byType(MorphMenuButton).at(1));
      gesture = () async {
        for (var i = 0; i < 2; i++) {
          await tap(at, 'open');
          await settle(900);
          await tap(const Offset(20, 300), 'close');
          await settle(900);
        }
      };
      await tap(at, 'open');
      await settle(900);
      await tap(const Offset(20, 300), 'close');
      await settle(1500);
    }
    if (_detail) {
      debugProfileBuildsEnabled = true;
      debugProfileLayoutsEnabled = true;
      debugProfilePaintsEnabled = true;
    }
    for (var run = 0; run < _runs; run++) {
      await settle(300);
      final start = timings.length;
      _marks = [];
      if (_cpu) await _startCpu();
      final from = developer.Timeline.now;
      var end = start;
      Future<void> body() async {
        await gesture();
        await settle(300);
        await tester.pump();
        await settle(100);
        end = timings.length;
      }

      FlutterTimeline.debugCollectionEnabled = true;
      var events = const <Object?>[];
      String? traceError;
      if (_vmTrace) {
        try {
          final trace = await binding.traceTimeline(
            body,
            streams: const ['Dart', 'Embedder', 'GC'],
          );
          events = (trace.json?['traceEvents'] as List<Object?>?) ?? const [];
        } on Object catch (error) {
          _vmTrace = false;
          traceError = '$error'.split('\n').first;
          await body();
        }
      } else {
        await body();
      }
      final blocks = FlutterTimeline.debugCollect().timedBlocks;
      Map<String, Object?>? cpu;
      if (_cpu) {
        try {
          cpu = await _cpuOf(from, timings.sublist(start, end));
        } on Object catch (error) {
          cpu = {'error': '$error'.split('\n').first};
        }
      }
      FlutterTimeline.debugCollectionEnabled = false;
      _runsOut.add({
        'from': from,
        'marks': _marks,
        'timings': [
          for (final t in timings.sublist(start, end))
            [
              t.timestampInMicroseconds(ui.FramePhase.vsyncStart),
              t.timestampInMicroseconds(ui.FramePhase.buildStart),
              t.timestampInMicroseconds(ui.FramePhase.buildFinish),
              t.timestampInMicroseconds(ui.FramePhase.rasterStart),
              t.timestampInMicroseconds(ui.FramePhase.rasterFinish),
              t.frameNumber,
            ],
        ],
        'events': _keep(events),
        'trace_error': traceError,
        'cpu': cpu,
        'blocks': [
          for (final b in blocks) [b.name, b.start.round(), b.end.round()],
        ],
      });
    }
    debugProfileBuildsEnabled = false;
    debugProfileLayoutsEnabled = false;
    debugProfilePaintsEnabled = false;
    for (final s in _subscriptions) {
      await s.cancel();
    }
  }

  Future<void> _finger(
    Offset from,
    List<Offset> path,
    String label, {
    int step = 8,
  }) async {
    final gesture = await tester.createGesture(pointer: _pointer++);
    _mark('$label down');
    await gesture.down(from);
    await settle(120);
    _mark('$label move');
    for (final point in path) {
      await gesture.moveTo(point);
      await settle(step);
    }
    _mark('$label up');
    await gesture.up();
    await tester.pump();
  }

  List<Offset> _line(Offset a, Offset b, int n) => [
    for (var i = 1; i <= n; i++) Offset.lerp(a, b, i / n)!,
  ];

  Future<void> _controls() async {
    final off = find.byType(MorphSwitch).at(0);
    final s = tester.getRect(off);
    for (var i = 0; i < 2; i++) {
      await _finger(s.center, [
        ..._line(s.center, s.centerLeft, 10),
        ..._line(s.centerLeft, s.centerRight, 20),
      ], 'switch');
      await settle(500);
    }
    final wide = find.byType(MorphSlider).at(0);
    final w = tester.getRect(wide);
    final t = Offset(
      w.left + 18.5 + tester.widget<MorphSlider>(wide).value * (w.width - 37),
      w.center.dy,
    );
    await _finger(
      t,
      [
        ..._line(t, w.centerLeft, 30),
        ..._line(w.centerLeft, w.centerRight, 60),
      ],
      'slider',
      step: 16,
    );
    await settle(600);
  }

  vm.VmService? _service;

  Future<void> _startCpu() async {
    try {
      final service = _service ??= await vmServiceConnectUri(
        (await developer.Service.getInfo()).serverWebSocketUri!.toString(),
      );
      await service.setFlag('profile_period', '250');
      await service.setFlag('profiler', 'true');
      await service.clearCpuSamples(
        developer.Service.getIsolateId(Isolate.current)!,
      );
    } on Object catch (error) {
      _cpuError = '$error'.split('\n').first;
    }
  }

  String? _cpuError;

  Future<Map<String, Object?>> _cpuOf(
    int from,
    List<ui.FrameTiming> frames,
  ) async {
    final service = _service ??= await vmServiceConnectUri(
      (await developer.Service.getInfo()).serverWebSocketUri!.toString(),
    );
    final isolate = developer.Service.getIsolateId(Isolate.current)!;
    final samples = await service.getCpuSamples(
      isolate,
      from,
      developer.Timeline.now - from,
    );
    final functions = samples.functions ?? const <vm.ProfileFunction>[];
    String nameOf(int index) {
      final Object? f = functions[index].function;
      return switch (f) {
        vm.FuncRef(:final name, :final owner) => switch (owner) {
          vm.ClassRef(name: final c) => '$c.$name',
          vm.FuncRef(name: final o) => '$o.$name',
          _ => name ?? '?',
        },
        vm.NativeFunction(:final name) => 'native $name',
        _ => '$f',
      };
    }

    final budget =
        1e6 / ui.PlatformDispatcher.instance.views.first.display.refreshRate;
    final windows = [
      for (final t in frames)
        (
          t.timestampInMicroseconds(ui.FramePhase.buildStart),
          t.timestampInMicroseconds(ui.FramePhase.buildFinish),
          t.frameNumber,
        ),
    ];
    final heavy = [...windows];
    heavy.sort((a, b) => (b.$2 - b.$1).compareTo(a.$2 - a.$1));
    final top = heavy.take(8).map((w) => w.$3).toSet();
    final perFrame = <int, (Map<String, int>, Map<String, int>, int)>{};
    final allIncl = <String, int>{};
    final allSelf = <String, int>{};
    var allCount = 0;
    for (final sample in samples.samples ?? const <vm.CpuSample>[]) {
      final ts = sample.timestamp ?? 0;
      final stack = sample.stack ?? const <int>[];
      if (stack.isEmpty) continue;
      for (final (bs, bf, n) in windows) {
        if (ts < bs || ts > bf) continue;
        final heavyFrame = bf - bs > budget / 3;
        if (!heavyFrame && !top.contains(n)) break;
        final names = {for (final i in stack) nameOf(i)};
        final self = nameOf(stack.first);
        if (heavyFrame) {
          allCount++;
          allSelf[self] = (allSelf[self] ?? 0) + 1;
          for (final name in names) {
            allIncl[name] = (allIncl[name] ?? 0) + 1;
          }
        }
        if (top.contains(n)) {
          final entry = perFrame[n] ??= (<String, int>{}, <String, int>{}, 0);
          entry.$2[self] = (entry.$2[self] ?? 0) + 1;
          for (final name in names) {
            entry.$1[name] = (entry.$1[name] ?? 0) + 1;
          }
          perFrame[n] = (entry.$1, entry.$2, entry.$3 + 1);
        }
        break;
      }
    }
    List<List<Object>> best(Map<String, int> counts, int n) {
      final list = counts.entries.toList();
      list.sort((a, b) => b.value.compareTo(a.value));
      return [
        for (final e in list.take(n)) [e.key, e.value],
      ];
    }

    return {
      'start_error': _cpuError,
      'period_us': samples.samplePeriod,
      'heavy_samples': allCount,
      'heavy_incl': best(allIncl, 60),
      'heavy_self': best(allSelf, 40),
      'frames': {
        for (final MapEntry(key: n, value: (incl, self, count))
            in perFrame.entries)
          '$n': {
            'samples': count,
            'incl': best(incl, 40),
            'self': best(self, 20),
          },
      },
    };
  }

  List<List<Object?>> _keep(List<Object?> events) {
    final kept = <List<Object?>>[];
    for (final event in events) {
      if (event is! Map<String, Object?>) continue;
      final name = event['name'] as String?;
      final ph = event['ph'] as String?;
      final ts = event['ts'] as num?;
      if (name == null || ts == null || ph == null) continue;
      final cat = event['cat'] as String? ?? '';
      final dur = event['dur'] as num?;
      final wanted =
          _phases.contains(name) ||
          cat.contains('GC') ||
          name.startsWith('Animator') ||
          name.startsWith('Dart') ||
          _detail ||
          (dur != null && dur >= 300);
      if (!wanted) continue;
      if (ph != 'X' && ph != 'B' && ph != 'E' && ph != 'i' && ph != 'I') {
        continue;
      }
      kept.add([ph, name, ts, dur, event['tid'], cat]);
    }
    return kept;
  }

  Map<String, Object?> report() => {
    'scene': _scene,
    'tier': const String.fromEnvironment('GALLERY_GLASS', defaultValue: 'auto'),
    'liquid_available': MorphGlassRenderer.liquidAvailable,
    'platform': Platform.operatingSystem,
    'refresh_rate':
        ui.PlatformDispatcher.instance.views.first.display.refreshRate,
    'detail': _detail,
    'now_at_end': developer.Timeline.now,
    'fusion_prefetch': MorphMenuFusion.prefetches,
    'fusion_served_ahead': MorphMenuFusion.debugServedAhead,
    'fusion_fused_here': MorphMenuFusion.debugFusedHere,
    'fusion_calls': _fuses,
    'runs': _runsOut,
  };
}
