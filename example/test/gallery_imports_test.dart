import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _import = RegExp(r"^import '([^']+)'([^;]*);", multiLine: true);

const _designLibraries = [
  'package:material_ui/',
  'package:cupertino_ui/',
  'package:flutter/material.dart',
  'package:flutter/cupertino.dart',
];

/// The imports of a Material or Cupertino library, other than Material's
/// icon glyphs, in the example files `lib/main.dart` reaches.
List<String> _designImports() {
  final seen = <String>{};
  final pending = ['lib/main.dart'];
  final found = <String>[];
  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    if (!seen.add(path)) continue;
    for (final match in _import.allMatches(File(path).readAsStringSync())) {
      final uri = match[1]!;
      if (_designLibraries.any(uri.startsWith)) {
        if (match[2]!.trim() != 'show Icons') found.add('$path: $uri');
      } else if (uri.startsWith('package:morph_example/')) {
        pending.add('lib/${uri.substring('package:morph_example/'.length)}');
      }
    }
  }
  return found;
}

void main() {
  test('the gallery app imports no Material or Cupertino but icons', () {
    expect(_designImports(), isEmpty);
  });
}
