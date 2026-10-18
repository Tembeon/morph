/// Structural rules for a package's `lib/`: the libraries it and its runtime
/// dependencies may load, the import direction between its modules, and the
/// purity of its motion files.
///
/// [checkArchitecture] reads a pub-resolved package root and reports every
/// [Violation]; `test/architecture_test.dart` holds morph's rules and ratchets
/// and runs the fixtures under `test/architecture/fixtures/` through the same
/// code.
library;

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;

/// The rule a [Violation] breaks.
enum Rule {
  /// A file in `lib/` imports or exports a forbidden library.
  forbidden,

  /// A runtime dependency is forbidden or reaches a forbidden library.
  dependency,

  /// A `*_motion.dart` file under `lib/src/` declares a Widget, State,
  /// Element or RenderObject, or reaches a file that does through its imports.
  motion,

  /// An import between two modules goes against the module table.
  direction,

  /// A file under `lib/src/` belongs to no module of the table.
  module,

  /// A file in `lib/` loads an SDK library outside the allow-list.
  sdk,

  /// The web build of the public libraries loads a native-only library.
  web,
}

/// One broken rule.
final class Violation {
  /// Creates a violation of [rule].
  const Violation(this.rule, this.key, this.where);

  /// The broken rule.
  final Rule rule;

  /// Names the violation in a ratchet; it does not change when lines move.
  final String key;

  /// The file and line where it happens.
  final String where;

  @override
  String toString() => '${rule.name}: $key ($where)';
}

/// A group of files under `lib/` and the modules it may not import.
final class Module {
  /// Creates a module rooted at [directory].
  const Module(
    this.name,
    this.directory, {
    this.nested = true,
    this.mayNotImport = const {},
  });

  /// The name the table uses for this module.
  final String name;

  /// The root-relative directory, with a trailing slash.
  final String directory;

  /// Whether files in subdirectories of [directory] belong to this module.
  final bool nested;

  /// The modules whose files this module may not import or export.
  final Set<String> mayNotImport;

  /// Whether the root-relative [path] belongs to this module.
  bool contains(String path) =>
      path.startsWith(directory) &&
      (nested || !path.substring(directory.length).contains('/'));
}

/// The rules [checkArchitecture] enforces.
final class ArchitectureRules {
  /// Creates a rule set.
  const ArchitectureRules({
    required this.forbidden,
    required this.sdkPackages,
    required this.sdkLibraries,
    required this.nativeOnly,
    required this.webConditions,
    required this.modules,
  });

  /// URIs no file may load; an entry ending in `/` covers a whole package.
  final Set<String> forbidden;

  /// Packages of the Flutter SDK. The dependency walk stops at them, so links
  /// inside the SDK are never reported.
  final Set<String> sdkPackages;

  /// The libraries of [sdkPackages] that `lib/` may load.
  final Set<String> sdkLibraries;

  /// Libraries that only exist on native platforms; an entry ending in `/`
  /// covers a whole package.
  final Set<String> nativeOnly;

  /// The `dart.library.*` conditions that hold in a web build.
  final Set<String> webConditions;

  /// The module table. Every file under `lib/src/` belongs to exactly one
  /// module; the most specific directory wins.
  final List<Module> modules;
}

/// Checks the package at [root] against [rules].
///
/// [packageConfig] is the package's `package_config.json`; its relative root
/// URIs resolve against its own location, as pub writes them.
List<Violation> checkArchitecture(
  Directory root,
  File packageConfig,
  ArchitectureRules rules,
) {
  final rootUri = root.absolute.uri;
  final pubspec = _Pubspec.read(File.fromUri(rootUri.resolve('pubspec.yaml')));
  final packages = _readPackageConfig(packageConfig);
  packages[pubspec.name] = rootUri.resolve('lib/');
  final checker = _Checker(rootUri, pubspec, packages, rules);
  final seen = <(Rule, String)>{};
  return [
    for (final violation in [
      ...checker.checkLib(),
      ...checker.checkMotion(),
      ...checker.checkDependencies(),
      ...checker.checkWeb(),
    ])
      if (seen.add((violation.rule, violation.key))) violation,
  ];
}

/// One import, export or part directive with every URI it may load.
final class _Directive {
  _Directive(this.verb, this.line, this.uri, this.branches);

  final String verb;
  final int line;

  /// The URI loaded when no condition of [branches] holds.
  final String uri;

  /// `(condition, uri)` pairs of the conditional branches, in source order.
  final List<(String, String)> branches;

  Iterable<String> get uris => [uri, for (final (_, uri) in branches) uri];

  String select(bool Function(String condition) holds) {
    for (final (condition, uri) in branches) {
      if (holds(condition)) return uri;
    }
    return uri;
  }
}

/// A class or mixin declaration and the names it extends, mixes in or is
/// constrained on.
final class _Type {
  _Type(this.file, this.name, this.supertypes);

  final Uri file;
  final String name;
  final List<String> supertypes;
}

final class _Source {
  _Source(this.directives, this.types);

  final List<_Directive> directives;
  final List<_Type> types;

  static _Source parse(Uri file) {
    final result = parseString(
      content: File.fromUri(file).readAsStringSync(),
      path: file.toFilePath(),
      throwIfDiagnostics: false,
    );
    final unit = result.unit;
    int lineOf(ast.AstNode node) =>
        result.lineInfo.getLocation(node.offset).lineNumber;
    final directives = <_Directive>[];
    for (final directive in unit.directives) {
      final verb = switch (directive) {
        ast.ImportDirective() => 'imports',
        ast.ExportDirective() => 'exports',
        ast.PartDirective() => 'includes',
        _ => null,
      };
      if (verb == null || directive is! ast.UriBasedDirective) continue;
      final uri = directive.uri.stringValue;
      if (uri == null) continue;
      final branches = <(String, String)>[
        if (directive is ast.NamespaceDirective)
          for (final branch in directive.configurations)
            if (branch.uri.stringValue case final branchUri?)
              (_condition(branch), branchUri),
      ];
      directives.add(_Directive(verb, lineOf(directive), uri, branches));
    }
    final types = <_Type>[];
    for (final declaration in unit.declarations) {
      switch (declaration) {
        case ast.ClassDeclaration(
          :final namePart,
          :final extendsClause,
          :final withClause,
        ):
          types.add(
            _Type(file, namePart.typeName.lexeme, [
              if (extendsClause != null) _typeName(extendsClause.superclass),
              ...?withClause?.mixinTypes.map(_typeName),
            ]),
          );
        case ast.MixinDeclaration(:final name, :final onClause):
          types.add(
            _Type(file, name.lexeme, [
              ...?onClause?.superclassConstraints.map(_typeName),
            ]),
          );
        default:
      }
    }
    return _Source(directives, types);
  }

  static String _condition(ast.Configuration branch) {
    final name = branch.name.components.map((part) => part.name).join('.');
    return switch (branch.value?.stringValue) {
      final value? => "$name == '$value'",
      null => name,
    };
  }

  static String _typeName(ast.NamedType type) => type.name.lexeme;
}

final class _Pubspec {
  _Pubspec(this.name, this.dependencies);

  final String name;

  /// The keys of `dependencies:`, without `dev_dependencies:`.
  final List<String> dependencies;

  // A line reader instead of a YAML parser: package:yaml is not a dependency
  // of morph, and only the top-level `name:` and the keys of the top-level
  // `dependencies:` map are needed.
  static _Pubspec read(File file) {
    String? name;
    final dependencies = <String>[];
    var inDependencies = false;
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      if (!line.startsWith(' ')) {
        inDependencies = line.trimRight() == 'dependencies:';
        if (RegExp(r'^name:\s*(\S+)').firstMatch(line) case final match?) {
          name = match.group(1);
        }
        continue;
      }
      if (!inDependencies) continue;
      if (RegExp(r'^  (\w+):').firstMatch(line) case final match?) {
        dependencies.add(match.group(1)!);
      }
    }
    if (name == null) throw StateError('${file.path} has no name');
    return _Pubspec(name, dependencies);
  }
}

/// Maps each package name to the directory its `package:` URIs resolve in.
Map<String, Uri> _readPackageConfig(File file) {
  final packages = <String, Uri>{};
  final config = jsonDecode(file.readAsStringSync());
  if (config case {'packages': final List<Object?> entries}) {
    for (final entry in entries) {
      if (entry case {
        'name': final String name,
        'rootUri': final String rootUri,
      }) {
        final packageUri = switch (entry) {
          {'packageUri': final String uri} => uri,
          _ => '',
        };
        packages[name] = _directory(
          _directory(file.absolute.uri.resolve(rootUri)).resolve(packageUri),
        );
      }
    }
  }
  return packages;
}

List<Uri> _dartFiles(Uri directory) {
  final files = [
    for (final entity in Directory.fromUri(directory).listSync(recursive: true))
      if (entity is File && entity.path.endsWith('.dart')) entity.absolute.uri,
  ];
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

Uri _directory(Uri uri) =>
    uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');

bool _covers(Set<String> entries, String uri) => entries.any(
  (entry) => entry.endsWith('/') ? uri.startsWith(entry) : uri == entry,
);

final class _Checker {
  _Checker(this.root, this.pubspec, this.packages, this.rules)
    : lib = root.resolve('lib/');

  final Uri root;
  final Uri lib;
  final _Pubspec pubspec;
  final Map<String, Uri> packages;
  final ArchitectureRules rules;
  final Map<Uri, _Source> _sources = {};

  _Source source(Uri file) =>
      _sources.putIfAbsent(file, () => _Source.parse(file));

  late final List<Uri> files = _dartFiles(lib);

  String relative(Uri file) => file.path.substring(root.path.length);

  String where(Uri file, _Directive directive) =>
      '${describe(file)}:${directive.line}';

  /// [file] as messages name it: root-relative inside `lib/`, a `package:`
  /// URI inside a dependency.
  String describe(Uri file) {
    if (file.path.startsWith(lib.path)) return relative(file);
    for (final MapEntry(key: name, value: directory) in packages.entries) {
      if (file.path.startsWith(directory.path)) {
        return 'package:$name/${file.path.substring(directory.path.length)}';
      }
    }
    return file.toFilePath();
  }

  /// The file [uri] names when it is a relative or `package:` URI that does
  /// not lead into the SDK.
  Uri? resolve(Uri from, String uri) {
    final parsed = Uri.parse(uri);
    if (parsed.scheme == 'dart') return null;
    if (parsed.scheme != 'package') return from.resolveUri(parsed);
    final [name, ...path] = parsed.pathSegments;
    if (rules.sdkPackages.contains(name)) return null;
    final directory = packages[name];
    if (directory == null) {
      throw StateError('$uri: package $name is not in package_config.json');
    }
    return directory.resolve(path.join('/'));
  }

  /// The file of this package's `lib/` that [uri] names, if any.
  Uri? inLib(Uri from, String uri) {
    final parsed = Uri.parse(uri);
    if (parsed.scheme == 'package' &&
        parsed.pathSegments.first != pubspec.name) {
      return null;
    }
    final file = resolve(from, uri);
    return file != null && file.path.startsWith(lib.path) ? file : null;
  }

  Module? moduleOf(String path) {
    Module? best;
    for (final module in rules.modules) {
      if (module.contains(path) &&
          (best == null || module.directory.length > best.directory.length)) {
        best = module;
      }
    }
    return best;
  }

  bool isSdk(String uri) =>
      uri.startsWith('package:') &&
      rules.sdkPackages.contains(Uri.parse(uri).pathSegments.first);

  /// Every directive URI reachable from [start], with the file and directive
  /// it appears in. [uris] picks the URIs of a directive; [follow] names the
  /// file a URI leads to, or null to stop there.
  Iterable<(Uri, _Directive, String)> reach(
    List<Uri> start,
    Iterable<String> Function(_Directive) uris,
    Uri? Function(Uri from, String uri) follow,
  ) sync* {
    final pending = [...start];
    final seen = <Uri>{};
    while (pending.isNotEmpty) {
      final file = pending.removeLast();
      if (!seen.add(file)) continue;
      for (final directive in source(file).directives) {
        for (final uri in uris(directive)) {
          yield (file, directive, uri);
          if (follow(file, uri) case final next?) pending.add(next);
        }
      }
    }
  }

  Iterable<Violation> checkLib() sync* {
    for (final file in files) {
      final path = relative(file);
      final module = moduleOf(path);
      if (module == null && path.startsWith('lib/src/')) {
        yield Violation(Rule.module, path, path);
      }
      for (final directive in source(file).directives) {
        for (final uri in directive.uris) {
          final key = '$path ${directive.verb} $uri';
          if (_covers(rules.forbidden, uri)) {
            yield Violation(Rule.forbidden, key, where(file, directive));
          } else if (isSdk(uri) && !rules.sdkLibraries.contains(uri)) {
            yield Violation(Rule.sdk, key, where(file, directive));
          }
          final target = inLib(file, uri);
          if (target == null || module == null) continue;
          final targetPath = relative(target);
          if (moduleOf(targetPath) case final other?
              when module.mayNotImport.contains(other.name)) {
            yield Violation(
              Rule.direction,
              '$path ${directive.verb} $targetPath',
              where(file, directive),
            );
          }
        }
      }
    }
  }

  Iterable<Violation> checkMotion() sync* {
    final hosts = _hostFiles();
    Uri? pure(Uri from, String uri) => switch (inLib(from, uri)) {
      final target? when !hosts.contains(target) => target,
      _ => null,
    };
    for (final motion in files) {
      final path = relative(motion);
      if (!path.startsWith('lib/src/') || !path.endsWith('_motion.dart')) {
        continue;
      }
      if (hosts.contains(motion)) {
        yield Violation(Rule.motion, '$path declares a widget or host', path);
      }
      for (final (file, directive, uri) in reach(
        [motion],
        (directive) => directive.uris,
        pure,
      )) {
        if (inLib(file, uri) case final target? when hosts.contains(target)) {
          yield Violation(
            Rule.motion,
            '$path reaches ${relative(target)}',
            where(file, directive),
          );
        }
      }
    }
  }

  /// The files of `lib/` that declare a Widget, State, Element or
  /// RenderObject, directly or through other classes of `lib/`.
  Set<Uri> _hostFiles() {
    final public = <String, List<_Type>>{};
    final private = <(Uri, String), _Type>{};
    for (final file in files) {
      for (final type in source(file).types) {
        if (type.name.startsWith('_')) {
          private[(file, type.name)] = type;
        } else {
          (public[type.name] ??= []).add(type);
        }
      }
    }
    final memo = <_Type, bool>{};
    bool isHost(_Type type) {
      if (memo[type] case final known?) return known;
      memo[type] = false;
      final result = type.supertypes.any((name) {
        final declared = name.startsWith('_')
            ? [?private[(type.file, name)]]
            : public[name] ?? const <_Type>[];
        return declared.isEmpty ? _frameworkHost(name) : declared.any(isHost);
      });
      return memo[type] = result;
    }

    return {
      for (final file in files)
        if (source(file).types.any(isHost)) file,
    };
  }

  // Flutter's Widget, State, Element and RenderObject families follow these
  // names. Only names that lib/ does not declare reach this test; morph's own
  // classes are followed through their declarations.
  static bool _frameworkHost(String name) =>
      name.endsWith('Widget') ||
      name.endsWith('State') ||
      name.endsWith('Element') ||
      name.startsWith('Inherited') ||
      RegExp('^Render[A-Z]').hasMatch(name);

  Iterable<Violation> checkDependencies() sync* {
    for (final dependency in pubspec.dependencies) {
      if (rules.sdkPackages.contains(dependency)) continue;
      if (_covers(rules.forbidden, 'package:$dependency/')) {
        yield Violation(
          Rule.dependency,
          'pubspec.yaml depends on $dependency',
          'pubspec.yaml',
        );
        continue;
      }
      final directory = packages[dependency];
      if (directory == null) {
        throw StateError('$dependency is not in package_config.json');
      }
      for (final (file, directive, uri) in reach(
        _dartFiles(directory),
        (directive) => directive.uris,
        (from, uri) =>
            _covers(rules.forbidden, uri) ? null : resolve(from, uri),
      )) {
        if (_covers(rules.forbidden, uri)) {
          yield Violation(
            Rule.dependency,
            '$dependency reaches $uri',
            where(file, directive),
          );
        }
      }
    }
  }

  Iterable<Violation> checkWeb() sync* {
    final entryPoints = [
      for (final file in files)
        if (!relative(file).substring('lib/'.length).contains('/')) file,
    ];
    for (final (file, directive, uri) in reach(
      entryPoints,
      (directive) => [directive.select(rules.webConditions.contains)],
      inLib,
    )) {
      if (_covers(rules.nativeOnly, uri)) {
        yield Violation(
          Rule.web,
          '${relative(file)} ${directive.verb} $uri',
          where(file, directive),
        );
      }
    }
  }
}
