# Round 2: independent Pixel 6a bottleneck review

2026-10-06. Read-only review; this report is the only file written. Code reviewed at HEAD `747d6b87e00394565da435d1909aad8fb2a296be`, branch `wip/measured-liquid-glass`. Concurrent edits to the integration tests and a new `2026-10-06-pixel6a-glyph-base` directory were present. The latter contained a device/launch record, not completed timing results when inspected. Glyph-atlas work belongs to the concurrent agent; findings below describe the recorded baseline, not that agent's eventual result.

**The next large opportunity is reducing the number of glass effects the engine must encode, while preserving their backdrop dependencies. Menu UI cost also remains independently too high.** The shader batch was useful, but it does not solve either problem. A Pixel menu still has raster p95 19.5–20.5 ms, UI p95 14.8–15.8 ms and raster p99 about 30.4 ms. Controls, tab bars and sheets meet the 16.67 ms budget at p95 with insufficient tail margin. Home scroll and segmented controls are substantially healthier.

There is meaningful identical-output work left. There is also a bigger architecture opportunity with a fidelity qualification: extend the proven container into bounded, automatically assembled batches inside package-owned composition stages. An arbitrary-tree global collector is unsafe. The current container itself is not generally pixel-identical at fractional positions, so broadening it must solve that problem rather than inherit an unearned IDENTICAL label.

## Evidence and limits

I reviewed CLAUDE.md's seam, channels, backdrop groups, container and performance passport; the renderer specification including its performance sections, Apple check, shader harness and final batch; the ten existing audit Markdown files; the 2026-10-05/06 result directories; and the current glass renderer, glass widgets, menu/bar/search paths, skin and liquid tracer. Numerical conclusions below come from committed results and source inspection. No new device benchmark was run.

Primary result sets:

| Evidence | Use in this review |
|---|---|
| `tool/ios_reference/perf/2026-10-06-shader-audit/e2e/` | Latest complete end-to-end scene runs, two before/after pairs, five repeats per launch |
| `tool/ios_reference/perf/2026-10-06-shader-audit/` | Same-binary shader parity and GPU work; final Vulkan batch includes the F14 revert |
| `tool/ios_reference/perf/2026-10-05-pixel6a-cpu-base/`, `…-cpu-menu/` | Controlled menu UI improvement and useful flat-tier comparison |
| `tool/ios_reference/perf/2026-10-05-pixel6a-attrib/` | Older mixed tab/menu engine slice attribution |
| `tool/ios_reference/perf/2026-10-05-pixel6a-gpu-t3/trace-menu-slices.txt` | Later menu trace after field-upload optimization |
| `tool/ios_reference/perf/2026-10-05-pixel6a-container-final/` | Repeated, interleaved density/container measurements |
| Pixel retain, GPU/upload, first-use and phase runs on 2026-10-05 | Attribution and completed-work checks |
| `2026-10-05-apple-verify/` and Apple container/first-use runs | Regression constraints and platform differences |

The latest end-to-end shader experiment ran `9f330b5`, comparing frozen runtime shaders against the candidate in that checkout. HEAD subsequently reverted F14 (`c60deca`) and added verification/documentation. The final shader GPU figures cover that revert, but there is **no complete six-scene end-to-end rerun of exact HEAD in the reviewed completed results**. Therefore the table below is the latest evidence, not a claim that HEAD was freshly measured. The first next measurement must freeze exact source plus any concurrent patch hashes.

Earlier audits correctly proposed several changes that are now implemented. Their speedup estimates are not remaining opportunities. In particular: cached menu face/rows, plain-union fast path, retained container grids, channels, retained glass compositor hooks, field upload batching, real pipeline warm-up, bounded submissions, uniform arena and shadow saveLayer removal already exist. Fake/frosted is not a universally cheaper replacement for liquid. The runtime governor and historical tier names should not be revived from those reports.

## 1. Where the time goes

### Latest Pixel scene timings

Liquid, Pixel 6a, Vulkan/Mali-G78, measured cadence approximately 16.665 ms, semantics disabled. Entries are the two after launches, each reporting the median of five runs. UI means Flutter's reported build duration, which includes the UI pipeline work covered by FrameTiming; it does not measure the entire accessibility pipeline. All times are ms.

| Scene | UI p50 | UI p95 | Raster p50 | Raster p95 | Raster p99 | Frames with UI or raster over budget / active frames |
|---|---:|---:|---:|---:|---:|---:|
| Home scroll | 2.82 / 2.88 | 5.74 / 5.60 | 8.15 / 8.49 | 11.46 / 11.51 | 13.86 / 13.04 | 2/403; 2/405 |
| Segmented | 5.12 / 5.03 | 7.63 / 7.42 | 8.30 / 8.73 | 10.71 / 11.40 | 12.31 / 12.93 | 0/435; 0/434 |
| Tab bar | 5.39 / 5.54 | 8.93 / 8.80 | 10.50 / 10.99 | 14.54 / 14.51 | 19.50 / 19.85 | 14/570; 14/557 |
| Controls | 5.01 / 4.77 | 12.44 / 12.20 | 8.94 / 8.91 | 15.18 / 15.02 | 19.15 / 20.44 | 14/400; 13/396 |
| Menu | 6.08 / 6.01 | 15.82 / 14.75 | 10.66 / 10.78 | 19.47 / 20.49 | 30.52 / 30.41 | 29/242; 23/245 |
| Sheet | 2.77 / 2.73 | 6.91 / 6.72 | 10.60 / 10.51 | 15.35 / 14.95 | 19.30 / 21.59 | 8/241; 6/241 |

Files: `…/e2e/pixel6a-shader-e2e-after1/liquid-e2e-after.json` and `…-after2/liquid-e2e-after.json`. The test's over-budget counter (`example/integration_test/glass_audit_test.dart:562`, reviewed baseline) counts **either stage exceeding budget**, not actual missed presentations. `totalSpan` p95 reaches 36.8–40.1 ms in menu, but pipeline span is not the sum of independent stage percentiles or a throughput budget.

The same files' separate first-use windows still contain large interaction outliers despite shader precache: menu worst UI 64.9 / 40.0 ms and raster 34.0 / 39.4 ms; tab bar worst UI 58.6 / 32.6 and raster 46.9 / 36.1 ms. Controls and segmented also have first-use UI spikes. These are whole first-use interaction windows, not proof of pipeline compilation on their first frame. Attribute the actual slow events; the successful first-glass warm-up does not establish first-interaction readiness.

### Attribution supported by traces

The recorded traces support raster encoding/submission as a major bottleneck. They do **not** give a clean current, per-scene division into on-CPU raster time and GPU execution time. A duration slice includes descheduling and driver waits; calling its whole duration CPU execution would overstate certainty.

The older mixed tab/menu trace (`…-attrib/trace-liquid-slices.txt`, 2,761 raster frames) has mean `GPURasterizer::Draw` 9.96 ms. Within it:

| Recorded component | Mean per raster frame | Interpretation |
|---|---:|---|
| `SurfaceFrame::Encode`, inclusive | 7.83 ms | Parent of much of the work below; do not add it again |
| Encode self | 2.80 ms | Uninstrumented encoding work and gaps within this slice |
| Raster `QueueSubmit`, self | 2.71 ms | Submission/driver duration; not necessarily all running CPU |
| `Canvas::saveLayer`, self | 1.74 ms | 10.42 calls/frame; 0.167 ms/call in this workload |
| `CreateGlyphAtlas`, inclusive | 0.88 ms | Includes bitmap/update work |
| `UpdateAtlasBitmap`, self | 0.56 ms | Only 613 events; 2.52 ms per event, hence a tail candidate |
| `LayerTree::Preroll` | 0.15 ms | Relatively small |
| `LayerTree::Paint`, inclusive | 0.27 ms | Relatively small; cached pictures still need engine dispatch |

The later menu trace (`…-gpu-t3/trace-menu-slices.txt`, 1,077 raster frames) still has Draw 9.37 ms, Encode 7.40 ms inclusive / 2.85 ms self, raster QueueSubmit 2.57 ms/frame, saveLayer self 1.55 ms/frame and glyph atlas 0.90 ms/frame inclusive. Its saveLayer mix/count differs, so 0.17 ms is **not a universal per-BackdropFilter coefficient**. Both traces include work outside precisely isolated steady interaction windows. The later trace includes startup and screenshot outliers; neither mean explains menu p95 by itself.

The layer census reports approximately 8.8 BackdropFilters / 8.85 glass layers per menu frame and 10.4 saveLayers versus about 1.1 in flat. Shadows no longer account for a removable saveLayer population (`glass-renderer.md:1015`). This makes layer consolidation attractive, but multiplying 8.8 by 0.17 explains only a small portion of 20 ms, and misses downstream encoding, capture and driver work.

On the UI thread, the later menu trace averages COMPOSITING 2.07 ms and PAINT 1.16 ms per frame. UI QueueSubmit contributes approximately 0.62 ms/frame; field uploads already reduced its calls from 1,236 to 880 over the comparable capture. BUILD/LAYOUT events nest and have different counts; their inclusive durations must not be added as independent totals. New-generation collections remain: 51 collections totaling 142 ms inclusive over about 21 s, 2.79 ms/event. This is evidence to investigate allocation-related tails, not proof that every slow menu frame is GC-bound.

GPU evidence is narrower. The final shader batch reduced synthetic Vulkan GPU cycles/layer by 8.1% on the big sheet, 1.2% on the frosted menu, 2.0% on mixed materials and 4.2% on the lifted lens. The 2.3% control result is within its ±5% noise. End-to-end raster did not improve. Kernel work periods weighted by GPU frequency are useful for paired work comparisons; they are not six-scene GPU completion timestamps. The completion thread's `waitForever` averages are **not GPU execution durations**.

### Scene diagnosis and the measurement still needed

| Scene | UI-thread diagnosis | Raster-thread diagnosis | GPU diagnosis / exact missing measurement |
|---|---|---|---|
| Home | Low UI p95; ordinary scrolling/layout/content dominates the remaining work more plausibly than fusion | Large liquid raster floor even without intensive deformation; static mattes do not eliminate backdrop/filter encoding | Measure rolling-background baseline, grouped body glass and chrome separately. Correlate per-frame GPU completion with raster submission and capture count before attributing the 8.5 ms median to bandwidth |
| Segmented | Moving lens/channel/layout work gives UI p50 about 5 ms; no current percentile failure | Lifted lens requires its own capture over track/content; common engine costs remain | Obtain phase-specific GPU timings: rest, press/lift, drag and settle. A lens shader win cannot remove its optical dependency |
| Tab bar | UI p95 about 8.8 ms; outer wrapper/item placement still rebuilds despite retained inner glass; content capture can repeat | Body plus lifted-lens stages, content display-list replay and possible scale-dependent glyph churn. Older tab/menu trace implicates atlas and submissions | Join current frame IDs to atlas-update slices, scale, number of independent captures and GPU busy/completion. Do this after the concurrent glyph change; do not double-count its gain |
| Controls | UI tails about 12.2 ms; multiple control/motion pipelines and parent/state updates need current CPU samples | Raster p95 about 15 ms, with many small effects whose fixed cost is important. Existing gallery container helps only a small subset | Measure one animated control, all controls, and static controls over a moving background; compare equal-content flat/liquid in the same timed protocol and count actual effects |
| Menu | Fusion is proven important: before the exact optimization it was about 45% of samples in >8 ms frames, both tiers. Current rich-menu CPU samples must be taken again | Worst raster tails; repeated glass effects, encoding/submission, animated text and ordinary menu/overlay content all matter | Record root open/close, submenu push/pop, reversal, drag and settle separately. Tag silhouette work, GC, atlas updates, filter/capture counts, raster running time and GPU completion on the same frames |
| Sheet | UI is relatively comfortable; p95 raster is the concern | Large body blur/refraction plus glass inside the sheet and overlay/route effects; capture dependency must remain | Time big-body blur/filter/resolve passes separately from interior controls. Current synthetic sheet GPU saving does not establish a sheet-scene GPU bottleneck |

The historical `…-cpu-menu` flat menu still has UI p95 11.58 and raster p95 14.61 ms. Liquid has UI p95 14.80 and raster p95 19.31 ms in that experiment. This proves that a material-only fix cannot erase all menu cost. It does **not** justify subtracting unrelated p95 values to assign exactly 4.7 ms to glass.

The exact attribution experiment should collect Perfetto scheduling (`sched_switch`/wakeups), Flutter frame IDs and phase events, FrameTimeline presentation, GPU work/frequency and available queue/fence events simultaneously. Calculate raster **running**, runnable and blocked durations per frame; annotate QueueSubmit and pipeline creation; assign GPU work to submission/completion intervals where the trace permits. If per-pass hardware timestamps require an engine build, say so and use that build for diagnosis only. Capture counts, render target area/formats and resolve/blur passes need engine instrumentation or a GPU capture; widget filter counts are insufficient. Use active frames only, screenshots outside timing, warm/cold separately, five repeats per launch and at least two cooled interleaved pairs. Reconfirm selected gains in release.

## 2. Remaining levers, ranked by gain × confidence

Labels describe the proposed output contract, not a promise that unimplemented code satisfies it. **IDENTICAL** means zero pixel/geometry/motion change, with backend verification. **NEAR** states a maximum admitted error. **VISIBLE** has no small proven bound; a sparse large difference still counts. Gains below are measured where explicitly stated; all other gains are hypotheses and have a decision gate.

RGBA8 bounds concern the deterministic SDR harness. On Apple, preserve the native wide-gamut/HDR range and inspect its rendered output separately; an RGBA8 screenshot bound does not prove HDR equality. All variants also retain nonvisual geometry, hit testing, semantics and motion timing.

### 1 — Make compatible batches automatic inside package-owned stages

**Potential: high. Confidence: high for compact resting peers; medium for gallery/menu integration. Fidelity: NEAR ≤1 RGBA8 channel step only for the admitted, verified coordinate domain; unrestricted current batching is VISIBLE.**

The measured Pixel density result is the strongest remaining architectural evidence. Averaging two interleaved cooled launches, resting N=4/8/16/32 raster p50 moves 7.83/9.05/10.43/11.48 → 6.42/7.08/8.07/9.17 ms; p95 moves 9.43/11.63/13.53/14.85 → 7.91/8.64/9.96/11.62. This is about 18–23% at p50, not the Apple 52–59% result. N=1 barely changes. Animated waves do not benefit because moving members leave the container. Gallery controls/sheet p50 improved only about 3%/6%: the current five-button batching does not cover their whole workload.

Targets: `lib/src/widgets/glass_container.dart:49`, `:98`, `:183`, `:206`; `glass_channel.dart:486`; `glass_renderer.dart:359`; `glass_liquid_draw.dart:179`, `:344`, `:388`; `bar_items.dart:1321`; `search_field.dart:399`.

Implementation sketch:

1. Have package-owned scaffold/chrome/menu/sheet planes install a **composition-stage collector**, so applications do not need to remember a container around every compatible row. Store stable registrations with paint-order stage, geometry revision, transform/clip chain, material/blur/optics, local sampling bounds and foreground-content association. Preserve the explicit container for arbitrary application content.
2. Bucket by actual compatibility, not `MorphGlassKind.button`: optical settings, blur, appearance representation, backdrop stage, clip/isolation and sampling semantics. Extend admission to surface/body modes, compatible bar/search bodies and already-fused menu fields. A menu field stays the authoritative menu field; do not substitute the skin merge law. Different materials may require separate batches or an existing material-map path.
3. Give the resting search capsule a true `still` callback. It currently passes `_still` as frames but no `still` argument (`search_field.dart:399`), while `MorphGlassFrame` defaults false (`glass_channel.dart:19`). Account for the ancestor press transform; do not declare it still during scale motion. Bars similarly need a meaningful settled signal. Current admission excludes bar/menu explicitly and accepts only layer mode.
4. Preserve individual local raster grids/matte bytes and sampling domains. A retained local-geometry atlas with per-member transforms is safer than evaluating all shapes on a new global lattice. Initially prove compact static peers; then permit moving one member while retaining all others. Atlas subregions must preserve nearest packed-code lookup, material footprint, guard texels and in-flight ownership. Do not increase MAX_SHAPES and shade every pixel against an unbounded list.
5. Partition distant regions by area as well as member count. One bounding rectangle joining top and bottom chrome can waste far more blur/shading than it saves. Overflow retains every surface through the existing path; capacity is currently 32.

Current pixel-aligned N=8 evidence reaches max difference 1. Fractional-placement comparisons reach 45–53 steps; gallery container shots reach about 70–76. That prevents an IDENTICAL or universal NEAR-1 claim. In the absence of an admitted domain, the theoretical channel difference remains up to 255. Do not snap native positions to make the test pass: that changes motion/layout. Solve local-grid preservation, or keep the broader behavior explicitly VISIBLE and optional.

**Gate:** first show ≥1 ms raster p95 or ≥10% reduction in a real failing scene, beyond launch noise, while N=1/common small scenes regress ≤0.2 ms. Pixel density already establishes the mechanism; menu integration still needs proof. Measure resulting captures separately from filters because grouped filters may already share a capture.

### 2 — Continue exact menu-field CPU work, with allocation accounting

**Potential: high for menu UI; confidence: medium-high. Fidelity: IDENTICAL, preserving arithmetic and sample order.**

Targets: `lib/src/widgets/menu_fusion.dart:50`, `:79`, `:238`; `glass_outline.dart:253`; `menu_motion.dart:1557`; `glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart:1103`.

The last fusion batch reduced liquid menu UI p95 18.96 → 14.80 ms and flat 14.02 → 11.58 with 57 recorded input hashes unchanged. That is already banked. Latest Pixel outline micro means are approximately 0.80/0.58/0.47 ms at radius 4/10/20, versus about 0.028 ms for plain union. These small synthetic means do not describe every rich menu or explain 45% of today's slow frames.

Retake event-conditioned AOT CPU/allocation samples first. Then target the remaining dense field, separable smoothing, normal construction and retained output creation. Cache exact normalized kernel values by exact `(radius, step, reach)` where reuse occurs; bound cache size because animation radii are often unique. Keep scratch arrays sized by capacity, precompute axis/corner data once, and avoid allocating temporary two-element/list objects where a scalar pair suffices. Profile before spending time on kernel exponentials: grid/blur work is likely larger.

Separate temporary scratch from immutable published field samples. The returned Float32 samples can outlive the call and the upload cache uses identity; blindly reusing their backing array can both corrupt in-flight rendering and skip an upload. A future leased pool needs explicit generation/release and GPU completion lifetime, plus forced-upload logic for a new revision. Scratch reuse is the lower-risk first step.

Further band culling must prove that skipped nodes cannot affect distance, gradients, halfMinor, optical-corner turns or clearance read by the shader. Sign-only arguments are insufficient. Preserve Gaussian weights, summation order, the current grid and sparse trace's ordering. The existing `<1` plain-union path and near-block dedup are already implemented. Translation canonicalization is only exact when it preserves floating sample coordinates and rounding; generic translation is not automatically an identity.

**Gate:** ≥0.75 ms menu UI p95 or a repeatable reduction of slow fusion frames and GC tails; target ≥2 ms for an invasive rewrite. Stop a micro-optimization that does not move current device CPU cost beyond noise. No radius snapping, earlier fusion cutoff, coarser grid or replacement smoothing under this label.

### 3 — Close the glyph-atlas tail, then re-rank raster work

**Potential: high for p99, unknown for p50; confidence: medium from baseline traces. Fidelity: IDENTICAL only for retained text with unchanged effective rasterization; otherwise NEAR/VISIBLE must be measured. Concurrent agent owns implementation.**

Targets for attribution: `lib/src/widgets/bar_items.dart:1448`, `menu.dart:1018`, `glass_liquid_draw.dart:701`; actual atlas update is engine code. Baseline updates cost 2.1–2.5 ms per occurrence on average, with about 0.6 ms/frame amortized. Averages hide expensive tail events. Continuous scale can invalidate atlas entries even when Dart text widgets and display lists are retained.

Do not duplicate the other agent's work. Evaluate it with matched frames, text size/scale, atlas update count/bytes, glyph cache occupancy and raster p95/p99. Preserving a cached glyph raster under arbitrary scale is not inherently pixel-identical. Avoid removing the measured tab-label magnification or menu scale to obtain a result. If the fix only relocates cost to a first-use spike, test every motion scale range and first submenu as well as warm opens.

**Gate:** fewer atlas-update events on the previously slow frames and a statistically repeatable tail improvement; revert any loss of text sharpness/placement or unbounded atlas memory. Update this rank after the agent's exact-HEAD measurements rather than adding its estimated gain to the container estimate.

### 4 — Fewer independent captures by construction

**Potential: high where a safe stage boundary is currently duplicated; confidence: medium. Fidelity: IDENTICAL for proven equal backdrop stages; VISIBLE across dependency boundaries.**

Targets: `glass_liquid_draw.dart:280`, `:306`, `:344`, `:388`, `:535`; `bar_items.dart:1363`; `menu.dart:1253`; `glass_container.dart:75`. Engine mechanism and grouping rules: `glass-renderer.md:320`, CLAUDE.md's BACKDROP GROUPS section.

A BackdropGroup shares capture, but every remaining filter still incurs filter/output encoding. A container removes effects as well. Treat these as two separate levers. Vulkan captures at the first group member; Metal's group behavior differs. Reusing a key across a surface that must see intervening paint can produce the wrong backdrop on either backend.

Construct package-owned stages explicitly: completed background → compatible body effects → their content → lifted lens/overlay effects. Search/navigation/toolbar peers on the same chrome plane can reuse the established chrome scope where their dependency is identical. Menu cards/submenus and sheet interiors must be audited for the paint they must sample. A lifted lens samples body glass plus content and therefore needs its later independent capture. Hero/satellite, edge fade and nested overlay stages cannot be collapsed just because their rectangles do not overlap.

The owner previously chose explicit ordering scopes instead of a global ancestry heuristic. Preserve that decision for arbitrary application trees. The bold extension is automatic grouping in components whose paint order the package owns, with explicit stages available to consumers; it is not a silent root-wide hoist based on unreliable PictureLayer bounds.

**Gate:** instrument actual FlipBackdrop/resolve counts and bytes/area, verify striped intervening content on Vulkan and Metal, and demand ≥0.5 ms limiting-stage p95 or a material GPU/energy reduction. If existing keys already share the capture, this experiment has zero capture-count gain; move to filter consolidation instead.

### 5 — Retain outer motion/layout and unchanged content snapshots

**Potential: medium, especially tab/menu UI; confidence: high that work exists, medium on end-to-end gain. Fidelity: IDENTICAL.**

Targets: `glass_channel.dart:109`, `:244`, `:289`, `:465`; `bar_items.dart:1205`, `:1282`, `:1321`, `:1477`; `menu.dart:605`, `:973`, `:1008`; `glass/renderer/internal/content_snapshot.dart:34`, `:157`, `:169`; `glass_liquid_draw.dart:701`.

Channels retain the inner renderer tree, but a frames-driven host still schedules an element build, and bar/menu ListenableBuilders still recreate outer positioning/transform wrappers. Move stable wrappers into retained render objects with motion values driving paint/parent data. In `_RenderLiveStack.follow`, offset-only changes currently call `markNeedsLayout`. Add a translation path for fixed constraints that updates paint offsets and transforms without relaying out children. Preserve hit testing, semantics geometry, overflow/clip behavior and compositor invalidation. Size/constraint changes keep the current layout path.

`GlassContentSource` marks paint on every captured frame and re-records the snapshot even if the source picture layers are unchanged. Track actual source layer/picture revisions, size, DPR and relevant compositing transforms. Reuse an immutable snapshot when all inputs are unchanged; unrelated lens motion should not regenerate it. Widget identity alone is not enough: independently animated descendants can change without replacing the widget. Keep the conservative image fallback for unsupported layers, count it and retain its correctness.

The content-copy painter should pre-cull nonintersecting slots/strips, and retain unchanged copy display lists if the effective copy transform/clip/source revision is unchanged. Moving scale still changes its drawing and may trigger engine glyph work. This saves Dart recording/compositing only to the extent measured; it does not make Impeller replay free.

**Gate:** improve current tab/menu UI p95 ≥0.5 ms or a meaningful phase duration, with identical frame hashes and unchanged pointer/accessibility behavior. Do not add a per-frame global transform map: that was already tried and its upkeep erased the saving.

### 6 — Engine-level preparation reuse for stable display lists and filter graphs

**Potential: high; confidence: medium-low until an engine prototype. Fidelity: IDENTICAL. Separate engine investment.**

Package entry points: `glass_channel.dart:414`, `glass_liquid_draw.dart:179`, `liquid_glass_layer.dart:1271`, `:1305`. Pinned engine investigation points recorded in `tool/audit/flutter-tricks-2026-10-05.md:49`, `:70`, `:81`: rasterizer damage policy, `Canvas::FlipBackdrop` and filter saveLayer processing.

Stock Impeller has no general raster cache that turns retained Flutter layers into reusable GPU output. `addRetained` avoids rebuilding some UI-side scene state; the engine still interprets/encodes the display lists and filters each frame. Merely adding RepaintBoundary wrappers cannot remove the roughly 7.4–7.8 ms Encode duration.

Prototype caching of immutable preparation: stable display-list tessellation/geometry, filter topology, constant pipeline selection, descriptor/layout preparation and resource allocation plans, keyed by display-list identity plus render-state/format dependencies. Rebind current textures, attachments, uniforms and ordering per frame. Count cache hits, CPU running time and allocation/command count. Reuse existing engine caches first; verify the uncached cost with samples before building another cache.

Do not replay stale Vulkan command buffers blindly: framebuffer/attachment identity, backdrop texture revision, synchronization and in-flight resources change. Do not cache final glass output while the background moves. A valid preparation cache can save raster CPU without freezing pixels; an image cache cannot generally do so for a backdrop effect.

**Gate:** ≥1.5 ms raster p95 or ≥15% raster running-time reduction in menu and one other intended scene, exact output and bounded memory. Reject if maintenance requires broad engine divergence for sub-noise gains. Package-level container work should precede this fork because it removes operations the stock engine otherwise has to process.

### 7 — Make independent capture bounded, or fuse filter passes in Impeller

**Potential: high GPU/bandwidth savings; confidence: low-medium, engine-dependent. Fidelity: IDENTICAL only with preserved input support and sampling domain.**

Targets: `liquid_glass_layer.dart:1254`, `:1271`, `:1449`; `internal/snap_rect_to_pixels.dart:20`; engine FlipBackdrop/filter machinery cited above.

On the pinned Vulkan path, a small output clip does not prevent the independent full-screen backdrop flip/resolve and redraw. Blur is already downsampled automatically; composing blur then runtime shader can introduce an intermediate re-rasterization. Investigate a bounded snapshot/subpass input and direct consumption of the blur intermediate by the runtime effect. This addresses costs GLSL arithmetic cannot remove.

Output coverage and input sampling support must be different concepts. Input includes blur support, refraction/dispersion, shrink, bilinear/softening reach and ancestor intersections. Preserve the old mirror domain even when output is tighter: `uBackdropBounds` participates in refracted sample mirroring, including unfrosted glass. Any partial update must restore previous background content and handle dependencies/rotation/edge cases. Engine backend capability and attachment lifetimes decide feasibility.

A 1080×2400 RGBA8 image is about 10.4 MB, but multiplying image size by flips is not measured external-memory traffic: tile memory, compression and resolves change it. Use hardware counters/pass captures for a bandwidth claim.

**Gate:** first prove captures/passes and GPU completion are material on a failing scene. Continue only for ≥10% scene GPU work/energy or ≥1 ms limiting-stage gain, no pixel changes and no new blocking synchronization. If raster encoding remains the limiting stage and presentation does not improve, classify it as an energy project rather than the frame-budget solution.

### 8 — Split invalidation and remove per-layer preparation waste

**Potential: small-medium; confidence: medium-high. Fidelity: IDENTICAL.**

Targets: `liquid_glass_layer.dart:1030`, `:1053`, `:1118`, `:1512`; `flutter_gpu_geometry_renderer_native.dart:283`, `:413`, `:485`; `internal/render_liquid_glass_geometry.dart:13`.

Separate authoritative geometry/transform revisions from appearance/palette/material-map revisions. `_prepareGeometryAppearance` can mark geometry dirty for mixed appearance changes; inspect which mixed data really shares the matte encoding before splitting targets. Avoid rerendering SDF when only a decoupled palette changed, but preserve matte visibility data that actually affects geometry. Cache shadow pictures by exact shadow/shape/visibility/offset inputs rather than recording them again on unrelated changes.

For field-only plain bodies, skip packing unused analytic shape/RSE uniforms and unused geometry-buffer work, once the renderer's field/material branches prove they do not read them. Cache exact settings/appearance resolutions, immutable shape descriptors and sort order by revisions. Keep current transform-only retained reuse; it already exists. Avoid replacing short linear lists with expensive per-frame maps without evidence.

**Gate:** ≥0.3 ms in the affected phase/scene or demonstrably lower allocation/GC tails. The number of layers multiplies small fixed costs, but package preparation alone cannot eliminate engine saveLayer processing. No expansion of queued submissions beyond the current safety bound; the Apple startup hang is documented and reproduced.

### 9 — Skin tracer: retain contour paths and reduce temporary graph allocation

**Potential: medium in skin-heavy scenes, low confidence of benefit in these six glass scenes. Fidelity: IDENTICAL for exact path reuse; topology rewrites are VISIBLE until proven.**

Targets: `lib/src/liquid_field.dart:617`, `:808`, `:911`, `:1098`, `:1157`; `lib/src/skin.dart:1158`, `:1253`.

Skin already has whole-input signature reuse and repaint-driven motion. `LiquidTracer` caches cluster loops, but when one cluster changes it reconstructs path commands for every cached cluster. Cache each cluster's immutable Path alongside its exact signature and loops, and assemble with `addPath` in the same order/fill rule. Verify combined fill semantics, not just vertex equality. Reuse signature/cache-entry storage where safe; keep exact comparison after hashing.

For actual tracer misses, use typed segment/vertex storage and capacity-kept grids instead of allocating many Offset/record/list objects. Preserve marching ambiguity decisions, segment order, current endpoint quantization and Chaikin output. An edge-ID stitcher can change the current rounded endpoint merge behavior; replacing it is not automatically IDENTICAL. A spatial broad phase for clustering must preserve cluster membership and fold order because chained smooth-min is order-dependent.

**Gate:** require current scene samples showing tracer/allocations are material, then ≥20% tracer CPU or ≥0.5 ms UI p95 in a representative skin workload. Do not transplant the glass outline's different smoothing algorithm or relax deterministic evaluation budgets to claim fidelity.

### 10 — Layout, semantics and GC tails as separate measured workloads

**Potential: medium for tails; confidence: medium. Fidelity: IDENTICAL, including accessibility behavior.**

Targets: `menu.dart:605`, `:966`, `:1669`; `bar_items.dart:1448`; `glass_channel.dart:109`, `:289`; `skin.dart:1158`; `menu_fusion.dart:79`.

Avoid recreating unchanged semantic labels/actions/selected state with every optical tick; update semantic bounds when their transform really changes. Preserve open/closed, disabled, focus and selected transitions. Current passport runs disable semantics, so a semantic optimization cannot explain their 14.8 ms menu build figure. Add a separate accessibility-enabled profile and end-to-end latency check.

Use allocation sampling and GC-to-frame correlation to rank sources: immutable surface lists/parts, closure/widget wrappers, field outputs, path/segment objects and snapshot recording. There is already reuse in several places; do not reinstate an old allocation finding without checking current code. Pool only owned scratch; immutable descriptions and GPU-live buffers need explicit lifetime. Avoid global suppression of notifications unless all frame-dependent consumers remain correct.

**Gate:** fewer collections on critical frames or ≥0.5 ms UI p95/p99 with no semantic regression; steady RSS must remain bounded over a long loop. GC is not an independent fixed tax that can be subtracted from every frame.

### 11 — Remaining shader/bucket experiments

**Potential: low for current raster-budget failures; medium for energy/large faces. Confidence: low-medium. Fidelity varies.**

Targets: `liquid_glass_layer.dart:1254`, `:1512`; `flutter_gpu_geometry_renderer_native.dart:283`, `:1103`; `shaders/liquid_glass_final_render_core.glsl`; `shaders/gpu/geometry_field_fragment.glsl`.

The retained batch already took the good measured shader wins. Uniform hoists/specialization, analytic geometry simplification and exact output-area reduction remain experiments. Label uniform/geometry rewrites IDENTICAL only after emitted-code/device parity. Smaller output buckets can be IDENTICAL only with unchanged input/mirror domain and texel mapping. Smaller allocation capacity is not the same as fewer shaded pixels.

RGBA16F field storage/manual taps or hardware filtering is **VISIBLE until bounded**: gradients near saddles and packed displacement can amplify small errors; no universal ≤1-step final bound exists. Half-resolution matte, larger field step, lower material-map resolution and moving blur after refraction are VISIBLE and have no acceptable native-look guarantee. Do not combine them with exact changes in one A/B.

**Gate:** complete parity harness on Vulkan, GLES and Metal, plus real-scene native motion checks; require a repeatable ≥5% GPU-work gain or ≥0.5 ms limiting-stage gain to justify new variants/ABI complexity. Do not infer wins from source ALU counts or Pixel readback wall time.

## What to stop doing

- Stop treating shader work as the primary route from menu raster p95 20 ms to a reliable 60 Hz frame. The final frosted-menu shader saving is 1.2% GPU work and end-to-end raster did not move.
- Stop re-proposing completed menu caching, union-tail, field upload, shadow-layer and warm-up fixes. Benchmark their current residual cost before extending them.
- Stop adding RepaintBoundaries indiscriminately or interpreting `addRetained` as Impeller raster-output caching. Retained UI scene construction and raster encoding are different costs.
- Stop global automatic backdrop sharing across arbitrary paint order. Preserve lens, content, overlay and edge-effect dependencies. Widget bounds/nonoverlap alone do not establish a common backdrop stage.
- Stop counting filter reduction as capture reduction, and stop promising constant cost from one global canvas. Sparse batches, appearance complexity and full bounding-area shading can regress.
- Stop extrapolating Apple's 52–59% container reduction to the Pixel or from N=32 density to a menu with different moving/lifted effects.
- Stop calling fractional-position container output identical: observed 45–76-step rim differences are real, even if most pixels match.
- Stop lowering blur/refraction, snapping radius/time, changing text magnification, dropping fields or coarsening geometry under an invisible-performance label. These are product/fidelity choices.
- Stop per-frame isolates, synchronous GPU readback and screenshots in timing windows. They add scheduling/latency or distort the workload.
- Stop unbounded queues, rings and mutable-buffer reuse without completion ownership. Uniform-arena and Apple queue fixes closed real failures; do not trade them away for microseconds.
- Stop subtracting independent percentiles, adding nested trace slices, using GPU wait-thread duration as GPU time, or using DVFS-sensitive shader wall timings on the Pixel.
- Stop optimizing motion getter arithmetic without samples: previous measurements found it tiny compared with fields, compositor work and engine submission.

## 3. What “nothing left to do” should mean

It cannot mean zero overhead. Native-looking moving backdrop glass requires current background sampling, correct ordered captures and optical work. It should mean that the package has headroom on the target device, no unexplained tails or avoidable repeated work, and further accepted-fidelity experiments fail a predefined return threshold.

Proposed **exit targets**, not observed results: Pixel 6a Vulkan, liquid fixed, actual 60 Hz, representative content, warm interactions, release confirmation. UI and raster stages run in a pipeline; these are separate ceilings, not a sum.

| Scene | UI p95 target | Raster p95 target | Tail target |
|---|---:|---:|---|
| Home scroll | ≤7 ms | ≤12 ms | UI/raster p99 ≤16.67 ms |
| Segmented | ≤8 ms | ≤12 ms | Same, including lift/drag/settle |
| Tab bar | ≤8 ms | ≤12.5 ms | Same, including text scale and selection reversal |
| Controls | ≤10 ms | ≤12.5 ms | Same, including simultaneous interactions |
| Menu | ≤10 ms | ≤13 ms | Same, separately for root/submenu/open/close/reversal |
| Sheet | ≤7 ms | ≤12.5 ms | Same, including detent motion and interior glass |

Presentation must also pass: <1% missed deadlines in every defined interaction phase, with a stretch goal <0.1% for repeated warm interactions, and no persistent cadence step-down. Report both stage-over-budget and actual FrameTimeline misses. A large first-use miss cannot disappear into a five-run median: report cold install, first glass, first lifted lens, first menu/submenu and first sheet separately. Current precache has already removed the main shader-startup cliff; any remaining interaction-specific pipeline/font/resource cliff needs attribution.

Require zero self-scheduled frames at settled idle, zero dropped shapes/geometry failures at N>32 fallback, bounded steady/peak CPU and GPU memory, no monotonic cache growth, and no thermal regression in a sustained 5–10 minute interaction loop. Measure the colder baseline and realistic sustained thermal state; a cooled 20-second success alone does not establish weak-device performance. Keep semantics-enabled operation responsive and correct. On iPhone, preserve the existing comfortable scene timings and native look; investigate repeated >0.2 ms or >5% critical-stage regression beyond the baseline noise.

The completion packet needs an exact commit/patch/engine manifest, cooled interleaved baseline/candidate runs, per-phase p50/p95/p99/worst, presentation results, raster running/blocked attribution, GPU work/completion where available, actual capture/filter/pass counts, memory, startup and parity films. Averages across scenes cannot compensate for a failing menu phase.

### Kill criteria

1. **Correctness first:** kill/default-disable any optimization that obtains its gain by a stale backdrop, wrong paint-order dependency, missing overflow shape, text/motion change, broken accessibility, resource lifetime violation or an unapproved VISIBLE difference. IDENTICAL candidates need deterministic backend parity; NEAR candidates must satisfy their stated maximum on the admitted domain. Gallery motion shots with run-to-run noise are not a substitute for a deterministic harness.
2. **Noise:** stop a package micro-optimization after two cooled interleaved pairs if its relevant stage gain is inside the baseline launch spread and no allocation/tail/energy benefit is established. The latest Pixel p50 launch spread reaches about 0.4 ms; do not ship a speculative 0.1 ms rewrite on that evidence.
3. **Real workload:** stop broad container integration if it improves only density stress tests. It must help a real intended scene enough to justify its complexity. Keep the proven opt-in density use case rather than forcing a global architecture.
4. **Area/invalidation:** split or reject a batch if empty-area shading/blur erases setup savings, or one moving member forces all static geometry to regenerate and performs worse than local mattes. Do not enlarge caps to conceal this scaling failure.
5. **Engine fork:** stop preparation/capture prototypes without the gains specified above, bounded memory and a maintainable patch. A fork is justified by measured engine cost, not by an assumption that a custom compositor is automatically faster.
6. **Memory/thermal:** initially investigate any >16 MiB steady or >32 MiB peak increase in these Pixel scenes; reject monotonic growth and sustained thermal/presentation regression. These are proposed project budgets, not current measured memory limits. A material increase requires a quantified benefit before adoption.
7. **Completion:** once all scene/phase targets, parity, startup, idle, accessibility and sustained tests pass, stop broad optimization when the remaining IDENTICAL/approved-NEAR candidates cannot produce ≥0.5 ms critical-stage p95/p99 or ≥5% sustained GPU/energy improvement. Document the residual costs and leave low-return shader/style experiments optional.

The most credible sequence is: finish exact-HEAD attribution and the glyph result; pursue exact menu CPU/allocation savings; extend automatic batching in package-owned stages with local-grid preservation; retain outer motion/snapshots; then fund an engine preparation/capture prototype if the residual trace still warrants it. Menu UI and raster are independent acceptance gates. Closing one must not be reported as closing the other.
