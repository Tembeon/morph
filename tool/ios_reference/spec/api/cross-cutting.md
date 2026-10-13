# Cross-cutting - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIView.tintColor` / `tintAdjustmentMode`, per-control tint properties, `UIControl` (`isEnabled`,
`isSelected`, `isHighlighted`, `state`, `UIControl.Event`, `isContextMenuInteractionEnabled`,
`showsMenuAsPrimaryAction`, `toolTip`, `isSymbolAnimationEnabled`), `UITraitCollection`
(`userInterfaceStyle`, `accessibilityContrast`, `preferredContentSizeCategory`,
`systemPrefersReducedResourceUsage` iOS 27), `UIAccessibility` (Reduce Motion, Reduce Transparency,
Prefers Cross-Fade, Darker System Colors), `UIBehavioralStyle`, `UIFeedbackGenerator`;
SwiftUI `tint(_:)`, `disabled(_:)`, `controlSize(_:)`, environment (`colorScheme`, `colorSchemeContrast`,
`accessibilityReduceMotion`, `accessibilityReduceTransparency`, `dynamicTypeSize`), `sensoryFeedback(_:trigger:)`,
`symbolEffect(_:)`.
morph: `MorphWidgetsTheme`, the per-control `*Style` classes with `light` / `dark` tables and `resolve`,
`MorphTypography`, engine `MorphTheme`, `enabled` / null-callback convention, `semanticLabel` params,
`reducedMotion` (from `MediaQuery.disableAnimations`), `MorphAdaptiveGlass`, and the public
surface of `lib/widgets.dart`.
Passports: [../states.md](../states.md), [../typography.md](../typography.md),
[../glass-renderer.md](../glass-renderer.md) (adaptive policy).

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIView.tintColor` iOS 7 (inherited down the view tree) | one accent for every control | none: accent hard-coded per style table (`0xFF0088FF` in `MorphSliderStyle.activeColor`, `MorphProgressStyle.progressColor`, `MorphDatePickerStyle.accentColor`, `MorphAlertStyle.preferredColor`, `MorphListStyle.iconColor`; `0xFF0082FC` `MorphTabBarStyle.selectedColor`; `0xFF007AFF` `MorphBarStyle.prominentColor`) | an app must restyle 7+ classes to change its accent | add `MorphWidgetsTheme.tint` (ambient accent) read by every control before its table |
| `UIView.tintAdjustmentMode` (.dimmed) iOS 7 | dims tint under a modal | none | low | skip |
| per-control tints: `UISwitch.onTintColor`, `UISlider.minimumTrackTintColor` / `maximumTrackTintColor` / `thumbTintColor`, `UIProgressView.progressTintColor` / `trackTintColor`, `UISegmentedControl.selectedSegmentTintColor`, `UIPageControl.pageIndicatorTintColor` / `currentPageIndicatorTintColor`, `UIActivityIndicatorView.color` (legacy) | per-control color overrides | `MorphSwitch.activeColor` / `trackColor`, `MorphSlider.activeColor` / `trackColor`, `MorphProgressView.progressColor` / `trackColor`, `MorphActivityIndicator.color`, `MorphGlassButton.tint`; segmented / tab bar / page control: style only | names follow neither UIKit nor one rule (`activeColor` vs `progressColor` vs `tint`) | rename for one rule (see Breaking); keep Flutter `Color` params |
| `UIControl.isEnabled` | disabled; subclasses draw it | null callback (`MorphSwitch`, `MorphSlider`, `MorphSegmentedControl`, `MorphTabBar`, `MorphStepper`, `MorphPageControl`); `enabled` (`MorphSearchField`, `MorphListRow`, `MorphTabItem`, `MorphBarButton`, `MorphAlertAction`, `MorphMenuSource`, `MorphMenuButton`); both (`MorphGlassButton`) | three conventions; disabled look itself is measured (states.md) | keep null-callback (Flutter idiom) everywhere, and add `enabled` to every control so a disabled control with a handler is expressible (as `MorphGlassButton` does) |
| `UIControl.isSelected` / `isHighlighted` / `state` | live state flags | internal (`MorphPress`, motion `isHighlighted`) | not observable | add `WidgetStatesController` param only on demand (low) |
| `UIControl.Event` (`touchDown`, `touchUpInside`, `valueChanged`, `primaryActionTriggered`, `menuActionTriggered`, ...) | target-action events | `onPressed`, `onChanged`, `onChangeEnd` (slider), `onOpen` (menus) | ok; no `onChangeStart` on `MorphSlider` | add `MorphSlider.onChangeStart` (Flutter `Slider` has it) |
| `UIControl.isContextMenuInteractionEnabled` / `contextMenuInteraction` iOS 14 | long-press context menu on any control | `MorphContextMenuRegion`, `MorphMenuSource(trigger: MorphMenuTrigger.hold)` | ok | keep |
| `UIControl.toolTip` iOS 15 | pointer tooltip | none | Flutter `Tooltip` wraps | skip (Flutter) |
| `UIControl.isSymbolAnimationEnabled` iOS 17, `UIButton.Configuration.symbolContentTransition` iOS 26 | SF Symbol effects | none (children are arbitrary widgets) | no SF Symbols in Flutter | skip |
| `UITraitCollection.userInterfaceStyle` | light / dark | `morphBrightnessOf`: `Theme` brightness, else `MediaQuery.platformBrightness`, else light; tables `Morph*Style.light` / `.dark` | ok | keep |
| `UITraitCollection.accessibilityContrast` / `UIAccessibilityDarkerSystemColorsEnabled` (Increase Contrast) | high-contrast colors and glass | none (`MediaQuery.highContrast` unread) | unmeasured on device | measure the Increase Contrast look; add high-contrast tables (`*.lightHighContrast` / `.darkHighContrast`) |
| `UIAccessibilityIsReduceTransparencyEnabled` | glass becomes frosted / opaque | none; Flutter exposes no such flag | the flat tier (`MorphGlassTier.flat`) is the natural answer | document: app passes `MorphAdaptiveGlass(tier: MorphGlassTier.flat)` when its own platform channel reports the setting; consider a `reduceTransparency` param |
| `UIAccessibilityIsReduceMotionEnabled`, `UIAccessibilityPrefersCrossFadeTransitions` | reduced motion / cross-fades | `MediaQuery.disableAnimations` -> `reducedMotion` (lens, knob travel, glow; approximation, unmeasured) and `MorphController.disableAnimations` (engine) | approximation; no cross-fade path | keep; replace by the Reduce Motion capture (states.md plan) |
| `UITraitCollection.preferredContentSizeCategory` (Dynamic Type) | text and control sizes scale | `MorphTypography` fixed point sizes; Flutter `TextScaler` applies to `Text` children; `MorphNavigationBar` measures with `MediaQuery.textScalerOf` | not audited across controls | audit every control under `TextScaler.linear(1.3+)`; declare per control |
| `UITraitCollection.systemPrefersReducedResourceUsage` iOS 27 (NEW), `UIApplication.systemPrefersReducedResourceUsage` + did-change notification | system asks apps to cut resource use | `MorphAdaptiveGlass` picks a tier once by GPU class | not read (Flutter does not expose it) | add `MorphAdaptiveGlass.reducedResourceUsage` input (app feeds it from a channel) to drop to `cheapTier` |
| `UIBehavioralStyle` (`.pad`, `.mac`) | Catalyst / Mac behaviour | none | - | skip |
| `UIFeedbackGenerator` (impact, selection, notification), control haptics | haptics | none fired by any control; seams exist (`MorphFlight.events`, `MorphContextMenuRegion` open/landing callbacks) | which native controls fire haptics is not public API and unmeasured | measure (switch toggle, slider ticks, stepper limit, menu open, context menu) on the device; add opt-in `MorphWidgetsTheme.haptics` calling Flutter `HapticFeedback` |
| `UIAccessibility` label / value / traits | VoiceOver | `semanticLabel` on `MorphSwitch`, `MorphSlider`, `MorphPageControl`, `MorphProgressView`, `MorphActivityIndicator`, `MorphSearchField`, `MorphDatePicker`, `MorphMenuButton`, `MorphBarButton`, `MorphSheetRoute`; formatters on `MorphStepper` / `MorphPageControl` / `MorphDatePicker`; no `semanticLabel` on `MorphGlassButton`, `MorphSegmentedControl`, `MorphTabBar` (labels from children) | mostly ok | add `MorphGlassButton.semanticLabel` for icon-only buttons |
| `UIAppearance` proxies | global styling | `MorphWidgetsTheme` (ThemeExtension) | requires a Material `Theme` (material_ui or Flutter) ancestor; a `WidgetsApp` / `CupertinoApp` app cannot theme, only falls back to tables | add a plain `InheritedTheme` host (`MorphWidgetsThemeScope`) in addition to the extension |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `View.tint(_:)` iOS 15 | ambient accent | none | same as `tintColor` | `MorphWidgetsTheme.tint` (+ scope widget) |
| `View.disabled(_:)` / `isEnabled` environment | ambient disable for a subtree | none | per-widget only | add an inherited `MorphEnabled` (low) |
| `controlSize(.mini/.small/.regular/.large/.extraLarge)` | ambient control size | none (one measured size per control) | sizes unmeasured | `MorphControlSize` enum shared by buttons, segmented, slider; measure first |
| `colorSchemeContrast`, `accessibilityReduceTransparency`, `accessibilityReduceMotion`, `dynamicTypeSize` | same as UIKit rows | see UIKit | - | see UIKit |
| `sensoryFeedback(_:trigger:)` iOS 17 | declarative haptics | none | same as `UIFeedbackGenerator` row | same |
| `symbolEffect(_:)` iOS 17 | SF Symbol animation | none | - | skip |

## Not relevant for Flutter
- Responder chain, target-action selectors, `NSCoding`, Interface Builder inspectables.
- `UIAppearance` proxy mechanics (`appearance(whenContainedInInstancesOf:)`): themes / `InheritedWidget`s.
- Mac Catalyst idiom styles, tvOS focus engine (Flutter focus is used: every control is focusable, Space / Enter activate).
- `UIAccessibility` selector APIs (`accessibilityActivate`, custom actions plumbing): Flutter `Semantics`.

## Naming and public surface (morph-wide)
- Prefix: every public type is `Morph*`, functions `morph*` / `showMorph*` / `presentMorphSheet` / `pushMorphZoom` - consistent. Exception to review: `presentMorphSheet` (widgets) vs `showMorphSheet` (engine) are two different things with near-identical names.
- Look tables: `Morph<Control>Style` with `light` / `dark` / `resolve` (17 classes), except `MorphScrollEdgeEffectThemeData` (and its param `theme` / `edgeEffectTheme` instead of `style`).
- `*Style` also names variant enums that mirror UIKit enums: `MorphScrollEdgeEffectStyle` (UIKit `UIScrollEdgeEffect.Style`), `MorphProgressViewStyle` (`UIProgressView.Style`), `MorphAlertActionStyle` (`UIAlertAction.Style`). Next to `MorphProgressStyle` (colors) vs `MorphProgressViewStyle` (enum) this reads ambiguously.
- Look-table names drift from widget names: `MorphSegmentedStyle` (for `MorphSegmentedControl`), `MorphProgressStyle` (for `MorphProgressView`), `MorphMenuStyle` (for `MorphMenuButton` / menus).
- `*Tuning` = measured constants (public, passed as params: `MorphMenuTuning`, `MorphZoomTuning`, `MorphBarMenuTuning`); `*Motion` = pure motion math; `*Metrics` / `*Layout` / `*Frame` / `*Placement` / `morphPlace*` = geometry. About 60 of the ~150 names exported by `widgets.dart` are motion / tuning / layout / painter-seam types: `MorphActivityIndicatorFrames`, `MorphAlertMotion`, `MorphAlertTuning`, `MorphBarCapsuleFrame`, `MorphBarCapsuleLayout`, `MorphBarItemFrame`, `MorphBarItemLayout`, `MorphBarMotion`, `MorphBarTransitionSpec`, `MorphDatePickerMotion`, `MorphDatePickerPlacement`, `MorphDatePickerTuning`, `morphPlaceDatePicker`, `MorphFlexSpec`, `MorphGlassButtonMotion`, `MorphTouchGlowMotion`, `MorphLensMotion`, `MorphLensSlot`, `MorphLensTuning`, `MorphMenuBlob`, `MorphMenuCard`, `MorphMenuLayout`, `MorphMenuMetrics`, `MorphMenuPlaced`, `MorphMenuPlacedKind`, `MorphMenuTarget`, `MorphMenuTargetKind`, `MorphMenuMorphSpec`, `MorphMenuMotion`, `MorphMenuProgress`, `MorphNavigationTitleMotion`, `MorphNavigationTransition`, `MorphPageControlMotion`, `MorphPageControlTuning`, `MorphPopoverMotion`, `MorphPopoverTuning`, `MorphPopoverPlacement`, `MorphPopoverArrowEdge`, `morphPlacePopover`, `MorphProgressMotion`, `MorphPushZoomMotion`, `MorphPushZoomTuning`, `MorphSearchMotion`, `MorphSearchTuning`, `MorphSheetMotion`, `MorphSliderMotion`, `MorphSmallLens`, `MorphSwitchMotion`, `MorphZoomMotion`, plus the painter seam (`MorphGlassSurface`, `MorphGlassKind`, `MorphGlassOptics`, `MorphGlassGlow`, `MorphGlassOutline`). An app developer needs none of them to use a control; every one becomes a semver commitment at 1.0.
- `MorphWidgetsTheme` and engine `MorphTheme` are two ThemeExtensions with different scopes (controls vs engine); fine, but both need a Material `Theme`.

## morph-only API
- `MorphTypography` (role styles + `resolve` adding opsz / wght / SF tracking on Apple platforms): keep (UIKit does this in the font system).
- Light / dark tables on every style: keep (UIKit uses dynamic colors; Dart needs explicit tables).
- `MorphAdaptiveGlass` / tiers: keep (performance goal).
- `reducedMotion` fields on motion classes: keep, approximation declared.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | No ambient accent (`tintColor` / `.tint()`): accent repeated in 7+ tables | high | S-M | `MorphWidgetsTheme.tint`, read by every control (slider fill, progress, prominent button, tab selection, date picker, alert preferred, bar prominent) |
| 2 | Theming needs a Material `Theme` ancestor | high (Cupertino-only and `WidgetsApp` apps are the target audience) | S | `MorphWidgetsThemeScope` (`InheritedTheme`) checked before the ThemeExtension |
| 3 | Public surface: ~60 motion / tuning / layout / seam types in `widgets.dart` | high (pre-1.0 semver) | S-M | move to `package:morph/motion.dart` (and a painter library for the glass seam); keep `*Tuning` that are constructor params public in `widgets.dart` |
| 4 | Increase Contrast and Reduce Transparency not handled | med (accessibility) | M (device measurement) | measure; high-contrast tables; flat tier for reduce transparency |
| 5 | Haptics: none, unmeasured which controls fire them natively | med | S-M | measure; opt-in haptics through `HapticFeedback` |
| 6 | Inconsistent disable convention (null callback vs `enabled` vs both) | med | S | null callback everywhere plus `enabled` on every control |
| 7 | Color parameter names (`activeColor`, `progressColor`, `tint`, `selectedColor`, `accentColor`, `prominentColor`, `preferredColor`) | med | S (rename) | one rule (Breaking) |
| 8 | Dynamic Type not audited | med | M | audit at large text scales |
| 9 | `controlSize` / size presets | low-med | M (measure) | `MorphControlSize` |
| 10 | `systemPrefersReducedResourceUsage` (iOS 27 NEW) not followed | low | S | input on `MorphAdaptiveGlass` |

## Breaking changes before 1.0
- Look tables vs variant enums: one rule, owner decision between
  (a) `*Style` = look tables everywhere (Flutter idiom: `ButtonStyle`); variant enums become `*Kind`:
  `MorphScrollEdgeEffectStyle` -> `MorphScrollEdgeEffectKind`, `MorphProgressViewStyle` -> `MorphProgressViewKind`,
  `MorphAlertActionStyle` -> `MorphAlertActionKind`; `MorphScrollEdgeEffectThemeData` -> `MorphScrollEdgeEffectStyle`; or
  (b) variant enums keep UIKit's `*Style` names; look tables become `*Appearance` (UIKit precedent:
  `UINavigationBarAppearance`): `MorphSwitchStyle` -> `MorphSwitchAppearance`, ..., `MorphScrollEdgeEffectThemeData` ->
  `MorphScrollEdgeEffectAppearance`, param `style:` -> `appearance:`.
  Recommendation: (b) - it mirrors UIKit's names for options (the brief's rule) and touches only look tables, which
  few apps construct. Either way: one parameter name for the look table on every widget (today `style`, but `theme` on
  `MorphScrollEdgeEffect` and `edgeEffectTheme` on `MorphNavigationBar`).
- Look-table names follow the widget: `MorphSegmentedStyle` -> `MorphSegmentedControl{Style|Appearance}`,
  `MorphProgressStyle` -> `MorphProgressView{Style|Appearance}` (only possible after the enum rename in (a); free in (b)).
- Color params: `MorphSwitch.activeColor` -> `onTint` (UIKit `onTintColor`), `MorphSlider.activeColor` -> `minimumTrackTint` / `trackColor` -> `maximumTrackTint`, `MorphProgressView.progressColor` / `trackColor` -> `progressTint` / `trackTint`, `MorphGlassButton.tint` stays `tint`. Alternative: keep Flutter's `activeColor` and rename the outliers only; either way document the UIKit name in each dartdoc.
- Move motion / tuning / layout / seam types out of `widgets.dart` (list above) into `motion.dart` / a glass-painter library.
- `presentMorphSheet` (widgets) vs `showMorphSheet` (engine): rename one (e.g. engine `showMorphSheet` -> `showMorphBottomShell` or widgets `presentMorphSheet` -> `showMorphSheetRoute`) so the measured sheet is the obvious choice.
- `MorphMenuStyle.buttonSize` -> a size param (a size inside a color table).
