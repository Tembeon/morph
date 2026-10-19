# Scroll edge effect - API parity (UIKit / SwiftUI iOS 27.1 vs morph)

Native: `UIScrollEdgeEffect` (`style`, `isHidden`), `UIScrollEdgeEffect.Style` (`.automatic`, `.soft`, `.hard`),
`UIScrollView.topEdgeEffect` / `leftEdgeEffect` / `bottomEdgeEffect` / `rightEdgeEffect`,
`UIScrollEdgeElementContainerInteraction` (`scrollView`, `edge`); SwiftUI `ScrollEdgeEffectStyle`,
`scrollEdgeEffectStyle(_:for:)`, `scrollEdgeEffectHidden(_:for:)`, `safeAreaBar(edge:alignment:spacing:content:)`.
All iOS 26; nothing added or changed in iOS 27.0 or 27.1.
morph (`package:morph/morph.dart`): `MorphScrollEdgeEffect` (`extent`, `edge`, `style`, `scrolledUnder`,
`appearance`, `opacity`, static `bandExtent`), `MorphScrollEdgeEffectStyle` (`soft`, `hard`),
`MorphScrollEdgeEffectAppearance` (`light`, `dark`, `resolve`, `hardColorMatrix`); hosts
`MorphNavigationBar.edgeEffect` / `edgeEffectAppearance` / `scrolledUnder`, `MorphNavigationConfig.edgeEffect` /
`scrolledUnder`, `MorphNavigationScaffold.edgeEffect`; theme entry `MorphThemeData.appearances`.
Passport: [../bars.md](../bars.md) ("Spec - inline title, large title, edge effect"), cost in
[../glass-renderer.md](../glass-renderer.md) ("Small blurs").

Model difference: UIKit owns the effect per scroll view and per edge and shows it while content lies
under a bar or under an element registered with `UIScrollEdgeElementContainerInteraction`.
`MorphNavigationScaffold` derives `scrolledUnder` from its scroll controller the same way; a standalone
`MorphScrollEdgeEffect` takes an explicit `extent` and `scrolledUnder` from the app.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | status | gap / proposal |
|---|---|---|---|---|
| `UIScrollEdgeEffect.Style.soft` iOS 26 | light blur band past the bar, dissolving fade | `MorphScrollEdgeEffectStyle.soft` | covered | - |
| `UIScrollEdgeEffect.Style.hard` iOS 26 | thin film: saturated blur, uniform fade, hairline | `MorphScrollEdgeEffectStyle.hard` | covered | - |
| `UIScrollEdgeEffect.Style.automatic` iOS 26, the default | hard under a nav bar, none under a floating toolbar or tab bar (bars.md) | none; defaults `soft` standalone, `hard` in the nav hosts | gap | `MorphScrollEdgeEffectStyle.automatic`, resolved by the host, every default |
| `UIScrollEdgeEffect.style` iOS 26 | the edge's style | `MorphScrollEdgeEffect.style`, `MorphNavigationBar.edgeEffect` | covered | - |
| `UIScrollEdgeEffect.isHidden` iOS 26 | turn the edge off | `edgeEffect: null` on hosts; standalone: do not build it | partial | keep nullable style |
| `UIScrollView.topEdgeEffect` iOS 26 | per-edge effect owned by the scroll view | `MorphNavigationScaffold` (automatic presence); standalone `edge: AxisDirection.up` with manual `scrolledUnder` | partial | scroll-coupled standalone (gap 2) |
| `UIScrollView.bottomEdgeEffect` iOS 26 | bottom edge | `edge: AxisDirection.down`, drawn with the top's values | partial | bottom law [sim, bars.md]: hard radius 2 + (h - 54) / 88 clamped to 2 - 2.5, soft +30 - 40 |
| `UIScrollView.leftEdgeEffect` / `rightEdgeEffect` iOS 26 | side edges | none (assertion) | gap (2 members) | later (low) |
| `UIScrollEdgeElementContainerInteraction` (`scrollView`, `edge`) iOS 26 | registers a custom bar so the effect shapes under it | `extent` passed by hand | gap | `MorphScrollEdgeBar` measuring its child; top hard band max(h, 62) [sim] |
| per-page effect sliding with its page on push / pop | effect belongs to each page's scroll view | one effect in the bar, cross-faded through `opacity` | approx | declared deviation (bars.md) |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | status | gap / proposal |
|---|---|---|---|---|
| `ScrollEdgeEffectStyle.hard` / `.soft` iOS 26 | as UIKit | `MorphScrollEdgeEffectStyle` | covered (2 members) | - |
| `ScrollEdgeEffectStyle.automatic` iOS 26 | as UIKit | none | gap | as UIKit |
| `scrollEdgeEffectStyle(_:for: Edge.Set)` iOS 26, nil = automatic | style per edge set, ambient to the scroll view | `edgeEffect` on `MorphNavigationBar` / `MorphNavigationConfig` / `MorphNavigationScaffold` (top only) | partial | `MorphToolbar.edgeEffect` (default automatic = none) |
| `scrollEdgeEffectHidden(_:for:)` iOS 26 | hide per edge | `edgeEffect: null` | partial | keep |
| `safeAreaBar(edge: VerticalEdge, ...)` iOS 26 | custom bar inset into the safe area, effect under it | none | gap | `MorphScrollEdgeBar` |
| `safeAreaBar(edge: HorizontalEdge, ...)` iOS 26 | side bar variant | none | gap | with horizontal edges |

Counts (n/a excluded): 17 applicable, 5 covered, 5 partial, 7 gaps.

## Not relevant for Flutter
- `UIScrollView` content inset adjustment around bars: Flutter `MediaQuery.padding` and slivers.
- tvOS / visionOS availability.
- The private `UIKit.ScrollEdgeEffectView` / `PocketSettings`: ported as `MorphScrollEdgeEffectAppearance` values (bars.md).

## morph-only API
- `MorphScrollEdgeEffectAppearance` (`backgroundColor`, `fadeOpacity`, `separatorColor`, `softBlurRadius`, `hardBlurRadius`, `softOverhang`, `softFadeStart`, `hardSaturation`, `hardBrightness`, `hardColorMatrix`): exposes the measured values; `backgroundColor` stands in for what lies behind the scroll view.
- `MorphScrollEdgeEffect.opacity`: a host-driven fade without an opacity layer above the blur.
- `MorphScrollEdgeEffect.bandExtent`: static helper.
- Flat tier: fade and hairline only, no blur (declared trade).

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | No custom-bar host (`safeAreaBar`, `UIScrollEdgeElementContainerInteraction`) | high | M | `MorphScrollEdgeBar({edge, child, style})` measuring the child and placing the effect |
| 2 | Standalone `scrolledUnder` is manual | high | S-M | drive it from a `ScrollController` or `MorphContentScroll`, with the nav bar's 0.35 s fade |
| 3 | No `automatic` style; defaults differ per widget | med | S | `MorphScrollEdgeEffectStyle.automatic` |
| 4 | Bottom edge drawn with top values | low-med | S meas. | confirm the [sim] bottom law on the device, then port it |
| 5 | `MorphToolbar` has no edge configuration | low | S | `MorphToolbar.edgeEffect` (default none, as native) |
| 6 | Left / right edges | low | M | later |

## Breaking changes before 1.0
- Done: `active` -> `scrolledUnder`; `MorphScrollEdgeEffectThemeData` -> `MorphScrollEdgeEffectAppearance`, `theme` -> `appearance`, `edgeEffectTheme` -> `edgeEffectAppearance`; `edge` asserts a vertical direction.
- Open: `MorphScrollEdgeEffect.style` default `soft` -> `automatic` once added; nav host defaults `hard` -> `automatic` (resolves to hard, no visual change).

## Behaviour fidelity

Family `scroll-edge` (`UIScrollEdgeEffect`):

| dimension | grade | evidence | open items |
|---|---|---|---|
| api | missing | tables above | automatic, custom-bar host, side edges |
| layout | unbacked | top band replayed: test/scroll_edge_effect_test.dart 'soft: ...' and 'the band ends at the bar ...' vs test/fixtures/ios27-device/bars/scroll-edge.json (hard = bar, soft = bar + 40) | `edge: down` draws the top's radius and overhang, undeclared; the `hardBlurRadius` dartdoc reads as if no bottom band were drawn |
| states | replayed | hard light, soft light, automatic dark (fade 0.6) vs the same fixture | dark separator and dark blur not asserted |
| transitions | replayed | fade on the 0.35 s critically damped spring: test/navigation_motion_test.dart vs ios27/bars/title-*.jsonl and ios27-device/bars/title-*.jsonl (edge opacity rms < 0.12) | per-page slide on push / pop: declared deviation |
| boundaries | replayed | the replay switches where the recorded offset crosses morph's large title height (`_crossings`) | standalone effect: app decides |
| configuration | missing | soft / hard x light / dark covered | `automatic`; bottom law; toolbar host |
| events | n/a | no callbacks | - |
| input | n/a | the effect takes no input; hosts animate only while scrolling (`isScrollingNotifier`) | - |
| mutation | n/a | - | - |
| accessibility | missing | - | Increase Contrast / Reduce Transparency behaviour of the effect unmeasured |
| optics | approx | blur radii, saturation matrix (2e-3), fade alpha, separator alpha, fade start replayed vs the device layers; blur raised to Impeller's half resolution, NEAR (scroll_edge_effect.dart dartdoc, test/blur_reach_test.dart) | Pixel energy of the raise pending (bars.md) |
| platform | approx | flat tier: fade and hairline only (test/scroll_edge_effect_test.dart 'flat edges keep their fade ...') | horizontal edges assert |
| performance | measured | Pixel 6a: the band blurs a copy around it, 7.6 -> 2.8 ms GPU a scrolling frame (glass-renderer.md "Small blurs", bars.md) | the half-resolution raise: Pixel GPU and energy pending |
