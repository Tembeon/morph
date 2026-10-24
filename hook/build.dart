import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_gpu_shaders/build.dart';
import 'package:flutter_gpu_shaders/environment.dart';
import 'package:hooks/hooks.dart';
import 'package:morph/src/glass/renderer/liquid_shader_variants.dart';

/// Builds the glass renderer's shaders for supported native targets.
Future<void> main(List<String> args) async {
  await build(args, buildMorphGlassBundle);
}

/// Writes the glass renderer's shaders into `build/shaderbundles/` under
/// the package root, the directory the pubspec lists as an asset: the
/// Flutter GPU bundle `morph_glass.shaderbundle` and one runtime-effect
/// library `<fileName>.iplr` per [LiquidShaderVariant].
///
/// The directory exists after every run, so the asset entry always
/// resolves. Web targets (no native asset types) skip compilation and leave
/// it as it is; a compilation failure leaves the shaders absent, and runtime
/// capability detection then draws flat glass.
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
      'morph: liquid shaders unavailable; glass draws flat. $error',
    );
  }
}

/// Search roots for shared GLSL and the bundle's GPU entry helpers.
/// Includes use names within these roots: Windows extended file paths do not
/// normalize parent-directory segments when the compiler opens a header.
List<Uri> shaderIncludeDirectories(Uri packageRoot) => [
  packageRoot.resolve('lib/src/glass/renderer/shaders/'),
  packageRoot.resolve('lib/src/glass/renderer/shaders/gpu/'),
];

Future<void> _compile(BuildInput input, BuildOutputBuilder output) async {
  await buildShaderBundleJson(
    buildInput: input,
    buildOutput: output,
    manifestFileName: 'morph_glass.shaderbundle.json',
    includeDirectories: shaderIncludeDirectories(input.packageRoot),
    glesLanguageVersion: 300,
    assetMode: ShaderBundleAssetMode.legacyOnly,
  );
  await _compileFinalVariants(input, output);
}

/// The runtime stages a target loads, as the Flutter tool compiles the
/// pubspec's shaders for it. A desktop host also runs the tests, whose
/// flutter_tester loads the Skia stage (the final pass's empty stub) or,
/// with `--enable-impeller`, the Vulkan one.
List<String> runtimeStagesFor(OS os) => switch (os) {
  OS.iOS => ['--runtime-stage-metal'],
  OS.macOS => ['--sksl', '--runtime-stage-metal', '--runtime-stage-vulkan'],
  _ => [
    '--sksl',
    '--runtime-stage-gles',
    '--runtime-stage-gles3',
    '--runtime-stage-vulkan',
  ],
};

/// Compiles the final pass once per [LiquidShaderVariant] into an Impeller
/// runtime-effect library, the format `FragmentProgram.fromAsset` decodes,
/// the variant's switches taken from the table.
Future<void> _compileFinalVariants(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  final root = input.packageRoot;
  final shaders = Directory.fromUri(
    root.resolve('lib/src/glass/renderer/shaders/'),
  );
  final entry = shaders.uri.resolve('liquid_glass_final_render.frag');
  final out = root.resolve('build/shaderbundles/');
  final impellerc = await findImpellerC();
  final stages = runtimeStagesFor(input.config.code.targetOS);
  await Future.wait([
    for (final variant in LiquidShaderVariant.values)
      _compileVariant(impellerc, [
        ...stages,
        '--iplr',
        '--input=${entry.toFilePath()}',
        '--input-type=frag',
        '--include=${shaders.path}',
        '--include=${impellerc.resolve('shader_lib/').toFilePath()}',
        for (final name in variant.defines) '--define=$name',
      ], out.resolve('${variant.fileName}.iplr')),
  ]);
  // impellerc's depfile lists the includes of the last stage it compiles,
  // the Skia stub's; every shader source reruns the hook instead.
  output.dependencies.addAll([
    for (final file in shaders.listSync(recursive: true))
      if (file is File) file.uri,
  ]);
  // The libraries are valid only for the engine whose impellerc wrote
  // them.
  output.dependencies.add(impellerc);
  final stamp = out.resolve('final_render.engine_stamp.json');
  await writeEngineStampIfChanged(stampUri: stamp, impellercExec: impellerc);
  output.dependencies.add(stamp);
}

Future<void> _compileVariant(
  Uri impellerc,
  List<String> arguments,
  Uri library,
) async {
  final file = File.fromUri(library);
  final spirv = File('${file.path}.spirv');
  // A failed compile leaves no library behind, never a stale one.
  if (file.existsSync()) file.deleteSync();
  final result = await Process.run(impellerc.toFilePath(), [
    ...arguments,
    '--sl=${file.path}',
    '--spirv=${spirv.path}',
  ]);
  if (spirv.existsSync()) spirv.deleteSync();
  if (result.exitCode != 0) {
    throw ProcessException(
      impellerc.toFilePath(),
      arguments,
      '${result.stderr}${result.stdout}',
      result.exitCode,
    );
  }
}
