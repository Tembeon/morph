import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/internal/content_snapshot.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_outline.dart';
import 'package:morph/widgets.dart';

import 'support/glass_scenes.dart';

/// Deterministic per-frame work counters of representative scenes, the
/// cheap proxy for the device's frame cost (tool/audit/perf-research
/// section 4.2): widget rebuilds, render object paints, re-recorded
/// pictures, backdrop captures, offscreen layers and outlines traced from
/// sampled fields per animated frame, and frames scheduled after the scene
/// settled.
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
        'offscreen snapshotImages traces idle';
    final lines = <String>[header];
    for (final MapEntry(:key, :value) in results.entries) {
      final r = value! as Map<String, Object?>;
      lines.add(
        '${key.padRight(22)}${'${r['frames']}'.padLeft(6)}'
        '${'${r['builds']}'.padLeft(7)}${'${r['paints']}'.padLeft(7)}'
        '${'${r['pictures']}'.padLeft(9)}${'${r['captures']}'.padLeft(9)}'
        '${'${r['offscreen']}'.padLeft(10)}'
        '${'${r['snapshotImages']}'.padLeft(15)}'
        '${'${r['traces']}'.padLeft(7)}${'${r['idle']}'.padLeft(5)}',
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
    for (final scene in glassScenes) {
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
  'snapshotImages',
  'traces',
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
  late final int _imageStart;
  late final int _traceStart;

  void start() {
    _imageStart = GlassContentSnapshot.debugImageFallbackCount;
    _traceStart = morphGlassOutlineDebugTraces;
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
      'snapshotImages': per(
        GlassContentSnapshot.debugImageFallbackCount - _imageStart,
      ),
      'traces': per(morphGlassOutlineDebugTraces - _traceStart),
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
