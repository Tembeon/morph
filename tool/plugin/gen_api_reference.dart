import 'dart:io';

import 'api_reference.dart';

/// Writes the use-morph skill's API reference from the reviewed public
/// API. Run from the package root after test/api/public_api.txt changes:
///
///     dart run tool/plugin/gen_api_reference.dart
void main() {
  File(apiReferencePath).writeAsStringSync(
    buildApiReference(
      publicApi: File('test/api/public_api.txt').readAsStringSync(),
      lib: Directory('lib'),
    ),
  );
  stdout.writeln('wrote $apiReferencePath');
}

/// Where the skill keeps the generated reference, from the package root.
const String apiReferencePath =
    'plugins/morph/skills/use-morph/references/api.md';
