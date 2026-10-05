# Shader audit: weak mobile GPUs

2026-10-05. Read-only audit; no shader, Dart, manifest, fixture, or build changes made. This file is the only audit output. Device tests and timings below are a **design**, not results obtained during this audit.

## Scope, evidence, and error vocabulary

Reviewed every line of the 15 `.frag` / `.glsl` files under `lib/src/glass/renderer/shaders`, including its GPU directory, and the relevant uniform packing, texture allocation, pass submission, caching and filter clipping in the two requested Dart call sites. Source baseline: HEAD `eb0572d721b6b7f1ceccadcf1e45163390dac951`; shader hashes at the end identify the actual working files read. Another agent owns shader edits; line references describe this snapshot, not its eventual changes.

Paths below use these explicit abbreviations, followed by ordinary line numbers:

- `S/` = `lib/src/glass/renderer/shaders/`.
- `G/` = `lib/src/glass/renderer/shaders/gpu/`.
- `C` = `lib/src/glass/renderer/shaders/liquid_glass_final_render_core.glsl`.
- `L` = `lib/src/glass/renderer/rendering/liquid_glass_layer.dart`.
- `N` = `lib/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart`.
- `SDK/` = `/opt/homebrew/Caskroom/flutter/3.19.1/flutter/` (installed SDK is 3.47.2, despite directory name).
- `E/` = `/tmp/flutter-src/engine/src/flutter/`, the pinned engine source used by the existing audit.

Fidelity labels apply to **additional error versus this implementation**, on the same backend and device, not to error against UIKit:

- **IDENTICAL (0)**: preserve operation order, inputs, sampler, and observable output; require zero differing output channels. A compiler can invalidate the prediction, so device comparison is still mandatory.
- **NEAR (N/255)**: proposed acceptance ceiling of N integer channel steps in SDR premultiplied RGBA, including alpha, at every pixel. These are expected engineering targets, **not measured or universal mathematical bounds** unless an explicit derivation is supplied. Do not hide failures with a percentile, average, or edge mask. Separate HDR tests use the stated absolute float tolerance, preserve values above 1, and compare premultiplied values.
- **VISIBLE**: no defensible small maximum for the admitted inputs, or a known larger change. The SDR worst-case cap is 255/255 per channel; HDR can exceed 1. Such ideas are rejected for this task unless a narrower, proven predicate makes them exact. “Subpixel” alone is not an image-error bound.

For NEAR proposals, default HDR gate is absolute channel error <= 1/255 over tested [0,4] output values unless specifically stated otherwise; values outside that domain require a new bound. A proposed optimization failing its stated ceiling does not land. Combined optimizations must satisfy a combined <= 2/255 SDR budget (and <= 2/255 HDR over that domain), not accumulate a fresh budget per optimization.

### Cost model and non-negotiable contracts

`CLAUDE.md:166-272` and `tool/ios_reference/spec/glass-renderer.md:9-57` make the caller's outline authoritative. Do not substitute a faster shape, fuse differently, reorder the smooth union, or switch tiers to claim an optimization. Existing plain unions are a separate, already implemented path. Runtime final shading executes on every rendered frame; geometry can be reused, including uniform translation (`L:929-939,973-1006`). Idle frames remain zero.

The Pixel 6a table (`CLAUDE.md:1207-1229`) records liquid-menu build p95 18.96 -> 14.80 ms, upload-related PAINT 1.42 -> 1.16 ms, and resting-button COMPOSITING 2.53 -> 1.24 ms. Liquid-menu **raster p95 remains ~20 ms** against a 16.67 ms budget. Those are CPU/raster measurements, not shader GPU timings. Do not attribute the CPU gains to fragment ALU, or predict that a shader cleanup removes the ten saveLayers. The GLES comparison (`tool/ios_reference/spec/glass-renderer.md:195-206`) also says fake/frosted are not cheap substitutes on this phone.

`tool/audit/flutter-tricks-2026-10-05.md:38-133` documents full-screen backdrop flips, clip-sized filter passes, blur downsampling plus a full-resolution runtime-effect input re-rasterization, no mobile raster cache, and wide-gamut intermediate bandwidth. These costs cap the frame benefit of an ALU-only change. Its upload recommendation is already implemented: `N:1094-1139` uses device-private RGBA32F, a staging buffer and `copyBufferToTexture`; it is no longer a host-visible texture overwritten per frame. Do not count this saving again.

## Ranked changes: expected gain × confidence

H/M/L describe likely savings **in the affected pass**, not promised milliseconds or frame percentages. Confidence is confidence in useful remaining work and fidelity, before emitted-code inspection. Vulkan and Metal need separate timing; GLES needs its own shader compilation and run.

| Rank | Proposal and location | Gain / confidence / frequency | Fidelity and expected maximum |
|---|---|---|---|
| 1 | Move the existing signed-distance/coverage rejection before material-map reads (`C:532-677`). | M-H on sparse mixed-material rectangles; high; every final pass. Saves 1 tint or 6 appearance fetch instructions in rejected pixels. | **IDENTICAL (0)**: use the exact existing predicate and base contour alpha. |
| 2 | Decode normal once, share coverage and light-axis calculations (`C:678-681,372-373,400-439,479-480,928-931`; `G/displacement_encoding.glsl:79-94`). | L-M; high semantic confidence, medium incremental gain because compiler CSE may already do it; all final variants. | **IDENTICAL (0)** with same FP32 expression/order. |
| 3 | Skip secondary palette fetches when contributor IDs coincide or the weight is exactly an endpoint (`C:593-657`). | M in material variant's solid regions; medium-high; every final frame. | **IDENTICAL (0)** for finite palette values and unchanged reconstruction arithmetic; reuse the fetched value in both operands, rather than cancelling blends algebraically. |
| 4 | Hoist uniform-only face/lighting scalars; specialize exact gamma=1 and wrap=0.5 cases (`C:148-209,399-428,797-872`; `L:619-681`). | M; medium-high; final plain/tint variants especially. | CPU-derived color constants **NEAR <= 1/255**; remove exponent-1 powers **NEAR <= 1/255**, target 0. Coordinate hoists separately gated below. |
| 5 | Exact interior/exterior lighting skips and fake exterior-only path (`C:352-506`; `S/fake_glass_surface.frag:82-209`). | M on large flat interiors and fake exterior ring; high if predicates are exact. | **IDENTICAL (0)** for exact zero-support conditions; no raised cutoffs. |
| 6 | Smaller *output* clip buckets with preserved backdrop sampling domain (`L:1249-1294`; snap helper:20). | M-H for small controls; medium due to allocation and capture interactions; every final frame. | **IDENTICAL (0)** only with identical captured samples/mirroring; blindly shrinking current bounds is **VISIBLE**. |
| 7 | Hoist smoothing budget and primitive invariants; eliminate duplicate local-point work (`G/sdf.glsl:285-303,338-354,358-395`). | L-M on changing analytic geometry; medium. | Source CSE **IDENTICAL (0)**; CPU arithmetic changes **NEAR <= 1/255 only after end-to-end test**, otherwise reject. |
| 8 | Backend-specific half for bounded color arithmetic, in small blocks (`C:168-171,484-504,921-937`). | M potential Metal / Mali Vulkan, none expected GLES; medium-low until compiler evidence. | **NEAR <= 2/255** SDR and absolute 2/255 HDR [0,4] for the chosen block; keep sensitive operations FP32. |
| 9 | Fake cap-angle predicate instead of atan/mod; precompute fake uniform lighting (`S/fake_glass_shape.glsl:79-88`; surface:88,124-163). | M for fake RSE rim; medium. | **NEAR <= 1/255**, branch-boundary cases mandatory. |
| 10 | Cold-path geometry/material struct and lookup simplification (`G/material_sdf.glsl:6-82`; gradient:39-55). | L-M with 8-16 changing shapes; medium-low because DCE may do it already. | **IDENTICAL (0)** if only dead values/indexing implementation change. |
| 11 | RGBA16F field: manual filtering first, hardware filtering second (`G/geometry_field_fragment.glsl:39-61`; `N:1114`). | L-M field pass/bandwidth, low total-frame gain; low fidelity confidence. | **VISIBLE without extra constraints**; experiment target <= 1/255, not a promised bound. |
| 12 | More shader variants / pretabulated RSE / generic power approximations. | Workload-specific; low confidence versus compile/cache/register/texture cost. | Exact specializations as above; approximations **VISIBLE until bounded**. Not first-line work. |

Order of experiments: 1, 2, 3, then 4/5; measure the real menu and controls before spending effort on 8-12. Rank 6 can outrun all ALU gains but needs compositor-aware fidelity checks.

## Full line-by-line audit ledger

Ranges group adjacent declarations/comments with their executable block. Includes are audited at their definitions rather than counted as independent draws.

### Final entrypoints and shared color helper

| File:line | Finding and disposition |
|---|---|
| `S/liquid_glass_final_render.frag:1-20` | Plain variant, `SHAPE_APPEARANCE=0`, `SHAPE_TINT=0`; no material sampler. Preserve compile-time exclusion. Its Skia stub is deliberately transparent, not a test of liquid fidelity. **IDENTICAL (0)** to keep. |
| `S/liquid_glass_final_render_tint.frag:1-20` | Tint variant already avoids contributor IDs, response decode and four palette lookups. Keep it; replacing all variants with one uber-shader adds pressure and may keep dead samplers live. **IDENTICAL (0)** to keep. |
| `S/liquid_glass_final_render_material.frag:1-20` | Full appearance variant. The common core avoids maintenance duplication, not repeated GPU draws: only one is selected (`L:535-540`). Do not report three executions per layer. **IDENTICAL (0)**. |
| `S/render.glsl:1-11` | Fixed Rec.709 dot weights. Changing luminance coefficients changes the measured face; **VISIBLE**, up to full-channel SDR differences over the wider pipeline. Keep. |
| `S/render.glsl:12-22` | Saturation already uses a linear chroma ramp. `saturation==1` is **not identity**, because of `+0.4*chromaWeight`. Constant division by .65 should strength-reduce; inspect code, no useful approximation to propose. A no-op saturation branch would be **VISIBLE**. |

### Final core, declarations through lighting

| File:line | Finding, action, and fidelity |
|---|---|
| `C:1-55` | FP32 coordinates are required. `uSize` belongs to the image-filter ABI and can be engine supplied; runtime effects expose no package-owned vertex stage. Do not assume CPU knows the final captured texture size. `uGeometryUVScale` already handles texture capacity. Keep ABI; **IDENTICAL (0)**. |
| `C:57-121` | Global aliases do not imply uniform evaluation on the CPU; their clamps/products are shader work unless compiler hoisted. Several uniforms are constants at this call site (`L:630-656`: light=(0,1), white highlight, black contour, size-response/transmittance/offset=0). Consider constant production specialization while retaining the generic test path; **IDENTICAL (0)** for those exact inputs. Avoid making another public quality tier. |
| `C:125-139` | `shapeLookup` divides by material dimensions for each palette lookup. Precompute inverse texture size and both row centers with the existing material binding; **NEAR <=1/255** gate, but exact texel/ID selection is required. Keep nearest sampling; no interpolated IDs. |
| `C:148-165` | `sliderKeyframes` and short-side smoothstep are uniform in all variants. Precompute the three dark transmission keyframes once per changed short side/slider. Preserve the breakpoint at .5. **NEAR <=1/255** after CPU FP32 packing; identical arithmetic is preferred. No reason to force both branches at each fragment. |
| `C:168-195` | Neutral wash can be represented by premultiplied emission plus opacity, avoiding divide then multiply in the consumer (`C:878`). Algebraic cancellation changes rounding: **NEAR <=1/255**; do not divide half values near alpha=1e-4. For plain/tint variants the whole neutral wash is uniform; for appearance variant blend shares are pixel-dependent. |
| `C:200-210` | Precompute light/dark/clear face-transfer keyframes, then blend per pixel only for SHAPE_APPEARANCE. **NEAR <=1/255**. Do not interpolate final nonlinear output from pre-shaded per-shape colors; that is a different transfer. |
| `C:214-245` | Light tint costs one scalar + three component powers; dark tint costs two scalar powers. Mixed light/dark executes both. Keep uniform endpoint branches. Precomputing tinted RGB alone is invalid because the exponent depends on backdrop luminance. Near-one exponents are not automatically cheap-to-remove; see the bound below. **VISIBLE** to replace them generically. |
| `C:251-257` | Color-model classification is uniform in plain/tint, per-contributor in full appearance. CPU can send shares or a specialization key. Preserve strict inequalities and legal integer codes. **IDENTICAL (0)** for classification of the existing 0/1/2/3 codes. Replacing ternaries merely to “remove branches” has no established gain. |
| `C:259-289` | `contourExtent` and `1/(2*uEdgeWidth)` are uniform; coverage is called at rejection, in lighting, and output. Compute coverage once and pass x/y. **IDENTICAL (0)** with unchanged operations; reciprocal-multiply reassociation **NEAR <=1/255**. Width<=0 must still bypass division. At default contour offset=0, interior coverage is exactly zero; a dedicated constant path can remove interior absorption work. |
| `C:294-304` | Tangency is reused by lobe and two contour consumers; compute once. Directionality clamp is uniform. **IDENTICAL (0)** with matching expression. For fixed light=(0,1), tangency=abs(normal.x), but retain generic harness coverage. |
| `C:306-314` | Mirror uses mod/abs/clamp. It already handles multi-period UV excursions. An “inside [0,1]” shortcut must also respect half-texel clamps. Positive UV mod often lowers to floor/multiply; no generic transcendental here. **IDENTICAL (0)** only with a proven same-result shortcut; replacing mirror by clamp is **VISIBLE**. A branch may lose on alternating edge pixels. |
| `C:316-327` | Repeated inverse of uniform affine basis: CPU can pack inverse columns and singular flag once when mapping changes (`L:1208-1227`), or compiler may hoist it. Keep abs(det)<1e-6 behavior. **NEAR target <=1/255**, not a global guarantee: changed UV rounding can cross sample/codec boundaries. Prefer unchanged FP32 division until threshold tests pass. |
| `C:329-350` | `lo`, `hi`, margin, extent are uniform. Keep the coherent interior early return: computes no inverse/mirror when samples stay captured. The function is called up to 3 times per pixel. Share bounds, inverse and matte anchor, but preserve operation order to target **IDENTICAL (0)**. Do not equate clip coverage with harmless discarded pixels: bounds affect refraction. |
| `C:352-390` | Existing disabled-light and deep-interior exits are useful. Reuse material alpha and coverage from main. A more powerful exact interior exit requires contour coverage=0, inward distance >=4*glintWidth, and either shadow strength=0 or inward >=bevelDepth+max(bevelOffset,0), with the size-adjusted depth if that ever changes. That makes all omitted contributions exactly zero: **IDENTICAL (0)**. Existing thresholds are part of baseline; do not raise them. |
| `C:393-410` | `exp2(2-4*wrap)` is uniform; wrap=.5 gives exponent exactly 1. Replace that power with max(axisAlignment,0) on a coherent exact-equality branch/specialization. **NEAR <=1/255**, expected 0; verify pow lowering. For wrap=.25/.0/.75/1, exponent is 2/4/.5/.25, allowing multiplies or square roots, but those rarer choices require the same gate. Keep the directional sign test. |
| `C:415-428` | Bevel depth, surface half-minor, size smoothstep and energy are uniform. `L:643` always sends size-response 0, hence sizeEnergy=1. A production constant removes the entire response calculation **IDENTICALLY (0)** for finite inputs; CPU generic hoist **NEAR <=1/255**. |
| `C:439-475` | Reuse facing from opposite-highlight selection. Retain the uniform bevel-enable branch. The penumbra conditional protects smoothstep with zero/reversed range; branchless evaluation can produce NaN before multiplying by zero. Do not approximate this cubic: its endpoints remove a documented normal seam. **IDENTICAL (0)** for CSE; arbitrary ramp simplification **VISIBLE**. |
| `C:479-506` | Reuse contour direction/coverage. Black contour and zero transmittance remove terms under the current CPU contract. Glint target deliberately exceeds SDR white; upper clamping, RGB8 intermediate caching, or dropping chroma gain is **VISIBLE**. Half experiments can start with bounded final color multiplies/lerps, not luminance/normal thresholds; **NEAR <=2/255** gate. |

### Final core main

| File:line | Finding, action, and fidelity |
|---|---|
| `C:510-530` | Affine map, normalized geometry UV, and bounds rejection are necessary. Combining `(matte-offset)/size * UVScale` into one coefficient is mathematically affine but can change nearest texel selection; **NEAR <=1/255 only if all boundary fixtures pass**, otherwise **VISIBLE**. Keep coordinates highp. Moving these into a runtime-effect vertex shader is unavailable in this API. |
| `C:532-555` | Geometry fetch happens first; tint-map fetch currently happens even for fully exterior matte pixels. Decode sd, compute the existing coverage/reject immediately after geometry fetch and before appearance setup. `materialAlpha` and the current rejection's `gContourAlpha` do not depend on the material map yet. **IDENTICAL (0)**. Do not move the later dark contour amplification before this predicate: that would change which pixels survive. |
| `C:546-570` | ceil(geometry size / material raster scale), max, reciprocal dimensions and lookup-row coordinates are draw constants. CPU can pack affine material-UV coefficients. **NEAR <=1/255** with ID address equality required; nearest floor must remain per pixel. Do not accidentally use allocated height instead of map height; the last two rows are palette. |
| `C:571-602` | Two fetches from one material image with different samplers: discrete contributor pair and filtered weights. The pair-order repair matters at swaps. Linear filtering the IDs directly or removing the repair is **VISIBLE**. Leave the small selection conditional unless emitted-code evidence shows a problem; add threshold cases at .5/255 and pair changes. |
| `C:603-657` | Four **dependent** palette fetches follow contributor decode: two tint + two response. First optimization: if IDs equal, fetch once per row; if primaryWeight exactly 1 or 0, fetch only contributing rows. Preserve the same quantized RGBA8 palette and packed response decoding; **IDENTICAL (0)** for finite values. Near-endpoint cutoffs are **VISIBLE** without a derivative bound. Alternative uniform palette avoids fetch latency but needs exact emulation of existing UNorm8 quantization and dynamic indexing benchmarking; target **IDENTICAL (0)**, low confidence. |
| `C:633-642` | Premultiplied tint blending then unpremultiplication is intentional. Tiny alpha divides amplify FP error and the zero-alpha fallback differs from tint-map generation. Do not globally replace this by straight RGB lerp. Keep FP32; **VISIBLE** to simplify without alpha constraints. |
| `C:661-681` | `decodeDisplacement` internally calls `decodeSurfaceNormal`, then main calls it again. Share one decoded normal, magnitude and rounded R/G/A codes; **IDENTICAL (0)**. This removes source duplication of unpacking/normalize, but compiler may already share it. No safe `geometryData.a==0` rejection: A stores low displacement bits, not alpha. A B-only sd rejection is the existing valid route. |
| `C:683-711` | Shrink scale clamp/reciprocal and axisLengthSquared are uniform; axis here is horizontal or vertical (`L:687-695`), allowing a coherent specialized axis projection. Preserve line endpoint clamp. CPU inverse/reciprocal changes target **NEAR <=1/255** with high-contrast UV tests. Zero shrink branch already skips the work. |
| `C:713-747` | Existing global dispersion bound chooses 1 backdrop fetch vs 3; do not raise .25. Zero displacement uses texelFetch on Vulkan/Metal to preserve identity. GLES has a sampled fallback. Keep that path: replacing texelFetch by a bilinear sample can change sharp edges. **IDENTICAL (0)** to retain. |
| `C:748-758` | Softening adds 2 backdrop fetches with fixed .5/.25/.25 weights, only in the no-dispersion arm. At appearanceVisibility exactly 0, identical taps could be reused, but bilinear-vs-texelFetch and backend subtexel behavior require **NEAR <=1/255**, not an automatic identity claim. Do not erase softening when visibility merely small. |
| `C:760-791` | Dispersion uses 3 background instructions, not 3+2; the branch skips softening. Preserve this baseline interaction. Red/blue fetches still fetch texture data even if only one component is read. Precompute dispersion multipliers; **IDENTICAL (0)** if same FP32 arithmetic. Setting dispersion to zero globally is **VISIBLE**. |
| `C:793-812` | Direct color path uses 3 gamma powers; gamma=1 specialization removes them. **NEAR <=1/255**, expected 0 for ordinary positive finite SDR inputs. Saturation and subsequent chroma are computed on different colors, so the two chroma min/max calculations cannot simply be merged. |
| `C:813-862` | Plain/tint variants have uniform model shares, tint slider and short side: precompute neutral emission/alpha, face transfer, dark contour multiplier and glint coefficients. Full appearance shares vary; hoist only endpoint constants. **NEAR <=1/255**. Avoid both direct and iOS computations in single-model production variants, but leave mixed-model behavior. |
| `C:863-905` | One luminance gamma power, plus light/dark tint powers when tint alpha>=.001. Keep black/white handling, relative saturation and separate transmittedColor used by the shadow. Gamma=1 is useful; generic polynomial or LUT replacement needs output-error certification. **VISIBLE** if accepted just on average error. |
| `C:907-937` | Coverage is recomputed again; share it, **IDENTICAL (0)**. Visibility is a material/backdrop mix and frost-dependent alpha: setting fragColor=0 whenever visibility=0 is wrong for unfrosted identity glass. Exterior contour remains a separate alpha contribution. Do not use discard in place of transparent output without proving attachment/compositing semantics. |

### GPU vertex, analytic geometry, field geometry, and codec

| File:line | Finding, action, and fidelity |
|---|---|
| `G/geometry_vertex.glsl:1-11` | Only gl_Position and an unused vTexCoord. Linker should remove the varying because fragments use gl_FragCoord. Removing it is **IDENTICAL (0)**, negligible gain; maintain host vertex stride. For these Flutter GPU passes a custom vertex output could carry a field grid affine coordinate, but interpolation rounding can alter cell/codec boundaries: **NEAR <=1/255** gate and usually low gain. Uniform precomputation is safer. |
| `G/geometry_fragment.glsl:1-46` | Shared std140 block includes material arrays unused by geometry. Compiler should drop loads, but reflected layout/CPU packer must remain consistent across all shaders (`N:733-822`). Shrinking a block is not a free per-fragment bandwidth win. FP32 codec requirement is correct. |
| `G/geometry_fragment.glsl:48-66` | Bounds pass traverses all shapes before exact scene pass. Existing squared comparison avoids sqrt and is valuable for sparse/expensive RSE mattes. For one cheap dense RRect, a specialized path without this bounds loop may be faster but must still write zero where support rejects: **IDENTICAL (0)** candidate. Do not disable it for every shape. |
| `G/geometry_fragment.glsl:69-98` | `length(scene.opticalNormal)` is calculated twice; reuse pixelSize, **IDENTICAL (0)**. Material/support alpha is only a support decision, not final alpha. Keep clear zero output. A conservative early `sd>=contourExtent` is only exact where also beyond the material AA fade; establish both limits. |
| `G/geometry_fragment.glsl:100-133` | Refraction mode is uniform; fits/mins depend on per-pixel halfMinor for fused groups. A single-shape halfMinor is uniform, so CPU could derive bevel/amount; **NEAR <=1/255** only after encoded matte + final tests. Quarter-circle sqrt is essential near bevelX=1; a low-degree polynomial is **VISIBLE**. Exact bevelX=0 skip may save sqrt/encode magnitude if branches are coherent; **IDENTICAL (0)**. |
| `G/geometry_field_fragment.glsl:1-38` | Same optical calculation fed by a field, not a place to re-fuse outlines. No shape loop. Shared uniforms contain prepacked field reciprocal texture size already (`N:845-855`). |
| `G/geometry_field_fragment.glsl:39-53` | Exactly 4 nearest RGBA32F fetches and three vec4 mixes. Addresses depend on coordinate arithmetic, not a preceding texture read. Retain clamp and last-cell behavior (grid edge uses cell=size-2, f=1). Hoist reciprocal field step: **NEAR <=1/255** gate. Hardware-filtered 16F discussion below. |
| `G/geometry_field_fragment.glsl:55-83` | All four samples precede rejection. A CPU conservative occupied rectangle/scissor could avoid empty field work **IDENTICALLY (0)** only if still writes/clears every texel later sampled. A coarse occupancy texture adds a fifth fetch and is likely unjustified. Zero-length gradient guard must remain. |
| `G/geometry_field_fragment.glsl:85-111` | Matches analytic bevel/encode block. Share source helper to avoid variant drift, **IDENTICAL (0)** with matching compilation; this is maintainability, not saved runtime work. Do not move halfMinor-dependent optics to CPU globally. |
| `G/displacement_encoding.glsl:1-44` | 12-bit diamond angle + magnitude already avoids trig. Keep highp and nearest. Packing cannot use FP16: integer codes through 4095 are not all representable. Hand bit operations may not compile across runtime GLES variants and need emitted-code evidence; **IDENTICAL (0)** is required for any codec rewrite. |
| `G/displacement_encoding.glsl:46-76` | sqrt companding preserves near-edge precision in B; replacing by linear UNorm changes rim/AA visibly. Encoding sign branch operates before the final shader, but still needs the full pipeline regression. Could share reciprocal ranges, not approximate sqrt. **IDENTICAL (0)** to retain. |
| `G/displacement_encoding.glsl:79-95` | Diamond-to-normal normalize is the only nonlinear decode. Main redundantly decodes it; consolidate (rank 2). Skipping normalization changes refraction direction magnitude and light response: **VISIBLE**. |
| `G/displacement_encoding.glsl:97-109` | **Keep arithmetic step-based sign decode.** `step(0, centered)` is a deliberate Mali Vulkan fix. Never restore ternary here to save multiply/subtract. **IDENTICAL (0)** preservation is mandatory; see compiler section. |

### SDF include

| File:line | Finding, action, and fidelity |
|---|---|
| `G/sdf.glsl:1-27` | Uniforms read globally, avoiding array copies. MAX_SHAPES=16 matches CPU truncation (`L:1556`). No proposal to raise it or copy arrays into locals. |
| `G/sdf.glsl:29-34` | Rounded rectangle is already cheap: abs/max/min and one length. Half-size/clamped radius are uniform per shape. Prepack values if profiling shows loads/ALU remain; **NEAR <=1/255** gate for arithmetic reassociation. |
| `G/sdf.glsl:36-65` | One RSE solve executes six sin/cos pairs + 12 scalar pow, then four more component powers and two sin/cos pairs at endpoints: **16 scalar powers, 8 sin, 8 cos**, before compiler fusion/CSE. Maintain six-step result; fewer steps or implicit-distance substitute **VISIBLE**. The final h/length also influences sign. See optional table discussion below. |
| `G/sdf.glsl:67-119` | Cheap no-radius, cap and degree<2 branches already skip iterative work. Cap test already replaces atan with dot/length using CPU 1-cos(span). Load only chosen octant and delay RSE uniform loads until shape-type branch if emitted code eagerly loads them; **IDENTICAL (0)**, possible occupancy benefit. Replacing both branches with selects may execute expensive RSE unnecessarily. |
| `G/sdf.glsl:121-138` | Ellipse has five Newton iterations plus final sin/cos: 6 pairs. Do not replace with fake ellipse formula: center failure documented. A true-circle specialization to length(p)-r is mathematically exact but not necessarily identical to this bounded solver at every coordinate; **NEAR target <=1/255**, otherwise reject, particularly center and transformed cases. |
| `G/sdf.glsl:140-167` | Shape type dispatch uniform for a loop iteration, coherent across fragments. CPU homogeneous-type pipeline specialization could remove dead solvers and RSE loads; **IDENTICAL (0)** if same SDF retained. High pipeline count/compile cost makes this secondary to culling. |
| `G/sdf.glsl:169-234` | Two gradients serve different purposes. `withExact=false` single-shape path already skips true corner normalization; optical 1.5× radius must remain. Do not replace with dFdx/dFdy. Ellipse center normalize(0) deserves non-finite probes; do not call a change there an optimization with guaranteed identity. Primitive half-size, squared ellipse radii, clamped corner radii, and transformed normal basis can be prepacked; target **NEAR <=1/255** with code-boundary tests. |
| `G/sdf.glsl:236-254` | Angular blend includes sqrt of normal difference and bounds expansion by k. Dot product shortcut `sqrt(2-2*dot)` assumes unit normals; transformed/blended gradients are not unit. Such substitution is **VISIBLE**. Keep current order and smooth-min floor. |
| `G/sdf.glsl:256-276` | getShapeCurvatureFactor has no caller in these shaders. Removing dead source is **IDENTICAL (0)**, zero expected GPU gain. Do not sell it as saved smoothstep. |
| `G/sdf.glsl:278-315,358-396` | Same local coordinate transform appears in distance and gradient paths; explicitly compute once and pass localPoint, **IDENTICAL (0)** if arithmetic unchanged. Compiler may already CSE. Delay RSE payload fetch for non-RSE shapes. HalfMinor/type class are uniform per primitive. |
| `G/sdf.glsl:317-355` | Squared bounds work is cheap; smoothingBudget is completely pixel-independent but summed per fragment. Pack it once (same float32 order), **IDENTICAL (0)** target. Do not replace sum by max: multiple smooth unions can expand cumulatively. An early stop once lowerBoundSquared==0 can preserve the reject outcome if total smoothing budget is separately available; **IDENTICAL (0)**. |
| `G/sdf.glsl:399-429` | Union struct carries curvatureFactor although geometry output no longer reads it. Remove dead member propagation only after reflection/compiler checks; **IDENTICAL (0)**, likely already DCE. Keep the two distinct weights: halfMinor uses k, normal uses angular blend. They are not redundant. |
| `G/sdf.glsl:430-480` | Empty/single-shape paths, uniform shapeCount break, startsGroup semantics and per-shape continue already present. Preserve evaluation order and tie rules (`<` vs `<=`); reordered min can select a different normal/material. Do not globally unroll 16 expensive solvers; benchmark 1/2/4-shape specializations only. New culling must account for smooth expansion and conservative distance scaling. **IDENTICAL (0)** required; approximate spatial dropping **VISIBLE**. |

Additional culling caution: `shapeBoundsDistanceSquared` calls its AABB distance a lower bound on the returned SDF, but CPU scales local SDF by the minimum singular value (`L:1570-1583`). For strongly anisotropic transforms the returned SDF is a conservative distance, not necessarily >= Euclidean distance to the transformed AABB. Audit additional culling proofs against that actual metric, not the comment alone. Example intuition: a long x stretch makes true horizontal distance much larger than min-scale local distance. Keep nonuniform scale/shear fixtures; do not widen existing culling based only on geometric AABBs (`G/sdf.glsl:303,317-333,457-466`). This is a validation risk, not a claimed measured regression.

### Material shaders and include

| File:line | Finding, action, and fidelity |
|---|---|
| `G/material_gradient_fragment.glsl:1-37` | Low-res map already uses 8 device pixels per axis (`N:259,338-351`), roughly 1/64 the matte pixel count. It uses the same SDF to choose ownership. Material shaders lack the explicit highp line used in geometry; inspect emitted Vulkan precision of 1e9 sentinels, IDs and distances before any mediump change. |
| `G/material_gradient_fragment.glsl:39-55` | A 16-way explicit tint lookup chain, while palette-row writes at 67-68 use dynamic uniform indexing already. Test replacing the chain with indexed access or a compiler-friendly switch, **IDENTICAL (0)**. Some Mali compilers lower dynamic indexing poorly; no unconditional recommendation. Gain only in low-res tint pass. |
| `G/material_gradient_fragment.glsl:58-71` | Two palette rows bypass all SDF. Preserve their placement, UNorm quantization and width>=16. Optional CPU palette upload may cost more submission/bandwidth than these few pixels; no likely gain. **IDENTICAL (0)** if same bytes. |
| `G/material_gradient_fragment.glsl:72-94` | Tint pass uses two uniform palette loads, not texture fetches. It blends premultiplied tint and stores straight color plus alpha. Never blindly pre-blend it on CPU: weights vary spatially. Generic float-to-half tint arithmetic target **NEAR <=1/255** only if IDs and geometry remain FP32. |
| `G/material_gradient_fragment.glsl:95-107` | Contributor IDs plus both weight orientations are all used. Do not drop alpha as “unused opacity” or compress to RGB565. **VISIBLE**. Quantized weights and IDs feed final branches, so demand exact IDs even on NEAR color changes. |
| `G/material_tint_gradient_fragment.glsl:1-4` | Include + define is a distinct output pipeline, not duplicate work performed alongside full material. Keep the compile-time split **IDENTICALLY (0)**. |
| `G/material_sdf.glsl:1-31` | Carries halfMinor and curvatureFactor that material output never consumes; optical gradient of underlying SceneSample also unnecessary here. DCE should remove them; slimmer distance+exact-normal+IDs struct is an **IDENTICAL (0)** source optimization with possible register benefit, not guaranteed. |
| `G/material_sdf.glsl:33-82` | Geometry distance and normal remain live to compare groups/cull later shapes. Removing smooth union entirely because final weight uses two distances is wrong. `geometryWeight` and halfMinor/curvature mixes are dead if their fields removed. Preserve nearest-pair update tie behavior. **IDENTICAL (0)** for true dead-code removal. |
| `G/material_sdf.glsl:85-138` | Extra filterReach=2*sqrt(2)*rasterScale protects bilinear weight footprints. Do not borrow geometry's tighter cull and omit this margin. A material outside-mask early-out must include filtered neighbors and palette rows; otherwise seam artifacts. **VISIBLE** to tighten casually. |
| `G/material_sdf.glsl:140-149` | Already returns exactly 1 for equal contributors. Keep this predicate for final-stage palette-fetch reduction. Width reciprocal can be shared where blendWidth constant, but nonlinear ownership remains per pixel. **IDENTICAL (0)** for unchanged calculation. |

### Fake shaders

| File:line | Finding, action, and fidelity |
|---|---|
| `S/fake_glass_shape.glsl:1-27` | Rounded-box SDF is cheap; fake ellipse is already approximate and guarded. Do not substitute it into liquid geometry. Precompute half-size/radius reciprocals only with **NEAR <=1/255** gate. |
| `S/fake_glass_shape.glsl:29-40` | Implicit RSE arc costs six scalar pow operations, not the full iterative solver. Algebra can share p^n to derive p^(n-1) by division and s^(1/n-1) by s-root/s, but tiny p/s and different rounding make this unsafe as a free identity. **VISIBLE unless bounded**, low priority. |
| `S/fake_glass_shape.glsl:42-89` | Replace atan+wrap test with dot(relative,diagonal)>length(relative)*cos(abs(span)) for the legal span interval, with explicit zero-relative/span handling and CPU-computed cosine. Liquid already uses this form but fake currently receives raw spans (`L:1609-1612`). **NEAR <=1/255** target; predicate equality/near-boundary differences must be tested. Not a proof of bit identity. |
| `S/fake_glass_shape.glsl:91-119` | Deep RSE interior already switches to rounded box at -6 pt, blends 4-6 pt. Increasing this region changes bevel distances; **VISIBLE** without an end-to-end bound. Type dispatch is uniform and useful. |
| `S/fake_glass_surface.frag:1-46` | `precision mediump` differs from liquid: on Vulkan it can permit low precision for position/SDF. On Metal/GLES the pinned runtime compiler behavior differs (below). Keep coordinate/SDF highp in any new precision partition. Raising it is a fidelity investigation, not a speed gain. uThickness is declared but unused; deleting it saves no ALU and shifts uniform ABI. |
| `S/fake_glass_surface.frag:48-80` | Analytic normals avoid multiple SDF evaluations. Ellipse reciprocal squared radii and light normalization can be CPU constants. Contour integral width reciprocal uniform. **NEAR <=1/255** target, retain zero guards. |
| `S/fake_glass_surface.frag:82-121` | Normal computed even when no lighting/contour can contribute. Exact support checks can avoid it. Crucially, with exteriorOnly>0.5 final RGB=0 and alpha=exteriorContourAlpha, so branch to a minimal distance+contour(+normal only if directional) path and skip bevel/glint/tint. **IDENTICAL (0)**. Do not return opaque contour RGB; current contour is black. |
| `S/fake_glass_surface.frag:124-171` | Bevel energy, glint width, wrapExponent and normalized light are uniform. Same hoists as liquid. Uniform strength==0 can skip entire bevel; highlight==0 can skip lobe. Use exact zero, not a new epsilon. **IDENTICAL (0)** for skips; CPU scalar hoists **NEAR <=1/255**. |
| `S/fake_glass_surface.frag:173-210` | Face emission compensation and alpha max preserve SDR premultiplication. Do not remove them to match liquid's HDR output. Deep interior with zero contour/bevel/glint can emit original tint exactly (same coverage) without lighting. **IDENTICAL (0)** if all omitted contributions exactly zero. Fake has no texture fetches here, but its separate backdrop filters remain a major cost; optimizing this shader does not remove them. |

## Fetch counts, dependencies, and pressure

Counts are texture instructions per fragment in the source, not memory transactions. Bilinear instructions can access four texels; cache locality and compiler elimination change physical cost. They exclude Impeller's separate blur, snapshot and compositing passes.

| Executable shader/path | Reads before coverage rejection | Surviving no-dispersion/no-soften | With softening | With dispersion |
|---|---:|---:|---:|---:|
| Final plain | 1 geometry | 2 total | 4 total | 4 total |
| Final tint | 1 geometry + 1 material | 3 total | 5 total | 5 total |
| Final appearance | 1 geometry + 2 map + 4 palette | 8 total | 10 total | 10 total |
| Analytic geometry | 0 | 0 | n/a | n/a |
| Field geometry | 4 field | 4 | n/a | n/a |
| Both material generators | 0 | 0 | n/a | n/a |
| Fake surface | 0 | 0 | n/a | n/a |

Outside geometryUV bounds, final variants return before any fetch (`C:524-535`). Rank 1 changes the rejected tint/appearance counts to **1**. Rank 3 can cut a solid full-appearance fragment from 8 to 6 total instructions, or from 10 to 8 with dispersion/softening. Palette addresses depend on map data; backdrop addresses depend on geometry displacement and sometimes sampled appearance visibility. Those serialized read chains matter even if small palette rows live in cache (`C:574-623,678-790`). Computing independent uniform color constants earlier can overlap arithmetic with fetch latency, but the driver schedules the actual instructions.

Register pressure is particularly plausible in full appearance: contributors, filtered weights, two tint vec4s, two response vec4s, model shares, geometry data, screen/matte coordinates and material state overlap (`C:574-657`). Decode/shade one palette endpoint at a time where possible, scope temporaries, and retain only tint/appearance/shares after the block. Reuse normal/coverage; avoid holding redUV/greenUV/blueUV and all samples simultaneously if the compiler does not shorten liveness (`C:760-790`). These changes are **IDENTICAL (0)** when arithmetic order is kept. They can also worsen texture latency hiding, so use register/spill/occupancy reports from emitted shaders, not a count of GLSL variable names.

Geometry carries multiple SceneSample structs across a loop (`G/sdf.glsl:445-479`); material carries even larger structs (`G/material_sdf.glsl:98-137`). Do not add arrays of per-pixel shape samples or fully unroll 16 RSE solves. Existing loop counts are uniform, but per-fragment culling and bisection direction diverge; a small branch/select for the two bisection endpoints may be efficient, while predicating an entire shape solve is not.

## Branches, precision, and numerical limits

### Preserve the Mali regression test in the complete shader

`tool/ios_reference/spec/glass-renderer.md:708-748` documents that a ternary sign decode produced sd=0 for all exterior samples **only when the rest of the final shader remained live**. A minimal decode-only probe compiled correctly. The resulting material alpha=.5 painted filter-sized boxes. Current `G/displacement_encoding.glsl:104-109` uses arithmetic `step`. Keep it even if a compiler report suggests a smaller ternary.

This is not evidence that every ternary is broken. It is evidence that source-equivalent rewrites, register layout and DCE can expose backend faults. After *every* shader change, run complete plain/tint/appearance outputs with B=0, B=127/255, B=128/255 and B=1, and run `example/integration_test/liquid_exterior_test.dart:1-119`. Preserve explicit branches that avoid invalid division/normalization (`C:320,442,639`; `G/geometry_fragment.glsl:96`; fake:138). `mix(a,b,0)` does not sanitize NaN in the unchosen expression. Use finite fixture inputs and separately report non-finite production behavior.

Uniform decisions (dispersion, soften, bevel enable, primitive type per loop, model for plain/tint) generally avoid lane divergence and skip meaningful work. Per-pixel short arithmetic selects can help, but “branchless” is not a goal. Avoid replacing texture-skipping branches with unconditional samples.

### Backend precision is not portable GLSL spelling

The empirical compiler facts in `tool/audit/flutter-tricks-2026-10-05.md:192-245` are the authority for this pinned build:

| Backend | Actual strategy | Protected FP32 domains |
|---|---|---|
| Mali Vulkan runtime stage | `mediump` can survive as SPIR-V RelaxedPrecision; it permits, does not guarantee, FP16 execution. Inspect decorations and the driver result. Runtime discriminator is `VULKAN`. | All coordinates, affine matrices/inverses, sampling UVs, distance/coverage, IDs, packed codes, tiny-alpha division and branch thresholds. |
| Apple Metal runtime stage | Plain mediump compiled to float. Explicit float16_t/f16vecN produces MSL half. Gate extension/types out of GLES and Skia, inspect emitted MSL. | Same domains; HDR glint target can exceed 1 and must retain range. Start with a bounded final color block, not the whole core. |
| Mali GLES runtime stage | Pinned mediump probe emitted highp; explicit FP16 asks for unsupported extensions on common GLES drivers. Leave float. | Same domains; lack of speedup is not a reason to lower coordinates. |
| Flutter GPU bundles | Use `IMPELLER_TARGET_METAL_IOS`, `_VULKAN`, `_OPENGLES` bundle macros, not runtime-stage assumptions. Verify every emitted stage. | Entire geometry/SDF/codec and material IDs stay FP32; sentinel 1e9 overflows FP16. |

Half roundoff for one number near 1 is about 1/2048 maximum rounding error; that is **not** the accumulated shader error. Nonlinear powers, cancellation in contour integrals, unpremultiplication near zero alpha and glint chroma amplification can multiply it. Stage the experiment: only bounded color products/lerps, then independently test transfer functions. Reject any single-block experiment exceeding 2/255 SDR/HDR [0,4]. On iOS also inspect the native wide-gamut/XR result; RGBA8 screenshot equality alone cannot validate HDR clipping.

### Exact special values before generic transcendental approximations

- `pow(x,1)` removal for exact gamma=1 / wrap=.5 is much safer than approximating a variable power (`C:399-401,797-800,864-872`). No epsilon snapping of the exponent. Subnormal/zero cases remain in the test set. Label NEAR <=1/255 until emitted code/device equality proves 0.
- `exp2` of uniform wrap belongs outside per-pixel work. The quarter-circle sqrt and normalize are already cheap relative to SDF pow loops; keep their exact shape response.
- For x in [0,1], dropping exponent a=.90667748 has maximum |x^a-x| at x=a^(1/(1-a)), approximately .036. Multiplying the light-scale amplitude .23940789 still gives ~.0086, or **2.2/255**, before tint powers/lighting (`C:218-224`). Thus even this “near 1” exponent fails a 1/255 premise.
- Replacing x^1.01150514 by x in darkFloor changes that term by about .00036 (<.1/255), but this bounds only that intermediate. Dark tint mix and glint amplification, HDR and output quantization still need final validation. Optional **NEAR <=1/255** isolated trial at `C:230-233`, low expected gain (one scalar power only on dark tint). Do not also replace x^1.85642966 by x² without a separate bound.
- A LUT for backdrop-luminance tint tone needs endpoint handling near zero where derivatives can be steep, and adds dependent reads. A polynomial must bound the **full transfer and final output**, not only least-squares power error. Neither is a recommended unmeasured NEAR change.
- An optional per-shape RSE table exploits the six dyadic steps: 65 endpoint angles on [0,pi/4], spacing pi/256, can hold c^n/s^n; sin²/cos² are shape-independent (`G/sdf.glsl:44-60`). This trades 16 pow + trig for dependent indexed fetches and a new upload per changed degree; 16 shapes × 65 nodes do not fit a tiny uniform block. CPU libm/FP32 differences can alter bisection signs. **VISIBLE until same decision sequence and <=1/255 output are demonstrated**; lower priority than keeping existing cap/cull fast paths. A GPU-built table would add a pass and must amortize across changing geometry.

## Resolution and format bounds

### Geometry matte: retain RGBA8, full resolution, nearest

`N:1033-1044` omits format; `SDK/bin/cache/pkg/flutter_gpu/lib/src/context.dart:177-189` defaults to RGBA8 UNorm and sampleCount=1. This is **not** the iPhone default XR filter format. `G/displacement_encoding.glsl:6-18` splits codes across bytes and `L:1081-1083` requests nearest.

For max displacement M, magnitude quantization alone is <= M/(2*4095). Diamond-angle rounding gives roughly <=1/1024 rad maximum directional error (normalization derivative peaks near the diamond diagonal), hence conservative vector error <=M/1024 + M/8190. At M=180 px, that is about .198 px. These are **existing** errors, not spare error budget. Bilinearly filtering packed G across a nibble carry is not interpolation of displacement; filtering the alpha byte as image alpha is also invalid.

Distance compander: with range R on one side, d=R*t² and normalized-code rounding |delta t|<=1/255, so |delta d| <= 2*sqrt(R*d)/255 + R/65025 away from side/clamp bookkeeping. At d=0 and R=120, the nearest nonzero decoded magnitude is .00185 px. At d=.5 the conservative error is about .063 px. Full-range bound ~2R/255 is much larger deep inside. This explains why changing R, precision, or downsampling shifts narrow AA/rim ramps even when the field looks smooth (`G/displacement_encoding.glsl:46-69,104-109`).

Half-resolution nearest matte introduces up to ~1 physical pixel sample-position error along each axis; refraction and one-pixel contour change conspicuously. Hardware-linear packed matte is corrupt. A decoded multi-channel FP16 matte could be filterable but costs more bandwidth (8 B vs 4 B), changes interpolation and normals, and still needs full silhouette quality. **VISIBLE**, reject as a same-image optimization.

### Field texture: distinguish storage, filtering, and sampling-grid errors

Current field is 16 bytes/node RGBA32F, nearest/manual bilinear (`N:1110-1134`; `G/geometry_field_fragment.glsl:39-61`). RGBA16F halves node upload/storage to 8 bytes and may allow one hardware-filtered instruction instead of four. The query `supportsTextureFormat` does not prove filterability for a usage; require a real sampling smoke render (existing audit:397-409,540-544). Keep a 32F fallback.

For ordinary finite half values, per-node relative rounding <=2^-11. Bilinear interpolation is convex, so interpolation of rounded nodes has absolute error <=maximum corner rounding error, before arithmetic. Example: distances 64-128 logical px have spacing .0625 (half-ULP .03125); multiplied by DPR3 this allows .09375 device px. Deep distances may not change coverage, but sampled gradient errors also rotate the normal and thus move high-contrast refracted content. Gradient component roundoff near 1 can be ~.00049, potentially ~.001-radian normalized-angle perturbations at healthy gradient norm and arbitrarily worse near a saddle. At displacement 180 px this alone can approach .18 px, before codec boundary changes. **No universal 1/255 final-channel bound.**

Hardware interpolation also changes weights. If a device effectively rounds interpolation fractions to b fractional bits, bilinear error can be bounded by `ex * maxHorizontalCornerDifference + ey * maxVerticalCornerDifference`, with ex,ey<=2^(-b-1) for round-to-nearest (use twice that for truncation), in addition to storage error. A 4-logical-pixel SDF grid with axis differences <=4 gives a <=.015625 logical px weight error at b=8, or .046875 device px at DPR3. This is a conditional example, not a claim that every device has 8-bit weights or every supplied field is 1-Lipschitz. Gradients/halfMinor need their own variation bounds.

Experiment ladder: (1) 16F + **same manual 4 taps**, isolating storage error; (2) 32F hardware filtering only where proven supported, isolating filter arithmetic; (3) 16F + hardware filtering. Require packed matte diff, decoded sd/normal/displacement diff and final image diff independently. Maintain exact center mapping `(grid+.5)/allocatedTextureSize`, including bucket padding; do not normalize by logical node dimensions. No mipmaps. A targeted field encoding normalized around its narrow active band could reduce distance rounding but changes upload/decoding and cannot sacrifice halfMinor/gradient precision without proof. Classify all as **VISIBLE until <=1/255 is demonstrated for an admitted domain**.

Coarsening the field grid is not equivalent to changing storage. For a smooth scalar field, bilinear interpolation error is bounded by h²/8 times the sum of sup second derivatives in x/y, but fused seams/medial axes may lack those bounded derivatives. No scene-independent bound is available here. Do not double the existing step and call it invisible.

### Material map: already low resolution

Material maps use RGBA8, 8× down per axis, plus two palette rows for full appearance (`N:259,338-351`). Quantized primaryWeight has <=1/510 error before sampling; multiplying response RGB by 4 turns one-half-code response error into <=2/255 (`C:624-657`). The current response alpha packs model+visibility in a 0..7 range, so decoding thresholds must remain highp. These are existing quantizations; a new float uniform palette changes their behavior unless it reproduces them.

Reducing material resolution further can change **IDs**, not just smooth weights. At a pair switch a one-cell shift can select unrelated tints/models: worst-case 255/255. Increasing it might improve fidelity but raises geometry/material work. Neither is a justified speed fix with a small general bound. Preserve the 8× choice while optimizing full-resolution material consumption.

## Blur, clips, and overdraw

1. **Keep composition order.** `L:1268-1282` does blur then refraction/color shader. Blurring after shader moves tint/rims across the silhouette and does not commute with nonlinear transfer or spatially varying displacement: **VISIBLE**, up to full-channel changes. Reusing one blur across unrelated backdrop stages likewise changes paint-order content (`CLAUDE.md:217-240`).
2. **Small frost is already folded.** `L:698-711` uses the fixed 3-tap kernel for device sigma<=1.25; `C:748-758` implements it. Larger Gaussian is already downsampled by Impeller before full-res re-rasterization (audit:90-112). Raising the cutoff or removing taps has no <=1/255 bound for checkerboard/text; **VISIBLE**. The kernel covariance is [[.5,.5],[.5,.5]] px² at visibility=1: it is diagonal-direction softening, not an isotropic Gaussian. Preserve its existing behavior when comparing optimizations.
3. **Output bucket waste is real.** `lib/src/glass/renderer/internal/snap_rect_to_pixels.dart:20-28` uses 64 px; `L:1251-1258,1289-1294` applies it. A 132×132 px button can cover 192×192 or 256×256 depending on placement, ratios 2.12× or 3.76× before contour padding. Geometry rendering separately rounds dimensions to 64 (`N:304-305,525`); capacity can be larger still, but viewport/scissor already restrict drawing to the active bucket (`N:499-512`). Do not count all allocated capacity as shaded area.
4. **A correction to the older “unfrosted=identical” recommendation:** regardless of whether Impeller supplies a full input texture, this renderer sets `uBackdropBounds` from its own filter clip (`L:1161-1171,1221-1227`). `C:336-349` mirrors refracted samples at those bounds. Shrinking the clip can therefore change unfrosted output too. Preserve the old sampling domain independently of a tighter output domain, and ensure actual input capture supports it; then a **0** difference is expected. Otherwise mark **VISIBLE**. For frost preserve blurred input support, ancestor intersections and the one-texel softening/bilinear margin, not just the outline.
5. **Test 32/16 px output buckets and separate matte active-size from capacity.** The output experiment must satisfy item 4. For analytic matte, drawing true width/height rather than bucket dimensions could save empty pixels while leaving the texture pool bucketed, but changing `uGeometrySize` changes UV quantization/material-map layout. Preserve exact texel mapping and guarantee writes for every sampled texel, including bilinear material edge footprint; **IDENTICAL (0)** is the requirement, not a consequence of merely setting scissor. Current dontCare load (`N:902-908`) makes stale texels a real risk after tighter draws.
6. **Sparse layer rectangles:** distance early-outs save shader work but not allocations, clears or compositing the bounding rectangle. CPU disjoint support draws/tile lists could help changing geometry if output is first deterministically initialized; new clears/draw calls can cost more. Never discard unwritten matte texels with dontCare. Splitting final glass into more BackdropFilters can add full-screen flips and change overlap semantics; do not propose it from shader overdraw alone.

## Synthetic on-device correctness and GPU benchmark design

This is a concrete implementation plan for a subsequent authorized change. None of these files is created by this audit. Ordinary `flutter test` uses the fallback and cannot validate these shaders; `CLAUDE.md:1143-1152` explicitly records that limitation.

### Proposed file layout

```text
tool/shader_audit/
  README.md                         protocol, device locks, frozen baseline IDs
  freeze.py                         copy dependency closure; SHA-256 manifest
  generate_fixtures.py               deterministic bytes, no screenshots/fonts
  run.py                            isolated build/run, backend verification
  compare.py                        channel maxima + failure coordinates/heatmaps
  summarize_gpu.py                  paired timings, confidence intervals
  engine/
    README.md                       pinned engine revision and build procedure
    gpu_timing.patch                benchmark-only Impeller query instrumentation
example/integration_test/
  shader_audit_test.dart             baseline/candidate offscreen correctness
  shader_gpu_bench_test.dart         warm, repeated pass batches; no readback inside
  shader_audit/
    fixture.dart                    typed case model / raw-byte loader
    uniform_layout.dart             checked ABI for final + reflected std140
    runtime_runner.dart             image-filter and direct runtime paths
    gpu_runner.dart                 GPU bundle render targets + readback
    cases.dart                      branch/boundary cross-product
    metrics.dart                    exact/toleranced premultiplied comparison
    gpu_timer.dart                  engine bridge; fails if unavailable
example/test_driver/shader_audit_driver.dart
example/assets/shader_audit/
  manifest.json                     hashes, format, dimensions, seeds, tolerance
  fixtures/*.rgba8                  generated opaque/translucent backdrop bytes
  fixtures/*.f32le                  fixed field nodes, no live CPU fusion
  fixtures/*.json                   uniform float32 bit patterns, shape payloads
  baseline/runtime/*.frag + *.glsl  frozen complete include tree
  baseline/gpu/*.glsl               frozen shaders, distinctly named bundle entries
  candidate/runtime/*              frozen candidate from a specified revision/tree
  candidate/gpu/*
  audit.shaderbundle.json           distinct baseline/candidate entrypoint names
example/build/shader_audit/<run>/   report.json, raw outputs, diffs, gpu.json, traces
```

Runtime `.frag` assets need entries under `flutter: shaders:` in the **harness build's** pubspec; GPU entries must be built into a legacy asset directory like current `hook/build.dart:7-43` and `morph_glass.shaderbundle.json:1-23`. `freeze.py` copies all includes and records root-relative provenance, file hashes and compiler flags; it must not accidentally compile a baseline entrypoint against a candidate shared include. Use a disposable checkout/copy so concurrent production edits cannot alter a run. Do not maintain a permanent second production renderer: frozen copies are test artifacts.

`uniform_layout.dart` names the final's 65 float slots at this snapshot (`L:619-695,1054-1075,1210-1227`), accounts for automatic uSize binding in filter mode, and asserts counts. GPU blocks use reflection as the real renderer does (`N:1174-1203`), not assumptions about std140 padding. Sampler indices: background=0, matte=1, tint/material nearest=2, full-material linear=3 (`L:1077-1095`). Every variant must load successfully; fallback/stub/unsupported is a failure for a requested backend, not a passing skipped comparison.

### Deterministic fixtures

Use fixed Float32 bit patterns for uniforms, little-endian field arrays, integer seed `0x5EED27` with a specified xorshift32 generator (mask to 32 bits each step), fixed sizes and fixed DPR transforms. Commit the generated bytes/hashes; regenerating on a device must not invoke libm with backend-specific results.

Backdrops: black/white; gray ramps; RGB/CMY primaries; 1-, 2-, 4-pixel checkerboards; slanted one-pixel lines; nearest-vs-bilinear impulses; deterministic noise; alpha checkerboard over black and white; an HDR synthetic float ramp up to 4 where supported. No platform fonts, animated images, live screen capture or camera. Sizes 1/2/3 px smoke targets, 31/32/33, 63/64/65, 127/128/129, and realistic 132×132, 512×256, 1080×2400 physical pixel canvases. Tiny targets test margin>extent behavior, not just throughput.

Matte fixtures: explicitly encoded valid byte codes for all 4096 angle bins and all 4096 magnitude bins in manageable sweeps, including nibble/byte carry boundaries; B sweep 0..255, particularly 0/127/128/255. Zero-filled exterior rows/columns; one-pixel support edge; axes, diagonals and alternating normals. Build fixed full-material map fixtures with every 0..15 ID, pairs in both orders, identical IDs, weights 0/1 and adjacent quantization values, palette sentinel colors, a third-pair junction, alpha near 0/.0001/.001, and palette rows immediately next to active map boundary. Use the real nearest/linear sampler split and larger texture capacity with poison bytes outside the valid subrect.

Field fixtures: a plane with known bilinear interpolation, circle/rounded-box samples generated once, fused two-body saddle, tiny/zero gradient, changing halfMinor, clamped border cells, 2×2 minimum field, non-square fields and bucket-padded textures. Distance values adjacent to FP16 exponent transitions, B-compander quantization midpoints, displacement half-code boundaries. These separate field-storage tests from shape generation.

Analytic/material inputs: 0/1/2/4/8/16 shapes; dense and sparse; every shape type; radius 0, tiny, full capsule; exact circles and eccentric ellipses; overlap/tie cases; multiple groups and marker signs; blend zero/tiny/normal; reflected/rotated/nonuniform/sheared transforms. Keep unsupported/degenerate inputs separately classified so undefined behavior does not silently become a loose tolerance.

Uniform sweep: all model codes plus mixed direct/light/dark/clear; slider 0/.5/1 and one representable value either side; visibility 0/1 and intermediate; gamma 1 and values around it; wrap .5 and neighbors; contour width 0/tiny/normal; shadow/highlight strengths 0 and either side of existing cutoffs; shrink absent/horizontal/vertical with endpoint projection; dispersion sign and values just below/equal/above .25/maxDisplacement; soften 0/1 together with dispersion; determinant either side of 1e-6. Translation through pixel and bucket boundaries (including negative), DPR 1/2/3 and a fractional scale, global origins above 2048 px. Use pairwise coverage for broad combinations plus exhaustive sweeps of dangerous thresholds.

### Render every executable variant, then compose it

1. **Runtime isolation:** load baseline and candidate plain/tint/appearance/fake programs simultaneously. Render the final shaders through `ImageFilter.shader` on a deterministic backdrop, with a nonempty clip and fixed transforms; for frozen direct inputs also offer `Paint.shader` into `PictureRecorder` + `Picture.toImage` to isolate shader arithmetic. The filter test is authoritative because uSize, origin, sampler and snapshot behavior differ from a direct paint. Never accept a decode-only result as a substitute for the full program.
2. **Offscreen filter scene:** construct a SceneBuilder with fixed backdrop picture first, fixed clip, then pushBackdropFilter (or the real layer host configured from fixtures) and a nonempty child, then `Scene.toImage(W,H)`. Include a RepaintBoundary-hosted equivalent to exercise the real render-layer hooks. Ensure the captured scene includes the backdrop; a boundary around the glass alone is an invalid test. Give baseline and candidate separate identical scenes at the same origin, not side by side over different coordinates.
3. **GPU isolation:** use the common quad vertex shader plus each of GeometryFragment, GeometryFieldFragment, MaterialGradientFragment, MaterialTintGradientFragment. Allocate fixed-format, sampleCount=1 targets, disable blending, overwrite the entire tested viewport (or clear poison padding deterministically). Submit **one render pass per command buffer**, as `N:529-550` documents nesting faults on Metal/Vulkan. Await completion/readback outside timed sections; keep source textures alive. Read byte data from the resulting image, verifying that packed channels, especially A, are not unpremultiplied/color-managed on the path.
4. **Raw-data transport trap:** geometry A is data, not opacity. Upload frozen packed matte/material bytes through Flutter GPU into explicit RGBA8 UNorm textures (field nodes into RGBA32F), with blending/color conversion disabled, then expose those textures as images for samplers. Do not route data through an image codec that premultiplies RGB by the arbitrary A byte. If `Texture.asImage().toByteData(rawRgba)` does not preserve every byte in an initial known-pattern test, add a readback transport pass that writes each data component into RGB with alpha=1, then read the four tiles; never infer code fidelity from PNGs. Report float field readback separately with an appropriate float target/format, or decode into diagnostic outputs. Compare raw UNorm payloads exactly for IDENTICAL geometry changes.
5. **End-to-end combinations:** baseline final+baseline matte; candidate final+same frozen matte (final-only delta); unchanged final+candidate geometry/material (upstream delta); then all candidate stages. Use both analytic and field mattes, both material variants, plain/blur-composed filter paths, ancestor clips and transformed origins. Shared include correctness follows from these consumers; a utility function is not a standalone shader variant.
6. **Known bug sentinel:** retain a complete nonoptimized final baseline using current arithmetic decode. All-zero matte + nonzero tint/highlight/material palettes must yield transparent output in its fully exterior domain (contour extent >.5). Include the actual exterior test over black on each device. Changing shader liveness can re-trigger the Vulkan fault even when the codec source is unchanged.

Compare baseline against itself first: require zero byte differences over repeated deterministic captures. For each case report maximum absolute error per R/G/B/A, count over tolerance, worst x/y and fixture ID, mean/p99 only as diagnostics, and temporal max across subpixel translation steps. Preserve failure images and raw data. A shader that passes a mean metric but has one bad contour pixel fails its per-channel ceiling. Check alpha/finite values before compositing; also composite over black and white to expose premultiplication errors. Read HDR with `rawExtendedRgba128` (`SDK/.../ui/painting.dart:1882-1892`), account for its alpha representation by converting both captures to the same premultiplied convention, and never clamp before comparison.

### GPU time: real queries, not Dart Stopwatch or FrameTiming

The pinned Flutter GPU Dart API exposes `submit(completionCallback:)`, not a GPU timestamp-query API (`SDK/bin/cache/pkg/flutter_gpu/lib/src/command_buffer.dart:240-248`). Completion latency includes queueing, CPU scheduling and readback; FrameTiming.rasterDuration is raster-thread time, not fragment GPU time. **A stock integration_test alone cannot truthfully produce per-variant GPU execution times.** The harness must either collect external profiler GPU measurements or use a benchmark-only instrumented engine. `gpu_timer.dart` must fail/mark unavailable when timing is absent, never substitute raster time under the GPU label.

Preferred reproducible implementation: apply `engine/gpu_timing.patch` only to a separate checkout of engine a804b26164. Add a small benchmark bridge to set `{caseId, variant, phase}`, enqueue queries around the actual Impeller offscreen render pass, and return completed measurements asynchronously. Carry tags through Dart/UI to raster execution, not a global “current case” flag racing queued work. Hook both Flutter GPU passes and runtime-effect filter passes. Candidate pipelines still use the real Flutter compiler; a separate native shader port is not equivalent.

- **Vulkan / Pixel 6a:** query pool + timestamps bracketing a complete render pass, outside the pass so store/resolve is included. Check queue-family timestampValidBits and timestampPeriod, mask wraparound, read 64-bit results + availability only after fences; reset only retired query ranges. Use valid start/end stages that bound prior work and completion, and report pass duration rather than claiming isolated ALU cycles. The timestamp support/unit rules are in the [Khronos Vulkan query specification](https://docs.vulkan.org/spec/latest/chapters/queries.html).
- **Metal / iPhone:** for one relevant pass per command buffer, collect `GPUEndTime-GPUStartTime` in completion handlers, with labels; this measures command-buffer GPU execution including pass setup/store. Existing submission hook is `E/impeller/renderer/backend/metal/command_buffer_mtl.mm:165-185`. For multi-pass blur/filter buffers use supported counter sampling/pass instrumentation or report the whole chain explicitly. Do not divide a whole unrelated frame's time by glass count. [Apple documents GPUStartTime and its pairing with GPUEndTime](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime).
- **GLES / Pixel 6a forced fallback:** if exposed, `GL_EXT_disjoint_timer_query` TIME_ELAPSED_EXT around the pass on Impeller's actual context; poll availability later, discard intervals when GPU_DISJOINT_EXT is set and require nonzero counter bits. Never create an unrelated GL context for timing this shader. If unavailable, mark GPU timing unavailable and use a profiler supporting this device. The [Khronos GLES extension](https://registry.khronos.org/OpenGL/extensions/EXT/EXT_disjoint_timer_query.txt) specifies asynchronous results and disjoint invalidation.

Instrument at render-pass boundaries, avoiding queries that split tiles into extra stores merely for each draw. Report both `pass_gpu_ns` and `chain_gpu_ns`; the latter for blur/downsample/re-rasterize/final. A standalone final pass with frozen textures is the shader microbenchmark; a real backdrop scene is the compositor benchmark. Include a same-size empty/simple-copy pass as a cost floor, report its absolute value and any subtraction separately. Do not conflate copy baseline differences with measured shader-only time.

Warm every actual pipeline/format/variant with nonempty output (>=4×4 runtime filter, 1×1 GPU smoke pass) and real uniforms. Then for each variant × 132²/512×256/1080×2400 × occupancy 0/10/50/100% × shader branch configuration, run >=60 warm-up batches and >=200 timed samples in >=5 paired ABBA blocks. Geometry/material should be forced to execute for microbenchmarks; separately benchmark cached production behavior. Preallocate targets, fixtures, uniform buffers and readback storage; no uploads, image encoding, screenshot, shader compilation, GC-triggering allocation or Dart printing inside the timed batch. Rotate a small ring of identical targets without overwriting in-flight resources. For tiny passes measure repeated whole passes or repeated draws with identical A/B structure, and label which; tile-local repeated overdraw is not representative of full pass bandwidth.

Store median/p95/p99 GPU ns, bootstrap confidence interval of paired delta, pixels processed, ns/pixel, register/spill data if tooling provides it, driver/OS/GPU, backend, SDK/engine/compiler hashes, source hashes, render formats, query availability, thermal state and observed GPU clock. Benchmark sustained normal clocks; do not compare a cold baseline against a hot candidate. Thermal rejection limits must be predeclared. Confirm promising changes with existing menu/controls frame audit, allocation counts, and idle-frame counters.

### Concrete run interface for the proposed harness

The commands in this subsection describe the files above **after implementation**; they are not commands that exist today. `run.py` should build from frozen revisions/copies, take the documented device lock for the entire session, install the test app, verify backend from startup logs, collect artifacts, and release only its own lock. iPhone lock protocol is `tool/ios_reference/spec/README.md:72-85`; Pixel uses `/tmp/morph-native/pixel.lock` (`tool/ios_reference/perf/audit_android.sh:33-34`). A busy lock means wait, never remove it. No devices were touched by this audit.

```sh
# From morph; baseline/candidate must be explicit immutable revisions/copies.
python3 tool/shader_audit/freeze.py --baseline BASE_REV --candidate CANDIDATE_REV
python3 tool/shader_audit/generate_fixtures.py --verify

# Pixel 6a Vulkan correctness, then forced Impeller GLES correctness.
python3 tool/shader_audit/run.py --device 26221JEGR12737 --backend vulkan --mode compare
python3 tool/shader_audit/run.py --device 26221JEGR12737 --backend opengles --mode compare

# Physical iPhone, preferably an A13/A14-class device as well as the 16 Pro.
python3 tool/shader_audit/run.py --device IPHONE_UDID --backend metal --mode compare

# GPU timings require the pinned instrumented engine outputs, supplied here.
python3 tool/shader_audit/run.py --device 26221JEGR12737 --backend vulkan --mode gpu --engine-config /tmp/shader-engine/android-profile.json
python3 tool/shader_audit/run.py --device 26221JEGR12737 --backend opengles --mode gpu --engine-config /tmp/shader-engine/android-profile.json
python3 tool/shader_audit/run.py --device IPHONE_UDID --backend metal --mode gpu --engine-config /tmp/shader-engine/ios-profile.json
python3 tool/shader_audit/summarize_gpu.py example/build/shader_audit/RUN_DIRECTORY
```

`engine-config` must specify local-engine source path, matching target **and host** artifacts, architecture and pinned revision, and the runner forwards the corresponding Flutter `--local-engine-src-path`, `--local-engine` and `--local-engine-host` options. It must not silently use the stock engine when the custom one is missing. Building that engine is an explicit prerequisite, not something a MethodChannel alone can supply.

Underneath, the stock correctness command is:

```sh
cd example
flutter drive --profile -d DEVICE_ID \
  --driver=test_driver/shader_audit_driver.dart \
  --target=integration_test/shader_audit_test.dart \
  --dart-define=SHADER_AUDIT_MODE=compare \
  --dart-define=SHADER_AUDIT_EXPECT_BACKEND=BACKEND
```

For GPU mode replace target with `shader_gpu_bench_test.dart`, set mode=gpu, and forward the configured local-engine flags. Test bridge returns `reportData`; the driver writes JSON/raw artifact payloads. Profile avoids debug shader/engine timing distortion. iPhone requires the existing signing/developer setup and a physical device, not simulator.

GLES forcing must be real: in the **disposable harness app's** Android manifest set `io.flutter.embedding.android.ImpellerBackend` to `opengles` (the mechanism used in the passport), retain EnableImpeller/EnableFlutterGPU, build/reinstall, then assert GLES in logcat. Vulkan run removes that forced value/sets the supported Vulkan configuration and checks startup. A Dart define named backend does not choose the engine backend. Do not pass `--no-enable-impeller`, which would test a different renderer. Example already opts into Flutter GPU (`example/android/app/src/main/AndroidManifest.xml:32`, `example/ios/Runner/Info.plist:27`).

Current, already existing regression command (with the proper device lock):

```sh
cd example
flutter test -d 26221JEGR12737 integration_test/liquid_exterior_test.dart
# Repeat against the physically connected iPhone device ID.
```

After a candidate passes synthetic tests and GPU timing, run the repository's existing `audit_android.sh` / `audit.sh` from frozen `AUDIT_SOURCE` checkouts with five repeats, liquid tier and appropriate device lock. Compare with `summarize.py`, and preserve the existing pixel/outline work-count tests. Source compilation alone and fallback widget goldens do not close the shader audit.

## Snapshot identification

SHA-256 of the 15 shader files read (before any later concurrent edits):

```text
bf7793b26533f6b00e1f0ed6f21ad4bf609a4ee8434ded745a637f6d7956b59c  S/fake_glass_shape.glsl
df6e9b0ec791dc9856bb45fba5bafd66c5a4293c641e7e661e01b6533044ca9b  S/fake_glass_surface.frag
97ace340a6269158785ff95bc7fb8f8216e947505d78167309b5f8e45789be70  S/liquid_glass_final_render.frag
16915049dfa1b98ca7d748ecae439ca5430f89389ede9a0974c56d7fb4b50912  S/liquid_glass_final_render_core.glsl
3cd597dd2b04a54525264342b4d4158a6a8d066edbe6896c5af564d24e9a64c9  S/liquid_glass_final_render_material.frag
38cdbc9e0e498cd4dbae8b002bda9261ec9798fe788adbc30801080d83770e83  S/liquid_glass_final_render_tint.frag
b908cdf6d5cb8e63ea0ef6b9ff86705bcbe938ffc97682325872732e18d1cfe4  S/render.glsl
92a1b2a1ca0dde6e5f769c6d2c3661dae3c87d247b950b85e560eba86156dd4d  G/displacement_encoding.glsl
62a3da803d401d9f0bde00404aa01d641d889d00b32ac8271d3321a6f2387190  G/geometry_field_fragment.glsl
5e288901fe0990a4ac765bfe2f57325bead9d60171d55a4373277a3c1cdeae54  G/geometry_fragment.glsl
9c688a341c5da32249c4b3b26ed5e28581155fbe435950304c0230396af4480e  G/geometry_vertex.glsl
74c3d8c7c2bb4571e79232812d7abd6ee0c62b134641cf4cec7d8c930da9844b  G/material_gradient_fragment.glsl
275915e8b65bd7f3b23ae88ae5c679f514f2eef539fdfd205870b692623fff9e  G/material_sdf.glsl
f04c2dd5bb998082e904d984ffa8734fa982b085c743adf5746855f02fe46f82  G/material_tint_gradient_fragment.glsl
ba50f647375dc795fd41f88d79183aca4b3b7ba7b52432c827f995a5bd475b28  G/sdf.glsl
```
