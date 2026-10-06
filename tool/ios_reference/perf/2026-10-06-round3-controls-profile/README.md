# Round 3 evidence (2026-10-06)

Base 84997e1; code commits 36fa94e (flat), 60719c3 (profiler); Pixel 6a 26221JEGR12737, Impeller Vulkan, 60 Hz, portrait.
The APK SHA-256 manifest identifies every archived build used here.
The ordinary controls baseline contains the flat edge fix; this scene
has no edge effect, so the controls renderer is identical to 84997e1.
The liquid/flat profile APKs use the extended menu_frames_test driver,
FRAMES_SCENE=controls, AUDIT_RUNS=3, FRAMES_CPU=true, CPU samples 250 us.
liquid_available is true and there are no CPU/timeline collection errors.
Full VM events, framework blocks and CPU samples remain in the reports.
summary.json retains heavy-frame aggregate CPU samples and phase means.

The coordinate trial patch is rejected, retained as coordinate-candidate.diff
(zero-context patch; apply with git apply --unidiff-zero).
Original/candidate real Impeller host captures are summarized in
host-pixels.json (five cases, both shader variants, maximum error 0).
It was tested against the original renderer, not just another shader
running through the changed renderer.

Sibling directories:

- round3-flat-energy: A/B/B/A, flat-a-1 / flat-b-1 / flat-b-2 / flat-a-3.
- round3-controls-energy: A/B/B/A, controls-a-1 / controls-b-2 /
  controls-b-3 / controls-a-4.
- round3-controls-gpu: one GPU-work launch per original/trial, five runs.
- round3-flat-gpu: one GPU-work launch per flat before/after, five runs.
- round3-flat-bench: five randomized repeats of Material / flat / no edge
  in one APK, seed 20261016; GPU median per run.
- round3-controls-native: baseline ordinary audit, two runs, native atrace
  scene/thread reductions; the manifest tracing change is temporary.

Energy summaries come from perf/energy.py and are reproducible from the
cached .energy.json reductions (the raw Perfetto traces are temporary).
These reductions include CPU frequency, scheduler busy share and thread
placement, not just ODPM rails. Windows are the report's monotonic scene
windows. Starts are below 37 C skin, thermal status 0, AC at 100 percent.

GPU summaries retain per-window values and a SHA-256 of each temporary
kernel trace. reduce_gpu.py uses the same window-overlap weighting as
perf/gpu_scenes.py with a binary frequency lookup. Its controls-a result
was checked against gpu_scenes.py: 5.014 ms / 2.176 Mcycles per frame.
GPU summary weighted values pool the windows; the bench reports median
per-run values separately.

Motion-held device captures are asynchronous: controls resting max 0,
switch max 15, slider max 233. The trial is not claimed identical on the
whole device sequence. This does not affect the landed flat change.

See tool/audit/codex-round3-report.md for the completed verdicts.
