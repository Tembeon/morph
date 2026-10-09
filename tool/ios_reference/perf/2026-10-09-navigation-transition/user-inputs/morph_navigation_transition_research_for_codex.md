# Morph: navigation, glass-group morphing, foreground blur — research & Codex brief

> **Companion document** to `morph_gpu_liquid_glass_research.md` (do not replace it).  
> **Date:** 2026-10-08. **Target:** Flutter 3.47.2, Impeller Vulkan (Pixel 6a), Metal; a distributable Flutter package, not a one-off application.  
> **Focus:** navigation transitions, persistent toolbar chrome, grouping/merging/splitting glass, text/icon transitions, reusable backdrops, geometry optimization, correctness and frame pacing.  
> **Audience:** Codex working **inside the `morph` repository**. This document is a research plan and a reference index, **not proof that the project already implements the proposals**.

---

## 0. How Codex should use this document

1. Read the *existing* `morph_gpu_liquid_glass_research.md` for general GPU/background/blur research. **Do not repeat that research.**
2. Inspect actual `morph` source code, tests, examples, the current experiment harness, and repository docs. Do **not** assume the class names in this document already exist.
3. Reconstruct the current rendering/animation graph with **actual file:line references**. Check where the package owns scene state, matte, background, glass optical material, foreground text, and Navigator integration.
4. Trace the real sequence `route transition -> layout -> layer tree -> backdrop capture -> blur -> matte -> refraction -> foreground -> output`, identifying work done on UI/raster/GPU threads.
5. Treat external repositories as **study material**; respect licences and do not copy private-API-dependent production implementations. Prefer ideas that work through supported public Flutter APIs.
6. Clearly separate **observed**, **source-confirmed**, **inferred**, **hypothesis**, and **needs benchmark**. An upstream README author's statement is *not* evidence of performance on Pixel 6a.
7. Default output is **audit + experiment proposals + isolated proof-of-concept**. Do not replace production architecture, API, or the baseline renderer without benchmarks and explicit project-level approval.
8. If an exact external code link has moved, search within the cited repository and record the actual current path/commit. Prefer pinning SHA before quoting or copying details into code review.

### Non-goals

- Reimplement the entire Apple glass optics pipeline.
- Replace the effective grouped Impeller Gaussian just because another blur exists.
- Build a new full Vulkan/Metal renderer or fork Flutter Engine before isolating a demonstrated blocker.
- Make the public package depend on private `CAFilter`, QuartzCore internals, or undocumented system APIs.
- Assume that overlapping BackdropFilters with one `BackdropKey` are safe, or that a shared backdrop is automatically cached across frames.

---

## 1. Local experimental facts — user/Codex-reported, not independently reproduced

These are **observations in the project's conversation**, not new benchmarks carried out for this document. Preserve exact harness conditions when quoting them.

### Previously reported Pixel experiments

- 16 lenses on **unchanged** backdrop: separate glass layers with shared `BackdropKey`: **13.1 ms GPU/frame**.
- The same test with **one shared layer**: **5.5 ms GPU/frame**.
- Same shared layer with a **reused precomputed built-in blur**: **2.9 ms GPU/frame**, picture difference reported `<= 1/255` for inspected frames.
- Shared `tent` blur: roughly **1.41 ms for 1** and **1.51 ms for 16 regions** *with equal total area*. This is encouraging for amortization, **not** a claim of constant cost when area/overlap grows.
- Experimental producer 5 passes -> 3: CPU producer recording **6.2 -> 4.8 ms**, UI p95 **11.35 -> 10 ms**, missed-present counts in two runs **9 -> 0**, **5 -> 2**; GPU cost grew slightly, and grouped stock Gaussian reportedly retained better pacing.
- Pixel/Impeller Vulkan multi-render-pass command-buffer experiment hit a reproducible issue; Flutter GPU pass-lifecycle and Vulkan load/store bugs have relevant upstream reports [F8, F9].
- 20 tests were reportedly passing, experiments were **not** enabled in production; verify current status in repository.

### Consequences

1. Preserve **grouped stock Gaussian** as the present baseline.
2. Look for reducing **route-level duplication, geometry recomputation, content-filtering work, full-screen capture, invalidation, and layout work**.
3. Keep GPU time, UI p95, and missed presents distinct; do not attribute a win on one metric to another.
4. Cache the blurred backdrop separately from the moving/merging optics **only if the actual backdrop content and dependent sampling area allow it**.
5. Maintain visual and behavioral correctness under *live route transition*, not just a static wallpaper.

---

## 2. The target use case, precisely

A toolbar floats above a Flutter Navigator. Pushing/popping routes changes toolbar items, labels, group shapes and nearby content. Some buttons persist, some disappear, some move together, some capsules **merge/split** with liquid bridges, and text/icons **blur/fade** during handoff. Underlying page content scrolls/slides/crossfades; the shared backdrop may therefore change every frame even if the toolbar's location stays fixed.

### Distinguish three types of text blur

- **B1 / BACKDROP TEXT:** route text rendered *behind glass* and sampled by its background. This belongs in shared background blur/refraction and must follow page motion.
- **B2 / FOREGROUND GLYPHS:** labels/icons **inside controls** that blur/fade during a transition. This is local foreground filtering, *not another backdrop capture*.
- **B3 / TRANSIENT OCCLUSION:** old and new route/toolbars may temporarily overlap, or one glass may sample another. This is a compositing/handoff correctness issue, not solvable solely with `ImageFiltered`.

**Codex must identify which blur is used in the actual code, and benchmark these separately.** In particular, do not rasterize the whole toolbar because one label morphs.

### Required interaction cases

- A -> B normal push; B -> A pop.
- Interactive iOS back swipe, including partial progress, pause, reverse, and cancellation.
- Push immediately followed by push/pop; retarget animation with nonzero velocity.
- One persistent element with stable ID; unmatched item; multiple new items; item removed.
- Two capsules become one, then split; groups merge while backdrop is also moving.
- Overlapping glass; navigation shell above sheet/dialog; nested Navigators; Hero transition.
- Dynamic titles, localization, RTL, scaling/accessibility font sizes, theme/vibrancy changes, Reduce Motion.
- Static backdrop, scrolling content, animated route, and animated glass independent of each other.

---

## 3. Candidate architecture: avoid recomputing the entire toolbar

This is a **proposed separation of responsibilities**. Adapt to existing `morph` concepts; do not introduce parallel systems if existing infrastructure already does the same thing.

```
Navigator/Router                    Persistent glass navigation chrome
   |                                           |
   | route progress + configuration            | stable ownership above route content
   v                                           v
RouteTransitionCoordinator <-------- Toolbar item descriptors / stable IDs
   |
   +-- matching / topology / spring state / interruption
   |
   +-- backdrop dependency and revisions ------- SharedBackdropProvider
   |                                               | source capture + cache
   |                                               | grouped stock Gaussian baseline
   |                                               + no unsupported inter-frame reuse
   |
   +-- group geometry state --------------------- Geometry/Merge Renderer
   |                                               | matte / SDF / local union
   |                                               | dirty regions / cached static geometry
   |
   +-- foreground state ------------------------- ContentTransitionRenderer
   |                                               | original / target glyphs
   |                                               | blur, fade, vibrancy / semantics
   v                                               v
                         final glass material compositor
```

### Invariants

- **One visual owner** of a persistent toolbar capsule during a route transition. Do not render two visible competing glass samples during handoff.
- Toolbar items may be represented as **immutable descriptors** on each route while a stable shell owns their rendered chrome. Do not force pages to retain both live glass subtrees.
- `Glass item identity`, `glass group membership`, and `content identity` are **distinct**. An unchanged back button may keep its material while its neighbors split or labels change.
- `Backdrop identity`, `backdrop processed texture`, `geometry matte`, `foreground filtered content`, and `material shader` have **independent invalidation policies**.
- **Offscreen semantics:** a cached image may be ready for optics but accessibility and hit testing must still track the active route and controls.
- Keep hit regions/layout deterministic; visual extra extents for bridges/glow must not inadvertently expand gesture targets.

### Possible transition state (illustrative only)

```text
TransitionSnapshot {
  fromRoute, toRoute, progress, velocity, direction, isInteractive,
  fromItems[], toItems[], matchedIds[],
  fromGroups[], toGroups[], activeConnectedComponents[],
  backgroundRevision, backdropCoverage,
  geometryRevision, foregroundRevision
}
```

Represent reversible progress without assuming monotonic `[0,1]`. On cancellation, old glyphs and hit targets must become authoritative again without resource leaks or ghost images.

---

## 4. Research threads and hypotheses

Each thread contains a **candidate** plus its failure modes. A source showing an effect does not establish faster GPU execution in Flutter.

### H1. Persistent chrome above Navigator, declared as route data

**Idea:** one shell owns glass and transition animation; routes provide descriptions of leading/trailing action clusters and title states. Item identity allows geometry/content handoff without a second toolbar renderer.

- Primary study: `sdegenaar/liquid_glass_widgets/docs/GLASS_NAVIGATION_TRANSITION.md` [R1]; `GlassNavigationShell`, `GlassBarItem`, pinned chrome, route matching, interactive progress.
- Apple comparison: glass transitions by ID and spacing [A1, A2]. Flutter's Hero moves a widget to an overlay while two routes animate [F2] — useful inspiration, but a permanently pinned shell may be simpler.
- Inspect *when* source route and destination route both paint, and whether the shell duplicates background sampling during route switches.
- Risks: nested navigator ownership, UI state, route title sliver/large titles, handoff ordering, Hero z-order, gesture interruptions.
- **Acceptance:** one visual shell; zero flash/duplicate controls on every frame; correct tap handling during partial progress; no new redundant captures.

### H2. Separate backdrop sharing, union topology, and local optical material

**Idea:** 16 lenses can share a backdrop while only 2–3 nearby lenses participate in an active merge. Restrict expensive union calculations to interacting components.

- Apple `GlassEffectContainer(spacing:)` combines nearby glass surfaces and morphs them [A1]. UIKit shows add-at-one-point-then-split [A3].
- Reconstruction author documents `splitGroups(rects, spacing)` and connected groups [R4] — author hypothesis/model, **not Apple's source**.
- Evaluate CPU spatial grouping (sweep line/grid) vs calculating all `N` SDF fields for every matte pixel. For small N, CPU overhead might beat shader savings; **measure**.
- Account for *nearby but visually non-overlapping* bridges and shadows; expanded bounds for refraction/blur.
- Add topology hysteresis only if actual oscillation/chattering is observed: `d_join < d_split`; test deterministic reverse motion and no delayed detach.
- **Acceptance:** off-group elements do not affect current matte cost; joined mask continuous, no topology flicker.

### H3. Metaball (blur alpha -> threshold) versus existing matte/SDF

**Idea:** maintain a low-resolution mask with unioned shapes, blur alpha and threshold it to create a liquid bridge, then use the resulting mask in the existing material shader.

- Source: James Randolph, *Backporting Liquid Glass* [P1], source implementation [R3]. Uses private `CAFilter` for iOS contest; **do not import this API** in production Flutter.
- Alternate sources: [R2] morph engine and [R5] smooth-min/SDF shape deformation.
- Compare **same target look**: current matte union, analytic smooth-min, and blurred-mask threshold; include edge AA, bridging width, different radii, intersecting shapes.
- Mask blur is **not** backdrop blur. Do not confuse them in profiler.
- Risks: extra offscreen passes, changing bridge width when resizing, blurry/aliased borders, alpha premultiplication, color loss after threshold, dirty-bounds padding.
- **Acceptance:** subjective match, crisp edges, no popping at join/split, p95/GPU cost less than or comparable to current geometry path.

### H4. Foreground text/icon morph as an independent transition

**Idea:** outgoing/incoming text and icons should not be re-rendered into the backdrop or merged alpha matte by default. Their local blur/fade/role-color changes happen above one shared glass material.

Study three controlled variants:

1. **F0 (baseline):** `ImageFiltered` around only the changing text/icon; `ImageFiltered.enabled=false` when no filter is needed [F3].
2. **F1:** cached `ui.Image` or alpha mask for a static glyph, with prefiltered soft/sharp (possibly 3–4) variants, crossfaded during transition. Build cache *per glyph/config*, not entire toolbar.
3. **F2:** batched/local content filter on a common small foreground surface, measuring if batching is cheaper than several independent `ImageFiltered` layers.

Optional **F3:** store one-channel alpha and apply contrast/vibrancy tint during composition; avoid caching per-theme colored glyph if viable. Reconstruction repo documents vibrancy roles [R4] but this is **not proof** of Apple's exact iOS formula.

**Correctness hazards:** glyph advances/layout vs image scaling; non-RGB/subpixel AA; premultiplied alpha halos; language changes; bold/variable fonts; font scale; accessibility; content clipping under capsule shrink; optical edge softness. Avoid caching dynamic input/caret/selection without a lifecycle policy.

For blurred crossfade, `mix(sharp, blurred, t)` is **not mathematically equal** to Gaussian blur at interpolated sigma. Compare temporal quality, not a single endpoint screenshot. Never imply alpha-mask-only coloring reproduces multicolored emoji/icons.

### H5. Transition physics without layout/rebuild storms

**Idea:** compute spring state on UI/animation side; minimize unnecessary layout, text rasterization, and matte updates. The result may be multiple scalar uniforms / transforms per frame.

- Sources: James Randolph's multiple springs, velocity-coupled jiggle [P1]; `anuero/LiquidGlass` elasticity, trailing droplet and glyph transform without relayout [R5]; `sdegenaar` liquid morph physics [R2].
- Try two stages: (1) stable route layout and interpolated optical geometry; (2) measured fallback to layout when content size truly changes.
- Independent springs can generate physically inconsistent states if out of sync; define ownership of position, shape, tint, and glyph opacity.
- Evaluate fixed-timestep vs wall-clock animation for low FPS; avoid introducing time drift or broken interactive gesture reversals.
- **Acceptance:** no snap at handoff, no loss of progress during interruption, reduced build/layout counts, acceptable sharp glyph appearance.

### H6. Snapshot and blurred route composition

**Idea:** cached blurred source for route A/B can sometimes be interpolated during route transitions. For linear Gaussian blur and a *pure crossfade with fixed images*:

`G((1-t) A + t B) = (1-t) G(A) + t G(B)`.

**This does NOT mean arbitrary Navigator transitions are equivalent.** Sliding, occlusion, alpha compositing in nonlinear color spaces, input clipping, depth, scroll and changing content invalidate the naïve simplification. Special-case only after controlled proof.

- For a fixed/statically shifted image, reuse/translate the cached blur while updating only exposed/dirty regions, *if* correct halo and sampling coordinates can be maintained.
- Use an explicit background revision and dependency region; do not trust widget `build` count as proxy for scene pixel changes.
- **Acceptance:** correct result under predictable cases, no lag/ghosting during scroll, performance gain **after including cost of backdrop capture**.

### H7. Reduce layer/pass explosion for foreground composition

- Inventory `ImageFiltered`, `Opacity`, `Clip*`, `saveLayer`, `RepaintBoundary`, render targets, and `BackdropFilter` in the route toolbar.
- Distinguish per-glyph `ImageFiltered` cost from parent `BackdropFilter` cost. Flutter docs explicitly prefer `ImageFiltered` for child filtering [F3, F4].
- Check `ClipRect` scopes around local text blur; blur needs its own halo but should not target full-screen area.
- Measure passes when `sigma=0`: prefer `enabled:false` where the filter genuinely should be disabled, but avoid layer-tree churn during active animation unless measured [F3].
- **Acceptance:** fewer/cheaper passes and stable pacing; do not trade correctness for opacity shortcuts.

### H8. Reuse stock Gaussian while decoupling new transition work

- Current grouped Gaussian seems strongest on Pixel under active updates. Treat as baseline until new end-to-end tests refute it.
- Shared `BackdropKey` **does not imply correct overlapping material**; Flutter warns about same-key overlapping backdrop filters [F5].
- In-frame snapshot sharing and across-frame caching are different. Verify `BackdropData`, `shared_filter_snapshot` and replay teardown in tagged Impeller source [F6].
- Different filters/bounds may prevent combined *filter passes* even if source backdrop capture is shared [F5].
- Geometry movement can reuse blur only where common captured coverage is sufficient and actual source pixels have not changed.
- **Acceptance:** isolate route/text/geometry costs without accidentally recomputing the background.

### H9. Handle Vulkan/Flutter GPU limitations independently

- Avoid grouping several dependent recording passes in one Flutter GPU command buffer without confirming lifecycle support for the project version [F8].
- Vulkan repeated `LoadAction.clear` / `load` reuse can be affected by a reported Impeller problem [F9].
- Merging **draw calls within one pass** is different from merging **dependent passes** that need different attachments.
- Keep GPU resource lifetime and in-flight frames safe; CPU `submit` is not necessarily GPU completion.
- Don't attribute all route transition glitches to shaders until baseline validation and frame capture.

---

## 5. Experiment matrix — the minimum useful end-to-end benchmark

### Test fixtures (fixed, reproducible)

- **S1:** static background + static toolbar (minimum cost).
- **S2:** static background + moving/merging toolbar (isolates optical/geometry/foreground).
- **S3:** scrolling text under fixed toolbar (tests backdrop text B1 / damage).
- **S4:** push/pop between two routes: one stationary shared button, a changed title, changing trailing groups; route background slide.
- **S5:** interactive back swipe 0 -> 0.6 -> 0.2 -> 1; another run cancels to 0; observe cache/handoff.
- **S6:** two groups merge/split while *foreground glyphs* locally blur/fade.
- **S7:** 1, 2, 4, 8, 16 items, separately **(a) equal total area** and **(b) equal area per item**.
- **S8:** overlapping and far-apart items with enlarged source/dependency rectangles.
- **S9:** RTL, long translated labels, 200% text scale, font weights, emoji and tinted icons.
- **S10:** mixed page+toolbar animation with modal/overlay/nested Navigator or Hero.

### Baseline versus candidates

| ID | Foreground | Morph geometry | Backdrop | Purpose |
|----|------------|----------------|----------|---------|
| V0 | Existing code | Existing code | Grouped stock Gaussian | **Keep untouched as control** |
| V1 | Existing code | Existing code | Same as V0 | Persistent navigation shell only |
| V2 | Local ImageFiltered | Existing code | Same as V0 | Foreground separation |
| V3 | Cached glyph variants | Existing code | Same as V0 | No per-frame glyph blur |
| V4 | Same as V2 or V3 | Active-component SDF union | Same as V0 | Local geometry update |
| V5 | Same as V2 or V3 | Blurred-mask metaballs | Same as V0 | Alternative matte path |
| V6 | Best stable variant | Best stable variant | Explicit dependency cache | Inter-frame reuse test |

Avoid simultaneously changing V1–V6. Every experiment must have an isolated toggle or branch and an identical visual reference.

### Instrumentation

**Capture:** Flutter UI/raster durations (median, p95, p99), GPU elapsed time (properly distinguished from GPU cycles), missed present count / frame pacing, CPU producer recording, backdrop captures, texture uploads/allocations, render passes, matte regen count/pixels, filtered glyph count/pixels, group topology updates, cache hits/misses, peak memory, warm-up, thermal/frequency state. Use RenderDoc/AGI/Perfetto as supported.

**Visual:** compare reference captures at t = `0, .1, .25, .5, .75, .9, 1`, both forward and reverse; pixel-difference maximum/mean where geometrically alignable, optional SSIM/LPIPS, plus text readability and edge stability. Test moving backgrounds, contrast text, small fonts, and 60/120 Hz where supported.

**Protocol:** physical Pixel 6a Impeller Vulkan, consistent profile/release mode, same screen pixels/brightness/thermal context and seeds, shader prewarm, alternate A/B order, repeated runs with distribution not only averages. Run mobile-specific baseline before any shader portability claim.

**Recorded output per run:**

```yaml
experiment_id: V2_S5_reverse_cancel
commit: "<sha>"
flutter_version: 3.47.2
backend: Impeller-Vulkan
device: Pixel-6a
scene: S5
foreground_variant: local_image_filtered
morph_variant: current_matte
backdrop_variant: grouped_gaussian
runs: 5
ui_p95_ms: null
raster_p95_ms: null
gpu_p95_ms: null
missed_presents: null
backdrop_captures_per_frame: null
geometry_pixels_updated: null
foreground_pixels_filtered: null
texture_peak_mb: null
visual_diff_max_255: null
notes: "<measured conditions / observed artifacts>"
```

Never fill absent metrics by estimation. A successful test run does not prove no performance regression.

---

## 6. Experiments to prioritize (suggested order)

1. **Audit actual route/toolbar ownership and current layer tree.** Mark duplicated controls during transition and draw boundaries; instrument capture counts. Output diagram + source lines.
2. **Persistent toolbar shell proof-of-concept** (one representative Navigator flow, no optical algorithm changes). Test push/pop + gesture reversal + accessibility/hit targets. Measure V0 vs V1.
3. **Foreground isolation:** compare per-label `ImageFiltered`, small shared filtered surface, and 2–4 cached glyph levels with original glass unchanged (V2/V3). Check text correctness and when filter is disabled.
4. **Geometry topology audit:** count active shapes / actual matte pixels; try local connected-components and/or cropped dynamic matte before alternative algorithm (V4).
5. **Metaball comparative lab:** blurred-alpha/threshold vs existing SDF at identical animated geometry (V5). Cancel if extra passes or quality regressions outweigh savings.
6. **Only then** independent backdrop revision + dependency region. Keep live capture fallback for uncooperative/unknown route content (V6).
7. Make **no production default changes** until a candidate wins end-to-end Navigation pacing on real hardware, not just a static lens microbenchmark.

### Stop / rollback criteria

- Introduces duplicate glass sampling, stale background, self-reflection, or unexpected z-order.
- Loses control text clarity, assistive semantics, hit testing, or transition reversibility.
- Beats a microbenchmark but worsens GPU p95 or end-to-end frame pacing relative to V0.
- Creates unbounded cache growth, unusable public API, unsupported private API dependency, or fragile Vulkan pass lifecycle.
- Requires repeated full-screen snapshots for a small foreground text effect.

---

## 7. Source library and code-reading map

All URLs below were checked as existing resources on **2026-10-08**. External repositories may change; pin SHAs when Codex starts code analysis. Each entry explains **what to extract, what it does not prove**.

### A. Apple — official API behavior (authoritative on API, not internals)

**[A1] Apple `GlassEffectContainer` — spacing and combined shapes**  
https://developer.apple.com/documentation/swiftui/glasseffectcontainer  
Read: effects drawn together; proximity/spacing controls when shapes blend. **Not** a specification of GPU passes, CPU graph algorithm, or source code of QuartzCore.

**[A2] Apple: Applying Liquid Glass to custom views — IDs / `matchedGeometry` / `materialize`**  
https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views  
Read: `glassEffectID`, `glassEffectUnion`, transition identity; `matchedGeometry` for effects within spacing; `materialize` for far-away adds/removes. Observe the choreography on device.

**[A3] Apple WWDC25: Build a UIKit app with the new design (23:52–24:34)**  
https://developer.apple.com/videos/play/wwdc2025/284/  
Read: `UIGlassContainerEffect`, `spacing`, overlapping frames; to split, place new views in same position *without animation*, then animate outward. Also note vibrancy and content labels at ~21:49.

**[A4] Apple WWDC25: AppKit design changes**  
https://developer.apple.com/videos/play/wwdc2025/310/  
Read: glass container shared background sampling, consistent grouping. **Do not** conclude filter results are cached across whole frames.

### B. Articles / comparative reverse-engineering

**[P1] James Randolph: “Backporting Liquid Glass” (2026-01-06)**  
https://jamesrandolph.me/tg-contest-2025  
Read: why frame-by-frame hierarchy snapshots + Metal were rejected; alpha blur + threshold metaballs; variable blur of selected edges; separating filtered glyphs and sharp overlay; multiple interruptible spring simulations. **Private CAFilter is an observation, not a permissible implementation for `morph`.**

**[P2] The QuartzCore reconstruction author's description (medfa12)**  
https://github.com/medfa12/liquid-glass-react  
Read: group splitting, vibrancy roles, concentric radii, shader variants, source backdrop ownership. Treat any statements about Apple's internals as an **independent reconstruction**, not verified Apple implementation.

### C. Repository references — study implementation, not blindly copy

**[R1] `sdegenaar/liquid_glass_widgets` — persistent pinned navigation**  
Repository: https://github.com/sdegenaar/liquid_glass_widgets  
Direct deep dive: https://github.com/sdegenaar/liquid_glass_widgets/blob/main/docs/GLASS_NAVIGATION_TRANSITION.md  
Study: `GlassNavigationShell`, pinned bar configuration, item IDs, fixed/shared/separate backgrounds, capsule budding/splitting, UI->Overlay ownership, transition handoff and interactive gesture. Use the repo tree to find actual class implementations; documentation is not performance proof.

**[R2] `sdegenaar/liquid_glass_widgets` — independent morph engine**  
https://github.com/sdegenaar/liquid_glass_widgets/blob/main/docs/LIQUID_MORPH_ENGINE.md  
Study: `GlassMorphController`, `LiquidMorphPhysics`, `LiquidMorphState`, spring/bridge phases, inactive trigger vs moving blob. Ask whether centralized physics avoids layout and GPU work for unaffected groups.

**[R3] `james01/Telegram-iOS` — source linked from Randolph's article**  
https://github.com/james01/Telegram-iOS  
Study: contest modifications / filter pipelines / animation choreography. This is a **large fork**: find relevant change history and actual lines rather than treating entire Telegram tree as a standalone library. Identify private framework dependencies before drawing portability conclusions.

**[R4] `medfa12/liquid-glass-react` — QuartzCore-inspired WebGL model**  
https://github.com/medfa12/liquid-glass-react  
Also: https://github.com/medfa12/liquid-glass-react-native  
Study: `splitGroups(rects, spacing)`, role-based vibrancy, adaptive fill, backdrop ownership, mip selection, shader variants. *Author's reconstruction; not a first-party source of Apple's proprietary code.* The web README itself points out that a live DOM backdrop cannot be directly read from WebGL; comparable constraints matter in Flutter.

**[R5] `anuero/LiquidGlass` — Metal SDF merging and elastic deformation**  
https://github.com/anuero/LiquidGlass  
Study: smooth-min fields, trailing spring droplet, elastic pull point, how the glyph follows deforming geometry via transform without constantly changing Auto Layout; background shared per screen. Unlike package API docs, inspect actual shader/host code and identify cost of capture.

**[R6] `BarredEwe/LiquidGlass` — explicit background update modes**  
https://github.com/BarredEwe/LiquidGlass  
Study: `.continuous`, `.once`, `.manual`, coordination between source capture and Metal output, lazy rendering. The README describes hierarchy capture / texture creation: do not assume “automatic update” implies zero-cost capture, accurate dirty regions, or Flutter compatibility.

**[R7] `quentinfasquel/CAFilterBuiltins` — CAFilter vocabulary for reading P1**  
https://github.com/quentinfasquel/CAFilterBuiltins/blob/main/Sources/CAFilterBuiltins/CAFilterBuiltins.swift  
Use strictly as research context for identifying private filters; **do not ship private CAFilter usage**.

### D. Flutter — official runtime behavior and tagged source

**[F1] Flutter Performance / frame profiling**  
https://docs.flutter.dev/tools/devtools/performance  
Measure UI/raster separately; supplement with actual GPU instrumentation.

**[F2] Flutter Hero transition lifecycle**  
https://docs.flutter.dev/ui/animations/hero-animations  
https://api.flutter.dev/flutter/widgets/Hero/flightShuttleBuilder.html  
Hero moves one representation to the Overlay, which illustrates route handoff; not necessarily the best persistent toolbar architecture.

**[F3] Flutter `ImageFiltered`**  
https://api.flutter.dev/flutter/widgets/ImageFiltered-class.html  
Child filtering (foreground), `enabled:false` to skip inactive filtering, differing from `BackdropFilter` (background).

**[F4] Flutter `BackdropFilter`**  
https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html  
Read: `BackdropGroup`/`BackdropKey`, performance, overlapping backdrop key caveat, `ImageFiltered` recommendation when only one child needs filtering.

**[F5] Flutter framework source docs about identical grouped filters**  
https://github.com/flutter/flutter/blob/3.47.2/packages/flutter/lib/src/widgets/basic.dart  
Verify: grouping can share captured backdrop; identical properties required to collapse filter passes; bounded blur can block full deduplication; same-key overlap may be visually wrong.

**[F6] Impeller Canvas tagged 3.47.2**  
https://github.com/flutter/flutter/blob/3.47.2/engine/src/flutter/impeller/display_list/canvas.cc  
Read `backdrop_data`, `shared_filter_snapshot`, and replay teardown (`EndReplay`); confirm exactly what is shared per replay and which resources survive.

**[F7] GaussianBlurFilterContents tagged 3.47.2**  
https://github.com/flutter/flutter/blob/3.47.2/engine/src/flutter/impeller/entity/contents/filters/gaussian_blur_filter_contents.cc  
Baseline internal downsampling, passes and memory assumptions; not a mandate to replace Gaussian.

**[F8] Flutter GPU pass lifecycle issue**  
https://github.com/flutter/flutter/issues/193867  
One recording pass / command buffer limitation and proposal to end on next command; verify resolved version before applying to a future Flutter SDK.

**[F9] Impeller Vulkan load/store issue**  
https://github.com/flutter/flutter/issues/193804  
Reported `LoadAction.load` texture reuse problem; isolate separately from morphing or backdrop correctness.

**[F10] Flutter GPU command-buffer source tagged 3.47.2**  
https://github.com/flutter/flutter/blob/3.47.2/engine/src/flutter/lib/gpu/command_buffer.cc  
Use to audit begin/end/submit ordering in custom producer; don't assume GPU completion after CPU submit.

### E. Related technical principles

- A compositor's damage-tracking model can help reason about invalidation and dependencies, but arbitrary Flutter widgets do not expose perfect pixel-level dirty regions to a package. Explicit source revisions are a safer first experiment.
- A separable Gaussian convolution is linear in a fixed color space, but a *composited route transition* often is not the same operation because occlusions, clipping, moving viewports, premultiplied alpha and sampling spaces matter.
- Analytical smooth-min and blurred-alpha threshold are **alternative implementations of geometry merging**; neither eliminates the need to evaluate refraction and compositing for visible pixels.
- Reading/manually reverse-engineering private framework internals is not the same as using unsupported APIs in distributable apps; keep the package public-API-only.

---

## 8. Questions Codex should explicitly answer in the audit

1. When pushing A -> B, **how many toolbar render subtrees** are mounted, painted and composited per frame? Show exact evidence.
2. Does a toolbar morph trigger **another backdrop capture**, Gaussian filter or `ImageFilter.shader` evaluation? Which step, why, and how often?
3. Is text blur B1 or B2 in each path? Which widget or render layer applies it, and what is the actual offscreen allocation size?
4. Does the group merge recompute **all matte pixels** or only active component bounds? Is updating the matte a Flutter GPU pass or Flutter Canvas child-layer operation?
5. Can unchanged background and changing glass safely reuse blur **without reading stale pixels or sampling outside the source coverage**?
6. Are matched items stable by ID when traversing routes, or keyed by positional order? What happens on RTL and dynamic content?
7. During interactive pop cancellation, which object owns transition position/velocity and which route remains authoritative?
8. Are overlap/self-sampling and hit-testing z-order guaranteed under sheets, nested navigators, and Hero overlays?
9. What is the actual device-GPU cost of foreground blur + content handoff? Not just a `dart:ui` benchmark.
10. Which feasible improvement has the **best measured end-to-end payoff** vs grouped Gaussian, with the lowest compatibility and maintenance risk?

---

## 9. Required Codex deliverables

Do this in stages; **do not invent metrics or claim sources were read without opening them**.

### Phase A — repository audit (no production changes)

- `docs/research/navigation-transition-audit.md`: real `morph` call graph, route/toolbar ownership, layer/pass diagram, file:line evidence, assumptions, bottleneck ranking.
- `docs/research/navigation-transition-reference-notes.md`: each relevant [A/P/R/F] source studied, actual source files and pinned SHAs, transferable ideas, incompatibilities/licence notes.
- Proposed measurable success criteria and experiment toggles, including visual golden strategy.

### Phase B — isolated proof-of-concept (behind debug/experimental toggles)

- A navigation demo with persistent toolbar + matched IDs + reversals.
- Variants V0–V3 first; only proceed to V4–V6 if earlier results warrant it.
- Add counters around backdrop capture, matte regeneration and foreground filters; avoid invasive instrumentation changing production timing.
- Keep baseline renderer available in all environments, especially Vulkan on older devices.

### Phase C — test report and decision

- Reproducible A/B measurements on Pixel 6a (or mark physical-device data as **not available**, never invent it).
- Screenshots/frames of transition progress with visual differences; tests for interrupted pop and overlap.
- Clear **keep / reject / investigate further** for each hypothesis, with engineering cost, fallback, API compatibility, GPU and UI budget.
- No production activation unless explicit approval and demonstrated benefit.

**Suggested first task for Codex:** "Read this document and the earlier GPU research, inspect the current `morph` code and experiment harness, then complete Phase A only. Focus on the existing toolbar, transition ownership, foreground text blur, and geometry work; cite actual file:line references and verify the relevant reference repositories before proposing changes."

---

## 10. Research log template

Append new findings; do not rewrite measured history.

```md
### Finding NAV-XXX — Short title
- Date / tested commit / Flutter version:
- Classification: observed | source-confirmed | inference | hypothesis
- Question:
- Evidence: local file:line, upstream URL/commit, screenshot/capture ID
- Test scenario and baseline:
- Measurements (UI/raster/GPU, variability, memory):
- Visual and accessibility results:
- Risk and platform exceptions:
- Decision: keep | reject | retry
- Next falsification test:
```

---

**Bottom line:** Optimize *route-level ownership and handoff* before replacing an already efficient blur algorithm. Share backdrop resources **without forcing all glass into one expensive union**, and separate local foreground glyph effects from global background optics. Measure actual navigation frame pacing, not just isolated lenses.
