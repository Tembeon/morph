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
python3 $D/run.py <serial> /tmp/nav/base.apk /tmp/nav/moto-base --gpu   # + kernel GPU work periods (gpuwork.txt, device.txt)
python3 $D/gpu.py /tmp/nav/moto-base                                     # GPU active ms and Mcycles per frame, per case
python3 $D/compare.py a=a1.json,a2.json b=b1.json,b2.json                # variants over launches: p95s, missed slots, worst frame
```

- `ARCH` is `arm` for 32-bit-only devices (Redmi 6A), `arm64` otherwise.
- Skia (Redmi): an install wipes the engine's compiled GL programs
  (code_cache), so the first run after it compiles every program it meets
  (200 - 1150 ms frames on the PowerVR). For steady-state numbers run once
  to install and warm, then again with `--no-install`.
- `NAV_MODES=flat` is required where liquid glass is unavailable (Skia).
- `slots_missed` in `summ.py` counts vsync slots between consecutive frames
  inside each window (gaps over 200 ms excluded): an estimate of dropped
  frames, not Android presentation jank.
- `run.py ... --real` with a bench built with `NAV_REAL_INPUT=true`: push
  and pop start from real input the runner injects (`input tap` on the
  message row, `input keyevent 4` for back) when the bench logs `NAVTAP` /
  `NAVKEY`, so they get the platform's input boost like a user's touch;
  the window starts at the input. Synthetic callbacks get no boost, and on
  the Moto the GPU then runs 265 - 1047 MHz window to window even in fixed
  performance mode.
- `run.py ... --60` launches with `morph-frame-rate 60` (MainActivity sets
  the window's maximum refresh rate); the system minimum must allow it.
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
