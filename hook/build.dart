import 'package:flutter_gpu_shaders/build.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'morph_glass.shaderbundle.json',
      includeDirectories: [
        input.packageRoot.resolve('lib/src/glass/renderer/shaders/gpu/'),
      ],
      glesLanguageVersion: 300,
      assetMode: ShaderBundleAssetMode.dataAssetsIfAvailable,
    );
  });
}
