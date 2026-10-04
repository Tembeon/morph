import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks/hooks.dart';

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
