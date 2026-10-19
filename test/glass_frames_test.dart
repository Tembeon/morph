import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/internal/multi_shader_builder.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/flat_body_shader.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/morph.dart';

import 'support/glass_scenes.dart';

/// The glass channel draws what a rebuild of every glass layer draws, up
/// to raster rounding: every scene of the perf counts, on every tier,
/// recorded frame by frame twice - once with the glass hosts pushing
/// frames into their render objects, once with every host rebuilding its
/// whole tree from the painter on every frame - and the frames compared
/// pixel for pixel. A channel may differ by one 8-bit level, as a label's
/// raster edge sampled under a transform that was composited again rather
/// than painted again does; no channel may differ by more, and the frames
/// with such pixels are counted and printed.
///
/// `GLASS_FRAMES_OUT=<file> flutter test test/glass_frames_test.dart`
/// also writes the frame hashes of the pushing run, to compare a tree
/// against another commit's.
void main() {
  final out = Platform.environment['GLASS_FRAMES_OUT'];
  final dumped = <String, Object?>{};

  setUpAll(() async {
    isLocalTest = true;
    await MultiShaderBuilder.precacheShaders([
      ShaderKeys.fakeGlassSurface,
      ...ShaderKeys.liquidGlassRenders,
    ]);
    // A flat container body that fuses fills its traced outline until
    // this loads: the first scene to fuse would differ from a later one.
    await MorphFlatBodyShader.precache();
  });
  tearDownAll(() {
    isLocalTest = false;
    if (out != null) {
      File(out).writeAsStringSync(
        '${const JsonEncoder.withIndent(' ').convert(dumped)}\n',
      );
    }
  });

  final rebuilt = <String, List<Uint32List>>{};
  final modes = switch (Platform.environment['GLASS_FRAMES_MODE']) {
    'rebuilt' => [false],
    'pushed' => [true],
    _ => [false, true],
  };
  for (final tier in MorphGlassTier.values) {
    for (final scene in glassScenes) {
      final name = '${scene.name}/${tier.name}';
      for (final push in modes) {
        testWidgets('glass frames: $name ${push ? 'pushed' : 'rebuilt'}', (
          WidgetTester tester,
        ) async {
          tester.view.physicalSize = const Size(402, 874);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          addTearDown(() => debugMorphGlassRebuildEveryFrame = false);
          debugMorphGlassRebuildEveryFrame = !push;
          final frames = await _record(tester, scene, tier);
          expect(frames, isNotEmpty);
          dumped[name] = [for (final f in frames) _hash(f)];
          if (!push) {
            if (modes.contains(true)) rebuilt[name] = frames;
            return;
          }
          final reference = rebuilt.remove(name);
          if (reference == null) return;
          expect(frames.length, reference.length, reason: name);
          final rounded = <String>[];
          for (var f = 0; f < frames.length; f++) {
            final (:worst, :pixels) = _compare(frames[f], reference[f]);
            expect(worst, lessThanOrEqualTo(1), reason: '$name frame $f');
            if (pixels > 0) rounded.add('frame $f: $pixels px');
          }
          if (rounded.isNotEmpty) {
            debugPrint('$name: one level apart in ${rounded.join(', ')}');
          }
        });
      }
    }
  }
}

/// The largest difference of one 8-bit channel between [a] and [b], and
/// how many pixels differ at all.
({int worst, int pixels}) _compare(Uint32List a, Uint32List b) {
  var worst = 0;
  var pixels = 0;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x == y) continue;
    pixels++;
    for (var shift = 0; shift < 32; shift += 8) {
      final d = (((x >> shift) & 0xFF) - ((y >> shift) & 0xFF)).abs();
      if (d > worst) worst = d;
    }
  }
  return (worst: worst, pixels: pixels);
}

Future<List<Uint32List>> _record(
  WidgetTester tester,
  GlassScene scene,
  MorphGlassTier tier,
) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(platform: TargetPlatform.iOS),
      builder: (BuildContext context, Widget? child) => MorphTheme(
        data: MorphThemeData(glass: .tier(tier)),
        child: child!,
      ),
      home: scene.build(),
    ),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 8),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 20),
  );
  final images = <ui.Image>[];
  var frame = 0;
  var active = true;
  void capture(Duration _) {
    if (!active) return;
    tester.binding.addPostFrameCallback((Duration _) {
      if (!active || frame++ % 3 != 0) return;
      final root = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
      images.add(root.toImageSync(const Rect.fromLTWH(0, 0, 402, 874)));
    });
  }

  tester.binding.addPersistentFrameCallback(capture);
  await scene.run(tester);
  active = false;
  final pixels = await tester.runAsync(() async {
    final out = <Uint32List>[];
    for (final image in images) {
      final data = await image.toByteData();
      out.add(Uint32List.fromList(data!.buffer.asUint32List()));
      image.dispose();
    }
    return out;
  });
  await tester.pumpAndSettle(
    const Duration(milliseconds: 8),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 20),
  );
  return pixels!;
}

String _hash(Uint32List words) {
  var a = 0x811c9dc5;
  var b = 0x01000193;
  for (final w in words) {
    a = ((a ^ w) * 0x01000193) & 0xFFFFFFFF;
    b = ((b + w) * 0x9E3779B1) & 0xFFFFFFFF;
  }
  return '${a.toRadixString(16)}${b.toRadixString(16)}';
}
