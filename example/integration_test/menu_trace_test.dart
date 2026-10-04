import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/widgets.dart';
import 'package:morph_example/gallery/gallery.dart';

/// Records the menu morph on a device: frame timings of every launch, a
/// timeline of two launches, and the painted geometry of both shapes on
/// every frame, written to `<tmp>/menu_trace_<TRACE_RUN>.json` for `devicectl` to
/// pull.
///
/// The button sits at the center of the screen with three rows, like the
/// probe's `center3` captures, so the geometry compares with them.
/// Run with `flutter drive --profile --driver test_driver/integration_test.dart
/// --target integration_test/menu_trace_test.dart`.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('menu trace', (WidgetTester tester) async {
    final trace = _Trace(binding, tester);
    await trace.run();
    File(
      '${Directory.systemTemp.path}/menu_trace_$_run.json',
    ).writeAsStringSync(jsonEncode(trace.report()));
    debugPrint('MENU TRACE ${trace.summary()}');
  });
}

const _scene = String.fromEnvironment('TRACE_SCENE', defaultValue: 'center');

const _run = String.fromEnvironment('TRACE_RUN', defaultValue: '0');

const _items = [
  MorphMenuItem(title: 'Copy', icon: Icons.copy),
  MorphMenuItem(title: 'Share', icon: Icons.ios_share),
  MorphMenuItem(title: 'Delete', icon: Icons.delete_outline, destructive: true),
];

class _TraceApp extends StatelessWidget {
  const _TraceApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
      builder: (BuildContext context, Widget? child) =>
          MorphScope(child: child!),
      home: const Scaffold(
        backgroundColor: Color(0xFF000000),
        body: Stack(
          children: [
            Positioned.fill(
              child: Center(child: MorphMenuButton(items: _items)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Trace {
  _Trace(this.binding, this.tester);

  final IntegrationTestWidgetsFlutterBinding binding;
  final WidgetTester tester;
  final List<ui.FrameTiming> _timings = [];
  final List<Map<String, Object?>> _events = [];
  final List<Map<String, Object?>> _frames = [];
  Map<String, Object?>? _timeline;
  bool _recording = false;
  RenderClipRRect? _menu;
  RenderBox? _source;
  RenderOpacity? _content;
  int _pointer = 1;

  void _timingsCallback(List<ui.FrameTiming> timings) =>
      _timings.addAll(timings);

  void _mark(String what) =>
      _events.add({'e': what, 't': developer.Timeline.now});

  Future<void> _tap(Offset at, int holdMs) async {
    final gesture = await tester.createGesture(pointer: _pointer++);
    _mark('down');
    await gesture.down(at);
    await tester.pump(Duration(milliseconds: holdMs));
    _mark('up');
    await gesture.up();
  }

  Future<void> _cycle(Offset button) async {
    await _tap(button, 130);
    await tester.pump(const Duration(milliseconds: 1500));
    await _tap(const Offset(50, 200), 66);
    await tester.pump(const Duration(milliseconds: 1600));
  }

  RenderBox? _glyph() {
    final glyphs = find
        .byWidgetPredicate(
          (Widget w) => w.runtimeType.toString() == '_Ellipsis',
        )
        .evaluate();
    return glyphs.isEmpty ? null : glyphs.last.renderObject as RenderBox?;
  }

  void _find() {
    final copy = find.text('Copy');
    if (copy.evaluate().isEmpty) {
      _menu = null;
      _content = null;
      _source = _glyph();
      return;
    }
    _source = _glyph();
    if (_menu?.attached ?? false) return;
    final clip = find.ancestor(of: copy.last, matching: find.byType(ClipRRect));
    _menu = clip.evaluate().first.renderObject! as RenderClipRRect;
    final opacity = find.ancestor(
      of: copy.last,
      matching: find.byType(Opacity),
    );
    _content = opacity.evaluate().first.renderObject! as RenderOpacity;
  }

  void _frame(Duration _) {
    if (!_recording) return;
    SchedulerBinding.instance.addPostFrameCallback(_frame);
    _find();
    final row = <String, Object?>{
      't': developer.Timeline.now,
      'v': SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds,
    };
    final menu = _menu;
    if (menu != null && menu.attached && menu.hasSize) {
      final rect = menu.localToGlobal(Offset.zero) & menu.size;
      final radius = (menu.borderRadius as BorderRadius).topLeft.x;
      row['G'] = [rect.left, rect.top, rect.width, rect.height, radius];
      row['a'] = _content?.opacity;
    }
    final source = _source;
    if (source != null && source.attached && source.hasSize) {
      final rect = source.localToGlobal(Offset.zero) & source.size;
      row['S'] = [rect.left, rect.top, rect.width, rect.height];
    }
    _frames.add(row);
  }

  Future<void> run() async {
    final Offset button;
    if (_scene == 'gallery') {
      runApp(const GalleryApp());
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Menu'));
      await tester.pump(const Duration(seconds: 1));
      final screen = (tester.view.physicalSize / tester.view.devicePixelRatio)
          .center(Offset.zero);
      final all = find.byType(MorphMenuButton).evaluate();
      button = all
          .map((Element e) {
            final box = e.renderObject! as RenderBox;
            return box.localToGlobal(box.size.center(Offset.zero));
          })
          .reduce(
            (a, b) => (a - screen).distance < (b - screen).distance ? a : b,
          );
    } else {
      runApp(const _TraceApp());
      await tester.pump(const Duration(seconds: 2));
      button = tester.getCenter(find.byType(MorphMenuButton));
    }
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    _events.add({
      'e': 'screen',
      'w': size.width,
      'h': size.height,
      'bx': button.dx,
      'by': button.dy,
      'scene': _scene,
      'hz': SchedulerBinding
          .instance
          .platformDispatcher
          .displays
          .first
          .refreshRate,
    });

    await _cycle(button);

    SchedulerBinding.instance.addTimingsCallback(_timingsCallback);
    _mark('timing');
    for (var i = 0; i < 6; i++) {
      await _cycle(button);
    }
    await tester.pump(const Duration(milliseconds: 500));
    SchedulerBinding.instance.removeTimingsCallback(_timingsCallback);

    _mark('geometry');
    _recording = true;
    SchedulerBinding.instance.addPostFrameCallback(_frame);
    for (var i = 0; i < 3; i++) {
      await _cycle(button);
    }
    _recording = false;
    _mark('timeline');
    try {
      final timeline = await binding.traceTimeline(() async {
        for (var i = 0; i < 2; i++) {
          await _cycle(button);
        }
      }, streams: const ['Dart', 'Embedder', 'GC']);
      _timeline = timeline.json;
    } on Object catch (error) {
      _events.add({'e': 'no timeline', 'error': '$error'});
    }

    await tester.pump(const Duration(milliseconds: 100));
  }

  Map<String, Object?> report() => {
    'events': _events,
    'timings': [
      for (final t in _timings)
        [
          t.timestampInMicroseconds(ui.FramePhase.vsyncStart),
          t.timestampInMicroseconds(ui.FramePhase.buildStart),
          t.timestampInMicroseconds(ui.FramePhase.buildFinish),
          t.timestampInMicroseconds(ui.FramePhase.rasterStart),
          t.timestampInMicroseconds(ui.FramePhase.rasterFinish),
        ],
    ],
    'frames': _frames,
    'timeline': _timeline,
  };

  String summary() {
    double ms(Duration d) => d.inMicroseconds / 1000;
    final over = [
      for (final t in _timings)
        if (ms(t.buildDuration) > 8.3 || ms(t.rasterDuration) > 8.3) t,
    ];
    final build = [for (final t in _timings) ms(t.buildDuration)];
    build.sort();
    final raster = [for (final t in _timings) ms(t.rasterDuration)];
    raster.sort();
    return 'frames ${_timings.length} over ${over.length} '
        'build worst ${build.isEmpty ? 0 : build.last} '
        'raster worst ${raster.isEmpty ? 0 : raster.last} '
        'geometry ${_frames.length}';
  }
}
