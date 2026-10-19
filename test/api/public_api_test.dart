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

  test('public signatures name only public morph types', () async {
    final api = await publicApi(Directory.current);
    final declaration = RegExp(
      r'^(?:\[[^\]]+\] )?(?:[a-z ]*?)(?:class|enum|mixin|typedef|extension type|extension) (\w+)|^[\w<>?, ]*? (\w+)(?:<[^>]*>)?\(',
    );
    final listed = <String>{
      for (final line in api.split('\n'))
        if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#'))
          if (declaration.firstMatch(line) case final match?)
            match.group(1) ?? match.group(2)!,
    };
    final leaks = <String>{
      for (final line in api.split('\n'))
        for (final name in RegExp(r'\b[Mm]orph[A-Z]\w*').allMatches(
          line
              .replaceAll(RegExp(r' = [^,})]+'), '')
              .replaceAll(RegExp(r' with .*$'), ''),
        ))
          if (!listed.contains(name.group(0))) name.group(0)!,
    };
    expect(
      leaks,
      isEmpty,
      reason:
          'These types appear in public signatures but no entry point '
          'exports them; export them or mark the member @internal. Mixins '
          'and default values may name internal types.',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
