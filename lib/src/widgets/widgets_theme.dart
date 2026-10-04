import 'package:flutter/material.dart' as sdk;
import 'package:material_ui/material_ui.dart';
import 'package:meta/meta.dart';

import 'package:morph/src/widgets/activity_indicator.dart';
import 'package:morph/src/widgets/alert.dart';
import 'package:morph/src/widgets/bar_items.dart';
import 'package:morph/src/widgets/date_picker.dart';
import 'package:morph/src/widgets/glass_button.dart';
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
/// Each control resolves its look in this order: its own `style`
/// argument, then the matching field here, then its built-in table for
/// the ambient brightness (`light` or `dark` on each style class). A
/// [ThemeData] already stands for one brightness, so this extension holds
/// one style per control; put a dark one in the dark theme.
@immutable
class MorphWidgetsTheme extends ThemeExtension<MorphWidgetsTheme>
    implements sdk.ThemeExtension<MorphWidgetsTheme> {
  /// Creates the extension; null fields fall through to the built-ins.
  const MorphWidgetsTheme({
    this.segmented,
    this.tabBar,
    this.switchStyle,
    this.slider,
    this.stepper,
    this.glassButton,
    this.menu,
    this.sheet,
    this.progress,
    this.activityIndicator,
    this.pageControl,
    this.bar,
    this.scrollEdgeEffect,
    this.alert,
    this.searchField,
    this.datePicker,
  });

  /// The look of every [MorphSegmentedControl] without its own style.
  final MorphSegmentedStyle? segmented;

  /// The look of every [MorphTabBar] without its own style.
  final MorphTabBarStyle? tabBar;

  /// The look of every [MorphSwitch] without its own style.
  final MorphSwitchStyle? switchStyle;

  /// The look of every [MorphSlider] without its own style.
  final MorphSliderStyle? slider;

  /// The look of every [MorphStepper] without its own style.
  final MorphStepperStyle? stepper;

  /// The look of every [MorphGlassButton] without its own style.
  final MorphGlassButtonStyle? glassButton;

  /// The look of every [MorphMenuButton] without its own style.
  final MorphMenuStyle? menu;

  /// The look of every sheet presented with [presentMorphSheet] without
  /// its own style.
  final MorphSheetStyle? sheet;

  /// The look of every [MorphProgressView] without its own style.
  final MorphProgressStyle? progress;

  /// The look of every [MorphActivityIndicator] without its own style.
  final MorphActivityIndicatorStyle? activityIndicator;

  /// The look of every [MorphPageControl] without its own style.
  final MorphPageControlStyle? pageControl;

  /// The look of every navigation bar and toolbar without its own style.
  final MorphBarStyle? bar;

  /// The look of every [MorphScrollEdgeEffect] without its own theme.
  final MorphScrollEdgeEffectThemeData? scrollEdgeEffect;

  /// The look of every alert and action sheet without its own style.
  final MorphAlertStyle? alert;

  /// The look of every [MorphSearchField] and [MorphSearchToolbar] without
  /// its own style.
  final MorphSearchFieldStyle? searchField;

  /// The look of every [MorphDatePicker] without its own style.
  final MorphDatePickerStyle? datePicker;

  /// The extension from the ambient [Theme], or null when there is no
  /// [Theme] above [context] or it has no such extension.
  static MorphWidgetsTheme? maybeOf(BuildContext context) {
    return switch (_themeHost(context)) {
      Theme() => Theme.of(context).extension<MorphWidgetsTheme>(),
      sdk.Theme() => sdk.Theme.of(context).extension<MorphWidgetsTheme>(),
      _ => null,
    };
  }

  /// Copies this extension with the supplied non-null control styles.
  @override
  MorphWidgetsTheme copyWith({
    MorphSegmentedStyle? segmented,
    MorphTabBarStyle? tabBar,
    MorphSwitchStyle? switchStyle,
    MorphSliderStyle? slider,
    MorphStepperStyle? stepper,
    MorphGlassButtonStyle? glassButton,
    MorphMenuStyle? menu,
    MorphSheetStyle? sheet,
    MorphProgressStyle? progress,
    MorphActivityIndicatorStyle? activityIndicator,
    MorphPageControlStyle? pageControl,
    MorphBarStyle? bar,
    MorphScrollEdgeEffectThemeData? scrollEdgeEffect,
    MorphAlertStyle? alert,
    MorphSearchFieldStyle? searchField,
    MorphDatePickerStyle? datePicker,
  }) => MorphWidgetsTheme(
    segmented: segmented ?? this.segmented,
    tabBar: tabBar ?? this.tabBar,
    switchStyle: switchStyle ?? this.switchStyle,
    slider: slider ?? this.slider,
    stepper: stepper ?? this.stepper,
    glassButton: glassButton ?? this.glassButton,
    menu: menu ?? this.menu,
    sheet: sheet ?? this.sheet,
    progress: progress ?? this.progress,
    activityIndicator: activityIndicator ?? this.activityIndicator,
    pageControl: pageControl ?? this.pageControl,
    bar: bar ?? this.bar,
    scrollEdgeEffect: scrollEdgeEffect ?? this.scrollEdgeEffect,
    alert: alert ?? this.alert,
    searchField: searchField ?? this.searchField,
    datePicker: datePicker ?? this.datePicker,
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
Brightness morphBrightnessOf(BuildContext context) {
  return switch (_themeHost(context)) {
    Theme() => Theme.of(context).brightness,
    sdk.Theme() => sdk.Theme.of(context).brightness,
    _ => MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light,
  };
}

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

/// Resolves a control style from an explicit value, the nearest supported
/// Material theme extension, then the measured brightness table.
@internal
T morphResolveStyle<T>(
  BuildContext context,
  T? explicit, {
  required T? Function(MorphWidgetsTheme) themed,
  required T light,
  required T dark,
}) {
  if (explicit != null) return explicit;
  final theme = MorphWidgetsTheme.maybeOf(context);
  return (theme == null ? null : themed(theme)) ??
      (morphBrightnessOf(context) == Brightness.dark ? dark : light);
}
