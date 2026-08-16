# Changelog

Versions are git tags; pin one. Pre-1.0, minor versions may break API.

## 0.2.0 - 2026-08-16

Two additions, both driven by tools that live over content instead of
covering it.

- `showMorph(modal: false)` (and the same flag on
  `MorphFlight.launch`): a NON-MODAL flight mounts no scrim at all, so
  the page underneath stays fully interactive while the surface hovers
  over it - a search field expanding over the list it filters. Nothing
  dims and there is no tap-outside dismissal (`barrierDismissible` has
  no barrier to attach to); Esc and the local history entry still
  close the flight. Modal stays the default.
- `MorphPiece.tint`: an ink wash that is PART of the skin instead of
  an overlay approximating it. Painted over the fill from the piece's
  RESOLVED geometry, so it stays glued to the mass through channel
  displacement, deflation and the landing squash; an airborne piece
  paints none. Clipped by the traced silhouette, so the neck to a
  neighbour stays untinted - ink soaks the body, not the bond. Content
  paints above it. Toggling only the tint is paint-only: no relayout,
  no re-trace, no subscription resync - a hover wash can flip per
  frame.

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
