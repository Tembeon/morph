# morph API reference

Generated from `test/api/public_api.txt` by `dart run tool/plugin/gen_api_reference.dart`; do not edit by hand. Each entry is the declaration's own first dartdoc sentence and its constructors, values or signature.

## `package:morph/morph.dart`

### DefaultMorphLocalizations

`class DefaultMorphLocalizations extends MorphLocalizations`

morph's English strings.

```dart
const DefaultMorphLocalizations()
static const LocalizationsDelegate<MorphLocalizations> delegate
```

### MorphActivityIndicator

`class MorphActivityIndicator extends StatefulWidget`

A spinner that looks and turns like iOS 27's UIActivityIndicatorView.

```dart
const MorphActivityIndicator({
  bool animating = true,
  bool hidesWhenStopped = true,
  MorphActivityIndicatorSize size = MorphActivityIndicatorSize.medium,
  Color? color,
  MorphActivityIndicatorAppearance? appearance,
  String? semanticLabel,
  Key? key,
})
static ({double box, double inner, double outer, double width}) metrics(
  MorphActivityIndicatorSize size,
)
```

### MorphActivityIndicatorAppearance

`class MorphActivityIndicatorAppearance implements MorphAppearance`

The look of a [MorphActivityIndicator].

```dart
const MorphActivityIndicatorAppearance({
  Color color = const Color(0x993C3C43),
})
static const MorphActivityIndicatorAppearance dark
static const MorphActivityIndicatorAppearance light
static MorphActivityIndicatorAppearance resolve(
  BuildContext context,
  MorphActivityIndicatorAppearance? explicit,
)
```

### MorphActivityIndicatorSize

`enum MorphActivityIndicatorSize`

The two sizes of a [MorphActivityIndicator], after UIActivityIndicatorView.Style.

```dart
medium,
large,
```

### MorphAlertAction

`class MorphAlertAction`

One button of an alert or an action sheet.

```dart
const MorphAlertAction({
  required String title,
  MorphAlertActionStyle style = MorphAlertActionStyle.normal,
  void Function()? onPressed,
  bool isPreferred = false,
  bool enabled = true,
  ValueListenable<bool>? enabledListenable,
})
```

### MorphAlertActionStyle

`enum MorphAlertActionStyle`

The role of a [MorphAlertAction], after UIAlertAction.Style.

```dart
normal,
cancel,
destructive,
```

### MorphAlertAppearance

`class MorphAlertAppearance implements MorphAppearance`

The look of an alert or an action sheet.

```dart
const MorphAlertAppearance({
  Color platterColor = const Color(0xA1FDFDFF),
  Color dimmingColor = const Color(0xFF000000),
  Color shadowColor = const Color(0x24000000),
  Color titleColor = const Color(0xFF000000),
  Color messageColor = const Color(0x993C3C43),
  Color buttonColor = const Color(0x1F767680),
  Color labelColor = const Color(0xFF000000),
  Color destructiveColor = const Color(0xFFFF383C),
  Color preferredColor = const Color(0xFF0088FF),
  Color preferredLabelColor = const Color(0xFFFFFFFF),
  Color placeholderColor = const Color(0x4C3C3C43),
  Color disabledLabelColor = const Color(0x4C3C3C43),
})
static const MorphAlertAppearance dark
static const MorphAlertAppearance darkHighContrast
static const MorphAlertAppearance light
static const MorphAlertAppearance lightHighContrast
static MorphAlertAppearance resolve(
  BuildContext context,
  MorphAlertAppearance? explicit,
)
```

### MorphAlertTextField

`class MorphAlertTextField`

A text field of an alert.

```dart
const MorphAlertTextField({
  String? placeholder,
  TextEditingController? controller,
  bool obscureText = false,
  TextInputType? keyboardType,
  void Function(String)? onChanged,
  bool? autofocus,
  bool autocorrect = true,
  bool enableSuggestions = true,
  TextCapitalization textCapitalization = TextCapitalization.none,
  List<TextInputFormatter>? inputFormatters,
  String? semanticLabel,
})
```

### MorphAppearance

`abstract interface class MorphAppearance`

A control's look as one value: its colors, metrics and materials.

```dart
MorphAppearance()
```

### MorphBackButtonDisplayMode

`enum MorphBackButtonDisplayMode`

How a back button shows the title of the screen it returns to, after UIKit's `UINavigationItem.BackButtonDisplayMode`.

```dart
standard,
generic,
minimal,
```

### MorphBadge

`class MorphBadge`

A badge on a bar button or a tab: a count, a short text or a dot (UIKit `UIBarButtonItem.Badge`, `UITabBarItem.badgeValue`, SwiftUI `badge(_:)`).

```dart
const MorphBadge.count(
  int count, {
  Color? foregroundColor,
  Color? backgroundColor,
})
const MorphBadge.indicator({Color? backgroundColor})
const MorphBadge.string(
  String text, {
  Color? foregroundColor,
  Color? backgroundColor,
})
static const Color defaultForegroundColor
```

### MorphBarAppearance

`class MorphBarAppearance implements MorphAppearance`

The look of a glass bar: its capsules, buttons and titles.

```dart
const MorphBarAppearance({
  Color capsuleColor = const Color(0xD9FFFFFF),
  Color rimColor = const Color(0x1F000000),
  Color shadowColor = const Color(0x1A000000),
  Color foregroundColor = const Color(0xFF000000),
  Color prominentColor = const Color(0xFF0088FF),
  Color prominentForegroundColor = const Color(0xFFFFFFFF),
  Color titleColor = const Color(0xFF000000),
  Color subtitleColor = const Color(0x993C3C43),
  Color disabledIconColor = const Color(0x55000000),
  Color disabledLabelColor = const Color(0x19000000),
  Color disabledProminentColor = const Color(0xFFD1D1D6),
})
static const MorphBarAppearance dark
static const MorphBarAppearance light
static MorphBarAppearance resolve(
  BuildContext context,
  MorphBarAppearance? explicit,
)
```

### MorphBarButton

`class MorphBarButton`

One button of a glass bar: a label or an icon.

```dart
const MorphBarButton({
  required Object id,
  String? label,
  Widget? icon,
  void Function()? onPressed,
  String? semanticLabel,
  List<MorphMenuEntry>? menu,
  bool enabled = true,
  MorphBadge? badge,
})
const MorphBarButton.back({
  String? label,
  void Function()? onPressed,
  String? semanticLabel,
  List<MorphMenuEntry>? menu,
  bool enabled = true,
  Object id = 'morph.back',
})
```

### MorphBarButtonGroup

`class MorphBarButtonGroup`

Buttons that share one glass capsule.

```dart
const MorphBarButtonGroup(
  List<MorphBarButton> buttons, {
  Object? id,
  MorphBarButtonStyle style = MorphBarButtonStyle.plain,
})
```

### MorphBarButtonStyle

`enum MorphBarButtonStyle`

The look of a [MorphBarButtonGroup]'s capsule, after UIKit's `UIBarButtonItem.Style`.

```dart
plain,
prominent,
```

### MorphContentScroll

`class MorphContentScroll`

The scrolls of the content under a tab bar, which a minimizing [MorphTabBar] follows (UIKit observes the tab's content scroll view, `setContentScrollView(_:for:)`).

```dart
MorphContentScroll()
```

### MorphContentScrollScope

`class MorphContentScrollScope extends StatefulWidget`

Feeds the scrolls of the content below it to the minimizing [MorphTabBar]s below it: put it above a screen's content and its bar.

```dart
const MorphContentScrollScope({
  required Widget child,
  MorphContentScroll? scroll,
  Key? key,
})
static MorphContentScroll? maybeOf(BuildContext context)
```

### MorphContextMenuRegion

`class MorphContextMenuRegion extends StatefulWidget`

A surface that becomes its own context menu when HELD, as a view with a `UIContextMenuInteraction` does: the thing under a resting finger grows as UIKit's preview grows ([measuredHoldGrowth]), and on the hold its preview lifts ([measuredPreviewScale] about its center) while the [menu] grows out of a blob at its center ([MorphMenuAttachment]) and the page dims.

```dart
const MorphContextMenuRegion({
  Key? key,
  required Widget child,
  List<MorphMenuEntry> menu = const <MorphMenuEntry>[],
  MorphSatellite? accessory,
  MorphMenuOrder order = MorphMenuOrder.automatic,
  bool? dismissOnSelect,
  MorphMenuAppearance? appearance,
  Widget? replica,
  Widget Function(BuildContext)? preview,
  Size? previewSize,
  void Function()? onPreviewTap,
  Duration holdDuration = measuredHoldDuration,
  bool lifts = true,
  bool enabled = true,
  bool opensOnSecondaryTap = true,
  double? maxScrimOpacity,
  Color? scrimColor,
  String? semanticLabel,
  void Function()? onHold,
  void Function()? onClose,
})
static void close(BuildContext context)
static const Duration measuredCommitDuration
static double measuredDimOpacity(Brightness brightness)
static const Duration measuredHoldDuration
static double measuredHoldGrowth(Duration held)
static const double measuredHoldGrowthPoints
static const double measuredLiftPoints
static const double measuredLiftScale
static const double measuredMenuGap
static double measuredPreviewScale(Size size)
static const double measuredRetractScale
```

### MorphDatePicker

`class MorphDatePicker extends StatefulWidget`

The iOS 27 compact date picker: a label that opens its picker in an overlay.

```dart
const MorphDatePicker({
  required DateTime value,
  required void Function(DateTime)? onChanged,
  MorphDatePickerMode mode = MorphDatePickerMode.date,
  MorphDatePickerStyle style = MorphDatePickerStyle.compact,
  int minuteInterval = 1,
  DateTime? minimumDate,
  DateTime? maximumDate,
  bool? use24HourFormat,
  int firstDayOfWeek = DateTime.sunday,
  DateTime? today,
  MorphDatePickerAppearance? appearance,
  String? semanticLabel,
  MorphDatePickerLocalizations localizations = const MorphDatePickerLocalizations(),
  Key? key,
})
```

### MorphDatePickerAppearance

`class MorphDatePickerAppearance implements MorphAppearance`

The look of a [MorphDatePicker] and its overlay.

```dart
const MorphDatePickerAppearance({
  Color labelFillColor = const Color(0x1F767680),
  Color labelColor = const Color(0xFF000000),
  Color accentColor = const Color(0xFF0088FF),
  Color platterColor = const Color(0xF2F9F9FF),
  Color shadowColor = const Color(0x24000000),
  Color titleColor = const Color(0xFF000000),
  Color weekdayColor = const Color(0x993C3C43),
  Color dayColor = const Color(0xFF000000),
  Color todayFillColor = const Color(0x1F0088FF),
  Color selectedDayColor = const Color(0xFFFFFFFF),
  Color selectedDayFillColor = const Color(0xFF000000),
  Color selectedDayTextColor = const Color(0xFFFFFFFF),
  Color chevronColor = const Color(0xFF000000),
  Color wheelBandColor = const Color(0x1F767680),
  Color wheelColor = const Color(0xFF000000),
  double wheelFadedOpacity = 0.4,
  double unavailableDayOpacity = 0.35,
})
static const MorphDatePickerAppearance dark
static const MorphDatePickerAppearance darkHighContrast
static const MorphDatePickerAppearance light
static const MorphDatePickerAppearance lightHighContrast
static MorphDatePickerAppearance resolve(
  BuildContext context,
  MorphDatePickerAppearance? explicit,
)
```

### MorphDatePickerLocalizations

`class MorphDatePickerLocalizations`

The texts and formats of a [MorphDatePicker], in one place as UIKit's `UIDatePicker.locale`: every field null keeps the measured en_US labels.

```dart
const MorphDatePickerLocalizations({
  String Function(DateTime)? dateFormatter,
  String Function(DateTime)? timeFormatter,
  String Function(String)? localize,
  String Function(DateTime)? calendarTitleFormatter,
  String Function(DateTime)? daySemanticFormatter,
  String Function(int)? numberFormatter,
})
```

### MorphDatePickerMode

`enum MorphDatePickerMode`

What a [MorphDatePicker] picks.

```dart
date,
time,
dateAndTime,
```

### MorphDatePickerStyle

`enum MorphDatePickerStyle`

How a [MorphDatePicker] shows itself, after UIKit's `UIDatePickerStyle` (`preferredDatePickerStyle`).

```dart
compact,
inline,
wheels,
```

### MorphGlassButton

`class MorphGlassButton extends StatefulWidget`

A glass button that responds to touch exactly like iOS 27's `UIButton.Configuration.glass()`.

```dart
const MorphGlassButton({
  required Widget child,
  required void Function()? onPressed,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
  Size minSize = const Size(44, 44),
  MorphGlassButtonAppearance? appearance,
  List<MorphMenuEntry>? menu,
  bool enabled = true,
  String? semanticLabel,
  Key? key,
})
const MorphGlassButton.clear({
  required Widget child,
  required void Function()? onPressed,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
  Size minSize = const Size(44, 44),
  MorphGlassButtonAppearance? appearance,
  List<MorphMenuEntry>? menu,
  bool enabled = true,
  String? semanticLabel,
  Key? key,
})
const MorphGlassButton.prominent({
  required Widget child,
  required void Function()? onPressed,
  Color? tint,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
  Size minSize = const Size(44, 44),
  MorphGlassButtonAppearance? appearance,
  List<MorphMenuEntry>? menu,
  bool enabled = true,
  String? semanticLabel,
  Key? key,
})
const MorphGlassButton.prominentClear({
  required Widget child,
  required void Function()? onPressed,
  Color? tint,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
  Size minSize = const Size(44, 44),
  MorphGlassButtonAppearance? appearance,
  List<MorphMenuEntry>? menu,
  bool enabled = true,
  String? semanticLabel,
  Key? key,
})
```

### MorphGlassButtonAppearance

`class MorphGlassButtonAppearance implements MorphAppearance`

The look of a [MorphGlassButton].

```dart
const MorphGlassButtonAppearance({
  Color fillColor = const Color(0xD9FFFFFF),
  Color clearFillColor = const Color(0x40FFFFFF),
  Color rimColor = const Color(0x1F000000),
  Color prominentColor = const Color(0xFF0088FF),
  Color prominentRimColor = const Color(0x33FFFFFF),
  Color foregroundColor = const Color(0xFF000000),
  Color prominentForegroundColor = const Color(0xFFFFFFFF),
  Color shadowColor = const Color(0x1A000000),
  Color disabledForegroundColor = const Color(0x4C3C3C43),
  Color disabledTintColor = const Color(0xFFD1D1D6),
})
static const MorphGlassButtonAppearance dark
static const MorphGlassButtonAppearance light
static MorphGlassButtonAppearance resolve(
  BuildContext context,
  MorphGlassButtonAppearance? explicit,
)
```

### MorphGlassContainer

`class MorphGlassContainer extends StatelessWidget`

Shades the resting glass of the controls below it in one glass layer: one geometry pass and one backdrop filter for all of them instead of one each.

```dart
const MorphGlassContainer({
  required Widget child,
  Color? solidBackdrop,
  Key? key,
})
```

### MorphGlassEffect

`class MorphGlassEffect extends StatefulWidget`

Liquid Glass behind app content, in a shape: SwiftUI's `glassEffect(_:in:)` and UIKit's `UIVisualEffectView` with a `UIGlassEffect`.

```dart
const MorphGlassEffect({
  required Widget child,
  ShapeBorder shape = const StadiumBorder(),
  MorphGlassStyle style = MorphGlassStyle.regular,
  Color? tint,
  bool interactive = false,
  MorphGlassButtonAppearance? appearance,
  Key? key,
})
```

### MorphGlassRenderer

`sealed class MorphGlassRenderer`

Which glass the controls draw: chosen by the device, or one fixed tier.

```dart
const MorphGlassRenderer()
const factory MorphGlassRenderer.adaptive()
const factory MorphGlassRenderer.tier(MorphGlassTier tier)
```

### MorphGlassStyle

`enum MorphGlassStyle`

The two Liquid Glass materials an app picks per surface (`UIGlassEffect.Style`, SwiftUI `Glass.regular` / `Glass.clear`).

```dart
regular,
clear,
```

### MorphGlassTier

`enum MorphGlassTier`

The two looks of the built-in glass, cheapest first.

```dart
flat,
liquid,
```

### MorphLargeTitle

`class MorphLargeTitle extends StatelessWidget`

The large title of a screen: 34 point bold text at the leading edge, in a [MorphNavigationBarMetrics.largeTitleHeight] tall area that scrolls with the content.

```dart
const MorphLargeTitle(
  String title, {
  String? subtitle,
  MorphBarAppearance? appearance,
  Key? key,
})
static double extentFor({required bool subtitle})
```

### MorphLargeTitleDisplayMode

`enum MorphLargeTitleDisplayMode`

When a [MorphNavigationScaffold] shows its title large, after UIKit's `UINavigationItem.LargeTitleDisplayMode`.

```dart
automatic,
always,
never,
```

### MorphListAccessory

`enum MorphListAccessory`

The standard accessory of a [MorphListRow], after UIKit's `UITableViewCell.AccessoryType`.

```dart
disclosureIndicator,
checkmark,
detailButton,
detailDisclosureButton,
```

### MorphListAppearance

`class MorphListAppearance implements MorphAppearance`

The look of an inset grouped list: [MorphListSection] and [MorphListRow].

```dart
const MorphListAppearance({
  Color backgroundColor = const Color(0xFFF2F2F7),
  Color cellColor = const Color(0xFFFFFFFF),
  Color highlightColor = const Color(0xFFD1D1D6),
  Color separatorColor = const Color(0x1F3C3C43),
  Color titleColor = const Color(0xFF000000),
  Color secondaryColor = const Color(0x993C3C43),
  Color chevronColor = const Color(0x4C3C3C43),
  Color iconColor = const Color(0xFF0088FF),
})
static const MorphListAppearance dark
static const MorphListAppearance light
static MorphListAppearance resolve(
  BuildContext context,
  MorphListAppearance? explicit,
)
```

### MorphListBackground

`class MorphListBackground extends StatelessWidget`

The page behind an inset grouped list: [MorphListAppearance.backgroundColor] under [child], the `backgroundColor` of a `UITableView(style: .insetGrouped)`.

```dart
const MorphListBackground({
  MorphListAppearance? appearance,
  Widget? child,
  Key? key,
})
```

### MorphListRow

`class MorphListRow extends StatefulWidget`

A row of an inset grouped list in the manner of a UIKit list cell (`UIListContentConfiguration` cell, subtitle cell and value cell).

```dart
const MorphListRow({
  Widget? title,
  Widget? subtitle,
  Widget? detail,
  Widget? leading,
  Widget? trailing,
  MorphListAccessory? accessory,
  void Function()? onAccessoryTap,
  Widget? child,
  void Function()? onTap,
  bool enabled = true,
  MorphListAppearance? appearance,
  Key? key,
})
```

### MorphListSection

`class MorphListSection extends StatelessWidget`

One section of an inset grouped list, as iOS 27 settings and index screens draw it: an optional [header], the [children] on one rounded card inset from the screen edges, and an optional [footer].

```dart
const MorphListSection({
  required List<Widget> children,
  Widget? header,
  Widget? footer,
  MorphListAppearance? appearance,
  Key? key,
})
```

### MorphLocalizations

`abstract class MorphLocalizations`

The strings morph's controls announce and show.

```dart
const MorphLocalizations()
static MorphLocalizations of(BuildContext context)
```

### MorphMenuAppearance

`class MorphMenuAppearance implements MorphAppearance`

The look of a [MorphMenuButton] and its menu.

```dart
const MorphMenuAppearance({
  Color glassColor = const Color(0xF2F9F9FF),
  Color shadowColor = const Color(0x33000000),
  double shadowElevation = 12,
  TextStyle textStyle = const TextStyle(fontSize: 17, color: Color(0xF5000000)),
  Color iconColor = const Color(0xF5000000),
  Color disabledIconColor = const Color(0x4C3C3C43),
  double iconSize = MorphMenuTuning.rowIconSize,
  Color destructiveColor = const Color(0xFFFF383C),
  Color highlightColor = const Color(0x1F000000),
  Color secondaryColor = const Color(0x993C3C43),
  Color disabledColor = const Color(0x4C3C3C43),
  Color separatorColor = const Color(0x14000000),
  Color submenuColor = const Color(0x66FFFFFF),
  Color glassTint = const Color(0x00000000),
  Color submenuRimColor = const Color(0xFFFFFFFF),
  Color submenuShadowColor = const Color(0x1E000000),
  Color paletteSelectionColor = const Color(0x10000000),
})
static const MorphMenuAppearance dark
static const MorphMenuAppearance light
static MorphMenuAppearance resolve(
  BuildContext context,
  MorphMenuAppearance? explicit,
)
```

### MorphMenuButton

`class MorphMenuButton extends _MorphMenuSourceWidget`

A round glass button that turns into its menu exactly like an iOS 27 `UIButton` whose menu is its primary action: the glass ellipsis configuration of [MorphMenuSource].

```dart
const MorphMenuButton({
  required List<MorphMenuEntry> menu,
  Widget? child,
  double size = MorphMenuTuning.buttonDiameter,
  MorphMenuAppearance? appearance,
  OverlayState? overlay,
  String? semanticLabel,
  bool enabled = true,
  MorphMenuOrder order = MorphMenuOrder.automatic,
  bool? dismissOnSelect,
  Key? key,
})
```

### MorphMenuDeferred

`class MorphMenuDeferred extends MorphMenuEntry`

Entries that load when the menu opens: `UIDeferredMenuElement`.

```dart
const MorphMenuDeferred(
  Future<List<MorphMenuEntry>> Function() load, {
  bool cache = true,
  Object? id,
  String loadingTitle = 'Loading...',
})
```

### MorphMenuDivider

`class MorphMenuDivider extends MorphMenuEntry`

A break between two groups of rows: a SwiftUI `Divider`.

```dart
const MorphMenuDivider()
```

### MorphMenuElementSize

`enum MorphMenuElementSize`

How a section lays out its rows: UIKit's `preferredElementSize`.

```dart
small,
medium,
large,
automatic,
```

### MorphMenuEntry

`sealed class MorphMenuEntry`

One element of a menu: a row, a section, a submenu, a divider, a deferred group or a free-form row.

```dart
const MorphMenuEntry()
```

### MorphMenuIconVisibility

`enum MorphMenuIconVisibility`

Whether a row shows its glyph: UIKit's `preferredImageVisibility`.

```dart
automatic,
visible,
hidden,
```

### MorphMenuItem

`class MorphMenuItem extends MorphMenuEntry`

A row that runs an action: `UIAction` or a SwiftUI `Button`.

```dart
const MorphMenuItem({
  required String title,
  String? subtitle,
  Widget? icon,
  Widget? selectedIcon,
  Color? iconColor,
  MorphMenuIconVisibility iconVisibility = MorphMenuIconVisibility.automatic,
  bool enabled = true,
  bool destructive = false,
  bool hidden = false,
  bool keepsMenuOpen = false,
  MorphMenuState state = MorphMenuState.off,
  void Function()? onSelected,
  void Function(bool)? onHighlightChanged,
})
```

### MorphMenuOrder

`enum MorphMenuOrder`

The order of a menu's entries relative to its button: `preferredMenuElementOrder`.

```dart
automatic,
priority,
fixed,
```

### MorphMenuSection

`class MorphMenuSection extends MorphMenuEntry`

A group of entries shown inline: `UIMenu` with `displayInline`, or a SwiftUI `Section`.

```dart
const MorphMenuSection({
  required List<MorphMenuEntry> children,
  String? title,
  bool singleSelection = false,
  MorphMenuElementSize elementSize = MorphMenuElementSize.large,
  bool palette = false,
  int? maxTitleLines,
})
```

### MorphMenuSource

`class MorphMenuSource extends _MorphMenuSourceWidget`

Turns [child] into its own morphing menu, as iOS 27 does for any `UIButton` with a menu, a `UIBarButtonItem.menu` or a control's context menu interaction.

```dart
const MorphMenuSource({
  required List<MorphMenuEntry> menu,
  required Widget child,
  Widget? look,
  ShapeBorder shape = const StadiumBorder(),
  MorphMenuTrigger trigger = MorphMenuTrigger.tap,
  void Function()? onTap,
  Color? color,
  Color? rimColor,
  bool focusable = true,
  MorphMenuAppearance? appearance,
  OverlayState? overlay,
  String? semanticLabel,
  bool enabled = true,
  MorphMenuOrder order = MorphMenuOrder.automatic,
  bool? dismissOnSelect,
  Key? key,
})
static void open(BuildContext context)
```

### MorphMenuState

`enum MorphMenuState`

The selection mark of a [MorphMenuItem]: UIKit's `UIMenuElementState`.

```dart
off,
on,
mixed,
```

### MorphMenuTrigger

`enum MorphMenuTrigger`

What makes a [MorphMenuSource] open its menu.

```dart
tap,
hold,
```

### MorphMenuWidget

`class MorphMenuWidget extends MorphMenuEntry`

A free-form row built by the app, for content no native element covers (a slider, a stepper, a custom control).

```dart
const MorphMenuWidget({
  required Widget Function(BuildContext) builder,
  double? height,
  Object? id,
})
```

### MorphNavigationBar

`class MorphNavigationBar extends StatefulWidget`

An iOS 27 navigation bar: glass button capsules at the sides, a title between them, no background of its own.

```dart
const MorphNavigationBar({
  String? title,
  String? subtitle,
  List<MorphBarButtonGroup> leading = const [],
  List<MorphBarButtonGroup> trailing = const [],
  bool titleVisible = true,
  bool scrolledUnder = false,
  bool animate = true,
  MorphScrollEdgeEffectStyle? edgeEffect = MorphScrollEdgeEffectStyle.hard,
  MorphScrollEdgeEffectAppearance? edgeEffectAppearance,
  MorphBarAppearance? appearance,
  MorphMenuAppearance? menuAppearance,
  double sideInset = MorphNavigationBarMetrics.sideInset,
  Key? key,
})
static double heightFor(double topInset)
```

### MorphNavigationBarHiding

`class MorphNavigationBarHiding`

How far a screen's navigation bar is hidden, 0 shown and 1 hidden, following [MorphNavigationScaffold.navigationBarHidden] and [MorphNavigationScaffold.setNavigationBarHidden].

```dart
static const double largeTitleFade
```

### MorphNavigationConfig

`class MorphNavigationConfig`

What one screen of a [MorphNavigationStack] shows in the shared bars.

```dart
const MorphNavigationConfig({
  String? title,
  List<MorphBarButtonGroup> leading = const [],
  List<MorphBarButtonGroup> trailing = const [],
  List<MorphBarButtonGroup> toolbarLeading = const [],
  List<MorphBarButtonGroup> toolbarTrailing = const [],
  bool titleVisible = true,
  bool scrolledUnder = false,
  bool animate = true,
  MorphScrollEdgeEffectStyle? edgeEffect = MorphScrollEdgeEffectStyle.hard,
  String? backButtonTitle,
  String? subtitle,
  MorphBackButtonDisplayMode backButtonDisplayMode = MorphBackButtonDisplayMode.standard,
  bool hidesBackButton = false,
  MorphLargeTitleDisplayMode largeTitleDisplayMode = MorphLargeTitleDisplayMode.never,
  bool navigationBarHidden = false,
  MorphNavigationBarHiding? barHiding,
})
```

### MorphNavigationPage

`class MorphNavigationPage<T> extends Page<T>`

A page of a [MorphNavigationStack.pages] stack (or of any Navigator 2 navigator) that shows [child] in a [MorphNavigationRoute]: it slides in and pops by the edge swipe, or with a [from] zooms out of that source.

```dart
const MorphNavigationPage({
  required Widget child,
  MorphSourceLink? from,
  LocalKey? key,
  String? name,
  Object? arguments,
  String? restorationId,
})
```

### MorphNavigationRoute

`class MorphNavigationRoute<T> extends PageRoute<T> with MorphMotionRouteMixin<T>`

A page of a [MorphNavigationStack] (or of any navigator) that moves like a UIKit navigation controller's.

```dart
MorphNavigationRoute({
  required Widget Function(BuildContext) builder,
  MorphSourceLink? from,
  RouteSettings? settings,
})
```

### MorphNavigationScaffold

`class MorphNavigationScaffold extends StatefulWidget`

One screen of an iOS 27 app: a scroll view under a navigation bar with an optional large title, the scroll edge effect, and an optional toolbar.

```dart
const MorphNavigationScaffold({
  required String title,
  required List<Widget> slivers,
  MorphLargeTitleDisplayMode largeTitleDisplayMode = MorphLargeTitleDisplayMode.automatic,
  String? subtitle,
  String? largeSubtitle,
  List<MorphBarButtonGroup> leading = const [],
  List<MorphBarButtonGroup> trailing = const [],
  List<MorphBarButtonGroup> toolbarLeading = const [],
  List<MorphBarButtonGroup> toolbarTrailing = const [],
  MorphScrollEdgeEffectStyle? edgeEffect = MorphScrollEdgeEffectStyle.hard,
  Color? backgroundColor,
  String? backButtonTitle,
  MorphBackButtonDisplayMode backButtonDisplayMode = MorphBackButtonDisplayMode.standard,
  bool hidesBackButton = false,
  String? backButtonSemanticLabel,
  ScrollController? controller,
  MorphBarAppearance? appearance,
  MorphNavigationSearch? search,
  bool navigationBarHidden = false,
  bool showsVerticalScrollIndicator = true,
  Key? key,
})
static void setNavigationBarHidden(
  BuildContext context, {
  required bool hidden,
})
```

### MorphNavigationSearch

`class MorphNavigationSearch`

The search of a [MorphNavigationScaffold] page: a search field stacked under the large title (UIKit `UINavigationItem.searchController` with the `stacked` search bar placement, the page of a search tab without `automaticallyActivatesSearch`; SwiftUI `searchable` with `navigationBarDrawer` placement).

```dart
const MorphNavigationSearch({
  TextEditingController? controller,
  FocusNode? focusNode,
  String? placeholder,
  void Function(String)? onChanged,
  void Function(String)? onSubmitted,
  bool? active,
  void Function(bool)? onActiveChanged,
  bool hidesNavigationBarDuringPresentation = true,
  MorphSearchFieldAppearance? appearance,
  String? closeLabel,
})
```

### MorphNavigationStack

`class MorphNavigationStack extends StatefulWidget`

A navigation stack in the iOS 27 manner: one navigation bar and one toolbar shared by every screen, whose glass buttons morph from one screen's into the next one's as screens are pushed and popped.

```dart
const MorphNavigationStack({
  required Widget home,
  MorphBarAppearance? appearance,
  MorphMenuAppearance? menuAppearance,
  String? backButtonSemanticLabel,
  GlobalKey<NavigatorState>? navigatorKey,
  List<NavigatorObserver> observers = const [],
  bool prefersLargeTitles = false,
  bool contentPopGestureEnabled = true,
  String? restorationScopeId,
  Key? key,
})
const MorphNavigationStack.pages({
  required List<Page<Object?>> pages,
  required void Function(Page<Object?>) onDidRemovePage,
  MorphBarAppearance? appearance,
  MorphMenuAppearance? menuAppearance,
  String? backButtonSemanticLabel,
  GlobalKey<NavigatorState>? navigatorKey,
  List<NavigatorObserver> observers = const [],
  bool prefersLargeTitles = false,
  bool contentPopGestureEnabled = true,
  String? restorationScopeId,
  Key? key,
})
```

### MorphPageControl

`class MorphPageControl extends StatefulWidget`

A page control that looks and steps like iOS 27's UIPageControl.

```dart
const MorphPageControl({
  required int count,
  required int page,
  required void Function(int)? onChanged,
  double? progress,
  MorphPageControlBackgroundStyle backgroundStyle = MorphPageControlBackgroundStyle.automatic,
  MorphPageControlAppearance? appearance,
  String? semanticLabel,
  String Function(int, int)? semanticValueFormatter,
  Key? key,
})
```

### MorphPageControlAppearance

`class MorphPageControlAppearance implements MorphAppearance`

The look of a [MorphPageControl].

```dart
const MorphPageControlAppearance({
  Color pageIndicatorColor = const Color(0x73FFFFFF),
  Color currentPageIndicatorColor = const Color(0xFFFFFFFF),
  Color platterColor = const Color(0xFFF0F0F2),
  Color platterIndicatorColor = const Color(0x40000000),
})
static const MorphPageControlAppearance dark
static const MorphPageControlAppearance darkHighContrast
static const MorphPageControlAppearance light
static const MorphPageControlAppearance lightHighContrast
static MorphPageControlAppearance resolve(
  BuildContext context,
  MorphPageControlAppearance? explicit,
)
```

### MorphPageControlBackgroundStyle

`enum MorphPageControlBackgroundStyle`

When a [MorphPageControl] shows its platter, after UIPageControl.BackgroundStyle.

```dart
automatic,
prominent,
minimal,
```

### MorphProgressView

`class MorphProgressView extends StatefulWidget`

A progress bar that looks and animates like iOS 27's UIProgressView.

```dart
const MorphProgressView({
  required double value,
  bool animated = true,
  MorphProgressViewStyle style = MorphProgressViewStyle.standard,
  Color? activeTrackColor,
  Color? inactiveTrackColor,
  MorphProgressViewAppearance? appearance,
  String? semanticLabel,
  Key? key,
})
static const double barHeight
static const double standardHeight
```

### MorphProgressViewAppearance

`class MorphProgressViewAppearance implements MorphAppearance`

The look of a [MorphProgressView].

```dart
const MorphProgressViewAppearance({
  Color inactiveTrackColor = const Color(0x33787880),
  Color activeTrackColor = const Color(0xFF0088FF),
})
static const MorphProgressViewAppearance dark
static const MorphProgressViewAppearance darkHighContrast
static const MorphProgressViewAppearance light
static const MorphProgressViewAppearance lightHighContrast
static MorphProgressViewAppearance resolve(
  BuildContext context,
  MorphProgressViewAppearance? explicit,
)
```

### MorphProgressViewStyle

`enum MorphProgressViewStyle`

The two looks of a [MorphProgressView], after UIProgressView.Style.

```dart
standard,
bar,
```

### MorphSatellite

`class MorphSatellite`

A block standing above a context menu's preview, as UIKit's accessory views do - a reactions capsule over a message bubble - built when the menu opens, so it reads the state of that moment.

```dart
const MorphSatellite({
  double? height,
  required Widget Function(BuildContext) builder,
})
```

### MorphScrollEdgeEffect

`class MorphScrollEdgeEffect extends StatelessWidget`

The iOS 27 scroll edge effect: what replaces a bar's solid background when content scrolls under it.

```dart
const MorphScrollEdgeEffect({
  required double extent,
  AxisDirection edge = AxisDirection.up,
  MorphScrollEdgeEffectStyle style = MorphScrollEdgeEffectStyle.soft,
  bool scrolledUnder = true,
  MorphScrollEdgeEffectAppearance? appearance,
  double opacity = 1,
  Key? key,
})
static double bandExtent(
  MorphScrollEdgeEffectStyle style,
  double extent,
  MorphScrollEdgeEffectAppearance appearance,
)
```

### MorphScrollEdgeEffectAppearance

`class MorphScrollEdgeEffectAppearance implements MorphAppearance`

The look of a [MorphScrollEdgeEffect].

```dart
const MorphScrollEdgeEffectAppearance({
  Color backgroundColor = const Color(0xFFFFFFFF),
  double fadeOpacity = 0.5,
  Color separatorColor = const Color(0x1A000000),
  double softBlurRadius = 1.5,
  double hardBlurRadius = 2,
  double softOverhang = 40,
  double softFadeStart = 0.3407,
  double hardSaturation = 1.25,
  double hardBrightness = 0.03,
})
static const MorphScrollEdgeEffectAppearance dark
static const MorphScrollEdgeEffectAppearance light
static MorphScrollEdgeEffectAppearance resolve(
  BuildContext context,
  MorphScrollEdgeEffectAppearance? explicit,
)
```

### MorphScrollEdgeEffectStyle

`enum MorphScrollEdgeEffectStyle`

How a [MorphScrollEdgeEffect] separates the content under a bar.

```dart
soft,
hard,
```

### MorphScrollIndicator

`class MorphScrollIndicator extends StatefulWidget`

UIKit's vertical scroll indicator over a scroll view driven by [controller]: a thin bar along the trailing edge that shows while the content moves and fades out once it rests (see [MorphScrollIndicatorTuning] for the measured look and timing).

```dart
const MorphScrollIndicator({
  required ScrollController controller,
  EdgeInsets padding = EdgeInsets.zero,
  EdgeInsets contentPadding = EdgeInsets.zero,
  Color? color,
  Key? key,
})
```

### MorphSearchField

`class MorphSearchField extends StatefulWidget`

The iOS 27 search field: a glass capsule with a magnifier, the text and a clear button.

```dart
const MorphSearchField({
  TextEditingController? controller,
  FocusNode? focusNode,
  String? placeholder,
  void Function(String)? onChanged,
  void Function(String)? onSubmitted,
  bool enabled = true,
  bool autofocus = false,
  MorphSearchFieldAppearance? appearance,
  String? semanticLabel,
  String clearLabel = 'Clear text',
  double height = MorphSearchTuning.height,
  bool glass = true,
  Key? key,
})
static const double maxTextScale
```

### MorphSearchFieldAppearance

`class MorphSearchFieldAppearance implements MorphAppearance`

The look of a [MorphSearchField] and a [MorphSearchToolbar].

```dart
const MorphSearchFieldAppearance({
  Color capsuleColor = const Color(0xD9FFFFFF),
  Color rimColor = const Color(0x1F000000),
  Color shadowColor = const Color(0x1A000000),
  Color textColor = const Color(0xFF000000),
  Color placeholderColor = const Color(0x993C3C43),
  Color restingPlaceholderColor = const Color(0x69000000),
  Color glyphColor = const Color(0xFF000000),
  Color clearColor = const Color(0xFF000000),
  Color clearGlyphColor = const Color(0xFFFFFFFF),
  Color cursorColor = const Color(0xFF426AF3),
  Color disabledFillColor = const Color(0x0F767680),
  Color stackedFillColor = const Color(0x1F767680),
})
static const MorphSearchFieldAppearance dark
static const MorphSearchFieldAppearance light
static MorphSearchFieldAppearance resolve(
  BuildContext context,
  MorphSearchFieldAppearance? explicit,
)
```

### MorphSearchTabBar

`class MorphSearchTabBar extends StatefulWidget`

A floating [MorphTabBar] with a search tab that turns into a search field, as iOS 27 shows a UITabBarController whose UISearchTab activates search.

```dart
const MorphSearchTabBar({
  required List<MorphTabItem> items,
  required int selected,
  required void Function(int)? onChanged,
  required bool active,
  required void Function(bool) onActiveChanged,
  TextEditingController? controller,
  FocusNode? focusNode,
  String? placeholder,
  void Function(String)? onQueryChanged,
  void Function(String)? onSubmitted,
  String? searchLabel,
  String? closeLabel,
  MorphTabBarAppearance? appearance,
  MorphSearchFieldAppearance? searchAppearance,
  MorphTabBarMinimizeBehavior minimizeBehavior = MorphTabBarMinimizeBehavior.automatic,
  Widget? bottomAccessory,
  MorphContentScroll? contentScroll,
  Key? key,
})
```

### MorphSearchToolbar

`class MorphSearchToolbar extends StatefulWidget`

The bottom-placed search bar of iOS 27: a search field in the toolbar that expands above the keyboard when it is focused.

```dart
const MorphSearchToolbar({
  TextEditingController? controller,
  FocusNode? focusNode,
  String? placeholder,
  List<MorphBarButtonGroup> leading = const [],
  List<MorphBarButtonGroup> trailing = const [],
  void Function(String)? onChanged,
  void Function(String)? onSubmitted,
  void Function(bool)? onActiveChanged,
  bool? active,
  MorphSearchFieldAppearance? appearance,
  MorphGlassButtonAppearance? buttonAppearance,
  String? closeLabel,
  bool hidesNavigationBarDuringPresentation = true,
  Key? key,
})
```

### MorphSegment

`class MorphSegment`

One segment of a [MorphSegmentedControl]: UIKit's segment title (`insertSegment(withTitle:at:animated:)`).

```dart
const MorphSegment(String title, {bool enabled = true, double? width})
```

### MorphSegmentedControl

`class MorphSegmentedControl extends StatefulWidget`

A segmented control whose selection lens moves exactly like UISegmentedControl's on iOS 27.

```dart
const MorphSegmentedControl({
  required List<MorphSegment> segments,
  required int? selectedIndex,
  required void Function(int)? onChanged,
  bool proportionalWidth = false,
  MorphSegmentedControlAppearance? appearance,
  Key? key,
})
static const double maxTextScale
static const double releaseSlop
```

### MorphSegmentedControlAppearance

`class MorphSegmentedControlAppearance implements MorphAppearance`

The look of a [MorphSegmentedControl].

```dart
const MorphSegmentedControlAppearance({
  double height = 32,
  double inset = 2,
  Color trackColor = const Color(0x1F767680),
  Color lensColor = const Color(0xFFFFFFFF),
  Color liftedLensColor = const Color(0x40FFFFFF),
  Color lensBorderColor = const Color(0x33000000),
  Color shadowColor = const Color(0x1F000000),
  TextStyle textStyle = const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: Color(0xFF000000)),
  TextStyle selectedTextStyle = const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF000000)),
  double contentPadding = 9.15,
  double disabledOpacity = 0.5,
})
static const MorphSegmentedControlAppearance dark
static const MorphSegmentedControlAppearance darkHighContrast
static const MorphSegmentedControlAppearance light
static const MorphSegmentedControlAppearance lightHighContrast
static MorphSegmentedControlAppearance resolve(
  BuildContext context,
  MorphSegmentedControlAppearance? explicit,
)
```

### MorphSheet

`abstract class MorphSheet`

What the content of a sheet presented with [showMorphSheet] can do with its sheet.

```dart
MorphSheet()
static MorphSheet? maybeOf(BuildContext context)
static MorphSheet of(BuildContext context)
static ScrollController scrollControllerOf(BuildContext context)
```

### MorphSheetAppearance

`class MorphSheetAppearance implements MorphAppearance`

The look of a sheet presented with [showMorphSheet].

```dart
const MorphSheetAppearance({
  Color dockedColor = const Color(0xFFFFFFFF),
  Color floatingColor = const Color(0xF2F9F9F9),
  Color grabberColor = const Color(0x4D3C3C43),
  Color dimmingColor = const Color(0xFF000000),
  Color textColor = const Color(0xFF000000),
})
static const MorphSheetAppearance dark
static const MorphSheetAppearance light
static MorphSheetAppearance resolve(
  BuildContext context,
  MorphSheetAppearance? explicit,
)
```

### MorphSheetDetent

`class MorphSheetDetent`

A height a sheet rests at, after UISheetPresentationController.Detent.

```dart
const MorphSheetDetent.custom(
  double Function(double) resolver, {
  Object? identifier,
})
const MorphSheetDetent.fraction(double fraction)
const MorphSheetDetent.height(double value)
static const MorphSheetDetent fitted
static const MorphSheetDetent large
static const MorphSheetDetent medium
```

### MorphSheetRoute

`class MorphSheetRoute<T> extends PopupRoute<T> with MorphMotionRouteMixin<T>, GlassBackdropCacheRoute<T>`

The route [showMorphSheet] pushes: the sheet as a real navigator route, so the back button, `Navigator.pop` and pop scopes work as on any route.

```dart
MorphSheetRoute({
  required Widget Function(BuildContext) builder,
  required List<MorphSheetDetent> detents,
  MorphSourceLink? from,
  MorphSheetDetent? initialDetent,
  MorphSheetDetent? largestUndimmedDetent,
  bool grabberVisible = false,
  bool dismissible = true,
  bool scrollingExpandsSheet = true,
  MorphSheetAppearance? appearance,
  String? semanticLabel,
  void Function(MorphSheetDetent)? onDetentChanged,
  void Function()? onDismissAttempt,
  RouteSettings? settings,
})
```

### MorphSlider

`class MorphSlider extends StatefulWidget`

A slider that moves exactly like iOS 27's UISlider.

```dart
const MorphSlider({
  required double value,
  required void Function(double)? onChanged,
  void Function(double)? onChangeStart,
  void Function(double)? onChangeEnd,
  double min = 0,
  double max = 1,
  Color? activeTrackColor,
  Color? inactiveTrackColor,
  MorphSliderAppearance? appearance,
  String? semanticLabel,
  int ticks = 0,
  bool animated = false,
  Key? key,
})
static const double height
static const double keyboardStep
```

### MorphSliderAppearance

`class MorphSliderAppearance implements MorphAppearance`

The look of a [MorphSlider].

```dart
const MorphSliderAppearance({
  Color activeTrackColor = const Color(0xFF0088FF),
  Color inactiveTrackColor = const Color(0x1A000000),
  Color thumbColor = const Color(0xFFFFFFFF),
  Color tickColor = const Color(0xFFC6C6C8),
  double disabledOpacity = 0.5,
})
static const MorphSliderAppearance dark
static const MorphSliderAppearance darkHighContrast
static const MorphSliderAppearance light
static const MorphSliderAppearance lightHighContrast
static MorphSliderAppearance resolve(
  BuildContext context,
  MorphSliderAppearance? explicit,
)
```

### MorphSliverListSection

`class MorphSliverListSection extends StatelessWidget`

A [MorphListSection] as a sliver that builds its rows lazily, for a long list in a [CustomScrollView] (a `UITableView` section of many cells, SwiftUI `Section` in a `List`).

```dart
const MorphSliverListSection({
  required Widget Function(BuildContext, int) itemBuilder,
  required int itemCount,
  Widget? header,
  Widget? footer,
  MorphListAppearance? appearance,
  Key? key,
})
```

### MorphSource

`class MorphSource extends StatelessWidget`

Attaches [link] to [child], so presentations shown from the link morph out of and back into [child].

```dart
const MorphSource({
  required MorphSourceLink link,
  required Widget child,
  ShapeBorder shape = const RoundedRectangleBorder(),
  Key? key,
})
```

### MorphSourceLink

`final class MorphSourceLink`

Names a widget as the source a presentation morphs out of and back into.

```dart
MorphSourceLink()
```

### MorphStepper

`class MorphStepper extends StatefulWidget`

A stepper that responds to touch exactly like iOS 27's UIStepper.

```dart
const MorphStepper({
  required double value,
  required void Function(double)? onChanged,
  double min = 0,
  double max = 100,
  double step = 1,
  Color? backgroundColor,
  Color? foregroundColor,
  MorphStepperAppearance? appearance,
  String? decrementLabel,
  String? incrementLabel,
  String Function(double)? semanticFormatterCallback,
  Key? key,
})
static const Duration repeatInterval
static const Size size
```

### MorphStepperAppearance

`class MorphStepperAppearance implements MorphAppearance`

The look of a [MorphStepper].

```dart
const MorphStepperAppearance({
  Color backgroundColor = const Color(0x163C3C43),
  Color foregroundColor = const Color(0xFF000000),
  Color limitForegroundColor = const Color(0x4C3C3C43),
  Color pressedOverlay = const Color(0x14000000),
  bool pressedReplacesFill = false,
  Color dividerColor = const Color(0x4C3C3C43),
  double dividerHeight = 24,
})
static const MorphStepperAppearance dark
static const MorphStepperAppearance light
static MorphStepperAppearance resolve(
  BuildContext context,
  MorphStepperAppearance? explicit,
)
```

### MorphSubmenu

`class MorphSubmenu extends MorphMenuEntry`

A row that opens a nested menu as a card stacked over this one: a nested `UIMenu` or SwiftUI `Menu`.

```dart
const MorphSubmenu({
  required String title,
  required List<MorphMenuEntry> children,
  String? subtitle,
  Widget? icon,
  bool destructive = false,
  bool enabled = true,
  bool hidden = false,
  bool singleSelection = false,
  MorphMenuElementSize elementSize = MorphMenuElementSize.large,
})
```

### MorphSwitch

`class MorphSwitch extends StatefulWidget`

A switch that moves exactly like iOS 27's UISwitch.

```dart
const MorphSwitch({
  required bool value,
  required void Function(bool)? onChanged,
  Color? activeTrackColor,
  Color? inactiveTrackColor,
  MorphSwitchAppearance? appearance,
  String? semanticLabel,
  Key? key,
})
```

### MorphSwitchAppearance

`class MorphSwitchAppearance implements MorphAppearance`

The look of a [MorphSwitch].

```dart
const MorphSwitchAppearance({
  Color activeTrackColor = const Color(0xFF34C759),
  Color inactiveTrackColor = const Color(0x29787880),
  Color thumbColor = const Color(0xFFFFFFFF),
  double disabledOpacity = 0.5,
})
static const MorphSwitchAppearance dark
static const MorphSwitchAppearance darkHighContrast
static const MorphSwitchAppearance light
static const MorphSwitchAppearance lightHighContrast
static MorphSwitchAppearance resolve(
  BuildContext context,
  MorphSwitchAppearance? explicit,
)
```

### MorphTabAccessoryEnvironment

`enum MorphTabAccessoryEnvironment`

Where a tab bar's bottom accessory is laid out (UIKit `UITabAccessory.Environment`, the `tabAccessoryEnvironment` trait; SwiftUI `TabViewBottomAccessoryPlacement`).

```dart
none,
regular,
inline,
static MorphTabAccessoryEnvironment of(BuildContext context)
```

### MorphTabBar

`class MorphTabBar extends StatefulWidget`

A floating tab bar whose selection lens moves exactly like iOS 27's UITabBar.

```dart
const MorphTabBar({
  required List<MorphTabItem> items,
  required int selected,
  required void Function(int)? onChanged,
  void Function(int)? onReselected,
  MorphTabBarAppearance? appearance,
  MorphTabBarMinimizeBehavior minimizeBehavior = MorphTabBarMinimizeBehavior.automatic,
  Widget? bottomAccessory,
  MorphContentScroll? contentScroll,
  Key? key,
})
static const double maxTextScale
```

### MorphTabBarAppearance

`class MorphTabBarAppearance implements MorphAppearance`

The look of a [MorphTabBar].

```dart
const MorphTabBarAppearance({
  Color barColor = const Color(0xB8FFFFFF),
  Color shadowColor = const Color(0x24000000),
  Color platterColor = const Color(0x13000000),
  Color liftedLensColor = const Color(0x33FFFFFF),
  Color lensBorderColor = const Color(0x40000000),
  Color selectedColor = const Color(0xFF0082FC),
  Color color = const Color(0xFF0D0D0D),
  double blurSigma = 12,
})
static const MorphTabBarAppearance dark
static const MorphTabBarAppearance light
static MorphTabBarAppearance resolve(
  BuildContext context,
  MorphTabBarAppearance? explicit,
)
```

### MorphTabBarMinimizeBehavior

`enum MorphTabBarMinimizeBehavior`

When a [MorphTabBar] minimizes to its selected tab while the content under it scrolls (UIKit `UITabBarController.MinimizeBehavior`, SwiftUI `TabBarMinimizeBehavior`).

```dart
automatic,
never,
onScrollDown,
onScrollUp,
```

### MorphTabItem

`class MorphTabItem`

One item of a [MorphTabBar].

```dart
const MorphTabItem({
  required IconData icon,
  required String label,
  IconData? selectedIcon,
  MorphBadge? badge,
  bool enabled = true,
  MorphTabRole? role,
})
```

### MorphTabRole

`enum MorphTabRole`

What a [MorphTabItem] stands for beyond an ordinary tab (SwiftUI `TabRole`).

```dart
search,
```

### MorphTheme

`class MorphTheme extends StatelessWidget`

Applies [data] to the morph controls below it and installs the glass [MorphThemeData.glass] chooses.

```dart
const MorphTheme({
  required MorphThemeData data,
  required Widget child,
  Key? key,
})
static bool get liquidGlassAvailable
static String? get liquidGlassUnavailableReason
static MorphThemeData? maybeOf(BuildContext context)
static MorphThemeData of(BuildContext context)
static Future<void> precacheGlass()
```

### MorphThemeData

`class MorphThemeData`

The settings every morph control below a `MorphTheme` reads.

```dart
const MorphThemeData({
  Brightness? brightness,
  Color? tint,
  bool haptics = true,
  MorphGlassRenderer? glass,
  List<MorphAppearance> appearances = const <MorphAppearance>[],
})
```

### MorphToolbar

`class MorphToolbar extends StatelessWidget`

The iOS 27 toolbar: glass capsules floating over the bottom of the screen.

```dart
const MorphToolbar({
  List<MorphBarButtonGroup> leading = const [],
  List<MorphBarButtonGroup> trailing = const [],
  MorphBarAppearance? appearance,
  MorphMenuAppearance? menuAppearance,
  double sideInset = MorphToolbarMetrics.sideInset,
  double bottomInset = MorphToolbarMetrics.bottomInset,
  double keyboardInset = MorphToolbarMetrics.keyboardInset,
  Key? key,
})
static double get capsuleHeight
```

### MorphTypography

`abstract final class MorphTypography`

The text of the measured controls: the sizes and weights UIKit draws each control's labels with, and the system font set the way CoreText sets it.

```dart
MorphTypography()
static const TextStyle alertAction
static const TextStyle alertMessage
static const TextStyle alertTitle
static const TextStyle barButton
static const TextStyle barButtonProminent
static const TextStyle body
static const TextStyle button
static const TextStyle datePickerCompact
static const TextStyle datePickerDay
static const TextStyle datePickerDaySelected
static const TextStyle datePickerTitle
static const TextStyle datePickerWeekday
static const TextStyle largeTitle
static const TextStyle listFooter
static const TextStyle listHeader
static const TextStyle listSubtitle
static const TextStyle menuItem
static TextStyle resolve(TextStyle style, {bool? apple})
static const TextStyle searchField
static const TextStyle segment
static const TextStyle segmentSelected
static const TextStyle tabLabel
static const TextStyle tabLabelSelected
static const TextStyle title
static double tracking(double size)
static bool get usesAppleSystemFont
static double? weightAxis(FontWeight weight)
```

### showMorphActionSheet

`Future<MorphAlertAction?> showMorphActionSheet(`

Shows an action sheet the way iOS 27 presents one, and completes with the action the user chose.

```dart
Future<MorphAlertAction?> showMorphActionSheet(
  BuildContext context, {
  String? title,
  String? message,
  List<MorphAlertAction> actions = const [],
  BuildContext? anchor,
  Rect? anchorRect,
  MorphAlertAppearance? appearance,
  bool? useRootNavigator,
})
```

### showMorphAlert

`Future<MorphAlertAction?> showMorphAlert(`

Shows an alert that moves like an iOS 27 UIAlertController, and completes with the action the user chose.

```dart
Future<MorphAlertAction?> showMorphAlert(
  BuildContext context, {
  String? title,
  String? message,
  List<MorphAlertAction> actions = const [],
  List<MorphAlertTextField> textFields = const [],
  MorphAlertAppearance? appearance,
  bool? useRootNavigator,
})
```

### showMorphSheet

`Future<T?> showMorphSheet<T>(`

Presents [builder]'s content in a sheet that moves like an iOS 27 UISheetPresentationController, and completes with the value the sheet is popped with.

```dart
Future<T?> showMorphSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  MorphSourceLink? from,
  List<MorphSheetDetent> detents = const [MorphSheetDetent.large],
  MorphSheetDetent? initialDetent,
  MorphSheetDetent? largestUndimmedDetent,
  bool grabberVisible = false,
  bool dismissible = true,
  bool scrollingExpandsSheet = true,
  MorphSheetAppearance? appearance,
  String? semanticLabel,
  bool? useRootNavigator,
  void Function(MorphSheetDetent)? onDetentChanged,
  void Function()? onDismissAttempt,
})
```

## `package:morph/glass_painter.dart`

### MorphGlassGlow

`class MorphGlassGlow`

The glow a finger raises on a pressed glass surface, in one frame.

```dart
const MorphGlassGlow({
  required double wash,
  required Offset center,
  required double radius,
  required double gain,
})
```

### MorphGlassKind

`enum MorphGlassKind`

The role a surface plays in a control.

```dart
track,
lens,
knob,
thumb,
button,
bar,
menu,
```

### MorphGlassOptics

`class MorphGlassOptics`

The refraction tuning UIKit gives a liquid lens.

```dart
const MorphGlassOptics({
  double liftedDisplacement = 9,
  double unliftedDisplacement = 0,
  double unliftedBlurRadius = 0,
  double contentWrapperDisplacement = -17.5,
  double innerShadowRadius = 3,
  double innerShadowOpacity = 0.06,
  double innerShadowOffsetY = 7,
})
static const MorphGlassOptics large
static const MorphGlassOptics small
```

### MorphGlassOutline

`class MorphGlassOutline`

The silhouette a control has fused some of its glass surfaces into.

```dart
const MorphGlassOutline(Path path)
```

### MorphGlassPainter

`abstract class MorphGlassPainter`

Renders the glass surfaces of the measured controls.

```dart
const MorphGlassPainter()
```

### MorphGlassScope

`class MorphGlassScope extends InheritedTheme`

Installs a [MorphGlassPainter] for the measured controls below it.

```dart
const MorphGlassScope({
  required MorphGlassPainter painter,
  required Widget child,
  Key? key,
})
static MorphGlassPainter? maybeOf(BuildContext context)
```

### MorphGlassSurface

`class MorphGlassSurface`

One surface of a control in one frame, handed to a [MorphGlassPainter].

```dart
const MorphGlassSurface({
  required MorphGlassKind kind,
  required RRect shape,
  required Color color,
  required Brightness brightness,
  double lift = 0,
  double scaleX = 1,
  double scaleY = 1,
  MorphGlassOptics? optics,
  double? blurRadius,
  Color? tint,
  double transmissionGamma = 1,
  bool enabled = true,
  bool glass = true,
  double opacity = 1,
  MorphGlassGlow? glow,
  List<BoxShadow>? shadows,
  MorphGlassStyle? style,
})
```
