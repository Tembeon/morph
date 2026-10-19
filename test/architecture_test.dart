import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'architecture/checker.dart';

/// The renderer directories the widget layer may not import.
const _rendererInternals = [
  'composition',
  'geometry',
  'internal',
  'pass',
  'rendering',
];

/// The module names of [_rendererInternals].
final _glassInternals = [for (final dir in _rendererInternals) 'glass $dir'];

/// morph's structural rules for the current layout; the sketch in
/// `docs/architecture/foundation-sketch.md` describes the target layout.
final _rules = ArchitectureRules(
  forbidden: {
    'package:material_ui/',
    'package:cupertino_ui/',
    'package:flutter/material.dart',
    'package:flutter/cupertino.dart',
    'package:motor/',
  },
  sdkPackages: {
    'flutter',
    'flutter_driver',
    'flutter_gpu',
    'flutter_localizations',
    'flutter_test',
    'flutter_web_plugins',
    'integration_test',
    'sky_engine',
  },
  sdkLibraries: {
    'package:flutter/animation.dart',
    'package:flutter/foundation.dart',
    'package:flutter/gestures.dart',
    'package:flutter/painting.dart',
    'package:flutter/physics.dart',
    'package:flutter/rendering.dart',
    'package:flutter/scheduler.dart',
    'package:flutter/semantics.dart',
    'package:flutter/services.dart',
    'package:flutter/widgets.dart',
    'package:flutter_gpu/gpu.dart',
  },
  nativeOnly: {'dart:ffi', 'package:flutter_gpu/'},
  webConditions: {
    'dart.library.html',
    'dart.library.js_interop',
    'dart.library.js_interop_unsafe',
    'dart.library.js_util',
    'dart.library.ui_web',
  },
  modules: [
    const Module('api', 'lib/', nested: false),
    Module(
      'engine',
      'lib/src/',
      nested: false,
      mayNotImport: {'api', 'glass', ..._glassInternals, 'widgets'},
    ),
    const Module(
      'glass',
      'lib/src/glass/',
      mayNotImport: {'api', 'engine', 'widgets'},
    ),
    // The renderer's modules behind its seam (renderer.dart): the widget
    // layer reaches them only through it.
    for (final dir in _rendererInternals)
      Module(
        'glass $dir',
        'lib/src/glass/renderer/$dir/',
        mayNotImport: {'api', 'engine', 'widgets'},
      ),
    Module(
      'motion',
      'lib/src/motion/',
      mayNotImport: {
        'api',
        'engine',
        'glass',
        ..._glassInternals,
        'theme',
        'widgets',
      },
    ),
    Module(
      'theme',
      'lib/src/theme/',
      mayNotImport: {'api', 'engine', 'glass', ..._glassInternals, 'widgets'},
    ),
    Module(
      'widgets',
      'lib/src/widgets/',
      mayNotImport: {'api', ..._glassInternals},
    ),
  ],
);

/// The violations `lib/` has today, per rule. Each set only shrinks: the
/// change that removes a violation deletes its entry, and a new violation is
/// fixed instead of listed.
const _ratchet = <Rule, Set<String>>{
  Rule.forbidden: {},
  Rule.dependency: {},
  Rule.direction: {
    'lib/src/glass/renderer/geometry/glass_geometry.dart imports lib/src/liquid_field.dart',
    'lib/src/glass/renderer/internal/content_snapshot.dart imports lib/src/live.dart',
    'lib/src/glass/renderer/internal/optimized_clip.dart imports lib/src/live.dart',
    'lib/src/glass/renderer/liquid_glass.dart imports lib/src/live.dart',
    'lib/src/glass/renderer/rendering/liquid_glass_layer.dart imports lib/src/live.dart',
    // The raster anchor goes with the container joins (glass composition M9).
    'lib/src/widgets/glass_liquid_draw.dart imports lib/src/glass/renderer/internal/raster_phase.dart',
    // The liquid capability bootstrap, renderer code living in widgets/.
    'lib/src/widgets/glass_liquid_native.dart imports lib/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart',
    'lib/src/widgets/glass_liquid_native.dart imports lib/src/glass/renderer/internal/glass_warm_up.dart',
    'lib/src/widgets/glass_liquid_native.dart imports lib/src/glass/renderer/internal/liquid_capability.dart',
    'lib/src/widgets/glass_liquid_native.dart imports lib/src/glass/renderer/internal/multi_shader_builder.dart',
    'lib/src/widgets/glass_liquid_web.dart imports lib/src/glass/renderer/internal/liquid_capability.dart',
  },
};

/// Each fixture under `test/architecture/fixtures/` and the one violation it
/// must produce.
const _fixtures = {
  'forbidden_export':
      'forbidden: lib/morph.dart exports package:material_ui/material_ui.dart (lib/morph.dart:1)',
  'transitive_dependency':
      'dependency: fake_shaders reaches package:flutter/material.dart (package:fake_vectors/src/matrix.dart:1)',
  'motion_imports_host':
      'motion: lib/src/widgets/thing_motion.dart reaches lib/src/widgets/thing.dart (lib/src/widgets/thing_motion.dart:2)',
  'direction':
      'direction: lib/src/glass/layer.dart imports lib/src/widgets/button.dart (lib/src/glass/layer.dart:1)',
  'sdk_library':
      'sdk: lib/src/probe.dart imports package:flutter_test/flutter_test.dart (lib/src/probe.dart:2)',
  'web_native':
      'web: lib/src/clock.dart imports dart:ffi (lib/src/clock.dart:1)',
  'unknown_module': 'module: lib/src/host/host.dart (lib/src/host/host.dart)',
};

void main() {
  group('lib/', () {
    late final List<Violation> violations;

    setUpAll(() {
      violations = checkArchitecture(
        Directory.current,
        File('.dart_tool/package_config.json'),
        _rules,
      );
    });

    test('every file under lib/src/ belongs to a module', () {
      final orphans = [
        for (final violation in violations)
          if (violation.rule == Rule.module) violation.key,
      ];
      expect(
        orphans,
        isEmpty,
        reason:
            'Add a Module for the directory of each file to _rules.modules in '
            'test/architecture_test.dart:\n  ${orphans.join('\n  ')}',
      );
    });

    for (final rule in Rule.values) {
      if (rule == Rule.module) continue;
      test('${rule.name} violations match the ratchet', () {
        final problems = _ratchetProblems(
          rule,
          violations,
          _ratchet[rule] ?? const {},
        );
        expect(problems, isEmpty, reason: problems.join('\n'));
      });
    }
  });

  group('fixtures', () {
    for (final MapEntry(key: name, value: violation) in _fixtures.entries) {
      test(name, () {
        final root = _materialize(name);
        final found = checkArchitecture(
          root,
          File('${root.path}/package_config.json'),
          _rules,
        );
        expect([for (final violation in found) '$violation'], [violation]);
      });
    }
  });
}

List<String> _ratchetProblems(
  Rule rule,
  List<Violation> violations,
  Set<String> allowed,
) {
  final found = {
    for (final violation in violations)
      if (violation.rule == rule) violation.key: violation.where,
  };
  final set = '_ratchet[Rule.${rule.name}] in test/architecture_test.dart';
  return [
    for (final MapEntry(key: key, value: where) in found.entries)
      if (!allowed.contains(key))
        "New ${rule.name} violation at $where. Fix it; if it must stay for now, add to $set:\n    '$key',",
    for (final key in allowed)
      if (!found.containsKey(key))
        "'$key' no longer occurs. Delete it from $set.",
  ];
}

/// Copies the fixture [name] into a temporary package root. Fixture files
/// end in `.txt` so that the analyzer and pub leave them alone; the copy
/// drops that suffix and adds an empty pubspec and package config where the
/// fixture has none.
Directory _materialize(String name) {
  final source = Directory('test/architecture/fixtures/$name');
  final root = Directory.systemTemp.createTempSync('morph_architecture_');
  addTearDown(() => root.deleteSync(recursive: true));
  for (final entity in source.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = entity.path.substring(source.path.length + 1);
    final target = File(
      '${root.path}/${path.endsWith('.txt') ? path.substring(0, path.length - 4) : path}',
    );
    target.parent.createSync(recursive: true);
    entity.copySync(target.path);
  }
  final pubspec = File('${root.path}/pubspec.yaml');
  if (!pubspec.existsSync()) pubspec.writeAsStringSync('name: morph\n');
  final config = File('${root.path}/package_config.json');
  if (!config.existsSync()) {
    config.writeAsStringSync('{"configVersion": 2, "packages": []}');
  }
  return root;
}
