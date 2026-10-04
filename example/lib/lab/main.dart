import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:morph/widgets.dart';

import 'package:morph_example/lab/lab_app.dart';

/// Runs the device capture scene compiled from MORPH_LAB_SCENARIO.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const encoded = String.fromEnvironment('MORPH_LAB_SCENARIO');
  final scenario =
      (jsonDecode(utf8.decode(base64Decode(encoded))) as Map<String, Object?>)
          .cast<String, Object?>();
  await MorphGlassRenderer.precache();
  if (!MorphGlassRenderer.liquidAvailable) {
    throw StateError('The liquid renderer is unavailable for this capture');
  }
  runApp(LabApp(scenario: scenario));
}
