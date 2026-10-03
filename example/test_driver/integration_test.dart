import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Runs an integration test, saves its screenshots under
/// `build/screenshots/` (or `SCREENSHOT_DIR`) and its report, without the
/// screenshot bytes, to `build/qa_report.json`.
Future<void> main() {
  final dir = Platform.environment['SCREENSHOT_DIR'] ?? 'build/screenshots';
  return integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          final file = File('$dir/$name.png');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes);
          return true;
        },
    writeResponseOnFailure: true,
    responseDataCallback: (Map<String, Object?>? data) async {
      final report = <String, Object?>{...?data};
      report.remove('screenshots');
      File(
        'build/qa_report.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    },
  );
}
