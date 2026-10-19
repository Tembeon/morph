import 'dart:convert';
import 'dart:io';

import 'package:morph/src/glass/renderer/liquid_shader_variants.dart';

/// Prints the liquid final-pass variants hook/build.dart compiles, as JSON
/// (`[{"name": fileName, "defines": [...]}]`), for offline.py.
void main() {
  stdout.writeln(
    jsonEncode([
      for (final variant in LiquidShaderVariant.values)
        {'name': variant.fileName, 'defines': variant.defines},
    ]),
  );
}
