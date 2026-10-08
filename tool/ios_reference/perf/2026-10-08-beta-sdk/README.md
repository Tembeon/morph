# Beta SDK experiment provenance

Source base: f3cb00a4f8dd3336aa5ede796c55314ffa3ecf32.
`compatibility.patch` contains the production sampling fix. `inputs/sources.json`
hashes the final library/shaders/hook and Navigation harness. SDK records
include full framework, engine and Dart revisions. Input locks preserve
the SDK-pinned dependency changes. Verification logs use ASCII escapes
for non-ASCII diagnostic separators.

The SDK is installed permanently at `/Users/tembeon/.local/share/flutter-beta`.
`/opt/homebrew/bin/flutter-beta` and `dart-beta` point into it; ordinary
Flutter/Dart commands still select stable. Check with a new login shell:

```sh
flutter --version
flutter-beta --version
dart-beta --version
```

Use separate checkouts and resolved package configurations. The runner
records the selected SDK with each APK and restores the installed gallery
around every device launch:

```sh
python3 tool/ios_reference/perf/stage_bench/run_android.py build --flutter flutter-beta --target lib/perf/navigation_stage_bench.dart --apk /tmp/morph-beta/nav.apk --define NAV_MODES=flat,liquid --define NAV_MOTIONS=enter,nested-push,nested-pop,toolbar --define NAV_PAGES=navigation --define NAV_RUNS=5 --define NAV_WARM_MS=500 --define NAV_SAMPLE_MS=800 --define NAV_SEED=2026100811 --define NAV_SHOTS=true --define NAV_SHOT_OFFSETS=0,160,420,640
python3 tool/ios_reference/perf/stage_bench/run_android.py run --apk /tmp/morph-beta/nav.apk --out /tmp/morph-beta/results --name beta-nav --trace gpu --pull-artifacts
```

Omit `--flutter flutter-beta` in the stable control checkout. Actions save
frames 0, 1, 4, 10, 20, 34, 48; NAV_SHOT_OFFSETS selects scroll positions
only and does not change these action frames. Reports distinguish the
initial beta's nearest-sampling regression from corrected-beta controls.

`paired-gaussian.patch` is an isolated beta-only research patch against
the base stage harness. Apply it only in a disposable checkout, then build:

```sh
python3 tool/ios_reference/perf/stage_bench/run_android.py build --flutter flutter-beta --apk /tmp/morph-beta/gaussian.apk --define STAGE_LAYOUTS=single,large --define STAGE_MODES=blur,exact,paired --define STAGE_SIGMAS=2 --define STAGE_RUNS=5 --define STAGE_SHOTS=true
```

The Gaussian's three-sigma reference is mathematically paired, not
calibrated to Impeller's downsampled/truncated native kernel. Pixel errors
against stock are retained; neither custom mode passes the appearance or
whole-chain GPU gate. Native shots occur after timing collection.

`input-probe.patch` replaces that patch with a byte-encoding probe of the
second runtime pass's input dimensions. Its successful beta-input-v2 build
record preserves the defines (input only, one run, 300 ms warm-up, 800 ms
sample, shots enabled). All six decoded phases return 1082 by 2402 on the
1080 by 2400 screen. This dimension probe is not a performance candidate.
The initial probe launch rejected an unsupported mode after a patch
application failed; its restoration notes/log are retained separately.

`input-screen-probe.patch` adds a separate displayed-frame check: input
mode keeps its last scene after writing the report and the temporary runner
captures it with Android exec-out screencap before restoring the gallery.
It disables Flutter phase PNGs and selects only the small region. The
existing displayed frame also encodes 1082 by 2402; raw screen PNG and
input-screen-sizes.json preserve the independent decode. The temporary
capture hook is research-only, not part of the production runner.

`results` retains raw timing JSON, exact build inputs, device/backend
notes and compressed streamed GPU events. `compatible-summary` and
`gaussian-summary` are reproducible with stage_bench/summarize.py.
Frame/GPU windows, event attribution and missing-frequency rules are
the existing runner/reducer protocol. Timings are not presentation FPS.

Pixel JSON retains SHA-256 hashes and whole-frame/chrome error metrics.
`compare_nav.py` accepts a results directory, baseline/candidate launch
names and an output path. The second corrected-beta Navigation PNG set
was pulled by Gaussian launch 1 after Navigation launch 2 had saved it;
no intervening Navigation benchmark wrote those filenames. All native
PNGs were analyzed before disposable captures were cleaned. The contact
image is a small retained witness of the initial SDK regression.

`manifest.json` hashes the evidence. No APKs, SDK binaries, cache trees
or unrelated pre-existing device captures are stored in Git.
