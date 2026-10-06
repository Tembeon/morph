import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:morph/widgets.dart';

import 'support/shader_harness.dart';

/// The synthetic shader harness on a device: every case of
/// support/shader_harness.dart rendered offscreen through the package's
/// runtime shaders and through the frozen baseline copy in the same app,
/// compared pixel by pixel, or with `--dart-define=SHADER_BENCH=true`
/// timed against each other.
///
/// Run it with tool/audit/shader/run_pixel.sh (or audit_android.sh /
/// audit.sh with `AUDIT_TARGET` set to this file); the report and the PNGs
/// land in `AUDIT_OUT`. `--dart-define=SHADER_CASES=a,b` runs only the
/// named cases; `--dart-define=SHADER_MAX_DIFF=n` is the largest channel
/// difference from the baseline the run accepts (default 0);
/// `SHADER_COPIES` (6) and `SHADER_FRAMES` (40) size the bench.
const bool _bench = bool.fromEnvironment('SHADER_BENCH');

const String _only = String.fromEnvironment('SHADER_CASES');

const int _maxDiff = int.fromEnvironment('SHADER_MAX_DIFF');

const int _copies = int.fromEnvironment('SHADER_COPIES', defaultValue: 6);

const int _frames = int.fromEnvironment('SHADER_FRAMES', defaultValue: 40);

/// The bench's cases when SHADER_CASES names none: a control row, a large
/// face, a frosted menu, the material variant, the tint variant, a lifted
/// lens, fake glass.
const String _benchCases =
    'regular-dark,big-sheet,menu-frosted,mixed-models,tint-pair,lens-lifted,'
    'fake-big-sheet';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shader parity', (WidgetTester tester) async {
    final out = Directory(
      const String.fromEnvironment('AUDIT_OUT').isEmpty
          ? '${Directory.systemTemp.path}/shader'
          : const String.fromEnvironment('AUDIT_OUT'),
    );
    out.createSync(recursive: true);
    final stale = File('${out.path}/report.json');
    if (stale.existsSync()) stale.deleteSync();
    await tester.runAsync(MorphGlassRenderer.precache);
    final harness = ShaderHarness(tester);
    final cases = harnessCasesNamed(
      _only.isEmpty && _bench ? _benchCases : _only,
    );
    final report = _bench
        ? await runShaderBench(
            harness,
            cases: cases,
            copies: _copies,
            frames: _frames,
          )
        : await runShaderParity(harness, cases: cases, outDir: out.path);
    report['liquid_available'] = MorphGlassRenderer.liquidAvailable;
    report['platform'] = Platform.operatingSystemVersion;
    File(
      '${out.path}/report.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    if (!_bench) {
      final parity = report['cases']! as Map<String, Object>;
      for (final MapEntry(:key, :value) in parity.entries) {
        final entry = value as Map<String, Object>;
        expect(entry['repeat'], 0, reason: '$key: repeat capture differs');
        expect(entry['remount'], 0, reason: '$key: remount differs');
        final diff = entry['diff']! as Map<String, Object>;
        expect(
          diff['max']! as int,
          lessThanOrEqualTo(_maxDiff),
          reason: '$key: $diff',
        );
      }
    }
  });
}
