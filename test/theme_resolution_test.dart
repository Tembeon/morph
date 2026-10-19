import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show MaterialApp;
import 'package:morph/morph.dart';
import 'package:morph/src/theme/theme.dart' show morphBrightnessOf;

final class _Control<T extends MorphAppearance> {
  const _Control(
    this.light,
    this.dark,
    this.resolve, {
    this.lightHighContrast,
    this.darkHighContrast,
  });

  final T light;
  final T dark;
  final T? lightHighContrast;
  final T? darkHighContrast;
  final T Function(BuildContext context, T? explicit) resolve;

  Future<T> resolveIn(
    WidgetTester tester, {
    MorphThemeData? theme,
    T? explicit,
    bool highContrast = false,
  }) async {
    late T resolved;
    Widget child = Builder(
      builder: (BuildContext context) {
        resolved = resolve(context, explicit);
        return const SizedBox();
      },
    );
    if (theme != null) child = MorphTheme(data: theme, child: child);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(highContrast: highContrast),
        child: child,
      ),
    );
    return resolved;
  }

  void run() {
    group('$T', () {
      testWidgets('the brightness picks the light or the dark table', (
        tester,
      ) async {
        expect(
          await resolveIn(tester, theme: const MorphThemeData()),
          same(light),
        );
        expect(
          await resolveIn(
            tester,
            theme: const MorphThemeData(brightness: .dark),
          ),
          same(dark),
        );
      });

      testWidgets('high contrast picks the contrast table where UIKit has '
          'one', (tester) async {
        expect(
          await resolveIn(
            tester,
            theme: const MorphThemeData(brightness: .light),
            highContrast: true,
          ),
          same(lightHighContrast ?? light),
        );
        expect(
          await resolveIn(
            tester,
            theme: const MorphThemeData(brightness: .dark),
            highContrast: true,
          ),
          same(darkHighContrast ?? dark),
        );
      });

      testWidgets('a theme appearance wins over the brightness', (
        tester,
      ) async {
        expect(
          await resolveIn(
            tester,
            theme: MorphThemeData(brightness: .light, appearances: [dark]),
          ),
          same(dark),
        );
      });

      testWidgets('an explicit appearance wins over the theme', (tester) async {
        expect(
          await resolveIn(
            tester,
            theme: MorphThemeData(brightness: .dark, appearances: [dark]),
            explicit: light,
          ),
          same(light),
        );
      });
    });
  }
}

void main() {
  const controls = <_Control<MorphAppearance>>[
    _Control<MorphActivityIndicatorAppearance>(
      MorphActivityIndicatorAppearance.light,
      MorphActivityIndicatorAppearance.dark,
      MorphActivityIndicatorAppearance.resolve,
    ),
    _Control<MorphAlertAppearance>(
      MorphAlertAppearance.light,
      MorphAlertAppearance.dark,
      MorphAlertAppearance.resolve,
      lightHighContrast: MorphAlertAppearance.lightHighContrast,
      darkHighContrast: MorphAlertAppearance.darkHighContrast,
    ),
    _Control<MorphBarAppearance>(
      MorphBarAppearance.light,
      MorphBarAppearance.dark,
      MorphBarAppearance.resolve,
    ),
    _Control<MorphDatePickerAppearance>(
      MorphDatePickerAppearance.light,
      MorphDatePickerAppearance.dark,
      MorphDatePickerAppearance.resolve,
      lightHighContrast: MorphDatePickerAppearance.lightHighContrast,
      darkHighContrast: MorphDatePickerAppearance.darkHighContrast,
    ),
    _Control<MorphGlassButtonAppearance>(
      MorphGlassButtonAppearance.light,
      MorphGlassButtonAppearance.dark,
      MorphGlassButtonAppearance.resolve,
    ),
    _Control<MorphListAppearance>(
      MorphListAppearance.light,
      MorphListAppearance.dark,
      MorphListAppearance.resolve,
    ),
    _Control<MorphMenuAppearance>(
      MorphMenuAppearance.light,
      MorphMenuAppearance.dark,
      MorphMenuAppearance.resolve,
    ),
    _Control<MorphPageControlAppearance>(
      MorphPageControlAppearance.light,
      MorphPageControlAppearance.dark,
      MorphPageControlAppearance.resolve,
      lightHighContrast: MorphPageControlAppearance.lightHighContrast,
      darkHighContrast: MorphPageControlAppearance.darkHighContrast,
    ),
    _Control<MorphProgressViewAppearance>(
      MorphProgressViewAppearance.light,
      MorphProgressViewAppearance.dark,
      MorphProgressViewAppearance.resolve,
      lightHighContrast: MorphProgressViewAppearance.lightHighContrast,
      darkHighContrast: MorphProgressViewAppearance.darkHighContrast,
    ),
    _Control<MorphScrollEdgeEffectAppearance>(
      MorphScrollEdgeEffectAppearance.light,
      MorphScrollEdgeEffectAppearance.dark,
      MorphScrollEdgeEffectAppearance.resolve,
    ),
    _Control<MorphSearchFieldAppearance>(
      MorphSearchFieldAppearance.light,
      MorphSearchFieldAppearance.dark,
      MorphSearchFieldAppearance.resolve,
    ),
    _Control<MorphSegmentedControlAppearance>(
      MorphSegmentedControlAppearance.light,
      MorphSegmentedControlAppearance.dark,
      MorphSegmentedControlAppearance.resolve,
      lightHighContrast: MorphSegmentedControlAppearance.lightHighContrast,
      darkHighContrast: MorphSegmentedControlAppearance.darkHighContrast,
    ),
    _Control<MorphSheetAppearance>(
      MorphSheetAppearance.light,
      MorphSheetAppearance.dark,
      MorphSheetAppearance.resolve,
    ),
    _Control<MorphSliderAppearance>(
      MorphSliderAppearance.light,
      MorphSliderAppearance.dark,
      MorphSliderAppearance.resolve,
      lightHighContrast: MorphSliderAppearance.lightHighContrast,
      darkHighContrast: MorphSliderAppearance.darkHighContrast,
    ),
    _Control<MorphStepperAppearance>(
      MorphStepperAppearance.light,
      MorphStepperAppearance.dark,
      MorphStepperAppearance.resolve,
    ),
    _Control<MorphSwitchAppearance>(
      MorphSwitchAppearance.light,
      MorphSwitchAppearance.dark,
      MorphSwitchAppearance.resolve,
      lightHighContrast: MorphSwitchAppearance.lightHighContrast,
      darkHighContrast: MorphSwitchAppearance.darkHighContrast,
    ),
    _Control<MorphTabBarAppearance>(
      MorphTabBarAppearance.light,
      MorphTabBarAppearance.dark,
      MorphTabBarAppearance.resolve,
    ),
  ];
  for (final control in controls) {
    control.run();
  }

  testWidgets('a nested theme replaces the appearances of the one above', (
    tester,
  ) async {
    late MorphSwitchAppearance resolved;
    await tester.pumpWidget(
      MorphTheme(
        data: const MorphThemeData(
          brightness: .light,
          appearances: [MorphSwitchAppearance.dark],
        ),
        child: MorphTheme(
          data: const MorphThemeData(brightness: .light),
          child: Builder(
            builder: (BuildContext context) {
              resolved = MorphSwitchAppearance.resolve(context, null);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(resolved, same(MorphSwitchAppearance.light));
  });

  for (final above in [true, false]) {
    testWidgets('an open sheet follows a theme change '
        '(theme ${above ? 'above' : 'below'} the navigator)', (tester) async {
      late BuildContext home;
      late BuildContext content;
      Widget app(Brightness brightness) {
        Widget theme(Widget child) => MorphTheme(
          data: MorphThemeData(brightness: brightness),
          child: child,
        );
        final page = Builder(
          builder: (BuildContext context) {
            home = context;
            return const SizedBox();
          },
        );
        return MaterialApp(
          builder: above
              ? (BuildContext context, Widget? child) => theme(child!)
              : null,
          home: above ? page : theme(page),
        );
      }

      await tester.pumpWidget(app(.light));
      unawaited(
        showMorphSheet<void>(
          home,
          detents: const [MorphSheetDetent.medium],
          builder: (BuildContext context) {
            content = context;
            return const Text('content');
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(morphBrightnessOf(content), Brightness.light);
      await tester.pumpWidget(app(.dark));
      await tester.pumpAndSettle();
      expect(morphBrightnessOf(content), Brightness.dark);
      expect(
        MorphSheetAppearance.resolve(content, null),
        same(MorphSheetAppearance.dark),
      );
    });
  }
}
