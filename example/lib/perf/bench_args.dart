import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Launch-time settings of the device benches, so one profile APK serves
/// every tier, scene selection and repeat count.
///
/// `tool/bench/bench.py` pushes `bench-args.json` (a flat string map keyed
/// by the dart-define names, for example `{"GALLERY_GLASS": "flat",
/// "AUDIT_SCENES": "menu,sheet"}`) into the app's external files directory
/// before a launch and removes it after. A key the file does not carry
/// falls back to the build's `--dart-define`.
abstract final class BenchArgs {
  static Map<String, String> _values = const {};

  /// Reads `bench-args.json` from the parent of [outDir] (the report
  /// directory, inside the app's external files directory).
  static void load(String outDir) {
    final file = File('${Directory(outDir).parent.path}/bench-args.json');
    if (!file.existsSync()) return;
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) return;
    _values = {
      for (final MapEntry(:key, :value) in decoded.entries) key: '$value',
    };
  }

  /// The launch value of [key], else [fallback].
  static String string(String key, String fallback) => _values[key] ?? fallback;

  /// The launch value of [key] as an integer, else [fallback].
  static int integer(String key, int fallback) =>
      int.tryParse(_values[key] ?? '') ?? fallback;

  /// The launch value of [key] as a flag, else [fallback].
  static bool flag(String key, {required bool fallback}) =>
      switch (_values[key]) {
        'true' => true,
        'false' => false,
        _ => fallback,
      };

  /// Tells the bench runner the run is over; it waits for this logcat line
  /// instead of polling for the report.
  static void done(String report) => debugPrint('MORPH_BENCH_DONE $report');
}
