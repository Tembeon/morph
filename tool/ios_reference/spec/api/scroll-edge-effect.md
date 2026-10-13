# Scroll edge effect - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIScrollEdgeEffect` (`style`, `isHidden`), `UIScrollEdgeEffect.Style` (`.automatic`, `.soft`, `.hard`),
`UIScrollView.topEdgeEffect` / `leftEdgeEffect` / `bottomEdgeEffect` / `rightEdgeEffect`,
`UIScrollEdgeElementContainerInteraction` (`scrollView`, `edge`); SwiftUI `ScrollEdgeEffectStyle`,
`scrollEdgeEffectStyle(_:for:)`, `scrollEdgeEffectHidden(_:for:)`, `safeAreaBar(edge:alignment:spacing:content:)`.
All iOS 26 (NEW with Liquid Glass); nothing added in iOS 27.
morph: `MorphScrollEdgeEffect` (`extent`, `edge`, `style`, `active`, `theme`, `opacity`, `bandExtent`),
`MorphScrollEdgeEffectStyle` (`soft`, `hard`), `MorphScrollEdgeEffectThemeData`;
`MorphNavigationBar.edgeEffect` / `edgeEffectTheme` / `scrolledUnder`, `MorphNavigationConfig.edgeEffect`,
`MorphWidgetsTheme.scrollEdgeEffect`.
Passport: [../bars.md](../bars.md) ("Spec - inline title, large title, edge effect"), cost in
[../glass-renderer.md](../glass-renderer.md) ("Small blurs").

Model difference: UIKit owns the effect per scroll view and per edge, and shows it
automatically while content lies under a bar (or under an element registered with
`UIScrollEdgeElementContainerInteraction`). morph's effect is a standalone overlay the app (or
`MorphNavigationBar`) places with an explicit `extent` and an explicit `active` flag.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIScrollEdgeEffect.Style.soft` iOS 26 (NEW) | light blur band past the bar + dissolving fade | `MorphScrollEdgeEffectStyle.soft` | none (measured: `softBlurRadius` 1.5, `softOverhang` 40, `softFadeStart` 0.3407) | keep |
| `UIScrollEdgeEffect.Style.hard` iOS 26 (NEW) | "thin film": saturated blur, uniform fade, hairline | `MorphScrollEdgeEffectStyle.hard` | none (`hardSaturation` 1.25, `hardBrightness` 0.03, `separatorColor`) | keep |
| `UIScrollEdgeEffect.Style.automatic` iOS 26 (NEW), the default | system picks (hard under a nav bar, none under a floating toolbar per bars.md) | none; `MorphScrollEdgeEffect.style` defaults to `soft`, `MorphNavigationBar.edgeEffect` to `hard` | defaults differ per widget instead of one `automatic` | add `MorphScrollEdgeEffectStyle.automatic` resolved by the host (nav bar -> hard, toolbar -> none, standalone -> soft) and make it every default |
| `UIScrollEdgeEffect.isHidden` iOS 26 (NEW) | turn the edge's effect off | `MorphNavigationBar.edgeEffect: null`; standalone: do not build it | different shape (nullable style vs bool) | keep nullable style on hosts; add `hidden` only if the automatic host lands |
| `UIScrollView.topEdgeEffect` / `bottomEdgeEffect` iOS 26 (NEW) | per-edge effect owned by the scroll view | `MorphScrollEdgeEffect.edge` = `AxisDirection.up` / `.down` | the effect is not tied to a scroll view; `active` must be computed by the app | add `MorphScrollEdgeEffect.automatic(controller:)` (or a `ScrollNotification` listener) that derives `active` from the scroll position |
| `UIScrollView.leftEdgeEffect` / `rightEdgeEffect` iOS 26 (NEW) | side edges (sidebars, horizontal scroll) | none: `edge` takes any `AxisDirection` but `.left` / `.right` paint as the bottom edge | silent misbehaviour | assert `edge` is vertical now; add horizontal edges later (low) |
| (automatic presence while content is under the bar) | effect follows content offset, switches in one frame | `MorphScrollEdgeEffect.active`, `MorphNavigationBar.scrolledUnder` (fade on crit 0.35) | two names for one concept | rename `active` -> `scrolledUnder` (see Breaking) |
| `UIScrollEdgeElementContainerInteraction` (`scrollView`, `edge`) iOS 26 (NEW) | registers a custom bar/view so the edge effect shapes under it | `MorphScrollEdgeEffect.extent` (app passes the bar's far edge) | no measuring of the custom bar | add a `MorphScrollEdgeBar` host that measures its child and places the effect (also covers SwiftUI `safeAreaBar`) |
| per-page effect sliding with its page on push/pop | effect belongs to each page's scroll view | one effect in the bar, cross-faded (`MorphScrollEdgeEffect.opacity`) | declared deviation in bars.md | keep (documented) |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `ScrollEdgeEffectStyle.automatic/.hard/.soft` iOS 26 (NEW) | same as UIKit | `MorphScrollEdgeEffectStyle` | missing `automatic` (UIKit row 3) | same as UIKit |
| `scrollEdgeEffectStyle(_:for: Edge.Set)` iOS 26 (NEW), nil = automatic | style per edge set, ambient to the scroll view | `MorphNavigationBar.edgeEffect`, `MorphNavigationConfig.edgeEffect` (top only) | no bottom-edge config on `MorphToolbar` | add `MorphToolbar.edgeEffect` (default automatic = none) |
| `scrollEdgeEffectHidden(_:for:)` iOS 26 (NEW) | hide per edge | `edgeEffect: null` | same as UIKit `isHidden` row | keep |
| `safeAreaBar(edge:alignment:spacing:content:)` iOS 26 (NEW) | custom bar inset into the safe area; scroll edge effect extends under it | none | gap: a custom top/bottom bar gets no effect unless the app places `MorphScrollEdgeEffect` with a hand-measured `extent` | add `MorphScrollEdgeBar` (same proposal as `UIScrollEdgeElementContainerInteraction`) |

## Not relevant for Flutter
- `UIScrollView` content inset adjustment / `contentInsetAdjustmentBehavior` around bars: Flutter `MediaQuery.padding` and slivers.
- tvOS / visionOS availability.
- The private `UIKit.ScrollEdgeEffectView` / `PocketSettings`: ported as `MorphScrollEdgeEffectThemeData` values (passport).

## morph-only API
- `MorphScrollEdgeEffectThemeData` (`backgroundColor`, `fadeOpacity`, `separatorColor`, `softBlurRadius`, `hardBlurRadius`, `softOverhang`, `softFadeStart`, `hardSaturation`, `hardBrightness`, `hardColorMatrix`, `light` / `dark`): keep (native look is not configurable; this exposes the measured values). `backgroundColor` is needed because Flutter cannot read "what lies behind the scroll view" - keep.
- `MorphScrollEdgeEffect.opacity` (fade without an `Opacity` layer): keep.
- `MorphScrollEdgeEffect.bandExtent` (static helper): keep.
- Flat tier draws fade + hairline only (no blur): keep, declared trade.

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | No custom-bar host (`safeAreaBar`, `UIScrollEdgeElementContainerInteraction`): the app must measure `extent` itself | high (any custom header / bottom bar over a list) | M | `MorphScrollEdgeBar({edge, child, style})` measuring the child, insetting `MediaQuery.padding`, placing the effect |
| 2 | `active` is manual; UIKit derives it from the scroll position | high | S-M | `MorphScrollEdgeEffect` driven by a `ScrollController` / `ScrollNotification` (reuse the nav bar's `scrolledUnder` fade, crit 0.35) |
| 3 | No `automatic` style; defaults differ (`soft` standalone, `hard` in the nav bar) | med | S | add `MorphScrollEdgeEffectStyle.automatic`, resolved per host |
| 4 | Bottom edge on `MorphToolbar` not configurable | low-med | S | `MorphToolbar.edgeEffect` (default none, as native under a floating toolbar) |
| 5 | Left / right edges accepted but drawn as bottom | low | S (assert) / M (support) | assert vertical now |

## Breaking changes before 1.0
- `MorphScrollEdgeEffect.active` -> `scrolledUnder` (same concept as `MorphNavigationBar.scrolledUnder`).
- `MorphScrollEdgeEffect.style` default `soft` -> `automatic` (once added); `MorphNavigationBar.edgeEffect` default `hard` -> `automatic` (resolves to hard, no visual change).
- `MorphScrollEdgeEffectThemeData` -> follow the package look-table rule from cross-cutting.md (it is the only `*ThemeData`; every other look table is `*Style`), and `MorphScrollEdgeEffect.theme` / `MorphNavigationBar.edgeEffectTheme` -> the same parameter name every other control uses for its look table.
- `MorphScrollEdgeEffect.edge` -> a vertical-only type (`VerticalDirection` or `AxisDirection` with an assert) until horizontal edges exist.
