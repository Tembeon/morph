import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../hook/build.dart' show shaderIncludeDirectories;

final _include = RegExp(r'^\s*#\s*include\s*[<"]([^">]+)[">]', multiLine: true);

void _check(File source, List<Uri> roots, Set<Uri> visited) {
  if (!visited.add(source.absolute.uri)) return;
  for (final match in _include.allMatches(source.readAsStringSync())) {
    final name = match[1]!;
    expect(
      name.split('/'),
      isNot(contains('..')),
      reason: '${source.path}: Windows extended paths cannot traverse $name',
    );
    // Flutter supplies this root to both compiler entry points.
    if (name.startsWith('flutter/')) continue;
    final candidates = roots.map((root) => File.fromUri(root.resolve(name)));
    final found = candidates.where((file) => file.existsSync());
    expect(
      found,
      isNotEmpty,
      reason:
          '${source.path}: $name must resolve from the compiler search roots',
    );
    _check(found.first, roots, visited);
  }
}

void main() {
  test('runtime shader includes resolve from Flutter asset search roots', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final entries = RegExp(
      r'^    - (lib/.*\.(?:frag|vert))$',
      multiLine: true,
    ).allMatches(pubspec);
    expect(entries, isNotEmpty);
    for (final entry in entries) {
      final file = File(entry[1]!);
      expect(file.existsSync(), isTrue, reason: file.path);
      _check(file, [file.absolute.parent.uri], {});
    }
  });

  test('bundle shader includes resolve from the build hook search roots', () {
    final manifest =
        (jsonDecode(File('morph_glass.shaderbundle.json').readAsStringSync())
                as Map)
            .cast<String, Object?>();
    final root = Directory.current.uri;
    final roots = [root, ...shaderIncludeDirectories(root)];
    for (final value in manifest.values) {
      final shader = (value! as Map).cast<String, Object?>();
      final file = File.fromUri(root.resolve(shader['file']! as String));
      expect(file.existsSync(), isTrue, reason: file.path);
      _check(file, roots, {});
    }
  });
}
