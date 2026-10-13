import 'package:flutter/material.dart' as sdk;
import 'package:material_ui/material_ui.dart';
import 'package:meta/meta.dart';

import 'package:morph/src/widgets/activity_indicator.dart';
import 'package:morph/src/widgets/alert.dart';
import 'package:morph/src/widgets/bar_items.dart';
import 'package:morph/src/widgets/date_picker.dart';
import 'package:morph/src/widgets/glass_button.dart';
import 'package:morph/src/widgets/list.dart';
import 'package:morph/src/widgets/menu.dart';
import 'package:morph/src/widgets/page_control.dart';
import 'package:morph/src/widgets/progress.dart';
import 'package:morph/src/widgets/scroll_edge_effect.dart';
import 'package:morph/src/widgets/search_field.dart';
import 'package:morph/src/widgets/segmented_control.dart';
import 'package:morph/src/widgets/sheet.dart';
import 'package:morph/src/widgets/slider.dart';
import 'package:morph/src/widgets/stepper.dart';
import 'package:morph/src/widgets/switch.dart';
import 'package:morph/src/widgets/tab_bar.dart';

/// Ambient looks for the measured controls as a [ThemeExtension].
///
/// Compatible with both material_ui and Flutter's Material ThemeData;
/// the nearest theme of either family owns the control's appearance.
///
/// Each control resolves its look in this order: its own `appearance`
/// argument, then the matching field here, then its built-in table for
/// the ambient brightness (`light` or `dark` on each appearance class). A
/// [ThemeData] already stands for one brightness, so this extension holds
/// one appearance per control; put a dark one in the dark theme.
@immutable
class MorphWidgetsTheme extends ThemeExtension<MorphWidgetsTheme>
    implements sdk.ThemeExtension<MorphWidgetsTheme> {
  /// Creates the extension; null fields fall through to the built-ins.
  const MorphWidgetsTheme({
    this.segmentedControl,
    this.tabBar,
    this.switchAppearance,
    this.slider,
    this.stepper,
    this.glassButton,
    this.menu,
    this.sheet,
    this.progressView,
    this.activityIndicator,
    this.pageControl,
    this.bar,
    this.scrollEdgeEffect,
    this.alert,
    this.searchField,
    this.datePicker,
    this.list,
  });

  /// The look of every [MorphSegmentedControl] without its own appearance.
  final MorphSegmentedControlAppearance? segmentedControl;

  /// The look of every [MorphTabBar] without its own appearance.
  final MorphTabBarAppearance? tabBar;

  /// The look of every [MorphSwitch] without its own appearance.
  final MorphSwitchAppearance? switchAppearance;

  /// The look of every [MorphSlider] without its own appearance.
  final MorphSliderAppearance? slider;

  /// The look of every [MorphStepper] without its own appearance.
  final MorphStepperAppearance? stepper;

  /// The look of every [MorphGlassButton] without its own appearance.
  final MorphGlassButtonAppearance? glassButton;

  /// The look of every [MorphMenuButton] without its own appearance.
  final MorphMenuAppearance? menu;

  /// The look of every sheet presented with [presentMorphSheet] without
  /// its own appearance.
  final MorphSheetAppearance? sheet;

  /// The look of every [MorphProgressView] without its own appearance.
  final MorphProgressViewAppearance? progressView;

  /// The look of every [MorphActivityIndicator] without its own appearance.
  final MorphActivityIndicatorAppearance? activityIndicator;

  /// The look of every [MorphPageControl] without its own appearance.
  final MorphPageControlAppearance? pageControl;

  /// The look of every navigation bar and toolbar without its own appearance.
  final MorphBarAppearance? bar;

  /// The look of every [MorphScrollEdgeEffect] without its own theme.
  final MorphScrollEdgeEffectAppearance? scrollEdgeEffect;

  /// The look of every alert and action sheet without its own appearance.
  final MorphAlertAppearance? alert;

  /// The look of every [MorphSearchField] and [MorphSearchToolbar] without
  /// its own appearance.
  final MorphSearchFieldAppearance? searchField;

  /// The look of every [MorphDatePicker] without its own appearance.
  final MorphDatePickerAppearance? datePicker;

  /// The look of every [MorphListSection] and [MorphListRow] without its
  /// own appearance.
  final MorphListAppearance? list;

  /// The extension from the ambient [Theme], or null when there is no
  /// [Theme] above [context] or it has no such extension.
  static MorphWidgetsTheme? maybeOf(BuildContext context) =>
      _extensionOf(context, _themeHost(context));

  /// Copies this extension with the supplied non-null control appearances.
  @override
  MorphWidgetsTheme copyWith({
    MorphSegmentedControlAppearance? segmentedControl,
    MorphTabBarAppearance? tabBar,
    MorphSwitchAppearance? switchAppearance,
    MorphSliderAppearance? slider,
    MorphStepperAppearance? stepper,
    MorphGlassButtonAppearance? glassButton,
    MorphMenuAppearance? menu,
    MorphSheetAppearance? sheet,
    MorphProgressViewAppearance? progressView,
    MorphActivityIndicatorAppearance? activityIndicator,
    MorphPageControlAppearance? pageControl,
    MorphBarAppearance? bar,
    MorphScrollEdgeEffectAppearance? scrollEdgeEffect,
    MorphAlertAppearance? alert,
    MorphSearchFieldAppearance? searchField,
    MorphDatePickerAppearance? datePicker,
    MorphListAppearance? list,
  }) => MorphWidgetsTheme(
    segmentedControl: segmentedControl ?? this.segmentedControl,
    tabBar: tabBar ?? this.tabBar,
    switchAppearance: switchAppearance ?? this.switchAppearance,
    slider: slider ?? this.slider,
    stepper: stepper ?? this.stepper,
    glassButton: glassButton ?? this.glassButton,
    menu: menu ?? this.menu,
    sheet: sheet ?? this.sheet,
    progressView: progressView ?? this.progressView,
    activityIndicator: activityIndicator ?? this.activityIndicator,
    pageControl: pageControl ?? this.pageControl,
    bar: bar ?? this.bar,
    scrollEdgeEffect: scrollEdgeEffect ?? this.scrollEdgeEffect,
    alert: alert ?? this.alert,
    searchField: searchField ?? this.searchField,
    datePicker: datePicker ?? this.datePicker,
    list: list ?? this.list,
  );

  /// Chooses the nearer endpoint's measured appearance without blending.
  @override
  MorphWidgetsTheme lerp(MorphWidgetsTheme? other, double t) {
    if (other == null) return this;
    return t < 0.5 ? this : other;
  }
}

/// The brightness the measured controls resolve their colors for: the
/// ambient [Theme]'s when there is one, otherwise the platform's from
/// [MediaQuery], otherwise light.
@internal
Brightness morphBrightnessOf(BuildContext context) =>
    _brightnessOf(context, _themeHost(context));

MorphWidgetsTheme? _extensionOf(BuildContext context, Widget? host) =>
    switch (host) {
      Theme() => Theme.of(context).extension<MorphWidgetsTheme>(),
      sdk.Theme() => sdk.Theme.of(context).extension<MorphWidgetsTheme>(),
      _ => null,
    };

Brightness _brightnessOf(BuildContext context, Widget? host) => switch (host) {
  Theme() => Theme.of(context).brightness,
  sdk.Theme() => sdk.Theme.of(context).brightness,
  _ => MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light,
};

/// Whether the platform asks for reduced motion above [context].
@internal
bool morphReducedMotionOf(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

Widget? _themeHost(BuildContext context) {
  Widget? host;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is Theme || widget is sdk.Theme) {
      host = widget;
      return false;
    }
    return true;
  });
  return host;
}

/// Resolves a control appearance from an explicit value, the nearest supported
/// Material theme extension, then the measured brightness table.
@internal
T morphResolveAppearance<T>(
  BuildContext context,
  T? explicit, {
  required T? Function(MorphWidgetsTheme) themed,
  required T light,
  required T dark,
}) {
  if (explicit != null) return explicit;
  final host = _themeHost(context);
  final theme = _extensionOf(context, host);
  return (theme == null ? null : themed(theme)) ??
      (_brightnessOf(context, host) == Brightness.dark ? dark : light);
}
