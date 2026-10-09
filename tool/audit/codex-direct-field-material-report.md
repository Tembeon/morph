# Mixed-appearance direct field experiment

2026-10-09, Pixel 6a, Impeller Vulkan, release arm64, 1080 x 2400,
DPR 2.625, 60 Hz. Flutter beta 3.49.0-0.2.pre, framework 38ec981bad,
engine 774a767348. This experiment is not admitted for production.
MORPH_DIRECT_FIELD_MATERIAL remains false by default.
Evidence: ../ios_reference/perf/2026-10-09-field-material.

## The observed fallback

The earlier Navigation graph census showed fields but direct_field=false
with MORPH_DIRECT_FIELD=true. The new release census also records mixed
appearance and tint-only specialization. In nested push/pop the fused
body is mixed solely by tint in the sampled phases; it retains a uniform
visibility/color response. Different visibility was an initial hypothesis,
not the observed reason in this fixture.

The first prototype supported the full contributor map only and excluded
tint-only layers. Its candidate therefore never activated in Navigation;
its timings are a negative control, not evidence of an optimization.
The revised prototype adds direct, fitted and full mixed specializations.
On sampled nested-push phases 0,1,4,5,6,8,10,20 the fused layer now reports
direct_field=true; settled phases 34/48 have no field. The original separate
shapes and other optical layers retain their old paths.

## What changes

The final ImageFilter shader reads the same RGBA32F optical nodes through
Flutter GPU Texture.asImage. The CPU contour, node sampling, interpolation,
pixel snapping, RGBA8 companding and material contributor/tint map are
preserved. The mixed geometry path skips its full-resolution matte allocation
and draw; the existing lower-resolution material draw remains. Texture rings
and retained image ownership follow the existing lifetime rules.

This removes a field-to-matte draw and target, not an optical backdrop layer.
It does not merge independent glass bodies. Changed CPU samples still need
a copy/upload command buffer; removing the draw does not necessarily remove
a submission on those frames. No framebuffer capture, toImageSync, blur
replacement, intentional frame delay, physics or default flag changes.
The new full mixed-color specialization compiles but this fixture qualifies
only the fitted tint specialization. Default-flag Metal autodemo is a
baseline integration check, not candidate Metal admission.

## Native image evidence

Each current report owns 40 frozen framework-root captures, taken after
all timed windows. Only shot_graphs-named PNGs are compared; old files on
the phone are excluded. These are not SurfaceFlinger screen captures.

The first active GPU pair has identical enter and toolbar chrome. Nested
chrome is mostly exact, with remaining <=2-channel differences plus four
isolated pixels above 2 across the matrix, maximum 10/255. Repeated controls
in the presentation cohort themselves have 14 chrome pixels above 2 and a
maximum 18; candidate repeats have 23 and maximum 18. Presentation pair
comparisons have 21/16 such pixels and maximum 11/18. Raw differences are
retained. No systematic material/glyph error appears in this limited matrix;
this is not a universal exact-pixel guarantee or admission of arbitrary
colors, transforms, text scales and cancellation scenarios.

## GPU and FrameTiming

Two launches per side, three repeats per launch; active version order
control-1, candidate-1, candidate-2, control-2. Separate presentation launches
occur between GPU launches. Both sides have identical benchmark performance
hints and direct-field flag; glyph cohorts and glyph atlas are disabled.
Launch medians, GPU ms/frame:

| Action | Control 1 / 2 | Candidate 1 / 2 |
|---|---:|---:|
| Enter | 5.105 / 5.126 | 5.108 / 5.051 |
| Nested push | 6.274 / 6.169 | 6.158 / 6.166 |
| Nested pop | 5.585 / 5.618 | 5.600 / 5.569 |
| Toolbar | 4.367 / 4.394 | 4.355 / 4.389 |

The first push GPU difference is about 1.8%; the reverse-order difference
is about 0.05%. It does not establish a repeatable GPU win. Push raster p95
is 20.60/22.24 ms in control and 21.58/20.17 in candidate; both exceed the
16.67 ms deadline. UI and raster tails vary by launch. GPU time overlaps
other work and cannot be subtracted from raster duration as a serial stage.

## Actual buffer presentation

Independent FrameTimeline ABBA: control-present-3, candidate-present-3,
candidate-present-4, control-present-4. Three 800 ms windows per action
per launch. The reader validates clock mapping, one actual Impeller surface,
unique buffer tokens and display mapping. Transactions alone do not count.
Median missed display intervals per launch:

| Action | Control 3 / 4 | Candidate 3 / 4 |
|---|---:|---:|
| Enter | 2 / 6 | 5 / 4 |
| Nested push | 6 / 7 | 3 / 9 |
| Nested pop | 3 / 3 | 5 / 6 |
| Toolbar | 1 / 2 | 1 / 1 |

Push improves in the first pair and worsens in the second; pop worsens in
both. Pooling six repeats gives control/candidate push 6.5/7 and pop 3/5.
This candidate has no repeatable presentation improvement. Windows omit
before-first/after-last gaps, so these are not complete input-latency values.
No new energy, RSS, cold-launch or weak-device measurements were collected.

The first presentation attempt ended with an expired owned Perfetto process
and failed before pulling its trace. It is not used. The runner now tolerates
recorder expiry and a non-Perfetto reused PID, preserves the output, and
still propagates permission/stop errors. Readers independently validate trace
coverage; tolerating expiry does not make a partial trace acceptable.
Four regression checks exercise these recorder conditions.

## Research and next experiment

The installed clean beta engine source confirms per-draw ShaderMetadata
allocation and binding replay in lib/gpu/render_pass.cc:292-319. The primary
[allocation issue](https://github.com/flutter/flutter/issues/190396) and
[binding-set proposal](https://github.com/flutter/flutter/issues/190397)
describe the engine-level costs. They do not quantify our small draw count.
A pipeline-state memoization optimization is already present in this SDK;
reimplementing it in Morph would not remove the remaining binding copies.

[The mixed-pipeline binding report](https://github.com/flutter/flutter/issues/192396)
identifies stale bindings across bindPipeline; clearBindings exists in this
beta. Any future single-pass atlas with different pipelines must clear and
rebind resources. This prototype uses separate passes and does not switch
pipelines within a pass.

[Arm's subpass analysis](https://developer.arm.com/community/arm-community-blogs/b/mobile-graphics-and-gaming-blog/posts/vulkan-subpasses-the-good-the-bad-and-the-ugly)
explains that reducing memory traffic can leave speed unchanged or worsen
scheduling on older Mali. It supports measuring the tradeoff, not predicting
an FPS improvement for Pixel. The old [contiguous backdrop proposal](https://github.com/flutter/flutter/issues/131568)
is closed; the installed canvas.cc:1977 already shares a filtered snapshot
when a capture key's filters are equal. Our distinct optical shaders are
not equal, so sharing their source alone does not trigger that shortcut.

Next useful work is actual optical-filter consolidation with preserved local
field/material coordinates, and frame CPU attribution of submission waits
versus running work. Removing this one geometry target was too small an
intervention to settle the fundamental cost. Per-frame whole-route snapshots
and unsafe dependent passes in one Flutter GPU command buffer remain poor
substitutes for a measured source/ownership design.

## Verification

Final beta analyze and dartdoc: zero issues/warnings. 1419 package tests,
21 example tests, 18 Python stage/trace tests; macOS release, default-flag
Metal AUTODEMO done without exceptions, and Wasm build passed. An earlier
package run had long-gap timeouts and failed; it is preserved rather than
reported as successful. The final full rerun passed. Android candidates
compile all three new shader specializations. No commits or SDK changes.
