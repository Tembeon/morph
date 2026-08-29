# Changelog

Versions are git tags; pin one. Pre-1.0, minor versions may break API.

## 0.3.0 - 2026-08-29

The tactile pass. The widgets layer learns how a glass surface answers
a finger, and the engine grows the two things that pass needed: a
contour on the mass and one spring family shared by button and flight.
The `Tug` rewrite breaks API; everything else is additive.

- `Tug` is rebuilt on the liquid-glass button model. ONE degree of
  freedom, the raw pull on the chase spring, and every visual is a pure
  function of its (value, velocity). Travel is
  `reach * tanh(give * d / reach)` at give 0.05, so a few percent of
  the finger transmits and the asymptote sits a whole side away
  instead of a wall ten px out; the silhouette reads the raw pull at
  `stretch` gain plus its velocity times `jiggle`, saturated and
  volume-corrected, so the flesh answers more than the body moves;
  pointer-down LIFTS by `pressGrow` px per axis on a 363ms half-bounce
  spring (negative sinks, for ink). The gesture layer is a raw
  `Listener` outside the arena, so a selector or a scrollable inside a
  Tug still wins its own drag, and `vertical` gates both the input and
  scaleY - a bar pins its height. Past a 2:1 aspect the transmission
  fades by itself.
  BREAKING: `follow`, `lean`, `TugPull`/`onPull` and
  `MorphPieceChannel.contentScaleX/Y` are gone. Ink lies on the body
  and cannot slide, so content deforms with the mass 1:1. `dead` is
  gone and `cap` is now `reach`: both changed units in the rewrite, so
  the rename breaks stale call sites loudly instead of silently losing
  20x of their travel.
- `MorphPillHost`: the selection pill's physics as a host you draw
  from. Everything is px along the track axis; the owner maps
  positions through two callbacks (`hit` for taps, `snap` for
  carries), feeds a raw pointer stream in and paints where `centerX`
  and `resolveSize` say. The grab is the native model: the DOWN lifts
  the pill in place on its own item and carries it to a held one, the
  finger then moves it by its own displacement, confined to the slot
  span by the snap grid itself, and the commit waits for the release.
  Every release walks through one door, so an interrupted journey
  cannot strand the pill between slots. Chrome sympathy comes out as
  `chromeShift` and `chromeBreath` for the bar's piece channel.
- `MorphSquash`: deformation from force. Positions in, one signed
  deviation out (`scaleX = 1 + d`, `scaleY = 1 - d`, area held), so
  gaining speed stretches, braking squashes, and constant speed leaves
  the body alone. Only positions are sampled, so it composes with any
  driver; the intended one is a `MorphPieceChannel` write on a
  selection blob.
- `MorphStroke` on `MorphSkin.stroke`: the mass carries its own
  contour. The stroke follows the same traced path as the fill, so
  necks, deformations and flight blobs are outlined for free. Inner by
  contract (clip plus double width), painted after the tints, and
  outside the trace signature - a stroke change repaints without
  re-tracing. `MorphPiece.morphable` folds it into the tag shape and
  the flight frame lerps the side through the concentric rebuild, so a
  container launches outlined and its contour dissolves as the surface
  becomes the dialog.
- `MorphMotion.glass`: the material-unification profile, close 420ms
  at bounce 0.3 with a -1.5 hint. It is a FAMILY, not an instance -
  the same character calibrated for flight mass, while Tug keeps its
  own 363ms spring for finger-scale amplitudes. Sharing the literal
  button spring was tried and rejected by hand: its undershoot past
  the handoff latch turns into a ~22px landing kick over a flight's
  hundreds of pixels.
- `MorphSkin.contentFilterQuality`: content is rasterized once in its
  own space and the channel transform only resamples it, so glyphs
  stop shuffling under a moving matrix. The filter layer is retained
  per child - the raster reuse the knob buys.

Fixes:

- `Tug` forgets its pointer at dispose. A finger still down when the
  subtree left the tree used to report its up into disposed
  controllers. `chaseStiffness` now reaches a live chase instead of
  being captured once, and a negative `volume` can no longer drive a
  NaN into the channel.
- Frames resuming after a gap (a route covering the scene, the app
  backgrounded) finish the journey instead of integrating the whole
  gap in 240Hz substeps.
- A stroked flight drew its contour twice, the shuttle's surface and
  the skin's blob over the same pixels. The blob's box is clipped out
  of the skin's stroke and the replica flies unstroked, the way it
  already flies unshadowed.

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
