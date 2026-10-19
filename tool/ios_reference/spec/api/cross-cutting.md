# Cross-cutting - API parity (UIKit / SwiftUI iOS 27.1 vs morph)

Catalog families: appearance, accessibility, haptics, typography, input, lifecycle, focus,
adaptive-layout, geometry (`tool/ios_reference/coverage/catalog.json`).
Native: `UITraitCollection`, `UIAppearance`, `UIView.tintColor`, `UIAccessibility`, `AXSettings`,
`UIFeedbackGenerator` family, `UIFont` / `UIFontMetrics`, `UIControl`, `UIFocusSystem`,
`UICornerConfiguration`, size classes and the iOS 27.1 vertical bar; SwiftUI `tint(_:)`,
`controlSize(_:)`, `dynamicTypeSize(_:)`, `sensoryFeedback(_:trigger:)`, the accessibility environment.
morph (`test/api/public_api.txt`): `MorphTheme` / `MorphThemeData` (`brightness`, `tint`, `haptics`,
`glass`, `appearances`), 17 `Morph*Appearance` look tables (light / dark, 7 with high contrast),
`MorphTypography`, `MorphLocalizations`, `semanticLabel` and formatter parameters, Reduce Motion
branches, keyboard focus on every control, `MorphGlassRenderer` / `MorphGlassTier`.
Passports: [../states.md](../states.md), [../typography.md](../typography.md),
[../lifecycle.md](../lifecycle.md), [../glass-renderer.md](../glass-renderer.md).
SDK 27.1 against 27.0: nothing new for appearance, accessibility, haptics, typography or focus
(UIKit headers, SwiftUI and SwiftUICore interfaces checked); 27.1 adds the vertical bar, the hinge,
reserved regions and arrangement view controllers (adaptive layout, below).

## UIKit
| UIKit API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIView.tintColor` iOS 7 | ambient accent | `MorphThemeData.tint`, read by the slider fill, progress, prominent glass button, tab selection, list icon, date picker accent, alert preferred action and prominent bar item; switch, segmented control and page control keep their system colors, as in UIKit | - | done |
| `UIView.tintAdjustmentMode` (.dimmed) iOS 7 | tints turn gray behind a modal presentation | none | the "source tint dim" of alerts.md | measure, then dim tinted tables under a modal route |
| `UITraitCollection.userInterfaceStyle`, `overrideUserInterfaceStyle` | light / dark per subtree | `MorphThemeData.brightness` (null follows `MediaQuery.platformBrightness`); a nested `MorphTheme` overrides a subtree | - | done |
| `accessibilityContrast`, `UIAccessibilityDarkerSystemColorsEnabled` | high-contrast system colors | `MediaQuery.highContrast` picks `lightHighContrast` / `darkHighContrast` in switch, slider, progress, segmented, page control, alert, date picker (read from UIKit, notes private) | label colors, tab bar, bars, menus, lists, search field, stepper, glass button not switched | port the label colors (read from UIKit); glass needs a device capture |
| `UIAppearance` proxies | per-class styling | `MorphThemeData.appearances` (one `Morph*Appearance` per type); a widget's `appearance` wins | - | done |
| per-control tints (`onTintColor`, `minimumTrackTintColor`, `maximumTrackTintColor`, `thumbTintColor`, `progressTintColor`, `trackTintColor`, `UIActivityIndicatorView.color`) | per-control colors | `activeTrackColor` / `inactiveTrackColor` / `thumbColor` on switch, slider, progress; `color` on the activity indicator; `tint` on glass buttons and `MorphGlassEffect`; tables for the rest | - | done |
| `systemPrefersReducedResourceUsage` iOS 27 (trait, `UIApplication`, did-change notification) | the system asks for less work | `MorphGlassRenderer.adaptive()` picks a tier once from the GPU | not read; Flutter does not expose it | an input on `MorphThemeData` an app feeds from a channel |
| `UIAccessibilityIsReduceMotionEnabled` | reduced motion | `MediaQuery.disableAnimations`; per-family branches (Behaviour fidelity) | engine flights, bars, progress unbacked | device pass (states.md) |
| `UIAccessibilityPrefersCrossFadeTransitions` iOS 14 | the cross-fade sub-setting | follows Reduce Motion | Flutter exposes one flag | none until the engine exposes it |
| `UIAccessibilityIsReduceTransparencyEnabled` | glass turns frosted | none | no Flutter flag; `MorphGlassRenderer.tier(MorphGlassTier.flat)` is the app-side stand-in, unmeasured against native | measure; then an app-fed input |
| `UIAccessibilityIsBoldTextEnabled`, `legibilityWeight` | heavier system font | none: `MediaQuery.boldText` is not read, and `MorphTypography.resolve` pins `wght` 510 / 590, which likely masks the bold weight `Text` merges in (inferred, not run) | gap | read `MediaQuery.boldTextOf`; measure UIKit's bold weights per role |
| `UIAccessibilityIsOnOffSwitchLabelsEnabled` iOS 13 | I / O glyphs on switches | none; Flutter exposes `MediaQuery.onOffSwitchLabels` | gap | `MorphSwitch` draws them; measure the glyphs |
| `AXShowBordersEnabled` iOS 26.1 (replaces the deprecated `UIAccessibilityButtonShapesEnabled`) | borders on buttons | none; not exposed by Flutter | gap | measure; app-fed input |
| `UILargeContentViewerInteraction`, `showsLargeContentViewer` iOS 13 | large HUD for bar items at accessibility sizes | none; bars cap their text scale instead | gap | after the Dynamic Type measurement |
| `preferredContentSizeCategory`, `adjustsFontForContentSizeCategory` | Dynamic Type | labels follow `MediaQuery.textScaler`, capped per control: tab bar, bar items, search toolbar 1.25; segmented 1.4; search field 1.5; date picker 2 (overlay 1.2); alert 2; menus uncapped | no cap has a native source | measure each control at the AX sizes |
| `accessibilityLabel` / `Value` / `Traits` / `Hint` | VoiceOver | `semanticLabel` on switch, slider, page control, progress, activity indicator, search field, date picker, menu button, menu source, bar button, context menu region, sheets; toggled state on the switch; values on slider (percent), stepper, page control, date picker; roles slider, header, tab bar / tab, mutually exclusive segments, checked menu rows, live regions | no label on `MorphGlassButton` (an icon-only button relies on its child), no hints | `MorphGlassButton.semanticLabel` |
| `accessibilityIncrement` / `Decrement` | adjustable | slider, stepper, page control, date picker wheels | - | done |
| `accessibilityCustomActions` | actions rotor; UIKit lists a view's context menu there | none | `MorphContextMenuRegion.menu` is out of VoiceOver's reach | custom semantics actions from the menu |
| `accessibilityViewIsModal`, `UIAccessibility.post(.screenChanged)` | modal focus | sheets, alerts, menus and the date picker overlay scope and name their route | - | done |
| `accessibilityPerformEscape` | two-finger Z dismisses | Flutter's iOS embedding forwards it as a dismiss action or a route pop (inferred), which morph's routes and flights take | untested with morph | add a test |
| `UIFeedbackGenerator` in UIKit controls | control haptics | `MorphThemeData.haptics` (default on): switch impact on a touch toggle, slider end and detent, page control scrub, date picker wheel row, menu row, alert action, context menu preview | the page control's jog impact and the context menu's drag-out and commit feedback are not played (read from UIKit, notes private); patterns mapped onto `HapticFeedback` | add the jog; declare the mapping on the public field |
| `UIImpactFeedbackGenerator`, `UISelectionFeedbackGenerator`, `UINotificationFeedbackGenerator` | app haptics | Flutter's `HapticFeedback` (impacts, selection) | soft / rigid, intensity and notification patterns have no Flutter API | n/a for morph |
| `UIFont.systemFont(ofSize:weight:)` | SF at a size | `MorphTypography.resolve`: `opsz` = size, `wght` 510 / 590, measured SF tracking | - | done |
| `UIFont.preferredFont(forTextStyle:)` | eleven text styles | control roles plus `body`, `listSubtitle`, `listHeader`, `listFooter` | no title1-3, headline, callout, subheadline, footnote, caption1-2 | add them as roles after measuring |
| `UIFontMetrics.scaledFont` / `scaledValue` | per-style Dynamic Type curve | none: one linear factor for every size; `opsz` and tracking keep the unscaled size (`TextStyle.getTextStyle` scales `fontSize` only) | wrong axes above 1x | resolve against the scaled size; per-style curve after measuring |
| `UIFontDescriptor.SystemDesign`, font width | rounded, serif, mono, condensed | none | - | low |
| `UIControl.isEnabled` | disabled | value controls: null `onChanged` (switch, slider, segmented, tab bar, stepper, page control, date picker); actions: `enabled` (glass button also null `onPressed`, bar button, list row, tab item, segment, menu entries, alert action, search field, context menu region) | two documented rules | keep |
| `isSelected` / `isHighlighted` / `state` | observable state | internal | not observable | on demand |
| `UIControl.Event` (touchDown, touchUpInside, touchDragExit / Enter, valueChanged, primaryActionTriggered) | events | `onPressed`, `onChanged`, `onChangeStart` / `onChangeEnd` (slider), `onReselected` (tab bar); drag-out release bound 70 pt (`MorphSegmentedControl.releaseSlop`, measured) | - | done |
| `showsMenuAsPrimaryAction`, `isContextMenuInteractionEnabled` | menus from controls | `MorphGlassButton.menu`, `MorphMenuButton`, `MorphMenuSource`, `MorphContextMenuRegion` | - | done |
| Full Keyboard Access, `UIFocusSystem`, `UIFocusHaloEffect` iOS 15 | keyboard focus and its halo | every control focusable: Space / Enter activate, arrows step (mirrored in RTL), Escape closes flights; a 3 pt `0xFF007AFF` capsule ring 3 pt outside | ring look and keys unmeasured; ring ignores `tint` | measure with Full Keyboard Access |
| `focusGroupIdentifier` iOS 15, `focusNode` / `autofocus` | focus groups, focus control | `focusNode` on search field, search tab bar, search toolbar, navigation search; `autofocus` on search field and alert text field | none on switch, slider, buttons | on demand |
| `transitionCoordinator.animate(alongsideTransition:)` | animate with a push or sheet | `MorphNavigationRoute`, `MorphSheetRoute` are Flutter routes | whether `ModalRoute.animation` follows the spring is undocumented | document |
| `restorationIdentifier` | state restoration | `MorphNavigationPage` restoration id (Navigator pages) | sheets, menus, search state not restored | low |
| size classes, `UISplitViewController`, tab sidebar | regular width | none: iPhone (compact) layouts only | no iPad forms | after the iPhone release |
| `keyboardLayoutGuide`, `safeAreaInsets` | keyboard and safe area | `MediaQuery` insets; `MorphToolbar.keyboardInset`; sheets | sheet keyboard motion (sheets.md) | - |
| iOS 27.1 NEW: `verticalBarEdge` trait, `preferredVerticalBarBehavior`, `UIBarButtonItem.axisBehavior`, `UINavigationItem.verticalBarCompressionBehavior`, `UIViewLayoutRegion.layoutRegionForBar(onEdge:extent:)` | bars on a vertical edge | none | new in 27.1 | track; no device shows it |
| iOS 27.1 NEW: `UIHinge`, `UIHingeInteraction`, `UIViewReservedRegion` (occlusion, division), `UIArrangementViewController` (split, overlay) | folds and arrangements | none (Flutter: `MediaQueryData.displayFeatures`) | - | track |
| `UICornerConfiguration`, `UICornerRadius.containerConcentric` iOS 26, `effectiveRadius(corner:)` | concentric corners | internal: sheets, push zoom and the navigation card follow `MediaQuery.displayCornerRadii`; `MorphGlassEffect.shape` takes any `ShapeBorder` | no public concentric radius | a concentric radius helper |
| `UIView.layoutRegions` (corner adaptation) iOS 26 | content clear of display corners | none | - | with the helper |
| `cornerCurve` (.continuous), `UIShape` iOS 17 | continuous shapes | `RoundedSuperellipseBorder`, `ShapeBorder` | - | done |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `tint(_:)` iOS 15, `preferredColorScheme` | ambient accent, scheme | nested `MorphTheme` with `tint` / `brightness` | - | done |
| `colorSchemeContrast` | contrast | high-contrast tables (7 controls) | as UIKit | as UIKit |
| `disabled(_:)` / `isEnabled` | ambient disable | none | per widget only | low |
| `controlSize(.mini ... .extraLarge)` | ambient size | `MorphActivityIndicatorSize`, `MorphMenuElementSize`, `MorphGlassButton.minSize` / `padding`, `MorphMenuButton.size`; no shared enum | sizes unmeasured | `MorphControlSize` after measuring |
| `dynamicTypeSize(_:)` range | limit Dynamic Type | internal caps, not adjustable | - | after the measurement |
| `accessibilityReduceMotion`, `ReduceTransparency`, `ShowBorders`, `DifferentiateWithoutColor`, `PrefersCrossFadeTransitions`, `LargeContentViewerEnabled`, `legibilityWeight` | settings | as UIKit rows | as UIKit | as UIKit |
| `accessibilityReduceHighlightingEffects` iOS 26.4 | fewer highlight effects | none; not exposed by Flutter | glows and press highlights ignore it | measure first |
| `sensoryFeedback(_:trigger:)` iOS 17; iOS 26 `.press(.button / .buttonIconOnly / .slider / .toggle / .tab)`, `.release(.slider)`, `.selection(.on / .off / .minimum / .maximum)` | declarative and control haptics | controls play theirs internally | no public hook for a custom control to play a control's haptic | low |
| `Font.TextStyle`, `Font.Design`, `Font.width` | text styles | as UIFont rows | as UIKit | as UIKit |
| `ConcentricRectangle`, `containerShape`, `containerCornerInsets` iOS 26 | concentric shapes | none | as `UICornerConfiguration` | as UIKit |
| `help(_:)` iOS 27 | tooltip | none | tooltips family | low |

## Not relevant for Flutter
- Responder chain, target-action selectors, `NSCoding`, Interface Builder inspectables, `UIBehavioralStyle`.
- `UIAppearance` proxy mechanics (`appearance(whenContainedInInstancesOf:)`): themes and inherited widgets.
- `UIKeyCommand`: Flutter `Shortcuts`. tvOS focus engine. `UIScene.closureConfirmation` (iPad windows).
- `UICanvasFeedbackGenerator`, generator styles beyond `HapticFeedback`: Flutter's surface, not morph's.
- Smart Invert (`accessibilityIgnoresInvertColors`): the whole Flutter view inverts. SF Symbol effects.
- VoiceOver selector plumbing (`accessibilityActivate`): Flutter `Semantics`.

## Naming and public surface (`public_api.txt`, 2026-10-19)
- One library `package:morph/morph.dart` plus `package:morph/glass_painter.dart` (the painter seam).
  Motion, tuning, metrics and layout types are `@internal`.
- Look tables: 17 `Morph<Widget>Appearance` (implementing `MorphAppearance`) with `light`, `dark`,
  `copyWith`, `resolve`; parameter `appearance`, secondary looks named by role (`buttonAppearance`,
  `menuAppearance`, `searchAppearance`, `edgeEffectAppearance`). Variant enums keep UIKit's names:
  `MorphAlertActionStyle`, `MorphBarButtonStyle`, `MorphDatePickerStyle`, `MorphGlassStyle`,
  `MorphProgressViewStyle`, `MorphScrollEdgeEffectStyle`. Color parameters use Flutter's Cupertino
  names. Consistent.
- Open:
  1. Selection index: `MorphTabBar.selected` / `MorphSearchTabBar.selected` vs
     `MorphSegmentedControl.selectedIndex` (UIKit `selectedIndex` / `selectedSegmentIndex`).
  2. Formatters: `MorphStepper.semanticFormatterCallback` (Flutter's name) vs
     `MorphPageControl.semanticValueFormatter`.
  3. Measured constants still public: `MorphContextMenuRegion.measured*` (11 members),
     `MorphSegmentedControl.releaseSlop` / `maxTextScale`, `MorphTabBar.maxTextScale`,
     `MorphSearchField.maxTextScale`, `MorphNavigationBarHiding.largeTitleFade`,
     `MorphSlider.keyboardStep`, `MorphStepper.repeatInterval`. Each is a semver commitment; the
     rule is that tunings are `@internal`.
  4. Public defaults name unexported types: `MorphMenuButton.size = MorphMenuTuning.buttonDiameter`,
     `MorphMenuAppearance.iconSize = MorphMenuTuning.rowIconSize`, `MorphToolbar` insets
     `= MorphToolbarMetrics.*`.
  5. `MorphNavigationConfig.largeTitleDisplayMode` defaults to `never`, the scaffold's to `automatic`.
  6. `MorphLocalizations` holds five strings with English defaults; UIKit localizes Back, Close,
     Search and Cancel in every system language.

## morph-only API
- `MorphTypography` (roles + `resolve`): keep; UIKit does this inside the font system.
- Light / dark / high-contrast tables: keep; UIKit resolves dynamic colors per trait.
- `MorphGlassRenderer` / `MorphGlassTier`, `MorphTheme.precacheGlass`: keep (performance goal).
- `MorphThemeData.haptics`: keep; UIKit has no switch, but apps ask for one.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | Dynamic Type: caps without a source, no per-style curve, `opsz` / tracking of the unscaled size, no large content viewer | H | M meas. | measure every control at the AX sizes; resolve at the scaled size |
| 2 | Bold Text and On/Off labels ignored although Flutter exposes both | H | S meas. | read `boldText` / `onOffSwitchLabels` |
| 3 | Reduce Motion: engine flights, bars, progress and the title fade have no source | H | M meas. | run `reduce_motion.sh` (owner switch) |
| 4 | Increase Contrast: labels and 10 of 17 tables not switched | M | S-M | port the read label colors; measure glass |
| 5 | Public tunings and unexported default names (Naming 3, 4) | M | S | make `@internal`, inline the defaults |
| 6 | Naming 1, 2, 5 | M | S | `selectedIndex`, `semanticFormatterCallback`, one default |
| 7 | Reduce Transparency, Show Borders, reduced resource usage: no input | M | M meas. | app-fed `MorphThemeData` inputs |
| 8 | Haptics: page control jog, context menu drag-out / commit; mapping not declared publicly | M | S | add; declare on `MorphThemeData.haptics` |
| 9 | Focus ring look and keys unmeasured, ring not tinted | L | S meas. | measure with Full Keyboard Access |
| 10 | No `MorphGlassButton.semanticLabel`, no custom actions for context menus | M | S | add |
| 11 | Text styles beyond the control roles; concentric corner helper | M | S-M | add after measuring |
| 12 | `tintAdjustmentMode`, `controlSize`, regular width, 27.1 vertical bar | L | M-L | later |

## Proposals before 1.0
Done since the last refresh: ambient tint (`MorphThemeData.tint`); a theme with no Material ancestor
(`MorphTheme`); one public library with `@internal` tunings; look tables renamed to
`*Appearance` with `appearance:`; color names; `showMorphSheet` returns a Future and the engine is not
public; `MorphMenuButton.size` out of the table; haptics; high-contrast tables for 7 controls.
Open:
- `MorphTabBar.selected` / `MorphSearchTabBar.selected` -> `selectedIndex`.
- `MorphPageControl.semanticValueFormatter` -> `semanticFormatterCallback`.
- `@internal` for the public measured constants (Naming 3); defaults that do not name internal types.
- One `largeTitleDisplayMode` default on config and scaffold.
- Reserve `MorphControlSize` before 1.0 if sizes are planned.

## Behaviour fidelity
| family / dimension | grade | evidence | open items |
|---|---|---|---|
| appearance / states | measured | light / dark tables from device references (states.md, per-control passports); `test/disabled_test.dart` | none in this family |
| appearance / configuration | measured | the default accent slot of each table is the measured systemBlue; precedence pinned in `test/controls_platform_test.dart:916-1015` | no capture with a non-default tint |
| appearance / accessibility | missing | high-contrast tables read from UIKit (states.md "Increase Contrast"); `test/accessibility_test.dart:243-322` checks which table resolves, not values | label colors and 10 tables missing; glass unmeasured |
| accessibility / transitions | unbacked | read: switch, slider, segmented, tab bar, alert, popover, navigation cross-fade, context menu hold, date picker fade (states.md, `test/accessibility_test.dart:36-155,182-219`); approx: glass button, flex, search lift, small lens | `lib/src/motion.dart:46-51`, `lib/src/scrim.dart:25`, `lib/src/widgets/bar_motion.dart:392`, `navigation_motion.dart:60`, `navigation_bar.dart:465-468`, `progress.dart:279`; no device pass |
| accessibility / layout, boundaries | unbacked | caps pinned by `test/controls_platform_test.dart:577-631` against morph's own numbers | every cap (see UIKit table) |
| accessibility / accessibility | unbacked | roles chosen to mirror UIKit traits; `test/controls_platform_test.dart:84-254` pins morph's semantics | no native accessibility tree capture; Bold Text, On/Off labels missing |
| accessibility / platform | missing | Flutter exposes Reduce Motion, high contrast, bold text, on/off labels, text scale | Reduce Transparency, cross-fade, Show Borders, reduced highlighting |
| haptics / events | read | moments read from UIKit (states.md "Haptics"); `test/accessibility_test.dart:56-69,157-180,221-241` | page control jog, context menu drag-out and commit |
| haptics / platform | approx | pattern mapping declared near / approximation on the internal enum (`lib/src/widgets/haptics.dart:12-34`) | feel never checked on the device |
| typography / layout | replayed | 25 native label widths in `example/integration_test/typography_parity_test.dart:11-94` (device, 1 pt gate); `test/typography_test.dart` pins the table | list roles and `datePickerDay` not in the parity table |
| typography / states, transitions | approx | GRAD axis not reproduced (typography.md); glyph policy NEAR (glass-renderer.md) | - |
| typography / accessibility | missing | - | per-style scaling, Bold Text, scaled `opsz` / tracking |
| typography / platform | approx | other platforms keep their font (declared, `typography.dart:17-19`) | macOS CoreText inferred |
| input / input | measured | release bound 70 pt (`segmented_control.dart:72-80`); drag paths replayed per family | claim distance is Flutter's touch slop (`touch_listener.dart:98`) |
| lifecycle / performance | measured | native lab counts vs host counts, ceilings in `test/lifecycle_counts_test.dart:103` (lifecycle.md) | device frame time is the admission test |
| focus / input, optics | unbacked | keys and ring pinned by `test/controls_platform_test.dart:255-447` against morph's own choice | `control_focus.dart:7,135,138` |
| adaptive-layout / layout | missing | - | regular width, landscape bars, 27.1 vertical bar |
| adaptive-layout / platform | unbacked | RTL mirrored in 26 widget files, tested (`controls_platform_test.dart:256-296,516-575`) | no native RTL capture |
| geometry / layout | measured | display-corner cards and sheets (navigation-pages.md, sheets.md) | no public concentric API |
