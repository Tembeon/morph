# Tint and mixed-appearance direct field

**Exploratory implementation - may be incorrect or incomplete.**

Implementation may be incorrect or incomplete. Results describe this prototype and its measured setup; they do not prove that the underlying approach cannot work. Recheck algorithm, coordinates, lifecycle, acquisition cost and measurement before drawing that conclusion.

Branch: `codex/exp-direct-field-material`. Source dependency/checkpoint: `codex/exp-owned-mip`.
This is a handoff of a prototype, not a production admission. Separate branch
checks were stopped at the owner request; see the branch validation document.

## What we wanted

Make direct field sampling apply to actual Navigation fused bodies whose appearance differs by tint, while retaining per-contributor material.

## What was implemented

Read owner field nodes directly and retain the lower-resolution tint/material map, skipping the geometry matte. This branch inherits the GPU/owned-source research stack but those paths can remain disabled.

## How to select it

MORPH_DIRECT_FIELD=true and MORPH_DIRECT_FIELD_MATERIAL=true. Other experimental flags false for the isolated comparison.

## What was observed and may be wrong

Limited native chrome comparison was acceptable, but FrameTimeline ABBA did not improve repeatably. Uploads and optical filter count remain. Coordinate mapping, target reuse or work attribution may still need correction.

Compare against the parent/control with equal SDK, source, warm-up and flags.
Before interpreting a result, establish that the intended path actually ran.
Check acquisition, producer, material/foreground consumers and native
presentation together. Existing frozen snapshots may contain stale instructions.

## Where to continue

lib/src/glass/renderer/shaders/liquid_glass_direct_field_tint.frag; lib/src/glass/renderer/rendering/liquid_glass_layer.dart; tool/audit/codex-direct-field-material-report.md

The global map is `docs/optimization-handoff.md`; raw research is on
`codex/optimization-evidence`. Dependencies are explicit source stacks, not
a recommendation to enable every inherited experiment simultaneously.
