# Historical shared same-frame backdrop prototype

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `exp/same-frame-backdrop`. Source dependency/checkpoint: `historical exp/same-frame-backdrop checkpoint`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Avoid repeated background acquisition and share native Gaussian and Morph optical input in the current frame.

## What was implemented

Preserve the earlier current-frame owned source benchmark and image/texture surface probes. Later owned-mip implementation is in codex/exp-owned-mip.

## How to select it

example/lib/perf/glass_stage_bench.dart; inspect recorded STAGE_* selections.

## What was observed and may be wrong

Capturing source, rendering/capture coordinate alignment, invalidation and frame publication may be incorrect. This version is not a proven way to borrow the Flutter compositor framebuffer.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

example/lib/perf/glass_stage_bench.dart

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
