import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// The Android screenshot path talks to the plugin's channel directly.
// ignore: implementation_imports
import 'package:integration_test/src/channel.dart';
import 'package:material_ui/material_ui.dart';
// The audit times the package's outline fusion on the device.
// ignore: implementation_imports
import 'package:morph/src/glass/renderer/internal/blur_reach.dart'
    show debugMorphHalfResolutionBlur;
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_container.dart';
// ignore: implementation_imports
import 'package:morph/src/widgets/glass_outline.dart';
// ignore: implementation_imports
import 'package:morph/src/widgets/menu_fusion.dart';
// ignore: implementation_imports
import 'package:morph/src/widgets/scroll_edge_effect.dart'
    show debugMorphEdgeEffectBoundsBlur;
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

import 'support/layer_census.dart';

/// The glass audit on a device: the gallery in dark mode, the states the
/// UIKit references in tool/ios_reference/references/dark show (resting
/// and held), screenshots of each, and the frame timings of every scene
/// while its glass moves.
///
/// Build it as a profile app (`flutter build ios --profile -t
/// integration_test/glass_audit_test.dart`), launch it with devicectl and
/// pull `tmp/glass/` from the app's data container. The glass tier is the
/// gallery's: `--dart-define=GALLERY_GLASS=liquid` (or fake, flat)
/// pins it for the whole run; the report also times the package's outline
/// fusion (the menu's blurred silhouette and a bar's fused capsules) and
/// whether the liquid tier is available at all (`liquid_available`: false
/// means every liquid shot is the fake glass fallback), and
/// `--dart-define=AUDIT_OUTLINES_ONLY=true` times only that.
/// `--dart-define=AUDIT_RUNS=5` repeats every timed gesture five times
/// (screenshots are taken once, never inside a timed window); the report
/// keeps each run and the median of the runs' percentiles. Percentiles
/// are over ACTIVE frames (build or raster above 0.3 ms), so idle frames
/// pumped while a scene settles do not dilute them.
/// `--dart-define=AUDIT_LIGHT=true` runs it in light, for the references
/// in tool/ios_reference/references/light (on the simulator for colors and
/// layout: `flutter test integration_test/glass_audit_test.dart -d <sim>`,
/// with `--dart-define=AUDIT_OUT=<absolute host path>`, since the simulator
/// app and its tmp are removed after the run).
///
/// The app runs without the semantics tree, as for a user without
/// VoiceOver (a test binding builds it by default, which cost up to 1.3 ms
/// of the UI thread per frame on the menu and controls scenes);
/// `--dart-define=AUDIT_SEMANTICS=true` measures with it.
///
/// On Android (tool/ios_reference/perf/audit_android.sh) it is a profile
/// APK with `AUDIT_OUT` in the app's external files directory; each
/// screenshot goes through the integration_test plugin's image view.
/// `--dart-define=AUDIT_SHOTS=false` skips the screenshots and
/// `--dart-define=AUDIT_SCENES=menu,controls` runs only the named scenes.
/// The report also carries the frame budget - the measured cadence, the
/// 10th percentile of the intervals between frames' vsync starts, not the
/// refresh rate the display reports - and the frames over it
/// (`over_budget`), p99s, why the liquid tier is unavailable, the device
/// class and the tier drawn at the end (`GALLERY_GLASS=auto` picks it by
/// the device class), the precache time,
/// and `first_use`: each scene's frames from entering its page to its
/// first timed run (home-scroll's start at runApp, the first glass frame).
///
/// Every timed run is bracketed by two zero-length timeline slices,
/// `scene:<name>:<run>:begin` and `...:end`, so a systrace capture of the
/// run (tool/ios_reference/perf/trace_android.sh) windows its slices by
/// scene (`atrace_slices.py <trace> --scenes`); the report keeps the same
/// windows on the timeline clock (`windows_us`, CLOCK_MONOTONIC on Android),
/// so the kernel's GPU work periods of a run with `AUDIT_GPUWORK=1` split by
/// scene (`gpu_scenes.py`).
/// `--dart-define=AUDIT_CENSUS=true` also counts the engine layers of
/// every frame inside those windows (support/layer_census.dart) into the
/// report's `census`; `AUDIT_CENSUS_OWNERS=true` names the owner of every
/// backdrop filter there too.
/// `--dart-define=AUDIT_IDLE_S=60` holds the gallery home still for that
/// many seconds after launch with no frames scheduled (the `idle` window
/// of `windows_us`), then for half as long under the live binding, which
/// schedules a frame after every frame (`idle-frames`), and counts the
/// frames of both in `idle_frames`; perf/energy_android.sh splits the
/// phone's power rails by these windows. `--dart-define=FUSION_PREFETCH=false`
/// (or true) overrides whether the menu fuses ahead on its workers; the
/// report counts the outlines served ahead and fused in the frame.
/// `--dart-define=AUDIT_STAGES_OFF=true` keeps the package's own glass
/// containers (a list section's, a search toolbar's) closed, every member in
/// its own layer: the reference a stage is measured against.
/// `--dart-define=AUDIT_LEGACY_BLURS=true` draws the small blurs as before
/// 2026-10-06: the edge effect blurring the whole pass behind it, a frost
/// just below Impeller's half resolution blur as given.
/// The audit holds the app in portrait: a phone lying
/// on its side with auto-rotate on would otherwise lay the gallery out in
/// landscape, where the later rows are off screen.
const bool _light = bool.fromEnvironment('AUDIT_LIGHT');

const int _runs = int.fromEnvironment('AUDIT_RUNS', defaultValue: 1);

const bool _semantics = bool.fromEnvironment('AUDIT_SEMANTICS');

const bool _shots = bool.fromEnvironment('AUDIT_SHOTS', defaultValue: true);

const String _scenesOnly = String.fromEnvironment('AUDIT_SCENES');

const bool _census = bool.fromEnvironment('AUDIT_CENSUS');

const bool _censusOwners = bool.fromEnvironment('AUDIT_CENSUS_OWNERS');

const bool _atlas = bool.fromEnvironment('AUDIT_ATLAS');

const int _idleSeconds = int.fromEnvironment('AUDIT_IDLE_S');

const bool _stagesOff = bool.fromEnvironment('AUDIT_STAGES_OFF');

const bool _legacyBlurs = bool.fromEnvironment('AUDIT_LEGACY_BLURS');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('glass audit', semanticsEnabled: _semantics, (
    WidgetTester tester,
  ) async {
    final audit = _Audit(binding, tester);
    binding.platformDispatcher.platformBrightnessTestValue = _light
        ? .light
        : .dark;
    SchedulerBinding.instance.addTimingsCallback(audit.timings.addAll);
    // ignore: invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
    if (_stagesOff) debugMorphGlassStagesOpen = false;
    if (_legacyBlurs) {
      // ignore: invalid_use_of_visible_for_testing_member
      debugMorphEdgeEffectBoundsBlur = false;
      // ignore: invalid_use_of_visible_for_testing_member
      debugMorphHalfResolutionBlur = false;
    }
    if (const bool.hasEnvironment('FUSION_PREFETCH')) {
      // ignore: invalid_use_of_internal_member
      MorphMenuFusion.debugPrefetch = const bool.fromEnvironment(
        'FUSION_PREFETCH',
      );
    }
    await audit.run();
    File('${_Audit.outDir.path}/report.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(audit.report()),
    );
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
  });
}

class _Audit {
  _Audit(this.binding, this.tester);

  static final Directory outDir = Directory(
    const String.fromEnvironment('AUDIT_OUT').isEmpty
        ? '${Directory.systemTemp.path}/glass'
        : const String.fromEnvironment('AUDIT_OUT'),
  );

  final IntegrationTestWidgetsFlutterBinding binding;
  final WidgetTester tester;
  final List<ui.FrameTiming> timings = [];
  final Map<String, List<(int, int)>> _scenes = {};
  final Stopwatch _clock = Stopwatch();
  int _pointer = 300;

  final Map<String, int> _idleFrames = {};

  Future<void> settle([int ms = 900]) =>
      tester.pump(Duration(milliseconds: ms));

  Future<void> shot(String name) async {
    if (!_shots) return;
    await tester.pump();
    if (Platform.isAndroid) {
      await _androidShot(name);
      return;
    }
    final data = await binding.callbackManager.takeScreenshot(name);
    final bytes = (data['bytes']! as List<Object?>).cast<int>();
    File('${outDir.path}/$name.png').writeAsBytesSync(bytes);
  }

  Future<void> _androidShot(String name) async {
    integrationTestChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'scheduleFrame') {
        ui.PlatformDispatcher.instance.scheduleFrame();
      }
      return null;
    });
    await integrationTestChannel.invokeMethod<void>(
      'convertFlutterSurfaceToImage',
    );
    await tester.pump();
    final bytes = await integrationTestChannel.invokeMethod<List<int>>(
      'captureScreenshot',
      <String, Object?>{'name': name},
    );
    await integrationTestChannel.invokeMethod<void>('revertFlutterImage');
    await tester.pump();
    if (bytes != null) File('${outDir.path}/$name.png').writeAsBytesSync(bytes);
  }

  final Map<String, (int, int)> _firstUse = {};
  int _enteredAt = 0;
  double _precacheMs = 0;

  final Set<bool> _semanticsWhileTimed = {};

  final LayerCensus? _layerCensus = _census
      ? LayerCensus(owners: _censusOwners)
      : null;

  final Map<String, List<List<int>>> _windowsUs = {};

  void _sceneMark(String scene, int run, String edge) {
    developer.Timeline.startSync('scene:$scene:$run:$edge');
    developer.Timeline.finishSync();
    final windows = _windowsUs[scene] ??= [];
    if (edge == 'begin') {
      windows.add([developer.Timeline.now, 0]);
    } else if (windows.isNotEmpty) {
      windows.last[1] = developer.Timeline.now;
    }
    if (edge == 'begin') {
      _layerCensus?.begin(scene);
    } else {
      _layerCensus?.end();
    }
  }

  final Map<String, List<Map<String, Object?>>> _atlasRuns = {};
  final List<(int, String)> _marks = [];

  void mark(String what) {
    if (_atlas) _marks.add((developer.Timeline.now, what));
  }

  Future<void> measure(String scene, Future<void> Function() body) async {
    for (var run = 0; run < _runs; run++) {
      _semanticsWhileTimed.add(SemanticsBinding.instance.semanticsEnabled);
      await settle(300);
      final start = timings.length;
      if (run == 0) _firstUse[scene] = (_enteredAt, start);
      _sceneMark(scene, run, 'begin');
      var end = start;
      var from = 0;
      Future<void> timed() async {
        from = developer.Timeline.now;
        _marks.clear();
        await body();
        await settle(300);
        await tester.pump();
        await settle(100);
        end = timings.length;
      }

      if (_atlas) {
        final trace = await binding.traceTimeline(
          timed,
          streams: const ['Embedder'],
        );
        (_atlasRuns[scene] ??= []).add(
          _atlasCounts(
            (trace.json?['traceEvents'] as List<Object?>?) ?? const [],
            from,
          ),
        );
      } else {
        await timed();
      }
      _sceneMark(scene, run, 'end');
      (_scenes[scene] ??= []).add((start, end));
    }
  }

  /// The glyph atlas work of one timed run: Impeller's CreateGlyphAtlas
  /// (every frame with text), UpdateAtlasBitmap (a frame that rasterizes
  /// glyphs the atlas does not hold yet) and the frames drawn, with the
  /// time of every update after the run's start and the run's gesture
  /// marks on the same clock.
  Map<String, Object?> _atlasCounts(List<Object?> events, int from) {
    final open = <(int, String), List<int>>{};
    final totals = <String, List<double>>{};
    final updates = <double>[];
    var first = 1 << 62;
    var last = 0;
    for (final event in events) {
      if (event is! Map<String, Object?>) continue;
      final json = event;
      final name = json['name'] as String?;
      final ph = json['ph'] as String?;
      final ts = (json['ts'] as num?)?.toInt();
      final tid = (json['tid'] as num?)?.toInt() ?? 0;
      if (name == null || ts == null) continue;
      if (name == 'GPURasterizer::Draw') {
        first = math.min(first, ts);
        last = math.max(last, ts);
      }
      void close(int begin, int finish) {
        final ms = (finish - begin) / 1000;
        (totals[name] ??= []).add(ms);
        if (name == 'UpdateAtlasBitmap') updates.add((begin - from) / 1000);
      }

      switch (ph) {
        case 'X':
          close(ts, ts + ((json['dur'] as num?)?.toInt() ?? 0));
        case 'B':
          (open[(tid, name)] ??= []).add(ts);
        case 'E':
          final stack = open[(tid, name)];
          if (stack != null && stack.isNotEmpty) close(stack.removeLast(), ts);
        case _:
      }
    }
    Map<String, double> of(String name) {
      final v = totals[name] ?? const <double>[];
      return {
        'count': v.length.toDouble(),
        'ms': v.fold(0.0, (double a, double b) => a + b),
        'max_ms': v.fold(0.0, math.max),
      };
    }

    final seconds = last > first ? (last - first) / 1e6 : 0.0;
    updates.sort();
    return {
      'seconds': seconds,
      'frames': of('GPURasterizer::Draw')['count'],
      'create': of('CreateGlyphAtlas'),
      'update': of('UpdateAtlasBitmap'),
      'append': of('AppendToExistingAtlas'),
      'updates_per_s': seconds > 0 ? updates.length / seconds : 0.0,
      'update_at_ms': updates,
      'marks': [
        for (final (t, what) in _marks) [(t - from) / 1000, what],
      ],
    };
  }

  Future<void> finger(
    Offset from,
    List<Offset> path, {
    Duration holdBefore = const Duration(milliseconds: 16),
    Future<void> Function()? whileHeld,
    Duration step = const Duration(milliseconds: 8),
  }) async {
    final gesture = await tester.createGesture(pointer: _pointer++);
    mark('down');
    await gesture.down(from, timeStamp: _clock.elapsed);
    await tester.pump(holdBefore);
    for (final p in path) {
      await gesture.moveTo(p, timeStamp: _clock.elapsed);
      await tester.pump(step);
    }
    if (whileHeld != null) await whileHeld();
    mark('up');
    await gesture.up(timeStamp: _clock.elapsed);
    await tester.pump();
  }

  static List<Offset> line(Offset a, Offset b, int n) => [
    for (var i = 1; i <= n; i++) Offset.lerp(a, b, i / n)!,
  ];

  Offset textIn(Finder scope, String text) => tester.getCenter(
    find.descendant(of: scope, matching: find.text(text)).first,
  );

  Future<void> open(String title) async {
    await settle(300);
    final entry = find.text(title);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    if (!(Offset.zero & screen).deflate(40).contains(tester.getCenter(entry))) {
      await tester.ensureVisible(entry);
      await settle(300);
    }
    _enteredAt = timings.length;
    await tester.tap(find.text(title));
    await settle(800);
  }

  Future<void> back() async {
    final semantics = _semantics ? null : tester.ensureSemantics();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Back').last);
    semantics?.dispose();
    await settle(800);
  }

  Future<void> run() async {
    if (outDir.existsSync()) outDir.deleteSync(recursive: true);
    outDir.createSync(recursive: true);
    _clock.start();
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (_outlinesOnly) {
      _outlines();
      return;
    }
    final precache = Stopwatch();
    precache.start();
    await MorphGlassRenderer.precache();
    _precacheMs = precache.elapsedMicroseconds / 1000;
    _enteredAt = timings.length;
    runApp(const GalleryApp());
    await settle(1500);
    if (_idleSeconds > 0) {
      await settle(300);
      final policy = binding.framePolicy;
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmark;
      await Future<void>.delayed(const Duration(seconds: 2));
      var before = timings.length;
      _sceneMark('idle', 0, 'begin');
      // ignore: use_named_constants
      await Future<void>.delayed(const Duration(seconds: _idleSeconds));
      _sceneMark('idle', 0, 'end');
      binding.framePolicy = policy;
      await tester.pump();
      await settle(300);
      _idleFrames['idle'] = timings.length - before;
      before = timings.length;
      _sceneMark('idle-frames', 0, 'begin');
      await settle(_idleSeconds * 500);
      _sceneMark('idle-frames', 0, 'end');
      _idleFrames['idle-frames'] = timings.length - before;
    }
    for (final (name, scene) in [
      ('home-scroll', _homeScroll),
      ('segmented', _segmented),
      ('tab-bar', _tabBar),
      ('controls', _controls),
      ('menu', _menu),
      ('sheet', _sheet),
      ('list', _list),
    ]) {
      if (_scenesOnly.isEmpty || _scenesOnly.split(',').contains(name)) {
        await scene();
      }
    }
    _outlines();
  }

  final Map<String, double> _outlineMicros = {};

  /// Whether the run only times the outlines
  /// (`--dart-define=AUDIT_OUTLINES_ONLY=true`).
  static const bool _outlinesOnly = bool.fromEnvironment('AUDIT_OUTLINES_ONLY');

  /// Times the fused outlines the package computes per frame while a
  /// menu morphs (blurred, and its plain union below a 1 pt fusion
  /// radius) or bar capsules pass close: the mean of 100 calls each,
  /// on shapes that move a little every call so nothing is reused.
  ///
  /// Every case runs twice. The first pass (`-cold`) pays one-time work
  /// that lands on whichever case comes first - after the timed scenes
  /// ~45 ms on the device, the 4 pt menu read 1.13 instead of 0.67 ms -
  /// so the steady numbers are the second pass.
  void _outlines() {
    double time(void Function(int i) body) {
      final watch = Stopwatch();
      watch.start();
      for (var i = 0; i < 100; i++) {
        body(i);
      }
      return watch.elapsedMicroseconds / 100;
    }

    for (final pass in ['-cold', '']) {
      for (final radius in [4.0, 10.0, 20.0]) {
        _outlineMicros['menu10-r${radius.round()}$pass'] = time(
          // ignore: invalid_use_of_internal_member
          (i) => morphMenuSilhouette(
            RRect.fromLTRBXY(70, 200 + i * 0.01, 330, 640, 32, 32),
            const RRect.fromLTRBXY(177, 652, 225, 700, 24, 24),
            radius,
          ),
        );
      }
      _outlineMicros['union$pass'] = time(
        // ignore: invalid_use_of_internal_member
        (i) => morphGlassContainerOutline([
          RRect.fromLTRBXY(70, 100 + i * 0.01, 330, 700, 26, 26),
          const RRect.fromLTRBXY(177, 100, 225, 148, 24, 24),
        ], 0),
      );
      _outlineMicros['bar-capsules$pass'] = time(
        // ignore: invalid_use_of_internal_member
        (i) => morphGlassContainerOutline([
          RRect.fromLTRBXY(16 + i * 0.01, 60, 160, 104, 22, 22),
          const RRect.fromLTRBXY(166, 60, 210, 104, 22, 22),
        ], 12),
      );
    }
  }

  Future<void> _segmented() async {
    await open('Segmented control');
    await shot('segmented-resting');
    final three = find.byType(MorphSegmentedControl).at(1);
    await finger(
      textIn(three, 'A'),
      const [],
      holdBefore: const Duration(milliseconds: 500),
      whileHeld: () => shot('segmented-held-selected'),
    );
    await settle();
    await tap(textIn(three, 'B'));
    await settle();
    await finger(
      textIn(three, 'B'),
      const [],
      holdBefore: const Duration(milliseconds: 500),
      whileHeld: () => shot('segmented-held-middle'),
    );
    await settle();
    await measure('segmented', () async {
      final a = textIn(three, 'A');
      final c = textIn(three, 'C');
      for (var i = 0; i < 3; i++) {
        await finger(a, [
          ...line(a, c, 40),
          ...line(c, a, 40),
        ], holdBefore: const Duration(milliseconds: 120));
        await settle(500);
      }
    });
    await back();
  }

  Future<void> _tabBar() async {
    await open('Tab bar');
    await tap(textIn(find.byType(MorphSegmentedControl).first, '3'));
    await settle();
    final bar = find.byType(MorphTabBar);
    await shot('tabbar3-resting');
    await finger(
      textIn(bar, 'Library'),
      const [],
      holdBefore: const Duration(milliseconds: 500),
      whileHeld: () => shot('tabbar3-held-other'),
    );
    await settle();
    await finger(
      textIn(bar, 'Home'),
      const [],
      holdBefore: const Duration(milliseconds: 500),
      whileHeld: () => shot('tabbar3-held-selected'),
    );
    await settle();
    final list = find.byType(CustomScrollView).last;
    await tester.fling(list, const Offset(0, -500), 1500);
    await settle(1200);
    await finger(
      textIn(bar, 'Home'),
      const [],
      holdBefore: const Duration(milliseconds: 500),
      whileHeld: () => shot('tabbar3-held-over-content'),
    );
    await settle();
    await measure('tab-bar', () async {
      final home = textIn(bar, 'Home');
      final radio = textIn(bar, 'Radio');
      for (var i = 0; i < 3; i++) {
        await finger(home, [
          ...line(home, radio, 50),
          ...line(radio, home, 50),
        ], holdBefore: const Duration(milliseconds: 150));
        await settle(500);
      }
    });
    await tester.fling(list, const Offset(0, 2000), 3000);
    await settle(1200);
    await tap(textIn(find.byType(MorphSegmentedControl).first, '4'));
    await settle();
    await back();
  }

  Future<void> tap(Offset at) =>
      finger(at, const [], holdBefore: const Duration(milliseconds: 60));

  Future<void> _controls() async {
    await open('Controls');
    await shot('controls-resting');
    final off = find.byType(MorphSwitch).at(0);
    final r = tester.getRect(off);
    final knob = tester.widget<MorphSwitch>(off).value
        ? Offset(r.right - 20, r.center.dy)
        : Offset(r.left + 20, r.center.dy);
    await finger(
      knob,
      const [],
      holdBefore: const Duration(milliseconds: 500),
      whileHeld: () => shot('switch-knob-held'),
    );
    await settle();
    final wide = find.byType(MorphSlider).at(0);
    final w = tester.getRect(wide);
    final v = tester.widget<MorphSlider>(wide).value;
    final thumb = Offset(w.left + 18.5 + v * (w.width - 37), w.center.dy);
    await finger(
      thumb,
      line(thumb, thumb + const Offset(-40, 0), 10),
      holdBefore: const Duration(milliseconds: 300),
      step: const Duration(milliseconds: 16),
      whileHeld: () => shot('slider-thumb-held'),
    );
    await settle();
    await measure('controls', () async {
      final s = tester.getRect(off);
      for (var i = 0; i < 2; i++) {
        await finger(s.center, [
          ...line(s.center, s.centerLeft, 10),
          ...line(s.centerLeft, s.centerRight, 20),
        ], holdBefore: const Duration(milliseconds: 120));
        await settle(500);
      }
      final t = Offset(
        w.left + 18.5 + tester.widget<MorphSlider>(wide).value * (w.width - 37),
        w.center.dy,
      );
      await finger(
        t,
        [
          ...line(t, w.centerLeft, 30),
          ...line(w.centerLeft, w.centerRight, 60),
        ],
        holdBefore: const Duration(milliseconds: 120),
        step: const Duration(milliseconds: 16),
      );
      await settle(600);
    });
    await back();
  }

  Future<void> _menu() async {
    await open('Menu');
    await shot('menu-resting');
    final tall = find.byWidgetPredicate(
      (Widget w) => w is MorphMenuButton && w.items.length == 10,
    );
    await tap(tester.getCenter(tall));
    await settle(900);
    await shot('menu-tall-open');
    timeDilation = 10;
    await tap(const Offset(20, 300));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      await shot('menu-tall-close-$i');
    }
    timeDilation = 1;
    await settle(1500);
    final button = find.byType(MorphMenuButton).at(1);
    await tap(tester.getCenter(button));
    await settle(900);
    await shot('menu-open');
    await tap(const Offset(20, 300));
    await settle(1500);
    await measure('menu', () async {
      for (var i = 0; i < 2; i++) {
        await tap(tester.getCenter(button));
        await settle(900);
        await tap(const Offset(20, 300));
        await settle(900);
      }
    });
    await back();
  }

  Future<void> _homeScroll() async {
    final list = find.byType(CustomScrollView).last;
    final center = tester.getCenter(list);
    await measure('home-scroll', () async {
      for (var i = 0; i < 2; i++) {
        await finger(center, line(center, center - const Offset(0, 300), 40));
        await settle(900);
        await finger(
          center - const Offset(0, 200),
          line(
            center - const Offset(0, 200),
            center + const Offset(0, 200),
            40,
          ),
        );
        await settle(900);
      }
    });
    await finger(
      center,
      line(center, center - const Offset(0, 150), 20),
      whileHeld: () => shot('home-scroll-held'),
    );
    await settle(900);
    await shot('home-scrolled');
    await finger(
      center - const Offset(0, 150),
      line(center - const Offset(0, 150), center + const Offset(0, 250), 20),
    );
    await settle(900);
  }

  Future<void> _list() async {
    await open('Lists');
    await shot('list-resting');
    await finger(
      tester.getCenter(find.text('Weather')),
      const [],
      holdBefore: const Duration(milliseconds: 500),
      whileHeld: () => shot('list-row-held'),
    );
    await settle();
    final page = find.byType(CustomScrollView).last;
    final center = tester.getCenter(page);
    await measure('list', () async {
      for (var i = 0; i < 2; i++) {
        await finger(center, line(center, center - const Offset(0, 300), 40));
        await settle(900);
        await finger(
          center - const Offset(0, 200),
          line(
            center - const Offset(0, 200),
            center + const Offset(0, 200),
            40,
          ),
        );
        await settle(900);
      }
    });
    await back();
  }

  Future<void> _sheet() async {
    await open('Sheets');
    await tap(tester.getCenter(find.text('Medium and large')));
    await settle(900);
    await shot('sheet-medium');
    await tap(const Offset(200, 80));
    await settle(1200);
    await measure('sheet', () async {
      for (var i = 0; i < 2; i++) {
        await tap(tester.getCenter(find.text('Medium and large')));
        await settle(900);
        await tap(const Offset(200, 80));
        await settle(900);
      }
    });
    await back();
  }

  Map<String, Object?> report() {
    final display = ui.PlatformDispatcher.instance.views.first.display;
    final rate = display.refreshRate > 0 ? display.refreshRate : 60.0;
    double ms(Duration d) => d.inMicroseconds / 1000;
    double pick(List<double> v, double q) =>
        v[math.min(v.length - 1, (v.length * q).floor())];
    final intervals = [
      for (var i = 1; i < timings.length; i++)
        (timings[i].timestampInMicroseconds(ui.FramePhase.vsyncStart) -
                timings[i - 1].timestampInMicroseconds(
                  ui.FramePhase.vsyncStart,
                )) /
            1000,
    ].where((double v) => v >= 4 && v <= 50).toList();
    intervals.sort();
    final cadence = intervals.length < 8 ? 1000 / rate : pick(intervals, 0.1);
    final budget = cadence;
    final glass = find.byType(MorphScope);
    final drawn = glass.evaluate().isEmpty
        ? null
        : MorphAdaptiveGlass.tierOf(tester.element(glass.first));
    double median(List<double> v) {
      final sorted = [...v];
      sorted.sort();
      return sorted[sorted.length ~/ 2];
    }

    Map<String, double>? stats(List<ui.FrameTiming> all) {
      final frames = [
        for (final f in all)
          if (ms(f.buildDuration) > 0.3 || ms(f.rasterDuration) > 0.3) f,
      ];
      if (frames.isEmpty) return null;
      List<double> sorted(double Function(ui.FrameTiming f) of) {
        final values = [for (final f in frames) of(f)];
        values.sort();
        return values;
      }

      final build = sorted((f) => ms(f.buildDuration));
      final raster = sorted((f) => ms(f.rasterDuration));
      final span = sorted((f) => ms(f.totalSpan));
      final vsync = sorted((f) => ms(f.vsyncOverhead));
      return {
        'n': frames.length.toDouble(),
        'build_p50': pick(build, 0.5),
        'build_p95': pick(build, 0.95),
        'build_worst': build.last,
        'raster_p50': pick(raster, 0.5),
        'raster_p95': pick(raster, 0.95),
        'raster_worst': raster.last,
        'span_p95': pick(span, 0.95),
        'vsync_p95': pick(vsync, 0.95),
        'over_8.3ms': [
          for (final f in frames)
            if (ms(f.buildDuration) > 8.3 || ms(f.rasterDuration) > 8.3) f,
        ].length.toDouble(),
        'build_p99': pick(build, 0.99),
        'raster_p99': pick(raster, 0.99),
        'over_budget': [
          for (final f in frames)
            if (ms(f.buildDuration) > budget || ms(f.rasterDuration) > budget)
              f,
        ].length.toDouble(),
      };
    }

    return {
      'tier': const String.fromEnvironment(
        'GALLERY_GLASS',
        defaultValue: 'auto',
      ),
      'liquid_available': MorphGlassRenderer.liquidAvailable,
      'liquid_unavailable_reason': MorphGlassRenderer.liquidUnavailableReason,
      'platform': Platform.operatingSystem,
      'refresh_rate': rate,
      'cadence_ms': cadence,
      'budget_ms': budget,
      'precache_ms': _precacheMs,
      'device_class': MorphAdaptiveGlass.deviceClass.name,
      'drawn_tier': drawn?.name,
      'first_use': {
        for (final MapEntry(key: scene, value: (start, end))
            in _firstUse.entries)
          scene: stats(timings.sublist(start, end)),
      },
      'semantics': [..._semanticsWhileTimed],
      'runs': _runs,
      'outline_us': _outlineMicros,
      'windows_us': _windowsUs,
      if (_idleSeconds > 0) 'idle_frames': _idleFrames,
      // ignore: invalid_use_of_internal_member
      'fusion_served_ahead': MorphMenuFusion.debugServedAhead,
      // ignore: invalid_use_of_internal_member
      'fusion_fused_here': MorphMenuFusion.debugFusedHere,
      if (_layerCensus case final census?) 'census': census.report(),
      if (_atlas)
        'atlas': {
          for (final MapEntry(key: scene, value: runs) in _atlasRuns.entries)
            scene: {
              'median': {
                for (final key in ['updates_per_s', 'frames', 'seconds'])
                  key: median([for (final r in runs) r[key]! as double]),
                'updates': median([
                  for (final r in runs)
                    (r['update']! as Map<String, double>)['count']!,
                ]),
                'update_ms': median([
                  for (final r in runs)
                    (r['update']! as Map<String, double>)['ms']!,
                ]),
                'create_ms_per_frame': median([
                  for (final r in runs)
                    (r['create']! as Map<String, double>)['ms']! /
                        math.max(1, r['frames']! as double),
                ]),
              },
              'runs': runs,
            },
        },
      for (final MapEntry(key: scene, value: windows) in _scenes.entries)
        scene: () {
          final runs = [
            for (final (start, end) in windows)
              ?stats(timings.sublist(start, end)),
          ];
          if (runs.isEmpty) return 'no frames';
          return {
            'median': {
              for (final key in runs.first.keys)
                key: median([for (final r in runs) r[key]!]),
            },
            'runs': runs,
          };
        }(),
    };
  }
}
