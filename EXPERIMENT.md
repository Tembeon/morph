# Historical fake glass and outline prototype

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `exp/fake-tier`. Source dependency/checkpoint: `historical exp/fake-tier checkpoint`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Provide a cheaper visually similar material where full liquid optics are too expensive.

## What was implemented

Preserve the fake-tier prototype, including union clipping and menu/button fusion behavior; compare it with later baseline work rather than assuming this checkpoint is current.

## How to select it

lib/src/glass/renderer/rendering/liquid_glass_layer.dart; lib/src/widgets/glass_liquid_native.dart.

## What was observed and may be wrong

Approximation, clipping, boundary sampling and material quality may be wrong. This older snapshot is not a blanket recommendation to reduce fidelity or proof about the best achievable fake material.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

lib/src/glass/renderer/rendering/liquid_glass_layer.dart; lib/src/widgets/glass_liquid_native.dart

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
