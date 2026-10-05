import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:morph/widgets.dart';

import '../integration_test/support/shader_harness.dart';

/// The shader harness on the host, as an exact parity oracle without a
/// device: flutter_tester's Impeller renders the same runtime-effect SPIR-V
/// the Pixel's Vulkan backend runs, on a software rasterizer.
///
///     flutter test --enable-impeller --enable-flutter-gpu \
///       test/shader_parity_host_test.dart
///
/// Without Impeller (a plain `flutter test`) there is no liquid tier and
/// the test does nothing. `--dart-define=AUDIT_OUT=<dir>` keeps the report
/// and the PNGs; `SHADER_CASES` and `SHADER_MAX_DIFF` as on the device.
const String _only = String.fromEnvironment('SHADER_CASES');

const int _maxDiff = int.fromEnvironment('SHADER_MAX_DIFF');

const String _out = String.fromEnvironment('AUDIT_OUT');

void main() {
  testWidgets('shader parity on the host', (WidgetTester tester) async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    tester.view.physicalSize = const ui.Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.runAsync(MorphGlassRenderer.precache);
    if (_out.isNotEmpty) Directory(_out).createSync(recursive: true);
    final report = await runShaderParity(
      ShaderHarness(tester),
      cases: harnessCasesNamed(_only),
      outDir: _out.isEmpty ? null : _out,
    );
    if (_out.isNotEmpty) {
      File(
        '$_out/report.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    }
    final cases = report['cases']! as Map<String, Object>;
    for (final MapEntry(:key, :value) in cases.entries) {
      final entry = value as Map<String, Object>;
      final diff = entry['diff']! as Map<String, Object>;
      // A summary line per case is the host run's output.
      // ignore: avoid_print
      print(
        '$key repeat ${entry['repeat']} remount ${entry['remount']} '
        'diff ${diff['max']} px ${diff['pixels']}',
      );
      expect(entry['repeat'], 0, reason: key);
      expect(entry['remount'], 0, reason: key);
      expect(diff['max']! as int, lessThanOrEqualTo(_maxDiff), reason: key);
    }
  });
}
