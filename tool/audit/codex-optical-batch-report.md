# Optical filter batching pilot, 2026-10-09

The prototype draws analytic bodies and independent owner field overlays into
one geometry render pass, then uses one optical filter. It does not construct
multiple dependent render passes on one command buffer. Pipeline switches
clear bindings. It is Android-only and disabled by default.

Eligibility requires separate and fused bar components, compatible optics and
appearance except tint, no exterior shadows, equal minor dimensions, disjoint
coverage and a bounded union area. Eligibility also participates in retained
structure invalidation so moving components can fall back safely.

The first native control/candidate comparison was inactive: all 40 sampled
frames retained zero overlays and unchanged optical layer counts. Timing
differences are control spread, not evidence of an optimization. The next
step is rejection diagnostics, followed by an active pixel/cadence comparison.
Original per-component material sampling must be checked before admission.

Evidence: ../ios_reference/perf/2026-10-09-optical-batch. Tests validate
eligibility, fallback on overlap/settings/shadows/sparse bounds, structure
changes and field shift identity. Full verification passed with default flags:
1423 package + 21 example tests, analyze/doc, macOS/AUTODEMO, Wasm.
