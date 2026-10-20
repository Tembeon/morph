import 'dart:io';

/// The skill's API reference, built from the reviewed public API
/// (test/api/public_api.txt) and the first sentence of each public
/// declaration's dartdoc in [lib].
///
/// Every public type and top-level function gets a section with its
/// summary and its constructors, values or signature, so the reference
/// cannot name a symbol the package no longer has and cannot miss one it
/// gained.
String buildApiReference({required String publicApi, required Directory lib}) {
  final summaries = _summaries(lib);
  const intro =
      'Generated from `test/api/public_api.txt` by '
      '`dart run tool/plugin/gen_api_reference.dart`; do not edit by hand. '
      "Each entry is the declaration's own first dartdoc sentence and its "
      'constructors, values or signature.';
  final out = <String>['# morph API reference', '', intro];
  for (final entry in _entries(publicApi)) {
    if (entry.library case final library?) {
      out.addAll(['', '## `$library`']);
      continue;
    }
    out.addAll(['', '### ${entry.name}', '', '`${entry.header}`']);
    if (summaries[entry.name] case final summary?) {
      out.addAll(['', summary]);
    }
    if (entry.body.isNotEmpty) {
      out.addAll(['', '```dart', ...entry.body, '```']);
    }
  }
  return '${out.join('\n')}\n';
}

/// The public type and function names [publicApi] declares.
Set<String> publicNames(String publicApi) => {
  for (final entry in _entries(publicApi))
    if (entry.library == null) entry.name,
};

class _Entry {
  _Entry.library(this.library) : name = '', header = '', body = const [];

  _Entry(this.name, this.header, this.body) : library = null;

  final String? library;
  final String name;
  final String header;
  final List<String> body;
}

final _declaration = RegExp(
  r'^(?:(?:sealed|abstract|final|base|interface)\s+)*'
  r'(?:class|enum|mixin|extension type|typedef)\s+(\w+)',
);

final _function = RegExp(r'^[\w<>?, ]+?\s(\w+)(?:<[^>]*>)?\(');

List<_Entry> _entries(String publicApi) {
  final lines = publicApi.split('\n');
  final entries = <_Entry>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.startsWith('# ')) {
      entries.add(_Entry.library(line.substring(2).trim()));
      i++;
      continue;
    }
    if (line.isEmpty ||
        line.startsWith(' ') ||
        line.startsWith(')') ||
        line.startsWith('}')) {
      i++;
      continue;
    }
    final type = _declaration.firstMatch(line);
    if (type != null) {
      final members = <String>[];
      i++;
      while (i < lines.length && lines[i].startsWith('  ')) {
        members.add(lines[i]);
        i++;
      }
      entries.add(_Entry(type.group(1)!, line.trim(), _shown(members)));
      continue;
    }
    final function = _function.firstMatch(line);
    final signature = [line];
    i++;
    if (line.trimRight().endsWith('(')) {
      while (i < lines.length) {
        signature.add(lines[i]);
        final closes = lines[i].startsWith(')') || lines[i].startsWith('})');
        i++;
        if (closes) break;
      }
    }
    if (function != null) {
      entries.add(_Entry(function.group(1)!, line.trim(), signature));
    }
  }
  return entries;
}

/// The constructors, static members and enum values of a type's
/// [members]: what a caller writes. Instance fields repeat the
/// constructor's parameters and are left out.
List<String> _shown(List<String> members) {
  final shown = <String>[];
  var i = 0;
  while (i < members.length) {
    final line = members[i];
    final text = line.substring(2);
    final opens =
        text.trimRight().endsWith('(') || text.trimRight().endsWith('({');
    final isConstructor = RegExp(
      r'^(?:const\s+)?(?:factory\s+)?[A-Z]\w*(?:\.\w+)?\(',
    ).hasMatch(text);
    final isStatic = text.startsWith('static ');
    final isValue = RegExp(r'^\w+,$').hasMatch(text.trim());
    if (isConstructor || isStatic || isValue) {
      shown.add(text);
      i++;
      if (opens) {
        while (i < members.length) {
          shown.add(members[i].substring(2));
          final closes =
              members[i].trim() == '})' ||
              members[i].trim() == ')' ||
              members[i].trim().startsWith('})');
          i++;
          if (closes) break;
        }
      }
      continue;
    }
    i++;
    if (opens) {
      while (i < members.length &&
          !(members[i].trim() == '})' || members[i].trim() == ')')) {
        i++;
      }
      i++;
    }
  }
  return shown;
}

/// The first sentence of each top-level declaration's dartdoc in [lib],
/// by name.
Map<String, String> _summaries(Directory lib) {
  final summaries = <String, String>{};
  final files = lib
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
  for (final file in files) {
    final lines = file.readAsLinesSync();
    final doc = <String>[];
    for (final line in lines) {
      if (line.startsWith('///')) {
        doc.add(line.length > 3 ? line.substring(3).trim() : '');
        continue;
      }
      if (line.startsWith('@')) continue;
      final type = _declaration.firstMatch(line);
      final function = type == null && !line.startsWith(' ')
          ? _function.firstMatch(line)
          : null;
      final name = type?.group(1) ?? function?.group(1);
      if (name != null && doc.isNotEmpty && !summaries.containsKey(name)) {
        summaries[name] = _firstSentence(doc);
      }
      doc.clear();
    }
  }
  return summaries;
}

String _firstSentence(List<String> doc) {
  final paragraph = <String>[];
  for (final line in doc) {
    if (line.isEmpty) break;
    paragraph.add(line);
  }
  final text = paragraph.join(' ');
  final end = RegExp(r'\.(\s|$)').firstMatch(text);
  return end == null ? text : text.substring(0, end.start + 1);
}
