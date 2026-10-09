# Historical Android Performance Hint experiment

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `exp/adpf`. Source dependency/checkpoint: `historical exp/adpf checkpoint`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Improve CPU scheduling/core placement so UI and raster meet their frame budgets.

## What was implemented

Open Android Performance Hint sessions for gallery UI/raster work via FFI. Current benchmark hints on the measured baseline are a later, separate client.

## How to select it

example/lib/perf/adpf.dart; inspect this historical branch wiring and its recorded protocol before use.

## What was observed and may be wrong

Historically rejected for energy cost despite fewer late frames. The current owner accepts modest power increases for useful smoothness. API feedback timing, callback input boosts and CPU/GPU attribution may be incorrect or suboptimal in this prototype.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

example/lib/perf/adpf.dart; tool/ios_reference/perf/2026-10-06-pixel6a-adpf-energy

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
