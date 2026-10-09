# Historical glass grouping prototype

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `exp/glass-container`. Source dependency/checkpoint: `historical exp/glass-container checkpoint`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Share optical/capture work across resting neighboring controls while preserving paint ordering and content barriers.

## What was implemented

Preserve container participation and fallback logic for opacity, clips, filters and viewports. Later measured container work exists in the working baseline.

## How to select it

lib/src/widgets/glass_container.dart; lib/src/widgets/glass_channel.dart.

## What was observed and may be wrong

Participation and z-order rules may be incomplete or incorrect. Historical tests do not establish that arbitrary nested content can safely share one optical layer.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

lib/src/widgets/glass_container.dart; test/glass_container_test.dart

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
