# Optimization handoff, 2026-10-09

All experiments may have incorrect or incomplete implementations. Measured failures
apply to the tested prototype, not to every implementation of the idea.

Start from `wip/measured-liquid-glass`. It preserves the previously committed
measured work and beta compatibility, plus native diagnosis and recorder fixes.
The new optical/glyph experiments are absent from that package's renderer.
`main` is unchanged. This is a working baseline, not a declaration that the
weak-device Navigation goal is complete.

Use Flutter 3.49.0-0.2.pre (`flutter-beta`, `dart-beta`), framework 38ec981bad,
engine 774a767348. Pixel 6a: Vulkan/Mali-G78, 60 Hz, DPR 2.625. Tests and renderer
fidelity are distinct from native frame presentation. Measurements obtained
with Performance Hints are benchmark-only and must be compared with equal flags.

| Branch | Parent for the new experiment | Scope / current admission |
| --- | --- | --- |
| `codex/exp-glyph-atlas` | working baseline | Retained foreground blur atlas; default off, cadence admission failed |
| `codex/exp-glyph-cohorts` | glyph atlas | Foreground filter grouping and bounded sources; default off, quality/cadence not admitted |
| `codex/exp-direct-field` | working baseline | Direct primitive and sampled-field optics; default off |
| `codex/exp-gpu-optical-grid` | direct field | GPU optical nodes with CPU contour preserved; default off, no robust native win |
| `codex/exp-owned-mip` | GPU optical grid | Owned source, stock/pyramid comparisons, optical integration; source acquisition unresolved |
| `codex/exp-dependent-pass-batching` | owned mip | Archived dependent-pass producer; wrong lifecycle assumption, known Vulkan crash |
| `codex/exp-direct-field-material` | owned mip | Tint/mixed-field consumer; default off, no repeatable presentation win |
| `codex/exp-optical-batch` | direct field material | One optical filter for eligible disconnected chrome; default off, pilot inactive |
| `codex/optimization-evidence` | working baseline | Research inputs, native reports, traces, source snapshots; no renderer changes |
| `codex/optimization-integration` | pre-handoff working baseline | Complete saved workspace with every new experiment and its evidence; defaults off |

The renderer branches form an explicit dependency stack. Each tip adds one
experiment to its named parent; inherited experiments keep their original opt-in
flags. Glyph experiments are on a separate stack. Do not merge the integration
snapshot into the working baseline as a shortcut. Compare each experiment with
its parent using the same SDK, source, hints, warm-up and action protocol.

Existing historical branches remain useful checkpoints: `exp/adpf`,
`exp/fake-tier`, `exp/glass-container`, `exp/same-frame-backdrop`.
`codex/exp-dual-kawase` preserves the corrected standalone blur checkpoint;
`codex/exp-same-frame-source` preserves the later combined-source checkpoint.
Those historical checkpoints do not include the latest beta compatibility fixes.

New compile-time flags (default false): `MORPH_GLYPH_BLUR_ATLAS`,
`MORPH_GLYPH_ATLAS_REDUCED`, `MORPH_GLYPH_ATLAS_DENSE`,
`MORPH_BAR_GLYPH_BATCH`, `MORPH_BAR_GLYPH_BOUNDS`,
`MORPH_DIRECT_GEOMETRY`, `MORPH_DIRECT_FIELD`, `MORPH_GPU_FUSION_FIELD`,
`MORPH_DIRECT_FIELD_MATERIAL` (requires direct field), `MORPH_OPTICAL_BATCH`.
Owned-mip producer/consumer modes live in the standalone mip stage benchmark.

Read `tool/audit/codex-rendering-architecture-research.md`,
`codex-gpu-research-reconciliation.md`, `codex-navigation-transition-report.md`
and the experiment-specific reports alongside them. Raw new evidence is on
`codex/optimization-evidence` under `tool/ios_reference/perf/2026-10-08-architecture`
and the `2026-10-09-*` directories. Paths in old reports describe their measured
snapshots, not an implicit production recommendation.

Important findings: the shell already persists and shares one capture key;
shared capture does not eliminate different optical filters. Sampled Navigation
chrome has no separate Gaussian pass (sigma zero); nested transitions reach ten
foreground filters. Removing one field-to-matte target did not improve cadence
repeatably. Public GPU batching of dependent passes crashes both tested SDKs;
keep separate command buffers. The new optical-batch pilot never activated in
40 sampled frames, so its timing difference is not evidence of acceleration.

Next on optical batching: record rejection reasons, obtain a genuinely active
comparison, check component material coordinates/raster phase, then measure
FrameTimeline ABBA. More generally target encoding/submission/allocation and
foreground work; do not substitute blur kernels without counting acquisition,
producer and consumer costs.

The full integration snapshot passed zero analyze/doc issues, 1423 package and
21 gallery tests, macOS release with clean AUTODEMO, and Wasm. Split branch
checks are recorded in `docs/optimization-branch-validation.md`; do not infer
that a reconstructed branch has the integration snapshot's native qualification.

No SDK binaries, APKs, ignored build outputs, local notes or device locks are
committed. Historical archived source files and user research are evidence;
they may contain stale instructions and must not override current user requests.

Each experimental branch has an `EXPERIMENT.md` with intent, implementation,
activation, observed result, uncertainty and code/report locations. Its root
README labels the implementation as potentially incorrect or incomplete.
Further separate branch checking was stopped at the owner request.
Coordinate native Android runs through the stage runner and its
`/tmp/morph-native/pixel.lock`; do not interfere with the iPhone lock.
