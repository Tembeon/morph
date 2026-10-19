/// Prints morph's public API: every name its entry points export, with its
/// kind and signature, one section per entry point. `test/api/public_api.txt`
/// holds the reviewed output; regenerate it from the package root with
///
/// ```sh
/// dart run tool/api/public_api.dart > test/api/public_api.txt
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// The libraries whose exports make up the public API, in section order.
const entryPoints = [
  'package:morph/morph.dart',
  'package:morph/glass_painter.dart',
];

/// Writes the API of the package root given as the only argument, or of the
/// current directory, to stdout.
Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    throw ArgumentError('Usage: public_api.dart [package-root]');
  }
  final root = Directory(arguments.isEmpty ? '.' : arguments.single);
  stdout.write(await publicApi(root));
}

/// The public API of the morph package at [root], as the text of
/// `test/api/public_api.txt`.
///
/// A name declared in morph lists its signature and its public members; a
/// member annotated `@override` appears only by name on the `overrides:`
/// line. A name re-exported from another package or the SDK lists only its
/// signature, marked with its source. A name an earlier section already lists
/// appears as a reference to that section.
Future<String> publicApi(Directory root) async {
  final lib = root.absolute.uri.resolve('lib').toFilePath();
  final collection = AnalysisContextCollection(
    includedPaths: [lib],
    sdkPath: _dartSdk(root),
  );
  try {
    final session = collection.contextFor(lib).currentSession;
    final out = StringBuffer();
    final listed = <Element, String>{};
    for (final entryPoint in entryPoints) {
      final result = await session.getLibraryByUri(entryPoint);
      if (result is! LibraryElementResult) {
        throw StateError('Cannot resolve $entryPoint: $result');
      }
      final elements = <Element>{
        for (final element
            in result.element.exportNamespace.definedNames2.values)
          if (_visible(element))
            if (element case PropertyAccessorElement(:final variable))
              variable
            else
              element,
      }.toList();
      elements.sort((a, b) => a.name!.compareTo(b.name!));
      if (out.isNotEmpty) out.writeln();
      out.writeln('# $entryPoint');
      for (final element in elements) {
        if (listed[element] case final section?) {
          out.writeln('${_kind(element)} ${element.name} (see $section)');
          continue;
        }
        listed[element] = entryPoint;
        final source = _source(element);
        if (source != null) {
          out.writeln('[$source] ${_signature(element)}');
          continue;
        }
        out.writeln(_signature(element));
        for (final member in _members(element)) {
          out.writeln('  $member');
        }
      }
    }
    return out.toString();
  } finally {
    await collection.dispose();
  }
}

// Under `flutter test` the running executable is the Flutter tester, not the
// Dart VM, so the analyzer cannot find the SDK by itself. The Dart SDK of the
// Flutter checkout that resolved the package works for both runners.
String? _dartSdk(Directory root) {
  final config = File.fromUri(
    root.absolute.uri.resolve('.dart_tool/package_config.json'),
  );
  if (!config.existsSync()) return null;
  if (jsonDecode(config.readAsStringSync()) case {
    'packages': final List<Object?> packages,
  }) {
    for (final package in packages) {
      if (package case {'name': 'flutter', 'rootUri': final String rootUri}) {
        final sdk = Directory.fromUri(
          config.absolute.uri.resolve('$rootUri/../../bin/cache/dart-sdk'),
        );
        return sdk.existsSync() ? sdk.path : null;
      }
    }
  }
  return null;
}

bool _visible(Element element) =>
    element.isPublic && !element.metadata.hasInternal;

/// The package or SDK library a re-exported [element] comes from, or null
/// when morph declares it.
String? _source(Element element) {
  final uri = element.library!.uri;
  if (uri.isScheme('dart')) return 'dart:${uri.path}';
  final package = uri.pathSegments.first;
  return package == 'morph' ? null : 'package:$package';
}

String _kind(Element element) => switch (element) {
  ClassElement() => 'class',
  MixinElement() => 'mixin',
  EnumElement() => 'enum',
  ExtensionTypeElement() => 'extension type',
  ExtensionElement() => 'extension',
  TypeAliasElement() => 'typedef',
  TopLevelFunctionElement() => 'function',
  TopLevelVariableElement() => 'variable',
  _ => throw StateError('No kind for ${element.kind}: $element'),
};

/// The declaration of [element] on one line, or with one parameter per line
/// when the line at [indent] would pass 80 columns.
String _signature(Element element, {String indent = ''}) {
  final line = _declaration(element, null);
  if (indent.length + line.length <= 80 ||
      element is! ExecutableElement ||
      element.formalParameters.isEmpty) {
    return line;
  }
  return _declaration(element, indent);
}

String _declaration(Element element, String? wrap) {
  final annotations = [
    if (element.metadata.hasDeprecated) '@Deprecated',
    if (element.metadata.hasProtected) '@protected',
    if (element.metadata.hasVisibleForTesting) '@visibleForTesting',
  ];
  final declaration = switch (element) {
    ClassElement() => _class(element),
    MixinElement() => _mixin(element),
    EnumElement() => _enum(element),
    ExtensionTypeElement() => _extensionType(element),
    ExtensionElement() => _extension(element),
    TypeAliasElement() =>
      'typedef ${element.name}${_typeParameters(element.typeParameters)} = '
          '${_type(element.aliasedType)}',
    TopLevelFunctionElement() => _function(element, wrap),
    ConstructorElement() => _constructor(element, wrap),
    MethodElement() => _method(element, wrap),
    GetterElement() =>
      '${_static(element)}${_type(element.returnType)} get ${element.name}',
    SetterElement() =>
      '${_static(element)}set ${element.name}'
          '${_parameters(element.formalParameters, null)}',
    PropertyInducingElement() => _variable(element),
    _ => throw StateError('No declaration for ${element.kind}: $element'),
  };
  return [...annotations, declaration].join(' ');
}

String _class(ClassElement element) =>
    '${[if (element.isSealed) 'sealed' else if (element.isAbstract) 'abstract', if (element.isBase) 'base', if (element.isInterface) 'interface', if (element.isFinal) 'final', if (element.isMixinClass) 'mixin', 'class ${element.name}${_typeParameters(element.typeParameters)}'].join(' ')}${_supertypes(element)}';

String _mixin(MixinElement element) =>
    '${element.isBase ? 'base ' : ''}'
    'mixin ${element.name}${_typeParameters(element.typeParameters)}'
    '${_clause('on', element.superclassConstraints)}'
    '${_clause('implements', element.interfaces)}';

String _enum(EnumElement element) =>
    'enum ${element.name}${_typeParameters(element.typeParameters)}'
    '${_clause('with', element.mixins)}'
    '${_clause('implements', element.interfaces)}';

String _extension(ExtensionElement element) =>
    'extension ${element.name}${_typeParameters(element.typeParameters)} '
    'on ${_type(element.extendedType)}';

String _extensionType(ExtensionTypeElement element) =>
    'extension type ${element.name}'
    '${_typeParameters(element.typeParameters)}'
    '(${_type(element.representation.type)} '
    '${element.representation.name})'
    '${_clause('implements', element.interfaces)}';

String _supertypes(InterfaceElement element) => [
  if (element.supertype case final type? when !type.isDartCoreObject)
    ' extends ${_type(type)}',
  _clause('with', element.mixins),
  _clause('implements', element.interfaces),
].join();

String _clause(String keyword, List<DartType> types) =>
    types.isEmpty ? '' : ' $keyword ${types.map(_type).join(', ')}';

String _function(ExecutableElement element, String? wrap) =>
    '${_type(element.returnType)} ${element.name}'
    '${_typeParameters(element.typeParameters)}'
    '${_parameters(element.formalParameters, wrap)}';

String _constructor(ConstructorElement element, String? wrap) {
  final type = element.enclosingElement.name;
  final name = switch (element.name) {
    null || 'new' => type,
    final name => '$type.$name',
  };
  return [
    if (element.isConst) 'const',
    if (element.isFactory) 'factory',
    '$name${_parameters(element.formalParameters, wrap)}',
  ].join(' ');
}

String _method(MethodElement element, String? wrap) =>
    '${_static(element)}${element.isAbstract ? 'abstract ' : ''}'
    '${_function(element, wrap)}';

String _variable(PropertyInducingElement element) => [
  if (element.isStatic && element is FieldElement) 'static',
  if (element.isLate) 'late',
  if (element.isConst) 'const' else if (element.isFinal) 'final',
  '${_type(element.type)} ${element.name}',
].join(' ');

String _static(ExecutableElement element) =>
    element.isStatic && element.enclosingElement is InstanceElement
    ? 'static '
    : '';

String _typeParameters(List<TypeParameterElement> parameters) {
  if (parameters.isEmpty) return '';
  final list = [
    for (final parameter in parameters)
      switch (parameter.bound) {
        final bound? => '${parameter.name} extends ${_type(bound)}',
        null => parameter.name!,
      },
  ];
  return '<${list.join(', ')}>';
}

/// [parameters] in parentheses: on one line when [wrap] is null, otherwise
/// one per line, indented under a declaration that starts at [wrap].
String _parameters(List<FormalParameterElement> parameters, String? wrap) {
  String describe(FormalParameterElement parameter) => [
    if (parameter.isRequiredNamed) 'required',
    _type(parameter.type),
    parameter.name ?? '_',
    if (parameter.defaultValueCode case final value?)
      '= ${value.replaceAll(RegExp(r'\s+'), ' ')}',
  ].join(' ');
  final required = [
    for (final parameter in parameters)
      if (parameter.isRequiredPositional) describe(parameter),
  ];
  final optional = [
    for (final parameter in parameters)
      if (!parameter.isRequiredPositional && !parameter.metadata.hasInternal)
        describe(parameter),
  ];
  final (open, close) = parameters.any((parameter) => parameter.isNamed)
      ? ('{', '}')
      : ('[', ']');
  if (wrap == null) {
    return '(${[...required, if (optional.isNotEmpty) '$open${optional.join(', ')}$close'].join(', ')})';
  }
  final lines = [for (final parameter in required) '$parameter,'];
  final head = optional.isNotEmpty && lines.isEmpty ? '($open' : '(';
  if (optional.isNotEmpty && lines.isNotEmpty) {
    lines.last = '${lines.last} $open';
  }
  lines.addAll([for (final parameter in optional) '$parameter,']);
  final tail = optional.isEmpty ? ')' : '$close)';
  return [
    head,
    for (final line in lines) '$wrap  $line',
    '$wrap$tail',
  ].join('\n');
}

String _type(DartType type) => type.getDisplayString();

/// The lines under a morph declaration: enum values in declaration order,
/// then constructors and the other public members sorted by name, then the
/// names of its overrides.
List<String> _members(Element element) {
  if (element is! InstanceElement) return const [];
  final members = <Element>[
    if (element is InterfaceElement && element is! EnumElement)
      ...element.constructors,
    ...element.fields.where((field) => field.isOriginDeclaration),
    ...element.getters.where((getter) => getter.isOriginDeclaration),
    ...element.setters.where((setter) => setter.isOriginDeclaration),
    ...element.methods.where((method) => method.isOriginDeclaration),
  ].where(_visible);
  final overrides = <String>{
    for (final member in members)
      if (member.metadata.hasOverride) member.displayName,
  }.toList();
  overrides.sort();
  final declared = [
    for (final member in members)
      if (!member.metadata.hasOverride &&
          !(member is FieldElement && member.isEnumConstant))
        (member is ConstructorElement ? 0 : 1, member.displayName, member),
  ];
  declared.sort(
    (a, b) => a.$1 != b.$1
        ? a.$1 - b.$1
        : a.$2 != b.$2
        ? a.$2.compareTo(b.$2)
        : _signature(a.$3).compareTo(_signature(b.$3)),
  );
  return [
    if (element is EnumElement)
      for (final value in element.constants) '${value.name},',
    for (final (_, _, member) in declared) _signature(member, indent: '  '),
    if (overrides.isNotEmpty) 'overrides: ${overrides.join(', ')}',
  ];
}
