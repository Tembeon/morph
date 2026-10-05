import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/glass/renderer/internal/glass_warm_up.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the frosted warm-up scene rasterizes offscreen', () async {
    await morphRasterizeFrostedWarmUp();
  });

  test('the frosted warm-up is a no-op without Impeller', () async {
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);
    await morphWarmFrostedPipelines();
    expect(reports, isEmpty);
  });
}
