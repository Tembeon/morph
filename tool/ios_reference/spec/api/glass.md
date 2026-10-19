# Glass - API parity (UIKit / SwiftUI iOS 27.1 vs morph)

Native: `UIGlassEffect`, `UIGlassEffect.Style`, `UIGlassContainerEffect`, `UIVisualEffectView`,
`UIBackgroundExtensionView`, `UIView.cornerConfiguration` / `UICornerConfiguration` / `UICornerRadius`;
SwiftUI `Glass`, `glassEffect(_:in:)`, `DefaultGlassEffectShape`, `GlassEffectContainer`,
`glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`, `GlassEffectTransition` /
`glassEffectTransition(_:)`, `backgroundExtensionEffect()`, `ConcentricRectangle`, `Edge.Corner.Style`,
`containerShape(_:)`, `GeometryProxy.concentricCornerRadii`.
morph (`package:morph/morph.dart`): `MorphGlassEffect` (`child`, `shape`, `style`, `tint`, `interactive`,
`appearance`), `MorphGlassStyle` (`regular`, `clear`), `MorphGlassContainer` (`child`, `solidBackdrop`),
`MorphGlassRenderer` (`.adaptive()`, `.tier(MorphGlassTier)`), `MorphGlassTier` (`flat`, `fake`, `liquid`),
`MorphThemeData.glass`, `MorphTheme.precacheGlass` / `liquidGlassAvailable` / `liquidGlassUnavailableReason`.
Painter seam (`package:morph/glass_painter.dart`): `MorphGlassScope`, `MorphGlassPainter` (`buildSurface`,
`buildFill`, `buildBody`, `buildGlow`, `buildLayer(spacing:, contentSlots:, outline:)`), `MorphGlassSurface`
(incl. `style`), `MorphGlassKind`, `MorphGlassOptics`, `MorphGlassGlow`, `MorphGlassOutline`.
Passports: [../glass-optics.md](../glass-optics.md), [../glass-renderer.md](../glass-renderer.md),
[../skin-merge.md](../skin-merge.md), [../lens-and-flex.md](../lens-and-flex.md).

SDK 27.1: no glass API changed since iOS 26.0. iOS 27.0 adds `GeometryProxy.concentricCornerRadii` and
`concentricCornerRadii(in:)`; iOS 26.1 adds `UIColorEffect(color:)` (n/a below).

Key finding: `MorphGlassEffect` puts glass behind app content (regular or clear, tinted, interactive).
App glass never fuses: `MorphGlassContainer` shades resting glass in one layer and shares one backdrop
read, but has no `spacing`. Fusion by the measured merge law exists only inside package controls (bar
capsules at spacing 12, the menu neck) and through the seam's `MorphGlassPainter.buildLayer(spacing:)`.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | status | gap / proposal |
|---|---|---|---|---|
| `UIGlassEffect(style:)` iOS 26 | glass material for a `UIVisualEffectView` | `MorphGlassEffect` | covered | - |
| `UIGlassEffect.Style.regular` / `.clear` iOS 26 | standard vs clear material | `MorphGlassStyle.regular` / `.clear` (`MorphGlassEffect.style`, `MorphGlassSurface.style`) | covered | clear look is an upstream fit (Behaviour fidelity) |
| `UIGlassEffect.tintColor` iOS 26 | tinted glass | `MorphGlassEffect.tint` | covered | tint tone is an upstream fit |
| `UIGlassEffect.isInteractive` iOS 26 | glass reacts to touch (flex lift, glow) | `MorphGlassEffect.interactive` | covered | motion assumed equal to a `.glass()` button's |
| `UIGlassContainerEffect` iOS 26 | one combined glass render, shared sampling | `MorphGlassContainer` | partial | shares the backdrop read; never fuses |
| `UIGlassContainerEffect.spacing` iOS 26 | members closer than spacing fuse | none (internal `buildLayer(spacing:)`) | gap | `MorphGlassContainer.spacing` fusing member `MorphGlassEffect`s by the merge law |
| `UIVisualEffectView(effect:)`, `.contentView` iOS 8 | host view; content above the glass | `MorphGlassEffect(child:)` | covered | - |
| `UIVisualEffectView.effect` (settable, animatable) | swap or animate the effect (nil <-> glass materializes) | style / tint swap in one frame | partial | animated change after measuring |
| `UIView.cornerConfiguration`, `UICornerConfiguration.capsule()` / `corners(radius:)` / `uniform*` iOS 26 | per-view corner spec | `MorphGlassEffect.shape`: `StadiumBorder`, `CircleBorder`, uniform `RoundedRectangleBorder` / `RoundedSuperellipseBorder` | partial | per-corner radii assert |
| `UICornerRadius.containerConcentric(minimum:)` iOS 26 | radius = container radius - inset | none | gap | `MorphConcentricBorder` |
| `UIView.effectiveRadius(corner:)` iOS 26 | resolved corner radius | none | gap | with `MorphConcentricBorder` |
| `UIBackgroundExtensionView` (`contentView`, `automaticallyPlacesContentView`) iOS 26 | mirrors content past the safe area under sidebars | none | gap | later, with split views |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | status | gap / proposal |
|---|---|---|---|---|
| `Glass.regular` / `.clear` iOS 26 | material values | `MorphGlassStyle` | covered (2 members) | - |
| `Glass.identity` iOS 26 | no glass, same view identity | none | gap | a `MorphGlassStyle.identity` only together with transitions |
| `Glass.tint(_:)`, `Glass.interactive(_:)` iOS 26 | value modifiers | `MorphGlassEffect.tint`, `.interactive` | covered (2 members) | parameters, not a value type |
| `View.glassEffect(_:in:)` iOS 26 | glass behind a view in any `Shape` | `MorphGlassEffect` | partial | four shape kinds, uniform radius only |
| `DefaultGlassEffectShape` iOS 26 | capsule default | `shape = StadiumBorder()` default | covered | - |
| `GlassEffectContainer(spacing:content:)` iOS 26 | fuse + share sampling | `MorphGlassContainer` | partial | as UIKit `spacing` |
| `View.glassEffectID(_:in:)` iOS 26 | identity for births and matched shapes | none | gap | `MorphGlassEffect.id` in a fusing container; birth law measured (skin-merge.md) |
| `View.glassEffectUnion(id:namespace:)` iOS 26 | several views drawn as one shape | none | gap | low |
| `GlassEffectTransition.matchedGeometry` / `.materialize` / `.identity`, `glassEffectTransition(_:)` iOS 26 | how glass enters / leaves | none | gap (4 members) | materialize measured [sim 2026-10-14]: opacity p, scale 1.2 - 0.2 p, gaussian blur 10 (1 - p) pt, linear in the driving progress, removal reversed, own shape while it fades |
| `backgroundExtensionEffect()` iOS 26 | as `UIBackgroundExtensionView` | none | gap | as UIKit |
| `ConcentricRectangle`, `Edge.Corner.Style.concentric(minimum:)` / `.fixed`, `containerShape(_:)` iOS 26 | concentric shape against the container shape | none | gap (3 members) | `MorphConcentricBorder` + an inherited container shape |
| `GeometryProxy.concentricCornerRadii`, `concentricCornerRadii(in:)` iOS 27.0 | read concentric radii | none | gap | same |

Counts (members an app developer uses, n/a excluded): glass material and container 30 applicable,
10 covered, 4 partial, 16 gaps; `UIVisualEffectView` (renderer-tiers) 3 applicable, 2 covered, 1 partial.

## Not relevant for Flutter
- `UIVisualEffect` subclassing, `NSCoding` / `NSCopying` of effects: Dart values are immutable.
- `UIBlurEffect`, `UIVibrancyEffect` (legacy materials): Flutter `BackdropFilter`; not Liquid Glass.
- `UIColorEffect(color:)` iOS 26.1: a solid color fill (`ColoredBox`).
- visionOS / tvOS / watchOS availability splits.
- `_UILiquidLensView`, `_UIFlexInteraction`: private; ported as internals (lens-and-flex.md).

## morph-only API
- `MorphGlassRenderer.adaptive()` / `.tier()`, `MorphGlassTier`: the renderer tier per session (performance goal, no native analogue). `adaptive()` dartdoc says "flat glass elsewhere"; the code draws fake glass where Flutter GPU is missing (web): fix the doc.
- `MorphTheme.precacheGlass`, `liquidGlassAvailable`, `liquidGlassUnavailableReason`: shader warm-up and capability.
- `MorphGlassContainer.solidBackdrop`: performance lever, trusts the color.
- `MorphGlassEffect.appearance` (`MorphGlassButtonAppearance`): flat colors without a painter or on the flat tier.
- Painter seam (`glass_painter.dart`): lets an app swap the renderer; consumers of the seam only.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | App glass never fuses (`spacing`, `glassEffectID`) | med | M-L (merge and birth laws measured; members must register with a container) | `MorphGlassContainer.spacing`, `MorphGlassEffect.id` |
| 2 | Clear and tinted glass look unmeasured (upstream fits) | high | M meas. | record `clearGlass` / tinted panels as for the regular face table |
| 3 | Concentric corners | med | S-M | `MorphConcentricBorder` (+ `concentricCornerRadii`) |
| 4 | `GlassEffectTransition` / animated `effect` | low-med | M (materialize measured on the sim) | `MorphGlassEffect.transition` |
| 5 | Arbitrary shapes in `MorphGlassEffect` | low-med | M | per-corner radii, then paths (fake glass only for paths) |
| 6 | Increase Contrast glass material | med | M meas. | measure on the device, then a high-contrast table |
| 7 | `glassEffectUnion`, `Glass.identity`, `backgroundExtensionEffect` | low | M | later |

## Breaking changes before 1.0
- Done: `MorphGlass` -> `MorphGlassScope`; per-surface `MorphGlassStyle { regular, clear }` public, `MorphGlassMaterial` internal; seam types moved to `glass_painter.dart`; the button docs no longer call regular glass clear.
- Open: `MorphGlassContainer.spacing` (default 0 keeps today's grouping) so the name means what `UIGlassContainerEffect` means before users rely on "never fuses".
- Open: a SwiftUI-style `Glass` value type is not needed while `MorphGlassEffect` takes `style` / `tint` / `interactive` as parameters; decide before adding `identity` and `transition`.

## Behaviour fidelity

Family `glass-material` (`UIGlassEffect`, `UIGlassContainerEffect`):

| dimension | grade | evidence | open items |
|---|---|---|---|
| api | missing | tables above | spacing, glassEffectID, union, transitions, concentric |
| layout | replayed | merge law: test/liquid_apple_merge_test.dart vs test/fixtures/ios27-device/merge/profiles-{uikit,swiftui}.json, necks.json (pair rms < 0.6 pt, page < 0.4); the glass outline traces the same `LiquidField` (lib/src/widgets/glass_outline.dart `_fuseContainer`); skin-merge.md | app glass does not fuse; 3+ mass mixing unmeasured |
| states | unbacked | regular face light / dark by size measured (glass-optics.md "Native face transfer") in `Ios27LiquidGlassColorModel`; menu card face replayed (test/menu_glass_body_test.dart vs ios27-device/menu_api/card-tone.json, 1.5 levels) | clear face and tint tone are upstream fits; no fixture or test for the regular face table; light material too bright in the sim audit (recheck after the face refit) |
| transitions | missing | materialize law [sim] and births (skin-merge.md) measured | neither implemented; animated style / tint changes unmeasured |
| boundaries | replayed | merge replay sweeps gaps 40 .. -5 pt at spacing 10 .. 80 | - |
| configuration | measured | face transfer per size (5 sizes) and appearance; `frostControls` off is a declared cost trade | the user's Clear / Tinted setting is not readable from Flutter (renderer `tint` 0) |
| events | n/a | glass fires no callbacks | - |
| input | approx | `interactive` runs `MorphGlassButtonMotion` (glass-button replays); lib/src/widgets/glass_effect.dart:32 declares it unmeasured on its own | record interactive glass on a plain panel |
| mutation | missing | - | native animates effect changes; morph swaps in one frame; unmeasured |
| accessibility | missing | states.md "Increase Contrast": glass material not ported | Increase Contrast glass; Reduce Transparency (not exposed by Flutter); Reduce Motion keeps the glow, no lift (approx) |
| optics | unbacked | measured: lens magnification / shrink (glass-optics.md table, references/dark + light), face transfer; test/glass_renderer_test.dart pins the lens values | rim, refraction 20 / 60, optical corner 1.5x, tint tone and clear face are upstream fits; `lensDispersion` -0.25 has no source |
| platform | n/a | see renderer-tiers | - |
| performance | measured | glass-renderer.md "Device numbers", "Glass container" (4 / 8 buttons 18 / 22 percent faster on the Pixel 6a), "Energy: ADPF" | - |

Family `renderer-tiers` (`UIVisualEffectView`; tiers have no native analogue):

| dimension | grade | evidence | open items |
|---|---|---|---|
| api | missing | `MorphGlassEffect` covers init / contentView | animated `effect` change |
| layout | n/a | every tier draws the package's outline (test/glass_outline_contract_test.dart) | - |
| states | measured | tier per device class from Pixel 6a Vulkan / GLES, iPhone 16 Pro, Redmi 6A Skia (glass-renderer.md "Adaptive policy"); test/glass_renderer_test.dart 'the adaptive tier' | Apple GPUs before the A13 and `unknown` -> liquid unmeasured |
| transitions | n/a | one tier per session; `MorphTheme.precacheGlass` removes the fake-to-liquid start (test/glass_pipeline_warm_up_test.dart, test/glass_startup_bounds_test.dart) | - |
| boundaries | approx | blur raised to Impeller's half resolution by at most 12 percent, NEAR (blur_reach.dart, test/blur_reach_test.dart) | - |
| configuration | approx | fake = liquid without refraction and lens optics, least-squares face line; flat = flat fill (both declared, glass-renderer.md "Tiers") | - |
| events, input, mutation | n/a | - | - |
| accessibility | n/a | - | Reduce Transparency could select a tier if Flutter exposed it |
| optics | approx | declared fake / flat looks; liquid optics graded above | - |
| platform | measured | liquid iOS / macOS / Android, fake on the web (glass_liquid_web.dart), flat on Skia and GLES (device runs above) | Windows / Linux not run (macOS stands in) |
| performance | measured | glass-renderer.md device sections; the passport marks the policy numbers as engineering defaults | - |
