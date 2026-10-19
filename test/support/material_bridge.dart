import 'package:material_ui/material_ui.dart';
import 'package:morph/morph.dart';

/// A [MaterialApp.builder] that hands the app theme's brightness to
/// morph, for tests that switch appearance through a Material theme.
Widget morphFromMaterial(BuildContext context, Widget? child) => MorphTheme(
  data: MorphThemeData(brightness: Theme.of(context).brightness),
  child: child!,
);
