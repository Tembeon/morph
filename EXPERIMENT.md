# Glyph filter cohorts and bounded sources

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `codex/exp-glyph-cohorts`. Source dependency/checkpoint: `codex/exp-glyph-atlas`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Reduce foreground filter count and filtered source area without changing hit targets, layout or measured motion.

## What was implemented

Group compatible neighboring glyph draws in a render stack; separately allow intrinsic content boxes for filters. The inherited atlas remains optional and must be disabled for cohort comparisons.

## How to select it

MORPH_BAR_GLYPH_BATCH or MORPH_BAR_GLYPH_BOUNDS, one at a time; MORPH_GLYPH_BLUR_ATLAS=false. Defaults false.

## What was observed and may be wrong

The narrow cohort opportunity reduced some filter counts but had native glyph differences and no robust cadence win. Bounded sources also lacked a presentation win. Compatibility and raster phase may be incomplete.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

lib/src/widgets/bar_glyph_filter.dart; lib/src/widgets/bar_items.dart; tool/audit/codex-glyph-cohort-report.md; tool/audit/codex-navigation-transition-report.md

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
