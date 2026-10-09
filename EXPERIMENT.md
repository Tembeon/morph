# Direct primitive and sampled-field optics

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `codex/exp-direct-field`. Source dependency/checkpoint: `wip/measured-liquid-glass`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Remove geometry target creation and field-to-matte work when the final optical filter can compute or sample geometry itself.

## What was implemented

Add direct single-primitive shading and direct RGBA32F owner-field sampling. CPU tracing and changed sample uploads remain. This is an earlier measured source checkpoint, not every later fix.

## How to select it

MORPH_DIRECT_GEOMETRY or MORPH_DIRECT_FIELD. Defaults false.

## What was observed and may be wrong

Uniform-appearance fields qualify; mixed Navigation tint initially falls back. Earlier direct-geometry builds predated a translation-uniform correction. Lower target count is not proof of lower submission or cadence cost.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

lib/src/glass/renderer/rendering/liquid_glass_layer.dart; lib/src/glass/renderer/shaders/direct_field.glsl; lib/src/glass/renderer/shaders/direct_geometry.glsl; tool/audit/codex-direct-field-report.md

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
