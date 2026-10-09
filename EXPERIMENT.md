# Retained glyph blur atlas

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `codex/exp-glyph-atlas`. Source dependency/checkpoint: `wip/measured-liquid-glass`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Reduce repeated foreground Gaussian passes during bar transitions by preparing reusable blurred glyph levels.

## What was implemented

Cache immutable foreground content, pack seven blur levels (optional dense/reduced variants), interpolate neighboring levels and apply opacity in a sampling shader.

## How to select it

MORPH_GLYPH_BLUR_ATLAS; optional MORPH_GLYPH_ATLAS_DENSE / MORPH_GLYPH_ATLAS_REDUCED. Defaults false.

## What was observed and may be wrong

Raster p95 improved in the measured implementation, but actual presentation worsened. Miss acquisition, publication timing, lifetime and interpolation may be wrong or unnecessarily expensive.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

lib/src/widgets/glyph_blur_atlas.dart; lib/src/widgets/bar_items.dart; tool/audit/codex-glyph-blur-atlas-report.md

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
