/// Exports resolved public declarations, including signatures and defaults.
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';

/// Writes the inventory to stdout. Run from the package root.
Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty && arguments.length != 1) {
    throw ArgumentError('Usage: export_api.dart [package-root]');
  }
  final root = Directory(
    arguments.isEmpty ? Directory.current.path : arguments.single,
  ).absolute.path;
  final collection = AnalysisContextCollection(includedPaths: [root]);
  final symbols = <String, Map<String, Object?>>{};
  try {
    for (final entry in const [
      'foundation.dart',
      'widgets.dart',
      'motion.dart',
      'glass_painter.dart',
    ]) {
      final path = '$root/lib/$entry';
      final result = await collection
          .contextFor(path)
          .currentSession
          .getLibraryByUri(Uri.file(path).toString());
      if (result is! LibraryElementResult) {
        throw StateError('Cannot resolve $entry: $result');
      }
      for (final element
          in result.element.exportNamespace.definedNames2.values) {
        final uri = element.library?.uri;
        if (!_visible(element) || uri == null) continue;
        final local = uri.scheme == 'package'
            ? uri.path.startsWith('morph/')
            : uri.toFilePath().startsWith('$root/lib/');
        if (!local) continue;
        final id = '${element.kind.name}:${element.lookupName}';
        final declaration = symbols.putIfAbsent(id, () => _describe(element));
        (declaration['exports']! as List<String>).add(entry);
      }
    }
    final keys = symbols.keys.toList();
    keys.sort();
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'schema': 1,
        'scope':
            'Resolved exports and declared members; inherited members '
            'are represented by supertype/interface signatures.',
        'symbols': {for (final key in keys) key: symbols[key]},
      }),
    );
  } finally {
    await collection.dispose();
  }
}

bool _visible(Element element) =>
    element.isPublic && !element.metadata.hasInternal;

Map<String, Object?> _describe(Element element) {
  final result = <String, Object?>{
    'name': element.lookupName,
    'kind': element.kind.name,
    'exports': <String>[],
    'signature': element.displayString(),
    if (element is FunctionTypedElement)
      'parameters': [
        for (final parameter in element.formalParameters)
          {
            'name': parameter.name,
            'type': parameter.type.getDisplayString(),
            'named': parameter.isNamed,
            'required': parameter.isRequired,
            'default': parameter.defaultValueCode,
          },
      ],
  };
  if (element is InstanceElement) {
    final members = <Element>[
      if (element is InterfaceElement) ...element.constructors,
      ...element.fields,
      ...element.getters,
      ...element.setters,
      ...element.methods,
    ].where(_visible).toList();
    members.sort(
      (a, b) => '${a.kind.name}:${a.lookupName}'.compareTo(
        '${b.kind.name}:${b.lookupName}',
      ),
    );
    result['members'] = [for (final member in members) _describe(member)];
    if (element is InterfaceElement) {
      result['supertypes'] = [
        if (element.supertype case final type?) type.getDisplayString(),
        for (final type in element.interfaces) type.getDisplayString(),
        for (final type in element.mixins) type.getDisplayString(),
      ];
    }
  }
  return result;
}
