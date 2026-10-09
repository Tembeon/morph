# Shared owned source with actual Morph optics

Read ../../../../audit/codex-owned-backdrop-optics-report.md before interpreting
these results. Pixel 6a, beta 3.49.0-0.2.pre, release, Vulkan, 60 Hz. Production
hook is null; this is a uniform-appearance, nonoverlapping, owned-source bench.

native/ contains the valid prepaint parity pilot and final admission GPU run
(N=4/16, three shuffled repeats, 400 ms warm-up / 1200 ms samples) and two
admission FrameTimeline launches (N=16, three repeats, no readbacks). Each
.screens directory contains full native PNGs and physical crop metadata.
Captures occur after all timed windows. JSON readers hash every input they
read. Shader-filter geometry is invalid in the old boundary-toImage captures;
those images are preserved only to diagnose the displaced coordinate mapping.

sources/ archives exact binary inputs. owned-optics-admission corresponds to
the final GPU/presentation binaries. owned-optics-delivered adds a SkSL-only
stub for the unused explicit-LOD probe; its Vulkan code is unchanged. The
compiled example producer bundle and release storage manifest live in assets/.
APK hashes and full Flutter framework/engine identity are in build JSON.
APKs remain in /tmp/morph-architecture; no gallery/stable APK was restored.

diagnostics/ is not an admission cohort. pilot uses invalid offscreen stock
captures. gpu-1 and safe-gpu-1 have native captures but publish the source in
the parent painter, allowing stale images in deeper optical repaint boundaries.
Their dynamic results are rejected. safe-presentation-1 has the same limitation.
owned-optics-batch-gpu-1 crashes before a report; its source is the batch
snapshot, not a complete measured run. Native driver stack and the runner's
timeout are retained. The working harness has no batch mode. Do not combine
diagnostic fresh-source results with the final presentation samples.

engine/ holds installed beta primary source evidence: Vulkan pass construction
begins a scope, deferred encoding ends it, while the public GPU wrapper queues
multiple encodables until submission. Dart source is stored as .dart.txt so it
is evidence rather than a standalone analyzer input. No native engine fix was
built. Verification logs retain normal package/gallery checks and native-only
probe compatibility; numerical/image readers have 22 passing tests.

To reproduce, build lib/perf/mip_stage_bench.dart with flutter-beta in release,
using a variant's exact build JSON defines. Run run_android.py with
--leave-installed; final GPU/quality uses --trace gpu --screen-shots, and
presentation uses --trace presentation without shots. Readers in protocol/
are the final reduction versions. Unpack gzip traces before presentation.py;
GPU summarize.py expects the corresponding .gpuwork.txt beside its report.
Global ../SHA256SUMS covers this evidence, including source snapshots and
native frame/crop pairs. No Apple, live-source, energy, whole-process memory,
arbitrary transform, mixed-appearance or Navigation admission is asserted.

stable-batch-check/ is a 2026-10-09 compatibility follow-up, not a performance
cohort. The archived batching source crashes twice on stable 3.47.2, while
the same source with separate submissions completes twice. Its README and
../../../../audit/codex-gpu-pass-lifecycle-report.md explain upstream lifecycle
limitations, source identity, native stacks and the old publication-order caveat.
