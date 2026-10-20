import 'dart:io';

const String _shaders = 'lib/src/glass/renderer/shaders/';

/// A non-sampler uniform declaration: its type, its name and its array
/// size, if any.
final RegExp glslUniform = RegExp(
  r'^uniform (float|vec2|vec3|vec4) (\w+)(?:\[([^\]]+)\])?;',
);

const Map<String, int> _floats = {'float': 1, 'vec2': 2, 'vec3': 3, 'vec4': 4};

/// The float index and size of every non-sampler uniform declared in
/// [lines], in declaration order from [start], array sizes evaluated with
/// [defines].
Map<String, (int, int)> glslLayout(
  Iterable<String> lines,
  int start,
  Map<String, int> defines,
) {
  final layout = <String, (int, int)>{};
  var index = start;
  for (final line in lines) {
    final match = glslUniform.firstMatch(line.trim());
    if (match == null) continue;
    var count = 1;
    if (match.group(3) case final size?) {
      // Left to right over * and /, as the declarations write them.
      final terms = size.split(' ').where((t) => t.isNotEmpty).toList();
      int value(String term) => defines[term] ?? int.parse(term);
      count = value(terms.first);
      for (var t = 1; t + 1 < terms.length; t += 2) {
        count = terms[t] == '*'
            ? count * value(terms[t + 1])
            : count ~/ value(terms[t + 1]);
      }
    }
    final floats = _floats[match.group(1)]! * count;
    layout[match.group(2)!] = (index, floats);
    index += floats;
  }
  return layout;
}

/// The final shader core's lines before its analytic include: the
/// declarations every variant compiles.
List<String> coreLines() {
  final core = File(
    '${_shaders}liquid_glass_final_render_core.glsl',
  ).readAsLinesSync();
  final include = core.indexWhere(
    (line) => line.contains('#include "analytic_geometry.glsl"'),
  );
  if (include <= 0) throw StateError('no analytic include in the core');
  return core.take(include).toList();
}

/// The float layout of the core's uniforms.
Map<String, (int, int)> coreLayout() => glslLayout(coreLines(), 0, const {});

/// The float index right after the core's uniforms.
int coreFloats() {
  final (last, size) = coreLayout().values.last;
  return last + size;
}

/// The analytic file's lines a variant compiles: its `#if SHAPE_TINT` and
/// `#if ANALYTIC_FUSED` blocks (with their `#else`) by [tint] and [fused],
/// every other conditional kept.
List<String> analyticLines({required bool tint, required bool fused}) {
  final lines = File('${_shaders}analytic_geometry.glsl').readAsLinesSync();
  final kept = <String>[];
  final open = <bool>[];
  bool active() => open.every((on) => on);
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#if')) {
      open.add(switch (trimmed) {
        '#if SHAPE_TINT' => tint,
        '#if ANALYTIC_FUSED' => fused,
        _ => true,
      });
      continue;
    }
    if (trimmed == '#else') {
      open.add(!open.removeLast());
      continue;
    }
    if (trimmed == '#endif') {
      open.removeLast();
      continue;
    }
    if (active()) kept.add(line);
  }
  return kept;
}

/// The lines of shaders/fused_tint.glsl, the box tint block the tint-only
/// matte variants of a fused body declare after the core.
List<String> fusedTintLines() =>
    File('${_shaders}fused_tint.glsl').readAsLinesSync();

/// The value of `#define [name]` in shaders/analytic_geometry.glsl.
int analyticDefine(String name) {
  final define = RegExp('^#define $name (\\d+)');
  for (final line in File(
    '${_shaders}analytic_geometry.glsl',
  ).readAsLinesSync()) {
    if (define.firstMatch(line) case final match?) {
      return int.parse(match.group(1)!);
    }
  }
  throw StateError('$name not defined');
}
