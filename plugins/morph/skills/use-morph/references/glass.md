# Glass: choosing, composing, keeping it fast

## Which glass is drawn

- `MorphThemeData.glass` decides for everything under the theme:
  - `MorphGlassRenderer.adaptive()` picks once per session from the GPU:
    liquid on a capable GPU (Impeller on Vulkan or Metal, Apple A13 and
    newer), flat on the OpenGL ES fallback, on Skia and on older Apple
    GPUs, where sampling the backdrop misses the frame budget. It never
    switches at runtime from frame timings.
  - `MorphGlassRenderer.tier(MorphGlassTier.flat)` or `.liquid` fixes
    the tier, for example from a user setting.
  - With no theme choosing glass, the controls draw flat.
- The tiers are only `flat` and `liquid`. Liquid draws flat wherever it
  cannot load (the web, a build without Flutter GPU, a shader failure)
  and until its shaders are loaded. The first `MorphTheme` loads them and
  holds the app's first frame until they are ready, so the first frame
  is liquid without any precache call.
  `MorphTheme.liquidGlassAvailable` and
  `MorphTheme.liquidGlassUnavailableReason` report the state.
- Shapes, motion, fusion (a menu growing out of its button, bar capsules
  merging) are identical on both tiers; only the shading differs.

## What a glass layer costs, and how to group it

Every separate liquid glass layer is a backdrop filter: the engine reads
what lies under it, filters it and composites it, about 0.3 to 0.75 ms of
raster per layer and frame on a Pixel 6a, whatever the layer's size. So:

- Wrap a row or cluster of glass buttons in `MorphGlassContainer`: their
  resting glass is shaded in one layer. Everything inside the container is
  content above its glass, so put what the glass must show through under
  the container, not inside it. A pressed, lifted or glowing member steps
  out into its own layer for that moment and rejoins at rest.
- `MorphGlassContainer(solidBackdrop: color)` declares that the glass sits
  on one opaque color (a card): it is then shaded as a plain paint, with no
  backdrop read at all. Declare it only where that color really is all the
  glass would show.
- `MorphListSection`, a resting `MorphSearchToolbar`, the navigation bar
  and the tab bar group their own glass; do not wrap them.
- Resting glass in one `BackdropGroup` shares one copy of the screen. Glass
  drawn over other glass (a card of buttons over a bar) needs a
  `BackdropGroup` of its own to show that glass through it.

## What breaks glass

- An `Opacity`, `ClipRRect`/`ClipPath`, `ImageFiltered`, `ShaderMask` or
  `BackdropFilter` between a glass control and the content it should show:
  the glass reads the layer that wrapper creates instead of the page. Put
  such wrappers above the whole control or below its content.
- Painting a blur yourself behind a morph control: the control already
  frosts what lies under it; a second blur doubles the cost and the look.
- Fading glass with `FadeTransition` inside a container: fade the whole
  container, or let the control's own appearance animate.

## Flat tier

Flat draws the same outlines with solid fills from the appearances (no
backdrop sampling), so it is the right default for low-end devices and a
fine user choice. Check both tiers when designing: a tint that reads on
glass may need its own appearance color on flat.
