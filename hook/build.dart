import 'dart:io';

import 'package:flutter_gpu_shaders/build.dart';
import 'package:hooks/hooks.dart';

/// Builds the liquid shader bundle for supported native targets.
Future<void> main(List<String> args) async {
  await build(args, buildMorphGlassBundle);
}

/// Writes `build/shaderbundles/morph_glass.shaderbundle` under the package
/// root, the directory the pubspec lists as an asset.
///
/// The directory exists after every run, so the asset entry always
/// resolves. Web targets (no native asset types) skip compilation and leave
/// it empty; a compilation failure leaves the bundle absent, and runtime
/// capability detection then draws the frosted tier.
Future<void> buildMorphGlassBundle(
  BuildInput input,
  BuildOutputBuilder output, {
  Future<void> Function(BuildInput, BuildOutputBuilder)? compile,
}) async {
  await Directory.fromUri(
    input.packageRoot.resolve('build/shaderbundles/'),
  ).create(recursive: true);
  if (!input.config.buildAssetTypes.contains('code_assets/code')) return;
  try {
    await (compile ?? _compile)(input, output);
  } on Object catch (error) {
    stderr.writeln(
      'morph: liquid shader bundle unavailable; using frosted glass. $error',
    );
  }
}

Future<void> _compile(BuildInput input, BuildOutputBuilder output) =>
    buildShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'morph_glass.shaderbundle.json',
      includeDirectories: [
        input.packageRoot.resolve('lib/src/glass/renderer/shaders/gpu/'),
      ],
      glesLanguageVersion: 300,
      assetMode: ShaderBundleAssetMode.legacyOnly,
    );
