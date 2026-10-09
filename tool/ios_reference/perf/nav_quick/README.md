# Quick navigation bench loop (Android, adb)

Lightweight tools used for the 2026-10-09 navigation work on a Redmi 6A
(Skia, 32-bit) and a Moto g86 power (Impeller Vulkan). Unlike
`stage_bench/run_android.py` they take no device lock, keep no backup of an
installed gallery and do not restore it: they install the bench APK over
whatever is there (`adb install -r -d`). Use them on test devices only, and
reinstall the gallery afterwards.

```sh
D=tool/ios_reference/perf/nav_quick
$D/build.sh /tmp/nav base arm --dart-define=NAV_MODES=flat --dart-define=NAV_MOTIONS=enter,nested-push,nested-pop,toolbar
python3 $D/run.py <serial> /tmp/nav/base.apk /tmp/nav/redmi-base            # report + logcat
python3 $D/run.py <serial> /tmp/nav/base.apk /tmp/nav/redmi-trace --cpu --skia  # + Dart timeline/CPU samples, Skia trace events
python3 $D/summ.py /tmp/nav/redmi-base.json /tmp/nav/redmi-new.json      # median over repeats, A -> B
python3 $D/enc.py /tmp/nav/redmi-trace.timeline.json [--all]             # raster frames: duration, render passes, top Skia events
python3 $D/uiframes.py trace.timeline.json trace.cpu.json 12             # inclusive Dart CPU profile of UI frames > 12 ms
python3 $D/cpu.py trace.cpu.json                                         # whole-run exclusive / inclusive profile
```

- `ARCH` is `arm` for 32-bit-only devices (Redmi 6A), `arm64` otherwise.
- `NAV_MODES=flat` is required where liquid glass is unavailable (Skia).
- `slots_missed` in `summ.py` counts vsync slots between consecutive frames
  inside each window (gaps over 200 ms excluded): an estimate of dropped
  frames, not Android presentation jank.
- `run.py ... --hz` asks MainActivity (`morph-max-refresh`) for the panel's
  highest refresh rate; the Moto still held the app at 60 fps.
- The VM timeline is a ring buffer: trace one motion with `NAV_RUNS=1` and
  `NAV_MOTIONS=nested-push` to keep its frames.
- `NAV_KEEP_APP=true` repeats a nested push in one app (pop, push again)
  instead of remounting the gallery per run.
- `NAV_TRACE_TICKERS=true` logs the tree per run, live tickers every
  250 ms (`LIVE`), the start stacks of tickers still running 1 s into a
  window (`TICKER`) and who requested frames (`SCHED`). Diagnostics only:
  it slows the windows.
- Moto g86 at 120 Hz: `adb shell settings put system min_refresh_rate 120`
  (restore 60.0); `cmd power set-fixed-performance-mode-enabled true` for
  steadier clocks (restore false). Synthetic actions get no touch boost.
- Keep the phone on a direct USB port with Stay awake on; a hub dropped the
  Moto mid-run.

Reference results of that session are in `../2026-10-09-nav-glyph-blur`.
