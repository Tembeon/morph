import 'package:flutter/material.dart' as sdk;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as material;
import 'package:morph/src/widgets/stepper.dart';
import 'package:morph/src/widgets/widgets_theme.dart';

void main() {
  testWidgets('SDK Theme resolves extension, brightness and changes', (
    tester,
  ) async {
    const custom = MorphStepperStyle(foregroundColor: Color(0xFF123456));
    MorphStepperStyle? resolved;
    Brightness? brightness;
    Widget scene({required bool dark}) => sdk.Theme(
      data: sdk.ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        extensions: const [MorphWidgetsTheme(stepper: custom)],
      ),
      child: Builder(
        builder: (context) {
          resolved = MorphStepperStyle.resolve(context, null);
          brightness = morphBrightnessOf(context);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(scene(dark: true));
    expect(resolved, same(custom));
    expect(brightness, Brightness.dark);
    await tester.pumpWidget(scene(dark: false));
    expect(brightness, Brightness.light);
  });

  testWidgets('nearest Material family wins and explicit style wins', (
    tester,
  ) async {
    const outer = MorphStepperStyle(foregroundColor: Color(0xFF123456));
    const inner = MorphStepperStyle(foregroundColor: Color(0xFF654321));
    MorphStepperStyle? resolved;
    MorphStepperStyle? explicit;
    await tester.pumpWidget(
      sdk.Theme(
        data: sdk.ThemeData.dark().copyWith(
          extensions: const [MorphWidgetsTheme(stepper: outer)],
        ),
        child: material.Theme(
          data: material.ThemeData.light().copyWith(
            extensions: const [MorphWidgetsTheme(stepper: inner)],
          ),
          child: Builder(
            builder: (context) {
              resolved = MorphStepperStyle.resolve(context, null);
              explicit = MorphStepperStyle.resolve(context, outer);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(resolved, same(inner));
    expect(explicit, same(outer));
  });
}
