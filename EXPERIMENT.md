# Disconnected chrome optical batching

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `codex/exp-optical-batch`. Source dependency/checkpoint: `codex/exp-direct-field-material`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Reduce independent optical filters and geometry targets by batching compatible disconnected components of one bar.

## What was implemented

Draw analytic body geometry and owner field overlays in one geometry render pass, then use one optical filter. Preserve original fields; gate on compatible optics, appearance, bounds and shadows.

## How to select it

MORPH_OPTICAL_BATCH; first pilot used MORPH_DIRECT_FIELD=true on both control/candidate. Defaults false.

## What was observed and may be wrong

Pilot did not activate in any of 40 sampled phases. No speedup or native batching quality is established. Eligibility may be overly restrictive or incorrect; material sampling coordinates and raster phase need active validation. Multi-draw implementation has not been natively qualified by this inactive run.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

lib/src/widgets/glass_liquid_draw.dart; lib/src/glass/renderer/internal/flutter_gpu_geometry_renderer_native.dart; test/glass_optical_batch_test.dart; tool/audit/codex-optical-batch-report.md

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
