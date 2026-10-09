# Optical filter batching pilot

Beta release, Pixel 6a, three repetitions of enter, nested push/pop and toolbar.
MORPH_OPTICAL_BATCH false/true, MORPH_DIRECT_FIELD true, benchmark Performance
Hints enabled on both sides. Protocol and SDK are in the build manifests.

The candidate did not activate in any of the 40 sampled shot graphs:
optical_overlays is zero everywhere and optical layer counts are unchanged.
These runs cannot support a batching performance or quality claim. Eligibility
diagnostics and an active native comparison remain outstanding. Default off.

The sampled chrome pixels are identical except two pop pixels (max 4/255).
Inputs preserve the exact rendering code built; a later test-only redundant
import removal passed final checks: 1423 package tests, 21 example tests,
zero analysis/doc issues, macOS release and clean AUTODEMO, Wasm.

Fresh phase PNGs and full GPU-work streams remain locally under
/tmp/morph-architecture/optical-batch/results. This compact handoff includes
JSON shot graphs and comparison metrics, not a complete visual trace archive.
