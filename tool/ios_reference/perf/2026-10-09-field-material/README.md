# Navigation mixed-field evidence

Read ../../../audit/codex-direct-field-material-report.md. The candidate
has no repeatable presentation win and remains off by default.

Pixel 6a, Vulkan, beta 3.49.0-0.2.pre, framework 38ec981bad,
engine 774a767348. All runs use release, direct field, benchmark performance
hints and live foreground Gaussian filters. Exact defines and SDK/binary
identity are in each results/*.build.json and apk-identity.json. APK binaries
remain in /tmp at the recorded paths; source archives allow rebuilding.

Sources:

- inputs-v1: initial full mixed-appearance specialization; tint-only excluded,
  therefore inactive in this fixture. control/candidate-gpu-1 belong here.
- inputs: exact active build inputs. Three new shader specializations include
  the observed fitted tint-only path. control/candidate-v2-gpu-1/2 and the four
  successful presentation launches use these APKs.
- final-inputs: rendering source with the analyzer-required braces repaired.
  post-build-repairs.diff records that semantics-preserving difference.
  Final mandatory SDK checks run on this source.
- protocol: final runner and readers. The runner repair after the first failed
  presentation attempt tolerates recorder expiry and a reused non-Perfetto
  PID. Reuse detection by process name is not a complete PID start-time proof.
  Trace readers must still validate coverage. Unit checks include permission
  failure and recorder exit between probe and signal. Renderer APKs need no
  rebuild for this host-only change.

Rendering source snapshots are a complete source/dependency/shader-input
manifest layered on HEAD 1325722. Protocol scripts and report snapshots are
separate. No SDK or engine changes were made. No unsafe multiple dependent
RenderPass experiment was repeated.

Launch order: initial no-op GPU control/candidate; active GPU control-1 /
candidate-1; failed control-present-1; successful presentation control-3 /
candidate-3 / candidate-4 / control-4; active GPU candidate-2 / control-2.
Each completed launch has three repeats per action. The failed presentation
has only its build/device/log record; it is excluded from reductions.

There are 400 owned frozen PNGs (40 per completed launch). All are copied
from fresh report shot_graphs names. Other stale device files are excluded.
Framework-root captures happen after timing and are not native SurfaceFlinger
screen shots. Pair and repeated-control image comparisons retain all raw
pixel errors. GPU traces and successful FrameTimeline traces are compressed.

Reproduce by placing the archived protocol at the repository's stage_bench
path. run_android.py build with each saved --define, beta, release and
lib/perf/navigation_stage_bench.dart; then run --schema stage --leave-installed
--pull-artifacts --trace gpu or the independent --trace presentation.
Use summarize.py for GPU/FrameTiming; presentation.py for decompressed
FrameTimeline traces with the corresponding report. compare_bounds.py
requires Pillow/NumPy and selects owned images only. The reader rejects
missing/ambiguous real buffer coverage rather than trusting transactions.

Final verification: 1419 package, 21 example and 18 Python tests;
zero analyze/doc issues; macOS release and default-flag Metal AUTODEMO;
Wasm. Earlier timeout failures and the failed Perfetto attempt remain in logs.
No energy, RSS, weak-device or candidate Metal admission is claimed.

Verify this archive with shasum -a 256 -c SHA256SUMS.
