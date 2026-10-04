import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('G2 remembers a failed bundle load across new layers', () async {
    final before = FlutterGpuGeometryRenderer.debugShaderBundleLoadCount;
    for (var i = 0; i < 3; i++) {
      await expectLater(
        FlutterGpuGeometryRenderer.fromAsset('missing-glass.shaderbundle'),
        throwsA(isA<Object>()),
      );
    }
    expect(FlutterGpuGeometryRenderer.debugShaderBundleLoadCount - before, 1);
  });
}
