import 'dart:io';

import 'package:data_assets/data_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

import '../hook/build.dart';

void main() {
  BuildInput input({required bool dataAssets, bool native = true}) {
    final builder = BuildInputBuilder();
    builder.setupShared(
      packageRoot: Directory.current.uri,
      packageName: 'morph',
      outputDirectoryShared: Directory.systemTemp.uri.resolve(
        'morph-hook-test/',
      ),
      outputFile: Directory.systemTemp.uri.resolve(
        'morph-hook-test-output.json',
      ),
    );
    builder.setupBuildInput();
    builder.config.setupBuild(linkingEnabled: false);
    if (dataAssets) builder.addExtension(DataAssetsExtension());
    if (native) builder.config.addBuildAssetTypes(['code_assets/code']);
    return builder.build();
  }

  test(
    'G6 consumers have no asset pointing into a missing build directory',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('- build/shaderbundles/')));
    },
  );

  test('G6 web and unsupported toolchains skip the GPU compiler', () async {
    var compiled = false;
    await buildMorphGlassBundle(
      input(dataAssets: false),
      BuildOutputBuilder(),
      compile: (_, _) async {
        compiled = true;
      },
    );
    expect(compiled, isFalse);
  });

  test(
    'G6 web skips GPU compilation even when data assets are enabled',
    () async {
      var compiled = false;
      await buildMorphGlassBundle(
        input(dataAssets: true, native: false),
        BuildOutputBuilder(),
        compile: (_, _) async {
          compiled = true;
        },
      );
      expect(compiled, isFalse);
    },
  );

  test(
    'G6 a missing compiler leaves an optional asset instead of failing the build',
    () async {
      final output = BuildOutputBuilder();
      await buildMorphGlassBundle(
        input(dataAssets: true),
        output,
        compile: (_, _) async {
          throw const FileSystemException('missing impellerc');
        },
      );
      expect(output.build().assets.encodedAssets, isEmpty);
    },
  );
}
