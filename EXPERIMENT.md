# Dependent GPU pass submission batching

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `codex/exp-dependent-pass-batching`. Source dependency/checkpoint: `codex/exp-owned-mip`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Reduce command buffer submission/encoding overhead across dependent blur-pyramid passes.

## What was implemented

Restore the archived producer variant recording several dependent render passes on one public Flutter GPU command buffer. It assumes a lifecycle the installed backends do not provide.

## How to select it

MIP_BATCH=true in example/lib/perf/mip_stage_bench.dart. Default false. MIP_OPTICS selects optical consumers.

## What was observed and may be wrong

This exact approach crashed on tested Vulkan stable and beta builds. The implementation/lifecycle assumption is wrong for those APIs. The result does not disprove safe batching with an engine fix or a different single-pass strategy. Keep the crash reproduction separate from working producers.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

tool/audit/codex-gpu-pass-lifecycle-report.md; archived owned-optics-batch source and crash evidence on codex/optimization-evidence

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
