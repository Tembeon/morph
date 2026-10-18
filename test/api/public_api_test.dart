import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/api/public_api.dart';

void main() {
  test('the public API matches test/api/public_api.txt', () async {
    final golden = File('test/api/public_api.txt');
    final actual = await publicApi(Directory.current);
    final expected = golden.readAsStringSync();
    if (actual == expected) return;
    final actualLines = actual.split('\n');
    final expectedLines = expected.split('\n');
    var line = 0;
    while (line < actualLines.length &&
        line < expectedLines.length &&
        actualLines[line] == expectedLines[line]) {
      line++;
    }
    String at(List<String> lines) =>
        line < lines.length ? lines[line] : '<end of file>';
    fail(
      'The public API differs from ${golden.path} at line ${line + 1}:\n'
      '  golden: ${at(expectedLines)}\n'
      '  actual: ${at(actualLines)}\n'
      'Review the change, then regenerate the golden from the package '
      'root:\n'
      '  dart run tool/api/public_api.dart > test/api/public_api.txt',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
