# Glass - API parity (UIKit / SwiftUI iOS 27 vs morph)

Native: `UIGlassEffect`, `UIGlassEffect.Style`, `UIGlassContainerEffect`, `UIVisualEffectView`,
`UIBackgroundExtensionView`, `UIView.cornerConfiguration` / `UICornerConfiguration` / `UICornerRadius`;
SwiftUI `Glass`, `glassEffect(_:in:)`, `GlassEffectContainer`, `glassEffectID(_:in:)`,
`glassEffectUnion(id:namespace:)`, `GlassEffectTransition` / `glassEffectTransition(_:)`,
`backgroundExtensionEffect()`, `ConcentricRectangle`, `Edge.Corner.Style`, `containerShape(_:)`.
morph: `MorphGlass`, `MorphGlassPainter`, `MorphGlassSurface`, `MorphGlassKind`, `MorphGlassOptics`,
`MorphGlassRenderer`, `MorphGlassMaterial`, `MorphGlassTier`, `MorphAdaptiveGlass`,
`MorphGlassDeviceClass`, `MorphGlassContainer`, `MorphGlassGlow`, `MorphTouchGlowMotion`,
`MorphGlassOutline`, `MorphGlassInspector` / `MorphGlassCensus` / `MorphGlassHint`, `MorphSmallLens`;
engine `MorphSkin`, `MorphPiece`, `MorphPieceChannel`, `MorphLink`, `MorphSkinStyle`.
Passports: [../glass-optics.md](../glass-optics.md), [../glass-renderer.md](../glass-renderer.md),
[../skin-merge.md](../skin-merge.md), [../lens-and-flex.md](../lens-and-flex.md).

Key finding: every public glass API in UIKit/SwiftUI is "put glass on MY view". morph has no
such widget. Glass reaches the screen only inside morph's own controls (button, bars, menu,
sheet, search, lenses); `MorphGlassPainter` / `MorphGlassSurface` is a renderer seam, not a
consumer API. `MorphGlassContainer` batches resting glass into one layer but does not fuse
(no `spacing`); the engine skin (`MorphSkin`) fuses by the measured merge law but paints a
flat color, not glass.

## UIKit
| UIKit API (type.member, availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `UIGlassEffect(style:)` iOS 26 (NEW) | glass material for a `UIVisualEffectView` | none public (internally `MorphGlassSurface` with `glass: true`) | no widget puts glass behind arbitrary content | add `MorphGlassEffect` widget (child + shape + style + tint + interactive) |
| `UIGlassEffect.Style.regular` / `.clear` iOS 26 (NEW) | standard vs clear (no wash, full bevel) material | `MorphGlassMaterial.regular` / `.clear` | renderer-wide (`MorphGlassRenderer.material`), not per surface; extra `.toolbar` case has no public native counterpart | add per-surface style (`MorphGlassEffect.style`, `MorphGlassSurface.material`); keep renderer default |
| `UIGlassEffect.tintColor` iOS 26 (NEW) | tinted glass | `MorphGlassSurface.tint` (painter seam); `MorphGlassButton.tint` (prominent only) | not settable on arbitrary glass | add `MorphGlassEffect.tint` |
| `UIGlassEffect.isInteractive` iOS 26 (NEW) | glass reacts to touch (flex lift, glow) | flex interaction is internal (`MorphGlassButtonMotion`, `MorphTouchGlowMotion` public as math only) | no way to make app glass interactive | add `MorphGlassEffect.interactive` driving the existing flex machine |
| `UIGlassContainerEffect.spacing` iOS 26 (NEW) | glass views closer than spacing fuse; one shared sampling region | `MorphGlassContainer` (grouping only, no `spacing`); fusion in `MorphSkin.blend` (flat) and internal `MorphGlassPainter.buildLayer(spacing:)` | name suggests the native container but it never fuses; no public glass fusion | add `MorphGlassContainer.spacing` (default 0 = today's grouping) fusing member `MorphGlassEffect`s by the skin law |
| `UIVisualEffectView(effect:)`, `.effect`, `.contentView` iOS 8 (glass effect iOS 26) | host view; content sits above glass; animating `effect` nil <-> glass materializes | none (would be `MorphGlassEffect.child`) | no animated glass appear/disappear | add `MorphGlassEffect.visible` (or `style: identity`) animated with the materialize transition once measured |
| `UIBackgroundExtensionView` (`contentView`, `automaticallyPlacesContentView`) iOS 26 (NEW) | mirrors content past safe area under sidebars/inspectors | none | iPad/sidebar layouts only | skip for now (phone-first; revisit with split views) |
| `UIView.cornerConfiguration` iOS 26 (NEW) | per-view corner spec | none (shapes are `ShapeBorder`/`RRect`) | - | keep Flutter `ShapeBorder` |
| `UICornerConfiguration.capsule()` / `corners(radius:)` / `uniformEdges(...)` iOS 26 (NEW) | capsule / fixed / per-edge corners | `StadiumBorder`, `RoundedRectangleBorder` (Flutter) | none | keep (Flutter) |
| `UICornerRadius.containerConcentric(minimum:)` iOS 26 (NEW) | radius = container radius - inset | none public (`MorphSheet` reads display corner radii internally) | concentric corners must be computed by hand | add `MorphConcentricBorder` (ShapeBorder resolving against an ancestor shape / display corners) |
| `UIView.effectiveRadius(corner:)` iOS 26 (NEW) | resolved radius | none | follows from the above | add with `MorphConcentricBorder` |

## SwiftUI
| SwiftUI API (availability) | meaning | morph equivalent | gap / mismatch | proposal |
|---|---|---|---|---|
| `Glass.regular` / `.clear` iOS 26 (NEW) | same as UIKit style row | `MorphGlassMaterial` | same as UIKit | see UIKit |
| `Glass.identity` iOS 26 (NEW) | no glass (conditional glass without changing view identity) | none | toggling glass needs a different widget | add as a `MorphGlassEffect` style value (`MorphGlassStyle.identity`) |
| `Glass.tint(_:)`, `Glass.interactive(_:)` iOS 26 (NEW) | value-type modifiers | none | morph has no glass value type | add a value type (see Breaking: `MorphGlass` becomes it) |
| `View.glassEffect(_:in:)` iOS 26 (NEW), default shape capsule (`DefaultGlassEffectShape`) | glass behind a view in a shape | none | top gap | add `MorphGlassEffect(shape: StadiumBorder())` default capsule |
| `GlassEffectContainer(spacing:content:)` iOS 26 (NEW), spacing nil = system default | fuse + share sampling | `MorphGlassContainer` (no spacing); `MorphSkinStyle.subtle` = default spacing 8 | same as UIKit container row | same as UIKit; default spacing 8 (`MorphSkinStyle.subtle.blend`) when null |
| `View.glassEffectID(_:in:)` iOS 26 (NEW) | identity for births / matched shapes across layout changes | `MorphPiece.id` + `MorphPieceChannel.birthScale` / `birthSpring` (flat skin); `MorphTag` for flights | measured birth law exists, but only for the flat skin and internal bar capsules | add `MorphGlassEffect.id` inside a fusing `MorphGlassContainer` reusing the birth law |
| `View.glassEffectUnion(id:namespace:)` iOS 26 (NEW) | several glass views drawn as one shape regardless of distance | nearest `MorphLink` (explicit neck between two pieces, flat skin) | no union for glass | add `MorphGlassEffect.unionId` (low priority) |
| `GlassEffectTransition.matchedGeometry` / `.materialize` / `.identity`, `glassEffectTransition(_:)` iOS 26 (NEW) | how glass enters/leaves a container | matchedGeometry ~ birth law (internal); materialize unmeasured | no public choice | add `MorphGlassEffect.transition` after a materialize capture |
| `backgroundExtensionEffect()` iOS 26 (NEW) | same as `UIBackgroundExtensionView` | none | - | skip (as UIKit) |
| `ConcentricRectangle`, `Edge.Corner.Style.concentric(minimum:)` / `.fixed`, `containerShape(_:)` iOS 26 (NEW) | concentric shape resolved against the container shape | none | same as UIKit concentric row | `MorphConcentricBorder` + an inherited container shape (`MorphContainerShape`) |

## Not relevant for Flutter
- `UIVisualEffect` subclassing / `NSCoding` / `NSCopying` of effects: Dart values are immutable.
- `UIBlurEffect` / `UIVibrancyEffect` (legacy materials): Flutter `BackdropFilter` covers blur; not Liquid Glass.
- visionOS / tvOS / watchOS availability splits.
- `_UILiquidLensView`, `_UIFlexInteraction`: private; morph ports them as internals (passport only).

## morph-only API
- `MorphGlass` (installs a painter), `MorphGlassPainter` (pluggable renderer seam: `buildSurface` / `buildFill` / `buildBody` / `buildGlow` / `buildLayer`): keep; the seam that lets an app swap the renderer.
- `MorphGlassRenderer` (`tier`, `blur`, `refraction`, `light`, `frostControls`, `precache`, `liquidAvailable`, `bestTier`, static optics constants): keep; `tint` (mirrors the user's Settings Clear/Tinted slider, which apps cannot set natively) - flag: document as a user-setting mirror, not app styling.
- `MorphGlassTier`, `MorphAdaptiveGlass`, `MorphGlassDeviceClass`: keep (performance goal; no native analogue).
- `MorphGlassContainer.solidBackdrop`: keep (performance lever).
- `MorphGlassInspector`, `MorphGlassCensus`, `MorphGlassHint`: keep (dev tooling).
- `MorphGlassSurface`, `MorphGlassKind`, `MorphGlassOptics`, `MorphGlassGlow`, `MorphGlassOutline`, `MorphTouchGlowMotion`, `MorphSmallLens`: painter-seam data and motion math; flag - consumers of the seam only, move out of `widgets.dart` (see cross-cutting.md).
- `MorphSkin` / `MorphPiece` / `MorphLink` / `MorphMass` / `MorphStroke`: keep (engine; flat liquid shapes for any app).

## Ranked gaps
| # | gap | need | cost | proposal |
|---|---|---|---|---|
| 1 | No widget puts glass behind app content (`glassEffect(_:in:)`, `UIVisualEffectView(UIGlassEffect)`) | high | M (seam exists: one surface through `MorphGlassPainter.buildSurface`, live frames, resting body only) | add `MorphGlassEffect({child, shape = StadiumBorder(), style = regular, tint, interactive = false})` |
| 2 | Per-surface regular vs clear material (only renderer-wide `MorphGlassMaterial`) | high | S-M | per-surface style on `MorphGlassSurface` + `MorphGlassEffect.style`; renderer keeps a default |
| 3 | Glass fusion for app glass (`GlassEffectContainer(spacing:)`, `glassEffectID`) | med | M-L (merge law + birth law exist; need glass members registered with a container) | add `MorphGlassContainer.spacing`; `MorphGlassEffect.id` for births |
| 4 | Interactive glass on arbitrary shapes (`Glass.interactive()`, `UIGlassEffect.isInteractive`) | med | M (flex machine exists in `MorphGlassButton`) | `MorphGlassEffect.interactive` with `onPressed`-less lift/glow |
| 5 | Tinted glass on arbitrary surfaces (`tintColor`, `Glass.tint`) | med | S once #1 exists | `MorphGlassEffect.tint` |
| 6 | Concentric corners (`containerConcentric`, `ConcentricRectangle`) | med | S-M | `MorphConcentricBorder` |
| 7 | `GlassEffectTransition` / animated `effect` (materialize) | low | M (needs a capture) | after a materialize recording |
| 8 | `glassEffectUnion` | low | M | later |
| 9 | `backgroundExtensionEffect` | low | M | skip on phone |

## Breaking changes before 1.0
- `MorphGlass` (InheritedTheme installing a painter) -> `MorphGlassScope`, freeing `MorphGlass` for a SwiftUI-style value type (`MorphGlass.regular`, `.clear`, `.identity`, `.tint(c)`, `.interactive()`) used by `MorphGlassEffect` and `MorphGlassButton` (cf. `GlassButtonStyle(_ glass:)`). Alternative if the name stays: name the value type `MorphGlassStyle`.
- `MorphGlassMaterial` -> split: per-surface `MorphGlassStyle { regular, clear }` (UIKit `UIGlassEffect.Style` names); the `toolbar` material becomes a renderer-internal role choice (bars pick it), not a public enum case.
- `MorphGlassContainer` semantics: add `spacing` now (default keeps today's behaviour) so the name matches `UIGlassContainerEffect` before users rely on "container never fuses".
- `MorphGlassButtonStyle` docs call regular glass "clear glass" (see buttons.md) - fix with the button renames.
- `MorphGlassSurface`, `MorphGlassKind`, `MorphGlassOptics`, `MorphGlassGlow`, `MorphGlassOutline`, `MorphTouchGlowMotion`, `MorphSmallLens` -> move to a painter/motion library (`package:morph/glass_painter.dart` or `motion.dart`), out of `widgets.dart`.
