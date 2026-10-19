import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';
import 'package:morph/src/glass/renderer/liquid_shader_variants.dart';
import 'package:morph/src/glass/renderer/shaders.dart';

import '../hook/build.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('morph-hook-test'));
  tearDown(() => root.deleteSync(recursive: true));

  BuildInput input({bool native = true}) {
    final builder = BuildInputBuilder();
    builder.setupShared(
      packageRoot: root.uri,
      packageName: 'morph',
      outputDirectoryShared: root.uri.resolve('shared/'),
      outputFile: root.uri.resolve('output.json'),
    );
    builder.setupBuildInput();
    builder.config.setupBuild(linkingEnabled: false);
    if (native) builder.config.addBuildAssetTypes(['code_assets/code']);
    return builder.build();
  }

  bool bundleDirectoryExists() =>
      Directory('${root.path}/build/shaderbundles').existsSync();

  test('G6 the pubspec asset directory is the one the hook writes', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- build/shaderbundles/'));
  });

  test('the final pass is built from the variant table alone', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('liquid_glass_final_render')));
    final wrappers = Directory('lib/src/glass/renderer/shaders')
        .listSync()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.startsWith('liquid_glass_final_render'));
    expect(wrappers, {
      'liquid_glass_final_render.frag',
      'liquid_glass_final_render_core.glsl',
    });
    final names = {
      for (final variant in LiquidShaderVariant.values) variant.fileName,
    };
    expect(names, hasLength(LiquidShaderVariant.values.length));
    expect(
      {
        ...ShaderKeys.liquidGlassRenders,
        ...ShaderKeys.liquidGlassAnalyticRenders,
        ...ShaderKeys.liquidGlassAnalyticFusedRenders,
      },
      {
        for (final variant in LiquidShaderVariant.values)
          ShaderKeys.finalRender(variant),
      },
    );
    for (final variant in LiquidShaderVariant.values) {
      expect(
        variant.directModel || variant.ios27Models,
        isTrue,
        reason: variant.name,
      );
      expect(!variant.fused || variant.analyticGeometry, isTrue);
      expect(
        ShaderKeys.finalRender(variant),
        endsWith('build/shaderbundles/${variant.fileName}.iplr'),
      );
    }
  });

  test('each target gets the runtime stages it loads', () {
    expect(runtimeStagesFor(OS.iOS), ['--runtime-stage-metal']);
    // The host tests load the Skia stub, or Vulkan under Impeller.
    expect(runtimeStagesFor(OS.macOS), [
      '--sksl',
      '--runtime-stage-metal',
      '--runtime-stage-vulkan',
    ]);
    for (final os in [OS.android, OS.linux, OS.windows]) {
      expect(runtimeStagesFor(os), [
        '--sksl',
        '--runtime-stage-gles',
        '--runtime-stage-gles3',
        '--runtime-stage-vulkan',
      ]);
    }
  });

  test(
    'G6 web skips the GPU compiler and still creates the directory',
    () async {
      var compiled = false;
      await buildMorphGlassBundle(
        input(native: false),
        BuildOutputBuilder(),
        compile: (_, _) async {
          compiled = true;
        },
      );
      expect(compiled, isFalse);
      expect(bundleDirectoryExists(), isTrue);
    },
  );

  test('G6 native targets compile the bundle', () async {
    var compiled = false;
    await buildMorphGlassBundle(
      input(),
      BuildOutputBuilder(),
      compile: (_, _) async {
        compiled = true;
      },
    );
    expect(compiled, isTrue);
  });

  test(
    'G6 a missing compiler leaves the directory instead of failing the build',
    () async {
      final output = BuildOutputBuilder();
      await buildMorphGlassBundle(
        input(),
        output,
        compile: (_, _) async {
          throw const FileSystemException('missing impellerc');
        },
      );
      expect(output.build().assets.encodedAssets, isEmpty);
      expect(bundleDirectoryExists(), isTrue);
    },
  );
}
