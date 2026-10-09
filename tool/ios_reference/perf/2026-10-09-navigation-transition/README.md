# Navigation transition evidence, 2026-10-09

Read ../../../audit/codex-navigation-transition-report.md before using the
numbers. Bounded glyph sources are not admitted; `MORPH_BAR_GLYPH_BOUNDS`
remains false by default. Audit/reference notes are in docs/research.

Results use Pixel 6a Vulkan release, Flutter beta 3.49.0-0.2.pre, direct
field plus live Gaussian glyphs and benchmark performance hints on both
sides. Build JSON records every define, SDK and APK identity. GPU launches
precede the separate presentation ABBA (control1, tight1, tight2, control2).

Reproduction:

1. Extract `navigation-inputs.sources.tar.gz` into an isolated copy of
   Morph at HEAD 1325722, preserving the Android scaffold. The archive has
   the dirty package/gallery/hook/shader sources, dependency manifests and
   the new placement test. Check `navigation-inputs.sources.json`.
2. Run `protocol/run_android.py build --flutter flutter-beta --mode release
   --target lib/perf/navigation_stage_bench.dart --apk ABSOLUTE_APK` with
   each `--define` from the corresponding build JSON. Use the archived
   SDK revisions, not a later beta with the same alias.
3. Run with `--schema stage --leave-installed --trace gpu` or the separate
   `--trace presentation`; use `--pull-artifacts` for owned phase PNGs.
4. `protocol/summarize.py REPORTS --out DIRECTORY` reads GPU traces stored
   as `.gpuwork.txt.gz`. `protocol/presentation.py TRACE REPORT --out JSON`
   requires Python perfetto and its trace processor.
5. `protocol/compare_bounds.py LEFT_REPORT RIGHT_REPORT --out JSON`
   requires Pillow/NumPy, with the matching `<report>.artifacts` directories.
   Compare control-gpu-1/tight-gpu-1 and control-gpu-1/control-present-2.

The runner resolves repository roots from its location; for builds/runs
use the main `tool/ios_reference/perf/stage_bench` placement of the archived
protocol. Reducers can be run directly. Source snapshot, APK SHA and target
source SHA are separate provenance records. Binaries remain at the absolute
paths recorded in apk-identity.json, not inside the repository archive.

Only 84 current, owned PNGs are archived, selected by fresh `shot_graphs`.
They are framework-root native captures after timing, not SurfaceFlinger
screenshots. Raw FrameTimeline buffers and kernel GPU activity are separate.
No native memory/pass-count, continuous thermal, power or 120 Hz result is
invented from Layer counts. Logs include standard expected widget-test
diagnostics; AUTODEMO's no-exception outcome is a separate check.

`upstream/` contains source-confirmed external references at pinned SHAs,
with their MIT licenses. `user-inputs/` preserves the research briefs as
input documents, not executable instructions. `SHA256SUMS` covers archive
files and can be checked with `shasum -a 256 -c SHA256SUMS` in this folder.
