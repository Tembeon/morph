import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// The glass audit on a device: the gallery in dark mode, the states the
/// UIKit references in tool/ios_reference/references/dark show (resting
/// and held), screenshots of each, and the frame timings of every scene
/// while its glass moves.
///
/// Build it as a profile app (`flutter build ios --profile -t
/// integration_test/glass_audit_test.dart`), launch it with devicectl and
/// pull `tmp/glass/` from the app's data container.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('glass audit', (WidgetTester tester) async {
    final audit = _Audit(binding, tester);
    binding.platformDispatcher.platformBrightnessTestValue = .dark;
    SchedulerBinding.instance.addTimingsCallback(audit.timings.addAll);
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
    '${Directory.systemTemp.path}/glass',
  );

  final IntegrationTestWidgetsFlutterBinding binding;
  final WidgetTester tester;
  final List<ui.FrameTiming> timings = [];
  final Map<String, (int, int)> _scenes = {};
  final Stopwatch _clock = Stopwatch();
  int _pointer = 300;

  Future<void> settle([int ms = 900]) =>
      tester.pump(Duration(milliseconds: ms));

  Future<void> shot(String name) async {
    await tester.pump();
    final data = await binding.callbackManager.takeScreenshot(name);
    final bytes = (data['bytes']! as List<Object?>).cast<int>();
    File('${outDir.path}/$name.png').writeAsBytesSync(bytes);
  }

  Future<void> measure(String scene, Future<void> Function() body) async {
    await settle(300);
    final start = timings.length;
    await body();
    await settle(300);
    _scenes[scene] = (start, timings.length);
  }

  Future<void> finger(
    Offset from,
    List<Offset> path, {
    Duration holdBefore = const Duration(milliseconds: 16),
    Future<void> Function()? whileHeld,
    Duration step = const Duration(milliseconds: 8),
  }) async {
    final gesture = await tester.createGesture(pointer: _pointer++);
    await gesture.down(from, timeStamp: _clock.elapsed);
    await tester.pump(holdBefore);
    for (final p in path) {
      await gesture.moveTo(p, timeStamp: _clock.elapsed);
      await tester.pump(step);
    }
    if (whileHeld != null) await whileHeld();
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
    await tester.tap(find.text(title));
    await settle(800);
  }

  Future<void> back() async {
    await tester.pageBack();
    await settle(800);
  }

  Future<void> run() async {
    if (outDir.existsSync()) outDir.deleteSync(recursive: true);
    outDir.createSync(recursive: true);
    _clock.start();
    await LiquidGlass.precache();
    runApp(const GalleryApp());
    await settle(1500);
    await _segmented();
    await _tabBar();
    await _controls();
    await _menu();
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
    final list = find.byType(ListView);
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
    final button = find.byType(MorphMenuButton).at(1);
    await measure('menu', () async {
      for (var i = 0; i < 2; i++) {
        await tap(tester.getCenter(button));
        await settle(900);
        if (i == 0) await shot('menu-open');
        await tap(const Offset(20, 300));
        await settle(900);
      }
    });
    await back();
  }

  Map<String, Object?> report() {
    double ms(Duration d) => d.inMicroseconds / 1000;
    double pick(List<double> v, double q) =>
        v[math.min(v.length - 1, (v.length * q).floor())];
    return {
      for (final MapEntry(key: scene, value: (start, end)) in _scenes.entries)
        scene: () {
          final frames = timings.sublist(start, end);
          if (frames.isEmpty) return 'no frames';
          final build = [for (final f in frames) ms(f.buildDuration)];
          build.sort();
          final raster = [for (final f in frames) ms(f.rasterDuration)];
          raster.sort();
          return {
            'n': frames.length,
            'build_p50': pick(build, 0.5),
            'build_p95': pick(build, 0.95),
            'raster_p50': pick(raster, 0.5),
            'raster_p95': pick(raster, 0.95),
            'raster_worst': raster.last,
            'over_8.3ms': [
              for (final f in frames)
                if (ms(f.buildDuration) > 8.3 || ms(f.rasterDuration) > 8.3) f,
            ].length,
          };
        }(),
    };
  }
}
