# GPU optical nodes with CPU contour

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `codex/exp-gpu-optical-grid`. Source dependency/checkpoint: `codex/exp-direct-field`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Move optical node calculation and host uploads to a small GPU pass while preserving the owner contour and geometry law.

## What was implemented

For up to four fused rounded boxes, retain the CPU outline but describe grid-relative inputs; compute RGBA32F optical nodes on GPU and retain texture contents across translation.

## How to select it

MORPH_GPU_FUSION_FIELD; compare original matte and optional MORPH_DIRECT_FIELD consumers separately. Defaults false.

## What was observed and may be wrong

Initial native timing showed no robust win. Extra submission, allocation, descriptor reuse and numerical work may offset removed CPU sampling; CPU contour remains. This is not a rejection of all GPU geometry.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

lib/src/widgets/glass_outline.dart; lib/src/glass/renderer/shaders/gpu/geometry_analytic_field_fragment.glsl; lib/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart; tool/audit/codex-gpu-research-reconciliation.md

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
