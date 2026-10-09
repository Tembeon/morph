# Historical combined same-frame source checkpoint

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `codex/exp-same-frame-source`. Source dependency/checkpoint: `historical 6c287f1 checkpoint`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Acquire a shared background once, blur it once, and feed the same source through full Morph optics across consumers.

## What was implemented

Preserve combined-source benchmark implementations as final-source.txt and earlier aligned/two-image/fused variants, with capture and submission attribution. Historical SDK state predates later beta fixes.

## How to select it

tool/ios_reference/perf/2026-10-07-combined-source/final-source.txt is the archived standalone implementation; follow its recorded build protocol.

## What was observed and may be wrong

Shared source acquisition and current-frame alignment remain central. toImageSync replays owned content rather than borrowing an already rendered framebuffer. Earlier comparisons/capture alignment may be wrong; inspect corrected measurements.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

tool/audit/codex-combined-source-report.md; tool/ios_reference/perf/2026-10-07-combined-source

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
