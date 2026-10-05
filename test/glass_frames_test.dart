import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:morph/src/glass/renderer/internal/multi_shader_builder.dart';
import 'package:morph/src/glass/renderer/shaders.dart';
import 'package:morph/src/widgets/glass_channel.dart';
import 'package:morph/widgets.dart';

import 'support/glass_scenes.dart';

/// The glass channel draws exactly what a rebuild of every glass layer
/// draws: every scene of the perf counts, on every tier, recorded frame by
/// frame twice - once with the glass hosts pushing frames into their
/// render objects, once with every host rebuilding its whole tree from the
/// painter on every frame - and the frames compared pixel for pixel.
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
      ShaderKeys.liquidGlassRender,
      ShaderKeys.liquidGlassMaterialRender,
      ShaderKeys.liquidGlassTintRender,
    ]);
  });
  tearDownAll(() {
    isLocalTest = false;
    if (out != null) {
      File(out).writeAsStringSync(
        '${const JsonEncoder.withIndent(' ').convert(dumped)}\n',
      );
    }
  });

  final rebuilt = <String, List<String>>{};
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
          dumped[name] = frames;
          if (!push) {
            rebuilt[name] = frames;
            return;
          }
          final reference = rebuilt[name];
          if (reference == null) return;
          expect(frames, orderedEquals(reference), reason: name);
        });
      }
    }
  }
}

Future<List<String>> _record(
  WidgetTester tester,
  GlassScene scene,
  MorphGlassTier tier,
) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(platform: TargetPlatform.iOS),
      builder: (BuildContext context, Widget? child) =>
          MorphAdaptiveGlass(tier: tier, child: child!),
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
  final hashes = await tester.runAsync(() async {
    final out = <String>[];
    for (final image in images) {
      final data = await image.toByteData();
      out.add(_hash(data!.buffer.asUint32List()));
      image.dispose();
    }
    return out;
  });
  await tester.pumpAndSettle(
    const Duration(milliseconds: 8),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 20),
  );
  return hashes!;
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
