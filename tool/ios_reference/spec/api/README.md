# API parity - morph vs the public iOS 27 SDK

These pages compare morph's public Dart API with UIKit and SwiftUI as they are declared in the public
iPhoneOS27.1.sdk (UIKit headers, the UIKit Swift overlay, SwiftUI.swiftinterface). They do not use
private or reverse-engineered material. The goal is a public 1.0 API in which an iOS developer
recognizes concepts, options and defaults, written in Flutter idioms (value + onChanged, Widget
children, Color, Semantics).

Each family page holds UIKit and SwiftUI tables (API, availability, meaning, morph equivalent, gap,
proposal), a list of native API that does not apply to Flutter, ranked gaps (need x cost), the
breaking changes it proposes before 1.0, and a behaviour fidelity table: per dimension of
`../../coverage/catalog.json`, a grade with the evidence behind it.

Grades: `replayed` (a test compares morph with a native recording or a value read from UIKit,
with recorded tolerances), `measured` (a native measurement morph uses, no test compares),
`read` (a constant read from UIKit, no recording), `approx` (a declared approximation),
`unbacked` (a number or behaviour with no source), `missing` (native behaviour morph lacks).

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

iOS 27.1 adds, for these families, only the vertical bar (`UIBarMinimization` vertical members,
`verticalBarCompressionBehavior`, SwiftUI `toolbarVertical*`), which phones do not show, and
`UIView.reservedRegions` / `GeometryProxy.reservedRegions` (adaptive layout).

## Coverage on 2026-10-19

API: applicable public UIKit and SwiftUI members an app developer reaches for, counted once when
both declare them. Grades: the weakest important item per dimension, details on the family page.
Across the widget families morph covers 326 of 755 members, 449 with the partial ones (43 and 59
percent).

| family | API covered (+partial) / applicable | replayed | unbacked | missing |
|---|---|---|---|---|
| glass material | 10 (+4) / 30 | layout, boundaries | states, optics | transitions, mutation, a11y |
| renderer tiers | 2 (+1) / 3 | - | - | - |
| scroll edge | 5 (+5) / 17 | states, transitions, boundaries | layout | configuration, a11y |
| button | 18 (+6) / 51 | boundaries, events | layout, transitions, mutation, optics, platform | states, a11y |
| badge | 9 (+5) / 18 | - | layout, optics | transitions, mutation, a11y, platform |
| navigation bar | 28 (+9) / 68 | states | mutation | boundaries, a11y, platform |
| toolbar | 7 (+4) / 14 | layout, states, configuration | mutation | transitions, boundaries, a11y, platform |
| navigation stack | 11 (+3) / 20 | states, input | transitions, mutation | platform |
| zoom transition | 2 (+2) / 11 | layout, input | transitions, boundaries, mutation, a11y, performance | configuration |
| tab bar | 21 (+7) / 34 | states, transitions, boundaries, input | layout | mutation, platform |
| tab minimize, accessory | 16 (+2) / 18 | - | platform, performance | mutation, a11y |
| search | 18 (+13) / 75 | states, input | a11y, performance | configuration |
| sheet | 19 (+9) / 41 | layout, states, transitions, boundaries, configuration | optics | a11y, platform |
| alert | 10 (+2) / 15 | states, transitions, input | layout, boundaries, a11y, optics | - |
| action sheet | 6 (+1) / 12 | layout, transitions, boundaries, events, input | optics | mutation |
| popover (general) | 0 (+3) / 14 | placement only | optics | api, states, configuration, events |
| presentation styles | 6 (+3) / 15 | - | states, configuration, input | layout, transitions, a11y, optics |
| menu | 36 (+7) / 51 | layout, transitions, events (replays restored in 256289a9) | states, boundaries, configuration, optics | input, a11y |
| context menu | 11 (+1) / 20 | states, boundaries | layout, input, mutation, a11y | transitions, optics |
| edit menu | 0 / 12 | - | - | all |
| switch | 5 (+4) / 11 | layout, states, boundaries, events, input | mutation, optics, platform | a11y |
| slider | 10 (+6) / 28 | layout, states, transitions, boundaries, events | input, mutation, a11y, optics, platform | configuration |
| stepper | 7 (+5) / 20 | - | layout, a11y, performance | configuration |
| segmented control | 10 (+6) / 25 | events | layout, a11y, optics, platform | mutation |
| date picker | 11 (+5) / 24 | layout | states, boundaries, mutation, a11y, platform | configuration |
| page control | 11 (+3) / 33 | states, events, input | layout, transitions, mutation, performance | boundaries, configuration, platform |
| progress | 7 (+2) / 13 | transitions, boundaries, mutation | states, a11y, platform, performance | - |
| activity indicator | 8 (+1) / 10 | - | layout, performance | a11y |
| list | 22 (+4) / 52 | - | states, platform | configuration, mutation, a11y |

Cross-cutting (cross-cutting.md): appearance 7 / 13, accessibility 5 / 18, haptics 0 (+1) / 5,
typography 2 (+3) / 8, focus 3 / 7, adaptive layout 1 / 7. Only typography's layout is replayed
(25 native label widths, 1 pt gate). The catalog's 58 families: 21 implemented, 19 partial, 18
missing.

## What the coverage says

- The motion of the core controls is the strongest part: tab bar lens, switch, slider, sheet,
  alert, action sheet and the navigation pop replay device recordings within recorded tolerances.
- The weakest is the look. Much of the liquid tier's optics (rim, refraction bevel, optical
  corners, clear face, tint tone) are the vendored renderer's presets, not measurements; colors,
  shadows and the flat tier's looks are mostly unsourced.
- Recordings exist that no test replays: the device holds of glass buttons, the segmented
  control's press and drag, the device tab taps, the stepper gestures, the switch's track color,
  the slider's track taps, the progress bar fill, the activity indicator's start and stop, the alert
  platter bounds, the list trees, the context menu at the bottom edge, the menu after a keyboard
  change and the regular glass face.
- Accessibility is thin everywhere: every text-scale cap is unbacked, Bold Text and On/Off Labels
  are ignored, the Reduce Motion device pass has never run, high-contrast label colors are not
  ported.

## Before a release

Ranked: behaviour that is wrong against UIKit, then evidence that exists but is not checked, then
missing behaviour by need.

1. Wrong against UIKit, small fixes:
   - date picker: `minimumDate` later than `maximumDate` clamps to the minimum; UIKit ignores both;
   - badge fill is the pre-iOS 26 systemRed, without a dark or high-contrast value;
   - segmented control `proportionalWidth` spreads padding with the room: slots about 71 / 212 / 78
     pt where the device shows 60 / 231 / 70;
   - the sheet's drag starts at Flutter's 18 pt slop, the device at 12 pt;
   - `MorphNavigationPage.restorationId` has no effect;
   - `onDetentChanged` fires for `animateTo`; UIKit reports only user changes;
   - the focus ring uses the pre-iOS 26 systemBlue;
   - public dartdoc names internal API (`MorphScope`, `open`, `[zoom]`, `MorphGlassInspector`,
     a `source:` parameter no control has) and `MorphGlassRenderer.adaptive` says flat where it
     falls back to fake.
2. Replay the recordings listed above; each is a test against fixtures already in the repo.
3. Accessibility: measure Dynamic Type per control and replace the caps; Bold Text; On/Off
   Labels; the Reduce Motion device pass; high-contrast label colors; a semantic label for
   icon-only glass buttons; VoiceOver custom actions for context menus; localizable default
   strings.
4. Missing behaviour with high need: an edit menu (Copy, Paste) on morph's text inputs
   (`SystemContextMenu`); pull to refresh; swipe actions; a general text field; the inline date
   picker; icon segments; non-glass button styles; a pop-up button.
5. Measure on the device what the look borrows today: the clear and tinted glass faces, the rim
   and refraction, the touch glow of buttons, the badge's placement and motion, the tab bar's
   minimize and accessory.

Owner decisions: the UIKit settings names that tab_bar_minimize.dart and tab-bar-minimize.md cite
from static reading (read them live with the probe, or drop the names); which families the first
release promises.

## Breaking changes still open

The family pages list their own. Across families:
- One name for a selected index: `MorphTabBar.selected` and `MorphSearchTabBar.selected` against
  `MorphSegmentedControl.selectedIndex`.
- One name for a semantic value formatter: `MorphPageControl.semanticValueFormatter` against
  `semanticFormatterCallback` on the stepper and the slider.
- Measured constants that are public parameters become `@internal` or move into appearances:
  `MorphContextMenuRegion.measured*`, `maxTextScale` on the segmented control, tab bar and search
  field, `MorphSegmentedControl.releaseSlop`, `MorphNavigationBarHiding.largeTitleFade`,
  `MorphSlider.keyboardStep`, `MorphStepper.repeatInterval`.
- Public defaults that name unexported types: `MorphMenuButton.size`
  (`MorphMenuTuning.buttonDiameter`), `MorphMenuAppearance.iconSize`, the `MorphToolbar` insets.
- `MorphNavigationConfig.largeTitleDisplayMode` defaults to `never`, `MorphNavigationScaffold` to
  `automatic`.
- Widget icons: `MorphTabItem.icon` is `IconData` only.
