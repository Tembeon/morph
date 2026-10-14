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

/// Ambient looks for the measured controls.
///
/// Install it as a [ThemeExtension] of material_ui's or Flutter's Material
/// ThemeData, or with a [MorphWidgetsThemeScope] in an app without a
/// Material [Theme] (a `WidgetsApp` or `CupertinoApp`). The nearer of the
/// two owns the controls below it.
///
/// Each control resolves its look in this order: its own `appearance`
/// argument, then the matching field here, then its built-in table for
/// the ambient brightness (`light` or `dark` on each appearance class)
/// with its accent replaced by [tint]. A [ThemeData] already stands for
/// one brightness, so this extension holds one appearance per control;
/// put a dark one in the dark theme.
@immutable
class MorphWidgetsTheme extends ThemeExtension<MorphWidgetsTheme>
    implements sdk.ThemeExtension<MorphWidgetsTheme> {
  /// Creates the extension; null fields fall through to the built-ins.
  const MorphWidgetsTheme({
    this.tint,
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

  /// The accent of every control that draws one (UIKit `tintColor`,
  /// SwiftUI `tint(_:)`), or null for iOS's systemBlue.
  ///
  /// It replaces the accent of a control's built-in table: the slider's
  /// and progress view's filled track, the tab bar's selected item, a
  /// prominent glass button and bar button, the date picker's accent, an
  /// alert's preferred action and a list row's icon. An explicit color
  /// parameter or an appearance (passed to the control or set here) wins
  /// over it.
  final Color? tint;

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

  /// The look of every sheet presented with [showMorphSheet] without
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

  /// The theme of the nearer [MorphWidgetsThemeScope] or Material [Theme]
  /// above [context], or null when neither holds one.
  static MorphWidgetsTheme? maybeOf(BuildContext context) =>
      _extensionOf(context, _themeHost(context));

  /// Copies this theme with the supplied non-null fields.
  @override
  MorphWidgetsTheme copyWith({
    Color? tint,
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
    tint: tint ?? this.tint,
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

  /// Blends [tint] and chooses the nearer endpoint's measured appearances
  /// without blending them.
  @override
  MorphWidgetsTheme lerp(MorphWidgetsTheme? other, double t) {
    if (other == null) return this;
    final near = t < 0.5 ? this : other;
    final tint = Color.lerp(this.tint, other.tint, t);
    return tint == near.tint ? near : near.copyWith(tint: tint);
  }
}

/// Installs a [MorphWidgetsTheme] for the measured controls below it
/// without a Material [Theme], as UIKit's `tintColor` and appearance
/// proxies reach every control of a view tree.
///
/// A nearer Material [Theme] holding a [MorphWidgetsTheme] extension wins
/// over a scope above it, and a nearer scope over a theme above it. An
/// inherited theme: alerts, sheets and menus presented from below it keep
/// it. The controls resolve their brightness from a Material [Theme] when
/// there is one, otherwise from the platform's ([MediaQuery]).
class MorphWidgetsThemeScope extends InheritedTheme {
  /// Installs [data] for [child].
  const MorphWidgetsThemeScope({
    required this.data,
    required super.child,
    super.key,
  });

  /// The theme the controls below use.
  final MorphWidgetsTheme data;

  /// The nearest scope's theme above [context], or null.
  static MorphWidgetsTheme? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<MorphWidgetsThemeScope>()
      ?.data;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      MorphWidgetsThemeScope(data: data, child: child);

  @override
  bool updateShouldNotify(MorphWidgetsThemeScope oldWidget) =>
      oldWidget.data != data;
}

/// The brightness the measured controls resolve their colors for: the
/// ambient [Theme]'s when there is one, otherwise the platform's from
/// [MediaQuery], otherwise light.
@internal
Brightness morphBrightnessOf(BuildContext context) =>
    _brightnessOf(context, _themeHost(context));

MorphWidgetsTheme? _extensionOf(BuildContext context, _Hosts hosts) {
  final themed = switch (hosts.theme) {
    Theme() => Theme.of(context).extension<MorphWidgetsTheme>(),
    sdk.Theme() => sdk.Theme.of(context).extension<MorphWidgetsTheme>(),
    _ => null,
  };
  if (themed != null && !hosts.scopeNearer) return themed;
  if (!hosts.scoped) return themed;
  return MorphWidgetsThemeScope.maybeOf(context) ?? themed;
}

Brightness _brightnessOf(BuildContext context, _Hosts hosts) =>
    switch (hosts.theme) {
      Theme() => Theme.of(context).brightness,
      sdk.Theme() => sdk.Theme.of(context).brightness,
      _ => MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light,
    };

/// Whether the platform asks for reduced motion above [context].
@internal
bool morphReducedMotionOf(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

typedef _Hosts = ({Widget? theme, bool scoped, bool scopeNearer});

_Hosts _themeHost(BuildContext context) {
  Widget? theme;
  var scoped = false;
  var scopeNearer = false;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is MorphWidgetsThemeScope && !scoped) {
      scoped = true;
      scopeNearer = theme == null;
    } else if (theme == null && (widget is Theme || widget is sdk.Theme)) {
      theme = widget;
    }
    return theme == null || !scoped;
  });
  return (theme: theme, scoped: scoped, scopeNearer: scopeNearer);
}

final Expando<Map<Color, Object>> _tinted = Expando('morph tinted tables');

/// The accent of the ambient [MorphWidgetsTheme], or null.
@internal
Color? morphTintOf(BuildContext context) =>
    MorphWidgetsTheme.maybeOf(context)?.tint;

/// Resolves a control appearance from an explicit value, the nearest
/// [MorphWidgetsTheme], then the measured brightness table, whose accent
/// [tinted] replaces by the theme's [MorphWidgetsTheme.tint].
///
/// A table tinted with one color is built once and shared, so a control
/// that compares its resolved appearance by identity sees no change while
/// the tint holds.
@internal
T morphResolveAppearance<T extends Object>(
  BuildContext context,
  T? explicit, {
  required T? Function(MorphWidgetsTheme) themed,
  required T light,
  required T dark,
  T Function(T table, Color tint)? tinted,
}) {
  if (explicit != null) return explicit;
  final hosts = _themeHost(context);
  final theme = _extensionOf(context, hosts);
  final own = theme == null ? null : themed(theme);
  if (own != null) return own;
  final table = _brightnessOf(context, hosts) == Brightness.dark ? dark : light;
  final tint = theme?.tint;
  if (tint == null || tinted == null) return table;
  final cache = _tinted[table] ??= <Color, Object>{};
  return cache.putIfAbsent(tint, () => tinted(table, tint)) as T;
}
