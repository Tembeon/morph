# Historical Dual Kawase / source-cache checkpoint

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `codex/exp-dual-kawase`. Source dependency/checkpoint: `historical a989c13 checkpoint`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Make large blur cheaper than stock Gaussian by using down/up-sampling and reusable source content.

## What was implemented

Preserve the corrected standalone producer experiments, their exact archived source patches and stage measurements. Historical SDK/API state may require rebuilding the harness.

## How to select it

Read tool/audit/codex-dual-kawase-followup.md and tool/ios_reference/perf/2026-10-07-dual-kawase; archived source/patch inputs describe the variant.

## What was observed and may be wrong

Kernel timing alone omits capture, target management, pass recording, submission and optical consumption. These costs and alignment affected the prototypes. A slower implementation does not refute Dual Kawase.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

tool/audit/codex-dual-kawase-followup.md; tool/ios_reference/perf/2026-10-07-dual-kawase

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
