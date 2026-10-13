# Buttons - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIButton` (`configuration`, `menu`, `showsMenuAsPrimaryAction`, `changesSelectionAsPrimaryAction`,
`preferredMenuElementOrder`, `role`, `isEnabled`), `UIButton.Configuration` (`.glass()`, `.prominentGlass()`,
`.clearGlass()`, `.prominentClearGlass()`, `buttonSize`, `cornerStyle`, `baseForegroundColor`,
`baseBackgroundColor`, `title` / `subtitle` / `image`, `imagePlacement`, `imagePadding`, `titlePadding`,
`titleAlignment`, `contentInsets`, `showsActivityIndicator`, `indicator`, `symbolContentTransition`);
SwiftUI `buttonStyle(.glass)`, `.glass(_:)`, `.glassProminent`, `GlassButtonStyle(_:)`, `controlSize`,
`buttonBorderShape`, `buttonSizing`, `Button(role:)` / `ButtonRole`.
morph: `MorphGlassButton`, `MorphGlassButtonStyle`, `MorphGlassButtonMotion`, `MorphMenuButton`
(button aspect), `MorphMenuSource` (shape/trigger aspect).
Passports: [../glass-button.md](../glass-button.md), [../menu-button.md](../menu-button.md),
[../states.md](../states.md).

Verified in the iOS 27.0 SDK: the four glass configurations are `UIButtonConfiguration
glassButtonConfiguration` / `prominentGlassButtonConfiguration` / `clearGlassButtonConfiguration` /
`prominentClearGlassButtonConfiguration` (Swift `.glass()`, `.prominentGlass()`, `.clearGlass()`,
`.prominentClearGlass()`), all iOS 26; no button API is new in iOS 27. SwiftUI `GlassButtonStyle(_ glass:)`
is iOS 26.1; `ButtonRole.confirm` / `.close` and `ButtonSizing` are iOS 26.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIButton.Configuration.glass()` iOS 26 (NEW) | regular glass button | `MorphGlassButton` with `tint: null` | morph docs call this "clear glass" (`MorphGlassButtonStyle.fillColor` "of the clear glass") - collides with UIKit's `.clearGlass()` | keep; fix naming (see Breaking) |
| `UIButton.Configuration.prominentGlass()` iOS 26 (NEW) | glass filled with the tint (accent by default) | `MorphGlassButton(tint: color)` | prominence is implied by a non-null `tint`; no default accent, so prominent needs an explicit color | add `MorphGlassButton.prominent(...)` (tint defaults to the ambient accent) |
| `UIButton.Configuration.clearGlass()` iOS 26 (NEW) | clear material (for media backdrops) | none | gap (passport API gaps) | add `MorphGlassButton.clear(...)` (needs per-surface clear material, glass.md #2) |
| `UIButton.Configuration.prominentClearGlass()` iOS 26 (NEW) | tinted clear | none | gap | add `MorphGlassButton.prominentClear(...)` |
| `Configuration.baseBackgroundColor` iOS 15 | fill / tint of prominent | `MorphGlassButton.tint` | name | keep `tint` (SwiftUI `.tint()`); doc as `baseBackgroundColor` |
| `Configuration.baseForegroundColor` iOS 15 | label color | `MorphGlassButtonStyle.foregroundColor` / `tintedForegroundColor` | only via style object, no per-button param | add `MorphGlassButton.foregroundColor` |
| `Configuration.buttonSize` (`.mini/.small/.medium/.large`) iOS 15 | preset metrics (insets, font, min height) | `MorphGlassButton.padding`, `minSize` (one measured size: 44 pt high, 17 pt title) | no presets; sizes unmeasured | add `size: MorphControlSize` after measuring the four sizes; keep `padding`/`minSize` as overrides |
| `Configuration.cornerStyle` (`.fixed/.dynamic/.small/.medium/.large/.capsule`) iOS 15 | corner shape | none (`MorphControlCapsule` is capsule only); `MorphMenuSource.shape` exists for menus | gap | add `MorphGlassButton.shape` (`ShapeBorder`, default `StadiumBorder`), same as `MorphMenuSource.shape` |
| `Configuration.title` / `attributedTitle` / `subtitle` / `image` iOS 15 | content slots | `MorphGlassButton.child` (any widget; `DefaultTextStyle` = `MorphTypography.button`, `IconTheme` size 22, colored) | no subtitle style, no title/subtitle/image layout | keep `child` (Flutter); add optional `MorphGlassButton.icon(icon:, label:, subtitle:)` constructor only if subtitles are measured |
| `Configuration.imagePlacement`, `imagePadding`, `titlePadding`, `titleAlignment` iOS 15 | layout of image vs title | none (app composes `Row`) | ok for Flutter | skip (composition), unless `.icon` constructor lands |
| `Configuration.contentInsets` iOS 15 | insets | `MorphGlassButton.padding` | name only | keep `padding` |
| `Configuration.showsActivityIndicator` iOS 15 | spinner replaces image | none | gap | add `MorphGlassButton.loading` using `MorphActivityIndicator` (measure placement) |
| `Configuration.indicator` (`.popup`) iOS 16 | chevron for pop-up buttons | none | tied to `changesSelectionAsPrimaryAction` | add with pop-up support |
| `Configuration.symbolContentTransition` iOS 26 (NEW) | animated symbol swap | none | Flutter has no SF Symbols | skip (app animates its child; `AnimatedSwitcher`) |
| `UIButton.menu` iOS 14 | attached menu | `MorphGlassButton.menu` (`List<MorphMenuEntry>`) | ok | keep |
| `UIControl.showsMenuAsPrimaryAction` iOS 14 | tap opens menu | implied by `menu != null && onPressed == null` (`MorphMenuTrigger.tap`); explicit on `MorphMenuSource.trigger` | implicit on the button | keep (Flutter-style inference); document the UIKit name |
| `UIButton.changesSelectionAsPrimaryAction` iOS 15 | pop-up button: shows the selected item as title | none | gap | add `MorphGlassButton.popUp` / `MorphPopUpButton` using `MorphMenuState` selection |
| `UIButton.preferredMenuElementOrder` iOS 16 | menu order | `MorphMenuButton.order`, `MorphMenuSource.order` (`MorphMenuOrder`) | missing on `MorphGlassButton` | add `MorphGlassButton.menuOrder` (forward) |
| `UIControl.Event.menuActionTriggered` iOS 14 | menu about to open | `MorphMenuButton.onOpen`, `MorphMenuSource.onOpen` | missing on `MorphGlassButton` | add `MorphGlassButton.onMenuOpen` (forward); also `dismissOnSelect` |
| `UIButton.role` (`.normal/.primary/.cancel/.destructive`) iOS 14 | semantic role (bold, red, keyboard) | none on buttons; alerts use `MorphAlertActionStyle` | gap | add `MorphGlassButton.role` later (low; affects color + Semantics) |
| `UIControl.isEnabled` | disabled | `MorphGlassButton.enabled`, or `onPressed: null` | ok; disabled look measured (`disabledForegroundColor`, `disabledTintColor`) | keep |
| `UIControl.isHighlighted` / `isHeld` (iOS 15) / `isHovered` (iOS 15) | live states | `MorphGlassButtonMotion.isHighlighted` / `isPressed` (math only) | not observable from the widget | add `MorphGlassButton.onHighlightChanged` or a `WidgetStatesController` (low) |
| `UIButton.configurationUpdateHandler`, `automaticallyUpdatesConfiguration` iOS 15 | restyle per state | `MorphGlassButtonStyle` light/dark + disabled fields | no per-state resolver | skip (`WidgetStateProperty` if ever needed) |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `buttonStyle(.glass)` / `GlassButtonStyle()` iOS 26 (NEW) | same as `.glass()` | `MorphGlassButton` | - | same as UIKit row 1 |
| `buttonStyle(.glassProminent)` iOS 26 (NEW) | same as `.prominentGlass()`; color from `.tint()` | `MorphGlassButton(tint:)` | needs explicit tint | `MorphGlassButton.prominent` with ambient tint |
| `buttonStyle(.glass(_ glass:))` / `GlassButtonStyle(_:)` iOS 26.1 (NEW) | any `Glass` value (clear, tinted, interactive) | none | needs a glass value type | add `MorphGlassButton.glass: MorphGlass` once the value type exists (glass.md Breaking) |
| `controlSize(.mini/.small/.regular/.large/.extraLarge)` iOS 13+, `.extraLarge` iOS 17 | ambient size | none | UIKit `buttonSize` row; SwiftUI is ambient | add `MorphControlSize` enum + per-widget `size`; optional ambient via theme |
| `buttonBorderShape(.automatic/.capsule/.circle/.roundedRectangle(radius:))` iOS 15+ | shape | none | same as `cornerStyle` | `MorphGlassButton.shape` |
| `buttonSizing(.automatic/.flexible/.fitted)` iOS 26 (NEW) | fill vs hug width | layout (`SizedBox(width: double.infinity)`) | none | skip (Flutter layout) |
| `Button(role: .destructive/.cancel)` iOS 15, `.confirm` / `.close` iOS 26 (NEW) | role; `.confirm` is prominent in toolbars, `.close` shows an xmark | none on `MorphGlassButton` (bar items are bars.md) | gap | `MorphGlassButton.role` (low) |
| `Menu { } primaryAction:` iOS 15 | button with primary action + long-press menu | `MorphGlassButton(onPressed:, menu:)` (`MorphMenuTrigger.hold`, unmeasured hold) | ok | keep |

## Not relevant for Flutter
- `UIButton.ButtonType`, `setTitle(_:for:)` and the other legacy per-state setters, `titleEdgeInsets` etc.: replaced by configurations; Flutter uses widgets.
- `UIButton.Configuration.macIdiomStyle`, `UIBehavioralStyle`: Mac Catalyst only.
- `pointerStyleProvider`, `isPointerInteractionEnabled`: iPad pointer; Flutter `MouseRegion` if ever needed.
- Target-action / `UIAction` / `primaryAction:` initializers: `VoidCallback onPressed`.
- `titleTextAttributesTransformer`, `imageColorTransformer`, `NSAttributedString`: `TextStyle` / `IconTheme` on the child.
- `UIImage.SymbolConfiguration`: no SF Symbols in Flutter.

## morph-only API
- `MorphGlassButtonMotion` (pure motion of the flex press, `highlightSlop`, glow constants): keep but move out of `widgets.dart` (cross-cutting.md).
- `MorphGlassButtonStyle.disabledForegroundColor` / `disabledTintColor`: keep (measured; UIKit derives them).
- `MorphGlassButtonStyle.rimColor` / `tintedRimColor` / `shadowColor`: keep (flat-tier look).
- `MorphMenuButton` (round glass ellipsis that is its own menu): keep as a convenience; native is `UIButton(.glass(), image: ellipsis, menu:, showsMenuAsPrimaryAction: true)`. Its diameter lives in `MorphMenuStyle.buttonSize` - flag (a size inside a color style).
- `MorphMenuSource` (`shape`, `trigger`, `color`, `rimColor`, `focusable`): keep (any widget becomes its own menu).

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | Clear glass variants (`.clearGlass()`, `.prominentClearGlass()`) | high (media / map overlays) | S-M (needs per-surface clear material) | `MorphGlassButton.clear`, `.prominentClear` |
| 2 | Prominent without an explicit color; no ambient accent | high | S | `MorphGlassButton.prominent`, tint from a theme accent (cross-cutting.md #1) |
| 3 | Size presets (`buttonSize` / `controlSize`) | med | M (measure mini/small/medium/large on the device) | `MorphControlSize` + `MorphGlassButton.size` |
| 4 | Shape (`cornerStyle` / `buttonBorderShape`) | med | S-M (capsule painter -> `ShapeBorder`; flex law already shape-agnostic) | `MorphGlassButton.shape` |
| 5 | Menu options on `MorphGlassButton` (`preferredMenuElementOrder`, `menuActionTriggered`, dismiss) | med | S (forward to `MorphMenuSource`) | `menuOrder`, `onMenuOpen`, `dismissOnSelect` |
| 6 | Activity indicator in the button | med | S-M | `MorphGlassButton.loading` |
| 7 | Pop-up button (`changesSelectionAsPrimaryAction`, `.popup` indicator) | low-med | M | `MorphPopUpButton` / `MorphGlassButton.popUp` |
| 8 | `role` | low | S | `MorphGlassButton.role` |
| 9 | Observable highlight / held state | low | S | `onHighlightChanged` |

## Breaking changes before 1.0
- `MorphGlassButton.tint` doc "null for the clear glass" -> "null for the regular glass"; `MorphGlassButtonStyle` field docs "clear glass" -> "regular glass" (UIKit's clear is a different material).
- `MorphGlassButtonStyle.tintedRimColor` -> `prominentRimColor`, `tintedForegroundColor` -> `prominentForegroundColor` (UIKit/SwiftUI say prominent).
- Variant selection: prefer named constructors `MorphGlassButton.prominent` / `.clear` / `.prominentClear` over "non-null tint means prominent"; `tint` then means `baseBackgroundColor` only.
- `MorphMenuStyle.buttonSize` -> a `size` on `MorphMenuButton` (or `MorphControlSize`), out of the color style.
- `MorphGlassButtonMotion` -> motion library (not `widgets.dart`).
