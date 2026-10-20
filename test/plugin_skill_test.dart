import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/plugin/api_reference.dart';
import '../tool/plugin/gen_api_reference.dart' show apiReferencePath;

/// The old names the skill still mentions so that an agent migrating old
/// code finds it; none of them may be public again.
const _retired = {'MorphTag', 'MorphSkin', 'showMorphMenu', 'showMorphDialog'};

void main() {
  final publicApi = File('test/api/public_api.txt').readAsStringSync();
  final names = publicNames(publicApi);

  test('the use-morph skill reference is generated from the public API', () {
    expect(
      File(apiReferencePath).readAsStringSync(),
      buildApiReference(publicApi: publicApi, lib: Directory('lib')),
      reason: 'run `dart run tool/plugin/gen_api_reference.dart`',
    );
  });

  test('the use-morph skill names only public symbols', () {
    final unknown = <String>{};
    final files = Directory('plugins/morph/skills/use-morph')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.md') &&
              !file.path.endsWith('api.md') &&
              !file.path.endsWith('migration.md'),
        );
    for (final file in files) {
      final text = file.readAsStringSync();
      for (final match in RegExp(
        r'\b((?:Morph|showMorph)[A-Z]\w*)',
      ).allMatches(text)) {
        final name = match.group(1)!;
        if (!names.contains(name) && !_retired.contains(name)) {
          unknown.add('${file.path}: $name');
        }
      }
    }
    expect(unknown, isEmpty);
    expect(names.intersection(_retired), isEmpty);
  });
}
