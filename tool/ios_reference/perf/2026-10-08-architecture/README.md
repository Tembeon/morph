# Beta architectural experiments, Pixel 6a, 2026-10-08

WIP evidence. Navigation launches use Flutter 3.49.0-0.2.pre, framework 38ec981bad,
engine 774a767348, profile/release arm64 (labeled per artifact), Pixel
26221JEGR12737, Vulkan, dark Navigation,
1x motion, 60 Hz. No stable SDK runs or release APK restoration between runs.
Experiments are disabled by default. No weak-device admission is claimed.
Direct field plus benchmark hints improves timing/presentation at measured
whole-phone power cost; the current glyph atlas fails presentation admission.

Glyph atlas findings: ../../../audit/codex-glyph-blur-atlas-report.md.
Architectural plan: ../../../audit/codex-rendering-architecture-research.md.
Owner research reconciliation and new mip probes:
../../../audit/codex-gpu-research-reconciliation.md.

Common timing runs: actual gallery entry, nested push/pop and toolbar; liquid
and flat; three shuffled repeats, seed 2026100814, warm 500 ms, sample 800 ms.
Action prewarm is on. Frozen native phase images are read after timing, not
used to infer presentation. Build JSON files record exact defines and APK/SDK
identity. Raster/UI/GPU stages overlap and must not be added or subtracted.

Launch order: control-1, atlas-1 (unrestricted), handoff-1 (live clear glyphs),
packed-1 (seven independently padded rows, half-DPR at sigma >=2), control-2,
packed-2, presentation-probe (control), dense-1 (13 rows), presentation-packed,
direct-1 (single primitive final geometry), direct-field-1 (sampled field
directly consumed by the final filter; ongoing).

Sources under sources are snapshots of the architectural variant inputs relative to
HEAD 1325722. APKs remain in /tmp/morph-architecture for ongoing experiments.
All phase comparisons retain per-image SHA-256 and pixel statistics. Only
selected original witness PNGs are stored here; the complete owned phases
remain under /tmp/morph-architecture/results/<name>.artifacts. Do not include
other, older fixture images from those artifact directories in comparisons.

The direct-1 archive records the initial single-primitive probe. A later
translation-uniform fix and the subsequent direct-field experiment are not
part of that binary. Its phase chrome max is 0/255; no robust timing benefit
is established, and this limited scope does not remove fused CPU fields.

FrameTimeline summaries retain raw matched buffers. Is Buffer? is the string
Yes. The reader matches the actual Impeller layer and maps MONOTONIC windows
through trace BOOTTIME clock snapshots. SurfaceFlinger jank flags and
presentation gaps are separate observations. The first presentation probe/packed pair has one repeat each. Later
control/combined/hints/live-glyph launches have three repeats each, still only
one launch per variant; repeat launches remain open.

Reproduce using tool/ios_reference/perf/stage_bench/run_android.py build with
--flutter flutter-beta, --target lib/perf/navigation_stage_bench.dart and the
exact --define values in that variant's build JSON. Run with --leave-installed,
--trace gpu and --pull-artifacts. For presentation, use its separate defines
(liquid only, one repeat, no shots) and --trace presentation. Reduce GPU runs
with stage_bench/summarize.py; reduce presentation traces with presentation.py
and the perfetto Python package. Compare phases with the archived beta-sdk
compare_nav.py, selecting exact control and candidate names.

Current beta checks: 1407 package tests, 21 gallery tests, seven opt-in
contour/descriptor tests, 20 Python reducer/numerical tests, zero analysis/doc warnings,
macOS release and web Wasm builds. Metal autodemo with GPU-field/direct-field
flags finishes with AUTODEMO done and no exception. Actual weak-device,
production fidelity and broader presentation admission remain open.

Later probes: presentation-control-3, presentation-combined-1,
presentation-hints-1, presentation-field-hints-1; sustained
energy-control-1 / energy-field-hints-1 / energy-field-hints-2 / energy-control-2;
gpu-field-hints-1 / cpu-field-hints-1. Details are in
../../../audit/codex-direct-field-report.md. Coarse GPU-grid liquid phase
maximum is 2/255; the first pair shows no robust timing win.

Sustained raw energy traces and larger frame-CPU traces remain in /tmp,
identified by archived SHA-256 files. Their JSON summaries retain provenance,
clock mapping, per-run results and limits. Original frame-cpu traces contain
systrace marker parse failures: scheduling-only summaries exclude every native
slice and report those errors. Their scheduler states cover exact frame phase
intervals. App-only trace frame-cpu-app-hints-2 validates all marker parse failures as
AllocatorVK fractional counters, with no malformed scope markers. Its audited
summary includes native scopes; see the direct-field report and exact reader
flags. release/ contains clean release presentation comparisons and a separate
100 Hz native CPU-stack diagnostic. These are not profile-to-release A/B pairs.
Immediate UI reports avoid the engine's release-mode one-second timing batch;
two candidate/control launches show improved UI/presentation, still over-budget
raster push. CPU samples implicate driver submission/allocation graph work.
Source hashes, exact symbols Build ID and per-action counts are retained.
Protocol snapshots are retained under protocol; source tarballs under sources.
APKs remain available in /tmp/morph-architecture; no release restoration runs.

research/ contains a native mip API color probe and numerical PSF results.
The former confirms mip preservation and medium-quality trilinear runtime
sampling on Pixel/Vulkan. It uses diagnostic readback, not a timing benchmark.
The latter specifies proposed box/tent4 generators, not native-driver behavior.
Neither measures live backdrop capture or claims a new FPS improvement.

shared-mip/ retains the subsequent owned-source producer benchmark, distinct
from those API/numerical probes. It includes a full N sweep with independent,
grouped and cached Gaussian controls; box/tent generators; fixed Vulkan rings;
frozen generator checks and two release FrameTimeline launches. A later matched
cohort tests a three-pass collapsed tent producer. Read
../../../audit/codex-shared-mip-report.md before interpreting GPU savings:
fresh five-pass tent loses presentation to grouped Gaussian, while unchanged
content benefits from reuse with either kernel. No live capture, Navigation
FPS improvement or production adoption is claimed. Source snapshots preserve
the binary inputs; protocol readers represent the final reducer versions.

owned-optics/ extends that fixture with actual Morph material/refraction and
foreground. N=4/16, three repeats, then two actual presentation launches at
N=16. Read ../../../audit/codex-owned-backdrop-optics-report.md: combining
separate layers is the largest cadence benefit; owned cached Gaussian saves
GPU work with <=1/255 frozen error but does not beat common stock cadence.
Fresh pyramids remain slower in presentation. Canonical native screen captures
detect and resolve the parent-painter/repaint-boundary source publication delay.
The archived diagnostics include invalid offscreen captures and a crashing
multi-pass public GPU submission, with installed engine source explaining
deferred Vulkan begin/end scope ordering. No live compositor source or
Navigation/weak-device admission follows. Final builds use the admission
source snapshot; the delivered snapshot additionally includes a web-only
SkSL stub for the unused native LOD probe.
