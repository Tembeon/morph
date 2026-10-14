# API parity - morph vs the public iOS 27 SDK

These pages compare morph's public Dart API with UIKit and SwiftUI as they are declared in the public
iPhoneOS27.0.sdk (UIKit headers, the UIKit Swift overlay, SwiftUI.swiftinterface). They do not use
private or reverse-engineered material. The goal is a public 1.0 API in which an iOS developer
recognizes concepts, options and defaults, written in Flutter idioms (value + onChanged, Widget
children, Color, Semantics).

Each family page holds UIKit and SwiftUI tables (API, availability, meaning, morph equivalent, gap,
proposal), a list of native API that does not apply to Flutter, ranked gaps (need x cost), and the
breaking changes it proposes before 1.0.

## Index

| family | page | passport |
|---|---|---|
| Glass material, container, fusion | [glass.md](glass.md) | glass-optics, glass-renderer, skin-merge, lens-and-flex |
| Glass buttons | [buttons.md](buttons.md) | glass-button, menu-button, states |
| Bars: bar items, navigation bar, toolbar | [bars.md](bars.md) | bars |
| Navigation stack, push, zoom | [navigation.md](navigation.md) | navigation-pages |
| Tab bar, search tab | [tab-bar.md](tab-bar.md) | tab-bar, search-tab-bar |
| Search | [search.md](search.md) | search, search-tab-bar |
| Sheets | [sheets.md](sheets.md) | sheets |
| Alerts, action sheets, popovers | [alerts.md](alerts.md) | alerts |
| Menus, context menus | [menus.md](menus.md) | menu-api, menu-button, context-menu |
| Segmented control | [segmented-control.md](segmented-control.md) | segmented-control |
| Switch | [switch.md](switch.md) | switch |
| Slider | [slider.md](slider.md) | slider |
| Stepper | [stepper.md](stepper.md) | stepper |
| Date picker | [date-picker.md](date-picker.md) | date-picker |
| Page control | [page-control.md](page-control.md) | page-control |
| Progress view, activity indicator | [progress.md](progress.md) | progress-view, activity-indicator |
| Lists | [lists.md](lists.md) | lists |
| Scroll edge effect | [scroll-edge-effect.md](scroll-edge-effect.md) | - |
| Shared across controls: tint, theming, naming, exports, a11y | [cross-cutting.md](cross-cutting.md) | - |

## Where the new API is

New public API with Liquid Glass (iOS 26/27), by family:
- Glass: `UIGlassEffect`, `UIGlassContainerEffect`, SwiftUI `Glass`, `GlassEffectContainer`, `glassEffectID` / `Union`.
- Buttons: `UIButton.Configuration` glass variants.
- Bars: `UIBarButtonItem` badge, `hidesSharedBackground` and `.prominent`; `UINavigationItem` subtitles; `ToolbarSpacer`; iOS 27 `UIBarMinimization`.
- Tab bar: `UITab`, `bottomAccessory`, `tabBarMinimizeBehavior`; iOS 27 `TabRole.prominent`.
- Slider: `UISlider.trackConfiguration` and the thumbless style.
- Scroll edge effect: `UIScrollEdgeEffect`.
- Lists (SwiftUI only): iOS 26 list section margins; iOS 27 `swipeActionsContainer`.

The segmented control, switch, stepper, date picker, page control, progress view and activity
indicator have no new API. Liquid Glass changed only how they look and move.

Passport corrections found here: `tab-bar.md` lists `UITabBar.leadingAccessoryView` /
`trailingAccessoryView`, which are tvOS-only (`API_UNAVAILABLE(ios)`). It also misses iOS 27
`TabRole.prominent`, `performBatchUpdates` and `UIBarMinimization`.

## Top gaps per family

Need is how often an app developer reaches for the API: H(igh) / M(ed) / L(ow).
Cost is S(mall) / M(edium) / L(arge); "meas." means the look or motion must be measured on the device first.

| family | gap | need | cost | proposal |
|---|---|---|---|---|
| cross-cutting | No ambient accent (`tintColor` / `.tint()`); accent repeated in 7+ look tables | H | S-M | `MorphWidgetsTheme.tint`, read by every control |
| cross-cutting | Theming requires a Material `Theme` ancestor | H | S | `MorphWidgetsThemeScope` (InheritedTheme) checked first |
| cross-cutting | ~60 motion / tuning / layout / seam types exported from `widgets.dart` | H | S-M | move to `motion.dart` / a glass-painter library |
| cross-cutting | Increase Contrast, Reduce Transparency, haptics, Dynamic Type not handled | M | M meas. | measure, then opt in |
| glass | No widget puts glass behind app content (`glassEffect(_:in:)`) | H | M | `MorphGlassEffect({child, shape, style, tint, interactive})` |
| glass | Regular vs clear is renderer-wide only | H | S-M | per-surface `MorphGlassStyle { regular, clear }` |
| glass | No fusion for app glass (`GlassEffectContainer(spacing:)`, `glassEffectID`) | M | M-L | `MorphGlassContainer.spacing`, `MorphGlassEffect.id` |
| buttons | No clear-glass variants | H | S-M | `MorphGlassButton.clear` / `.prominentClear` |
| buttons | Prominent needs an explicit color | H | S | `MorphGlassButton.prominent`, tint from the theme accent |
| buttons | No size presets / shape | M | M meas. | `MorphControlSize`, `MorphGlassButton.shape` |
| bars | No bar item badge (iOS 26) | H | S-M meas. | `MorphBarButton.badge: MorphBarBadge?` |
| bars | No subtitle / large subtitle (iOS 26) | H | M meas. | `subtitle` / `largeSubtitle` on scaffold, config, bar |
| bars | No `backButtonDisplayMode`, no `hidesBackButton` | H | S | `MorphBackButtonDisplayMode`, `hidesBackButton` |
| bars | No `titleView`, no title menu | M-H | M | `titleView`, `titleMenu` |
| navigation | No Navigator 2 / go_router path (pages API, `Page` class) | H | M | `MorphNavigationPage`, `MorphNavigationStack.pages` |
| navigation | No full-width content back swipe (iOS 26) | H | M meas. | default on in `MorphNavigationRoute` after measuring |
| navigation | No zoom from a bar button; no zoom `dimmingColor` / dismiss veto | M | S-M | bar buttons register tags; tuning + callback |
| tab bar | No tab badges | H | M meas. | `MorphTabItem.badge` + style colors |
| tab bar | A tap on the selected tab is not reported (scroll to top / pop to root) | H | S | `MorphTabBar.onReselected` |
| tab bar | No `selectedIcon`, icons only `IconData`, no public bar extent | M-H | S-M | `selectedIcon`, Widget icons, `MorphTabBar.extentFor` |
| tab bar | No minimize on scroll, no bottom accessory | M | L meas. | later, after measuring |
| search | Search can't be ended from code (`isActive` / `dismissSearch`) | H | S | controlled `active` + `onActiveChanged` |
| search | Search is not part of the navigation bars (`navigationItem.searchController`) | H | M | `MorphNavigationConfig.search` |
| search | No suggestions, no scope bar, one placement only | M | M-L | `suggestions`, `scopes`, `MorphSearchPlacement` |
| sheets | No dismiss veto / attempt callback (`presentationControllerShouldDismiss`) | H | M | `onDismissAttempt`; `PopScope.canPop` blocks drag too |
| sheets | No detent-change callback | H | S | `onDetentChanged` |
| sheets | No content-sized (`.fitted`) or resolver (`.custom`) detent | H | M | `MorphSheetDetent.custom(resolver)` + fitted |
| sheets | No full-screen cover, no corner radius | M | S-M | `presentMorphFullScreen`, `cornerRadius` |
| alerts | Actions can't be enabled live (OK after typing) | H | S | `MorphAlertAction.enabledListenable` |
| alerts | `MorphAlertTextField` lacks onChanged / autofocus / input options | H | S | add the TextField basics |
| alerts | No general popover with arbitrary content | M | M | `showMorphPopover` over the existing popover motion |
| menus | Context menu takes only app-built satellites, no standard rows | H | M | done 2026-10-14: `MorphContextMenuRegion.menu` (+ `order`, `preview`) |
| menus | No pop-up button showing the chosen value | H | M | `MorphPopUpButton<T>` over `MorphMenuSource` |
| menus | Row icons only `IconData`; no custom preview / commit; no close API | M | S-M | `icon: Widget?`, `preview`, `onPreviewTap`, `close` / `onClose` |
| segmented | No icon segments | H | M | `MorphSegment(title, {icon, semanticLabel, enabled, width})` |
| segmented | No "nothing selected" state, no per-segment enabled | M | S-M | `selectedIndex: int?`, `MorphSegment.enabled` |
| switch | Color names are the ones Flutter deprecated | H | S | rename (see breaking list) |
| switch | No widget-level thumb color, no focus API | M | S | `thumbColor`, `focusNode`, `autofocus` |
| slider | Fixed 0..1, no `min` / `max` | H | S | `min`, `max` |
| slider | No `onChangeStart` | H | S | add |
| slider | iOS 26 track configuration beyond even ticks (neutral value, enabled range, custom ticks); thumbless | M | L meas. | `MorphSliderTrackConfiguration`, `MorphSliderTick`, `thumbVisible` |
| stepper | No press begin/end, no custom stepping, no `wraps` | M | S | `onChangeStart` / `onChangeEnd`, `MorphStepper.custom`, `wraps` |
| date picker | No `minuteInterval` | H | S | `minuteInterval` + `roundsToMinuteInterval` |
| date picker | No inline (calendar) style | H | M | `MorphDatePickerVariant.inline` |
| date picker | Locale spread over 8 parameters, English defaults | H | M | one `MorphDatePickerLocalizations` |
| page control | No `hidesForSinglePage`, no widget-level colors | M | S | add both |
| progress | Spinner has no caption | M | S | `MorphActivityIndicator.label` |
| lists | No swipe actions | H | L | `MorphSwipeActions` / `MorphSwipeAction` (usable outside lists too, like iOS 27 `swipeActionsContainer`) |
| lists | No lazy / sliver section for long lists | H | M | sliver form of `MorphListSection` |
| lists | No checkmark accessory / selected state | H | S | `accessory: MorphListAccessory?` |
| scroll edge | `active` is manual; no host that measures a custom bar | H | S-M | drive from a `ScrollController`; `MorphScrollEdgeBar` (`safeAreaBar`) |

## Status after phase 2 (0.8.0)

Implemented: ambient accent (`MorphWidgetsTheme.tint`) and
`MorphWidgetsThemeScope`; `MorphGlassEffect` and per-surface
`MorphGlassStyle`; `MorphGlassButton.clear` / `.prominentClear`, prominent
defaulting to the accent; `MorphNavigationStack.pages` /
`MorphNavigationPage`; bar item badges (`MorphBadge`), subtitles,
`backButtonDisplayMode`, `hidesBackButton`,
`MorphLargeTitleDisplayMode.automatic` + `prefersLargeTitles`; tab bar
`onReselected`, badges, `selectedIcon`; slider `min` / `max` /
`onChangeStart`; sheet `onDetentChanged`, `onDismissAttempt` (PopScope
holds the drag), custom and fitted detents; live alert actions and text
field options; nullable segmented selection, `MorphSegment.enabled` /
`width`; list checkmark and detail accessories, `MorphSliverListSection`;
date picker `minuteInterval` and the reserved `MorphDatePickerStyle`.

Read from UIKit's code since (notes private; passports say what): badge
metrics and placement, subtitle fonts and large layout, the clear and
tinted glass glow, the dismiss attempt's release rule, minuteInterval's
round-down; list glyph identities and the disabled segment color are
recorded but not ported. Still static / needing a device: badge motion and
the tab badge's height, the inline subtitle gap, interactive glass, list
glyph outlines, the first segmented selection (lens path), the sheet's
rubber-band extent.

Not done: `MorphGlassContainer.spacing` (fusing app glass needs the skin's
merge law in the container's joined layer, a pixel-changing renderer
change); slider `trackConfiguration` (neutral value / ranges / custom
ticks: fill and tick looks unmeasured); date picker `inline` / `wheels`
drawing; search and menus (another work stream).

## Overall top 15 (need first, then cost)

1. Ambient accent `MorphWidgetsTheme.tint` + a theme scope that needs no Material `Theme` (cross-cutting; H, S).
2. Trim `widgets.dart`: motion / tuning / layout / seam types go to `motion.dart` and a painter library (cross-cutting; H, S-M).
3. `MorphGlassEffect`: glass behind any widget, with per-surface regular / clear, tint and interactive (glass; H, M).
4. Navigator 2 / go_router: `MorphNavigationPage` and `MorphNavigationStack.pages` (navigation; H, M).
5. Sheets: `onDetentChanged`, a dismiss veto (`onDismissAttempt` / `PopScope`), and fitted / custom detents (sheets; H, S-M).
6. Slider `min` / `max` / `onChangeStart` (slider; H, S).
7. Tab bar `onReselected` + badges + `selectedIcon` (tab bar; H, S-M).
8. Bar item badge + `backButtonDisplayMode` / `hidesBackButton` + subtitle (bars; H, S-M).
9. Search controlled `active` + search integrated in `MorphNavigationConfig` (search; H, S-M).
10. Alerts: live action enablement + TextField basics (alerts; H, S).
11. Context menu with standard rows (done: `MorphContextMenuRegion.menu`) and a pop-up button (menus; H, M).
12. Glass button variants: `.prominent` / `.clear` / `.prominentClear` named constructors (buttons; H, S-M).
13. Segmented control `MorphSegment` with icons, nullable selection and per-segment enabled (segmented; H, M).
14. Lists: accessory enum (checkmark / detail), sliver form, then swipe actions (lists; H, S -> L).
15. Date picker `minuteInterval` + localizations object + an inline variant (date picker; H, S-M).

## Breaking changes to make before the first public release

Two of these need the owner to decide; for each, the family pages offer options and this list gives
one recommendation.

Naming rules (decide first; the other renames follow from them):
- **Look table vs variant enum (owner decision).** morph calls its look tables `*Style`, but UIKit
  uses `Style` for variant enums (`UIDatePickerStyle`, `UIProgressView.Style`,
  `UIScrollEdgeEffect.Style`). The two clash today: `MorphProgressViewStyle` (an enum) sits next to
  `MorphProgressStyle` (a table). The two options:
  - (a) Keep `*Style` for look tables. Variant enums become `*Kind` / `*Variant`.
  - (b) Variant enums keep UIKit's `*Style` names. Look tables become `*Appearance` (UIKit
    precedent: `UINavigationBarAppearance`), and the parameter becomes `appearance:`.

  cross-cutting.md recommends (b). date-picker / progress / lists propose `*Variant` and
  `MorphListAppearance`, which fits (a). Either way, use one parameter name for the look table on
  every widget: today `MorphScrollEdgeEffect` uses `theme`, `MorphNavigationBar` uses
  `edgeEffectTheme`, and `MorphScrollEdgeEffectThemeData` is the only `*ThemeData`.
- **Look tables are named after their widget:** `MorphSegmentedStyle` -> `MorphSegmentedControl{Style|Appearance}`,
  `MorphProgressStyle` -> `MorphProgressView{Style|Appearance}`.
- **Color vocabulary (owner decision).** Use one scheme across switch, slider, progress and page
  control. The audit found two candidates:
  - Flutter's current Cupertino names: `activeTrackColor` / `inactiveTrackColor` / `thumbColor`.
    `CupertinoSwitch` deprecated `activeColor` / `trackColor`, which morph still uses.
  - UIKit's names: `onTint`, `minimumTrackTint` / `maximumTrackTint`, `progressTint` / `trackTint`.

  Recommendation: Flutter's names, with the UIKit name given in each dartdoc. Flutter developers type
  these parameters, and the deprecated pair is the worst of both.

Glass and buttons:
- `MorphGlass` (the painter-installing InheritedTheme) -> `MorphGlassScope`. This frees `MorphGlass` /
  `MorphGlassStyle` for a value type with `regular`, `clear`, `identity`, `tint` and `interactive`
  (SwiftUI `Glass`).
- Split `MorphGlassMaterial`: per-surface `{regular, clear}` becomes public, and the `toolbar` role
  becomes renderer-internal.
- `MorphGlassContainer`: add `spacing` now, so the name means what `UIGlassContainerEffect` means
  before users depend on "never fuses".
- `MorphGlassButton`: choose the variant with named constructors (`.prominent`, `.clear`,
  `.prominentClear`) instead of "non-null tint means prominent".
- `MorphGlassButtonStyle.tintedRimColor` / `tintedForegroundColor` -> `prominent*`.
- Fix the docs that call regular glass "clear".
- `MorphMenuStyle.buttonSize` -> a size parameter, out of the look table.

Bars and navigation:
- `MorphNavigationScaffold.largeTitle` (bool) -> `largeTitleDisplayMode: MorphLargeTitleDisplayMode`.
- `backTitle` -> `backButtonTitle`.
- `backLabel` -> `backButtonSemanticLabel`, on the stack and the scaffold.
- `leading` (a single `MorphBarButtonGroup?`) -> `List<MorphBarButtonGroup>` on the bar, scaffold and
  config. The back button is kept unless `hidesBackButton` is set.
- `MorphBarButtonGroup.prominent` (bool) -> `style: MorphBarButtonStyle.plain/.prominent`, done
  together with `tintColor`.
- `MorphNavigationBar.drift` exposes the unexported `MorphNavigationBarDrift`. Hide it, or export the type.
- `MorphNavigationTransition` (a constants class) -> `MorphNavigationTuning`. This frees the name
  for a transition value (`.slide`, `.zoom(from:)`, `.crossFade`) that absorbs `zoomSource` / `zoom`.
- Use one name for the zoom source everywhere: `from` (today `zoomSource`, `source:` and `from:`).
- `MorphNavigationStack`: add the `.pages(...)` constructor now, so Navigator 2 support is not a later reshape.

Tab bar and search:
- `MorphSearchTabBar.searching` / `onSearchingChanged` -> `active` / `onActiveChanged`.
- `MorphSearchTabBar.onQueryChanged` -> `onChanged`.
- Decide whether `MorphTabItem.icon` stays `IconData`, or becomes a Widget so SVG icons work.
- `MorphSearchToolbar.leading` / `trailing`: `List<MorphBarButton>` -> `List<MorphBarButtonGroup>`.
  Coordinate this with the bar_items refactor.
- `MorphSearchToolbar.buttonStyle` -> a `MorphBarStyle`.

Sheets, alerts and menus:
- `presentMorphSheet` (widgets, returns a Future) and `showMorphSheet` (engine, returns a
  `MorphFlight`) are the wrong way round for Flutter, where `showX` returns a Future.
  Recommendation: `presentMorphSheet` -> `showMorphSheet`, and the engine function ->
  `showMorphSheetFlight` (likewise `showMorphDialog` -> `showMorphDialogFlight`).
- `useRootNavigator`: one type and default (`bool?`) for sheets and alerts. Alerts use `bool = true` today.
- `MorphPopoverArrowEdge` -> `MorphPopoverArrowDirection { up, down, left, right }` (UIKit's meaning).
- `MorphPopoverPlacement.edge` -> `arrowDirection`.
- Rename `MorphMenuButton.items` / `MorphMenuSource.items` -> `menu`, matching `MorphGlassButton.menu`,
  `MorphBarButton.menu` and `UIButton.menu`.
- `MorphMenuItem.icon` / `MorphSubmenu.icon` / `selectedIcon`: `IconData?` -> `Widget?`, unless an
  additive `iconBuilder` is chosen instead.
- Stop exporting `MorphMenuLayout`, `MorphMenuMetrics`, `MorphMenuPlaced`, `MorphMenuPlacedKind`,
  `MorphMenuTarget` and `MorphMenuTargetKind`.

Value controls:
- `MorphSegmentedControl.segments: List<String>` -> `List<MorphSegment>`.
- `selected` -> `selectedIndex` (`int?`).
- `sizeByContent` -> `proportionalWidth`.
- `MorphSwitch` / `MorphSwitchStyle`: `activeColor` / `trackColor` -> `activeTrackColor` / `inactiveTrackColor`.
- `knobColor` -> `thumbColor`.
- `MorphSlider.ticks` (int) -> `trackConfiguration: MorphSliderTrackConfiguration?`. Keeping `ticks`
  as a shorthand is also possible; decide before 1.0.
- `MorphStepper.semanticValueFormatter` -> `semanticFormatterCallback`, the Flutter name the slider shares.

Pickers, indicators and lists:
- `MorphDatePicker.firstDate` / `lastDate` -> `minimumDate` / `maximumDate` (UIKit and `CupertinoDatePicker`).
- Fold the six formatter / `localize` callbacks into one `localizations` object.
- Reserve the variant enum `{compact, inline, wheels}` now.
- `MorphPageControlStyle.indicatorColor` / `currentIndicatorColor` -> `pageIndicatorColor` / `currentPageIndicatorColor`.
- `MorphProgressViewStyle` / `viewStyle` -> follows the naming rule above.
- `MorphActivityIndicator.semanticLabel` -> `String?`.
- `MorphListSection.header` / `footer`: `String?` -> `Widget?`.
- `MorphListRow.chevron` (bool) -> `accessory: MorphListAccessory?`.
- Reserve `MorphListAppearance` (insetGrouped now; plain and grouped later).

Scroll edge effect:
- `MorphScrollEdgeEffect.active` -> `scrolledUnder`, the same name `MorphNavigationBar` uses.
- Add `automatic` and make it the default.
- `edge` becomes vertical-only until horizontal edges are drawn.
