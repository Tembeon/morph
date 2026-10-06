import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

import '../integration_test/support/blur_harness.dart';
import '../integration_test/support/shader_harness.dart';

/// The edge effect's seeded blur draws the blur of the whole pass, and a
/// raised frost stays within its bound, on the host's Impeller:
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/blur_bound_host_test.dart
///
/// `--dart-define=BLUR_OUT=<dir>` writes both renders of every case.
/// Without Impeller there is no liquid tier and the test does nothing.
void main() {
  testWidgets('cheap small blurs draw the blurs they replace', (
    WidgetTester tester,
  ) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.runAsync(MorphGlassRenderer.precache);
    if (!MorphGlassRenderer.liquidAvailable) return;
    const out = String.fromEnvironment('BLUR_OUT');
    final report = await runBlurParity(
      ShaderHarness(tester),
      cases: blurCases,
      outDir: out.isEmpty ? null : out,
    );
    expectBlurParity(report);
  });
}
