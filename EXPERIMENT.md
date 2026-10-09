# Owned source, shared mip producer and optical consumers

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `codex/exp-owned-mip`. Source dependency/checkpoint: `codex/exp-gpu-optical-grid`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Amortize background acquisition/blur across many glass consumers, with cheaper low-resolution blur and fewer optical layers.

## What was implemented

Standalone owned-source fixture compares grouped Gaussian, five-pass pyramid, collapsed three-pass tent and cached output with actual Morph optics. A borrowed-image hook binds the source before consumer paint.

## How to select it

example/lib/perf/mip_stage_bench.dart; MIP_OPTICS, MIP_MODES, MIP_COUNTS and MIP_SHOTS. Production hook remains null.

## What was observed and may be wrong

Common optical layers had a strong controlled-fixture GPU benefit. Fresh pyramids lost presentation to grouped stock Gaussian. Arbitrary live route capture is unresolved, and earlier producer publication was one frame late. These producer/consumer details may be incorrect or suboptimal.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

example/lib/perf/mip_stage_bench.dart; lib/src/glass/renderer/internal/owned_glass_backdrop.dart; tool/audit/codex-shared-mip-report.md; tool/audit/codex-owned-backdrop-optics-report.md

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
