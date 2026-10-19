import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morph/src/theme/theme.dart';
import 'package:morph/src/widgets/stepper.dart';
import 'package:morph/src/widgets/morph_theme.dart';

void main() {
  testWidgets('MorphTheme resolves appearance, brightness and changes', (
    tester,
  ) async {
    const custom = MorphStepperAppearance(foregroundColor: Color(0xFF123456));
    MorphStepperAppearance? resolved;
    Brightness? brightness;
    Widget scene({required bool dark}) => MorphTheme(
      data: MorphThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        appearances: const [custom],
      ),
      child: Builder(
        builder: (context) {
          resolved = MorphStepperAppearance.resolve(context, null);
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

  testWidgets('the nearest theme wins and an explicit style wins', (
    tester,
  ) async {
    const outer = MorphStepperAppearance(foregroundColor: Color(0xFF123456));
    const inner = MorphStepperAppearance(foregroundColor: Color(0xFF654321));
    MorphStepperAppearance? resolved;
    MorphStepperAppearance? explicit;
    await tester.pumpWidget(
      MorphTheme(
        data: const MorphThemeData(
          brightness: Brightness.dark,
          appearances: [outer],
        ),
        child: MorphTheme(
          data: const MorphThemeData(
            brightness: Brightness.light,
            appearances: [inner],
          ),
          child: Builder(
            builder: (context) {
              resolved = MorphStepperAppearance.resolve(context, null);
              explicit = MorphStepperAppearance.resolve(context, outer);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(resolved, same(inner));
    expect(explicit, same(outer));
  });

  testWidgets('without a theme the platform brightness decides', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    Brightness? brightness;
    await tester.pumpWidget(
      MediaQuery.fromView(
        view: tester.view,
        child: Builder(
          builder: (context) {
            brightness = morphBrightnessOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(brightness, Brightness.dark);
  });
}
