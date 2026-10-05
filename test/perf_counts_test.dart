import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_body_shadow.dart';
import 'package:morph/widgets.dart';

/// Deterministic per-frame work counters of representative scenes, the
/// cheap proxy for the device's frame cost (tool/audit/perf-research
/// section 4.2): widget rebuilds, render object paints, re-recorded
/// pictures, backdrop captures and offscreen layers per animated frame,
/// and frames scheduled after the scene settled.
///
/// The counts are pinned in test/fixtures/perf/counts.json as ceilings:
/// an optimization may lower them, nothing may raise them. Rewrite the
/// fixture with `PERF_COUNTS_UPDATE=true flutter test
/// test/perf_counts_test.dart` after a change that lowers a count.
///
/// flutter_test has no Impeller, so the liquid tier builds its real widget
/// and render tree but paints through the renderer's fallback: captures
/// are the fallback's, the widget and paint counts are the liquid tier's.
void main() {
  final fixture = File('test/fixtures/perf/counts.json');
  final update = Platform.environment['PERF_COUNTS_UPDATE'] == 'true';
  final pinned = fixture.existsSync()
      ? (jsonDecode(fixture.readAsStringSync()) as Map<String, Object?>)
      : <String, Object?>{};
  final results = <String, Object?>{};

  setUpAll(() => isLocalTest = true);
  tearDownAll(() {
    isLocalTest = false;
    const header =
        'scene                 frames builds paints pictures captures '
        'offscreen bodyShadows idle';
    final lines = <String>[header];
    for (final MapEntry(:key, :value) in results.entries) {
      final r = value! as Map<String, Object?>;
      lines.add(
        '${key.padRight(22)}${'${r['frames']}'.padLeft(6)}'
        '${'${r['builds']}'.padLeft(7)}${'${r['paints']}'.padLeft(7)}'
        '${'${r['pictures']}'.padLeft(9)}${'${r['captures']}'.padLeft(9)}'
        '${'${r['offscreen']}'.padLeft(10)}'
        '${'${r['bodyShadows']}'.padLeft(12)}${'${r['idle']}'.padLeft(5)}',
      );
    }
    debugPrint(lines.join('\n'));
    if (update) {
      fixture.parent.createSync(recursive: true);
      fixture.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(results)}\n',
      );
    }
  });

  for (final tier in MorphGlassTier.values) {
    for (final scene in _scenes) {
      final name = '${scene.name}/${tier.name}';
      testWidgets('perf counts: $name', (WidgetTester tester) async {
        tester.view.physicalSize = const Size(402, 874) * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(platform: TargetPlatform.iOS),
            builder: (BuildContext context, Widget? child) =>
                MorphAdaptiveGlass(tier: tier, child: child!),
            home: scene.build(),
          ),
        );
        await _settle(tester);
        final counter = _Counter(tester);
        counter.start();
        await scene.run(tester);
        counter.stop();
        await _settle(tester);
        final idle = await _idleFrames(tester);
        final result = counter.result(idle);
        results[name] = result;
        if (update) return;
        final ceiling = pinned[name] as Map<String, Object?>?;
        expect(ceiling, isNotNull, reason: 'no pinned counts for $name');
        for (final key in _pinnedKeys) {
          expect(
            result[key]! as num,
            lessThanOrEqualTo(ceiling![key]! as num),
            reason: '$name: $key rose above its pinned ceiling',
          );
        }
      });
    }
  }
}

const _pinnedKeys = [
  'builds',
  'paints',
  'pictures',
  'captures',
  'offscreen',
  'bodyShadows',
  'idle',
];

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 8),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 20),
);

/// Frames still scheduled during five quiet seconds after the scene
/// settled; anything above zero is a ticker or a rebuild loop that never
/// sleeps.
Future<int> _idleFrames(WidgetTester tester) async {
  var frames = 0;
  for (var i = 0; i < 600; i++) {
    if (!tester.binding.hasScheduledFrame) break;
    frames++;
    await tester.pump(const Duration(milliseconds: 8));
  }
  return frames;
}

class _Counter {
  _Counter(this.tester);

  final WidgetTester tester;
  int _frames = 0;
  int _builds = 0;
  int _paints = 0;
  int _pictures = 0;
  int _captures = 0;
  int _offscreen = 0;
  int _frameBuilds = 0;
  int _framePaints = 0;
  Set<ui.Picture> _seen = {};
  late final int _shadowStart;

  void start() {
    _shadowStart = MorphGlassBodyShadow.debugSaveLayerCount;
    debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
      _frameBuilds++;
    };
    debugOnProfilePaint = (RenderObject object) {
      _framePaints++;
    };
    _seen = _collectPictures(
      tester.binding.renderViews.first.debugLayer!,
    ).toSet();
    tester.binding.addPersistentFrameCallback(_onFrame);
    _active = true;
  }

  bool _active = false;

  void _onFrame(Duration _) {
    if (!_active) return;
    tester.binding.addPostFrameCallback((Duration _) {
      if (!_active) return;
      final root = tester.binding.renderViews.first.debugLayer!;
      final pictures = _collectPictures(root);
      final fresh = pictures.where((p) => !_seen.contains(p)).length;
      _seen = pictures.toSet();
      if (_frameBuilds == 0 && _framePaints == 0 && fresh == 0) return;
      _frames++;
      _builds += _frameBuilds;
      _paints += _framePaints;
      _pictures += fresh;
      final (captures, offscreen) = _layers(root);
      _captures += captures;
      _offscreen += offscreen;
      _frameBuilds = 0;
      _framePaints = 0;
    });
  }

  void stop() {
    _active = false;
    debugOnRebuildDirtyWidget = null;
    debugOnProfilePaint = null;
  }

  Map<String, Object?> result(int idle) {
    double per(int total) =>
        _frames == 0 ? 0 : (total / _frames * 10).roundToDouble() / 10;
    return {
      'frames': _frames,
      'builds': per(_builds),
      'paints': per(_paints),
      'pictures': per(_pictures),
      'captures': per(_captures),
      'offscreen': per(_offscreen),
      'bodyShadows': per(
        MorphGlassBodyShadow.debugSaveLayerCount - _shadowStart,
      ),
      'idle': idle,
    };
  }

  static List<ui.Picture> _collectPictures(Layer root) {
    final out = <ui.Picture>[];
    void walk(Layer layer) {
      if (layer case PictureLayer(:final picture?)) out.add(picture);
      if (layer is ContainerLayer) {
        for (
          var child = layer.firstChild;
          child != null;
          child = child.nextSibling
        ) {
          walk(child);
        }
      }
    }

    walk(root);
    return out;
  }

  /// The independent backdrop captures (a null key is its own capture,
  /// a shared key one for all its members) and the offscreen layers.
  static (int, int) _layers(Layer root) {
    var independent = 0;
    final keys = <BackdropKey>{};
    var offscreen = 0;
    void walk(Layer layer) {
      switch (layer) {
        case BackdropFilterLayer(:final backdropKey):
          offscreen++;
          if (backdropKey == null) {
            independent++;
          } else {
            keys.add(backdropKey);
          }
        case OpacityLayer(:final alpha?) when alpha < 255:
          offscreen++;
        case ImageFilterLayer() || ColorFilterLayer() || ShaderMaskLayer():
          offscreen++;
        case _:
          break;
      }
      if (layer is ContainerLayer) {
        for (
          var child = layer.firstChild;
          child != null;
          child = child.nextSibling
        ) {
          walk(child);
        }
      }
    }

    walk(root);
    return (independent + keys.length, offscreen);
  }
}

class _Scene {
  const _Scene(this.name, this.build, this.run);

  final String name;
  final Widget Function() build;
  final Future<void> Function(WidgetTester tester) run;
}

Future<void> _drag(
  WidgetTester tester,
  Offset from,
  List<Offset> path, {
  Duration hold = const Duration(milliseconds: 120),
  Duration step = const Duration(milliseconds: 8),
}) async {
  final gesture = await tester.startGesture(from);
  await tester.pump(hold);
  for (final p in path) {
    await gesture.moveTo(p);
    await tester.pump(step);
  }
  await gesture.up();
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 8));
  }
}

List<Offset> _line(Offset a, Offset b, int n) => [
  for (var i = 1; i <= n; i++) Offset.lerp(a, b, i / n)!,
];

Widget _page(Widget child) => Scaffold(
  backgroundColor: const Color(0xFFF2F2F7),
  body: Stack(
    children: [
      for (var i = 0; i < 12; i++)
        Positioned(
          left: 0,
          right: 0,
          top: i * 80.0,
          height: 40,
          child: ColoredBox(color: Color(0xFF000000 | (i * 0x153F7B))),
        ),
      Center(child: child),
    ],
  ),
);

class _Controlled extends StatefulWidget {
  const _Controlled(this.builder);

  final Widget Function(Object? value, ValueChanged<Object?> onChanged) builder;

  @override
  State<_Controlled> createState() => _ControlledState();
}

class _ControlledState extends State<_Controlled> {
  Object? _value;

  @override
  Widget build(BuildContext context) =>
      widget.builder(_value, (Object? value) => setState(() => _value = value));
}

const _menuEntries = <MorphMenuEntry>[
  MorphMenuItem(title: 'Copy'),
  MorphMenuItem(title: 'Share'),
  MorphSubmenu(
    title: 'More',
    children: [
      MorphMenuItem(title: 'Sub one'),
      MorphMenuItem(title: 'Sub two'),
    ],
  ),
  MorphMenuItem(title: 'Delete'),
];

MorphBarButton _barIcon(String id) => MorphBarButton(
  id: id,
  icon: const SizedBox.square(dimension: 24),
  semanticLabel: id,
  onPressed: () {},
);

final _scenes = <_Scene>[
  _Scene(
    'segmented-drag',
    () => _page(
      _Controlled(
        (value, onChanged) => SizedBox(
          width: 300,
          child: MorphSegmentedControl(
            segments: const ['A', 'B', 'C'],
            selected: value as int? ?? 0,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
    (tester) async {
      final a = tester.getCenter(find.text('A'));
      final c = tester.getCenter(find.text('C'));
      await _drag(tester, a, [..._line(a, c, 40), ..._line(c, a, 40)]);
    },
  ),
  _Scene(
    'lens-held',
    () => _page(
      _Controlled(
        (value, onChanged) => SizedBox(
          width: 300,
          child: MorphSegmentedControl(
            segments: const ['A', 'B', 'C'],
            selected: value as int? ?? 0,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
    (tester) async {
      final a = tester.getCenter(find.text('A'));
      await _drag(tester, a, [
        for (var i = 0; i < 60; i++) a,
      ], hold: const Duration(milliseconds: 8));
    },
  ),
  _Scene(
    'tab-bar',
    () => _page(
      _Controlled(
        (value, onChanged) => MorphTabBar(
          items: const [
            MorphTabItem(icon: Icons.home, label: 'Home'),
            MorphTabItem(icon: Icons.search, label: 'Search'),
            MorphTabItem(icon: Icons.radio, label: 'Radio'),
          ],
          selected: value as int? ?? 0,
          onChanged: onChanged,
        ),
      ),
    ),
    (tester) async {
      final home = tester.getCenter(find.text('Home'));
      final radio = tester.getCenter(find.text('Radio'));
      await _drag(tester, home, [
        ..._line(home, radio, 50),
        ..._line(radio, home, 50),
      ], hold: const Duration(milliseconds: 150));
    },
  ),
  _Scene(
    'switch',
    () => _page(
      _Controlled(
        (value, onChanged) =>
            MorphSwitch(value: value as bool? ?? false, onChanged: onChanged),
      ),
    ),
    (tester) async {
      final s = tester.getRect(find.byType(MorphSwitch));
      await _drag(tester, s.center, [
        ..._line(s.center, s.centerLeft, 10),
        ..._line(s.centerLeft, s.centerRight, 20),
      ]);
    },
  ),
  _Scene(
    'slider',
    () => _page(
      _Controlled(
        (value, onChanged) => SizedBox(
          width: 340,
          child: MorphSlider(
            value: value as double? ?? 0.5,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
    (tester) async {
      final w = tester.getRect(find.byType(MorphSlider));
      await _drag(tester, w.center, [
        ..._line(w.center, w.centerLeft, 30),
        ..._line(w.centerLeft, w.center, 30),
      ], step: const Duration(milliseconds: 16));
    },
  ),
  _Scene('menu-card', () => _page(const MorphMenuButton(items: _menuEntries)), (
    tester,
  ) async {
    await tester.tap(find.byType(MorphMenuButton));
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    await tester.tapAt(tester.getCenter(find.text('More').last));
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    await tester.tapAt(const Offset(20, 840));
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
  }),
  _Scene(
    'nav-scroll',
    () => MorphNavigationStack(
      home: MorphNavigationScaffold(
        title: 'Inbox',
        largeTitle: true,
        trailing: [
          MorphBarButtonGroup([_barIcon('add'), _barIcon('more')]),
        ],
        toolbarLeading: [
          MorphBarButtonGroup([_barIcon('filter')], id: 'tbL'),
        ],
        slivers: [
          SliverList.builder(
            itemCount: 60,
            itemBuilder: (BuildContext context, int i) => SizedBox(
              height: 44,
              child: ColoredBox(
                color: Color(0xFF000000 | (i * 0x2A3F1B)),
                child: Text('Row $i'),
              ),
            ),
          ),
        ],
      ),
    ),
    (tester) async {
      await _drag(
        tester,
        const Offset(200, 600),
        _line(const Offset(200, 600), const Offset(200, 300), 40),
      );
    },
  ),
  _Scene(
    'sheet',
    () => _page(
      Builder(
        builder: (BuildContext context) => GestureDetector(
          key: const ValueKey<String>('source'),
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(
            presentMorphSheet<void>(
              context,
              detents: const [MorphSheetDetent.medium],
              builder: (BuildContext context) =>
                  const Center(child: Text('Sheet')),
            ),
          ),
          child: const SizedBox(width: 120, height: 48),
        ),
      ),
    ),
    (tester) async {
      await tester.tap(find.byKey(const ValueKey<String>('source')));
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      await tester.tapAt(const Offset(200, 100));
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
    },
  ),
];
