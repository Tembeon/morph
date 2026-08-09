# Changelog

Versions are git tags; pin one. Pre-1.0, minor versions may break API.

## 0.1.0 - 2026-08-09

The first tagged release.

- Engine (`package:morph/foundation.dart`): identity-based
  widget-to-overlay morphs on retargetable springs. `MorphTag` +
  `showMorph`/`showMorphDialog`/`showMorphSheet`, declarative
  `MorphAnchor`, `showMorphRoute` (the destination as a real Navigator
  route: live-state reparenting at settle, predictive back, drag on
  the settled page), `MorphSharedElement` (fade-through or solo
  flight), the displacement drag channel with commit heuristics,
  `MorphReveal` cascades, `MorphMotion` profiles and `MorphTheme`
  defaults. Flights and routes resolve the NEAREST overlay/navigator,
  so nested navigators keep their morphs inside themselves.
- The liquid skin: `MorphSkin`/`MorphPiece`/`MorphLink` fuse surfaces
  into one traced vector mass (no shaders), with flight necks, launch
  fellowships, per-cluster caching, an eval budget for bounded worst
  frames, and `MorphPieceChannel` - app-driven per-frame geometry with
  no widget rebuilds.
- Widgets (`package:morph/widgets.dart`): `showMorphMenu`,
  `MorphSurface`/`MorphTapTarget`, `SpringButton`, `Tug`,
  `ChaseSpring`.
- Example: a seven-scene tour of app mockups in a phone frame plus the
  sandbox playground; live at <https://tembeon.github.io/morph/>, API
  docs at <https://tembeon.github.io/morph/docs/>.
