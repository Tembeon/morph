import 'dart:convert';
import 'dart:io';

import 'package:data_assets/data_assets.dart';
import 'package:flutter_gpu_shaders/build.dart';
import 'package:flutter_gpu_shaders/environment.dart';
import 'package:hooks/hooks.dart';

/// Builds the optional liquid shader asset for supported native targets.
Future<void> main(List<String> args) async {
  await build(args, buildMorphGlassBundle);
}

/// Emits one data asset in hook-owned storage; unavailable toolchains use frost.
///
/// Web builds omit native asset types and skip compilation. Native toolchains
/// without data asset support also use frosted glass. Compilation failures leave the asset absent
/// so runtime capability detection can select that fallback.
Future<void> buildMorphGlassBundle(
  BuildInput input,
  BuildOutputBuilder output, {
  Future<void> Function(BuildInput, BuildOutputBuilder)? compile,
}) async {
  if (!input.config.buildDataAssets ||
      !input.config.buildAssetTypes.contains('code_assets/code')) {
    return;
  }
  try {
    await (compile ?? _compile)(input, output);
  } on Object catch (error) {
    stderr.writeln(
      'morph: liquid shader bundle unavailable; using frosted glass. $error',
    );
  }
}

Future<void> _compile(BuildInput input, BuildOutputBuilder output) async {
  final manifest = input.packageRoot.resolve('morph_glass.shaderbundle.json');
  final shaders = input.packageRoot.resolve('lib/src/glass/renderer/shaders/');
  output.dependencies.add(manifest);
  await for (final entry in Directory.fromUri(shaders).list(recursive: true)) {
    if (entry is File) output.dependencies.add(entry.uri);
  }
  final compiler = await findImpellerC();
  output.dependencies.add(compiler);
  final bundle = input.outputDirectory.resolve('morph_glass.shaderbundle');
  await Directory.fromUri(input.outputDirectory).create(recursive: true);
  final result = await Process.run(
    compiler.toFilePath(),
    shaderBundleImpellercArguments(
      outputBundleFilePath: bundle,
      manifestJson: jsonEncode(
        jsonDecode(await File.fromUri(manifest).readAsString()),
      ),
      manifestDirectory: input.packageRoot,
      shaderLibDirectory: compiler.resolve('shader_lib/'),
      includeDirectories: [shaders.resolve('gpu/')],
      glesLanguageVersion: 300,
    ),
    workingDirectory: input.packageRoot.toFilePath(),
  );
  if (result.exitCode != 0) {
    throw StateError('impellerc: ${result.stderr}');
  }
  output.assets.data.add(
    DataAsset(
      package: input.packageName,
      name: shaderBundleDataAssetName('morph_glass.shaderbundle'),
      file: bundle,
    ),
  );
}
