#!/bin/sh
# Frame timings of the glass audit on an Android phone, per glass tier.
# The Android twin of audit.sh: same app, same report, summarize.py reads both.
#
#   AUDIT_STEP=build|run|all      build the profile APKs, run them on the phone, or both (all)
#   AUDIT_TIERS="liquid frosted flat"   (auto = the adaptive governor picks)
#   AUDIT_RUNS=5                  timed repeats of every scene inside one launch
#   AUDIT_LABEL=pixel6a           names the result directory <date>-<label>
#   AUDIT_APPS=<dir>              where the built APKs are kept between the steps
#   AUDIT_SHOTS=<dir>             where the screenshots are pulled (not committed)
#   AUDIT_SERIAL=<adb serial>     default: the owner's Pixel 6a
#   AUDIT_SOURCE=<checkout>       the tree to build (a git worktree at a fixed commit keeps
#                                 other agents' uncommitted edits out of the numbers)
#   AUDIT_TARGET=<test file>      default integration_test/glass_audit_test.dart
#   AUDIT_REPORT=<name>           the report directory name, default glass
#   AUDIT_DEFINES="..."           extra --dart-define flags for the build
#   AUDIT_ARCH=android-arm        target platform (32-bit phones); default android-arm64
#   AUDIT_COLD=1                  pm clear before every launch: a cold pipeline cache
#   AUDIT_SUFFIX=<s>              appended to the tier in the APK and result names
#   AUDIT_GPUFREQ=1               sample the Mali GPU clock (cur_freq) twice a second while
#                                 the app runs: <tier>.gpufreq.txt, a histogram in device.txt
#   AUDIT_COOL_C=38               before every launch wait until the skin sensor
#                                 (VIRTUAL-SKIN) reads below this many degrees C
#   AUDIT_GPUWORK=1               record the kernel's per-app GPU work periods
#                                 (power/gpu_work_period, power/gpu_frequency) on the
#                                 CLOCK_MONOTONIC trace clock while the app runs:
#                                 <tier>.gpuwork.txt (tool/audit/shader/gpu_work.py)
#
# The app writes its report into its external files directory
# (/sdcard/Android/data/<package>/files/<report>), which adb can read from a
# non-debuggable profile build. Per tier the run also keeps the launch time
# (am start -W), the Impeller backend lines of logcat and the thermal status
# before and after: <tier>.json plus <tier>.device.txt.
#
# The run step expects the Pixel lock (/tmp/morph-native/pixel.lock, same
# protocol as the iPhone's device.lock in spec/README.md) to be held by the caller.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SOURCE=${AUDIT_SOURCE:-$ROOT}
export ANDROID_SERIAL=${AUDIT_SERIAL:-26221JEGR12737}
PKG=dev.tembeon.morph_example
STEP=${AUDIT_STEP:-all}
TIERS=${AUDIT_TIERS:-liquid frosted flat}
RUNS=${AUDIT_RUNS:-5}
LABEL=${AUDIT_LABEL:-pixel6a}
TARGET=${AUDIT_TARGET:-integration_test/glass_audit_test.dart}
REPORT=${AUDIT_REPORT:-glass}
DEFINES=${AUDIT_DEFINES:-}
SUFFIX=${AUDIT_SUFFIX:-}
APPS=${AUDIT_APPS:-/tmp/morph-perf/apks}
SHOTS=${AUDIT_SHOTS:-/tmp/morph-perf/shots/$LABEL}
OUT=$ROOT/tool/ios_reference/perf/$(date +%F)-$LABEL
DEVICE_DIR=/sdcard/Android/data/$PKG/files/$REPORT

if [ "$STEP" = build ] || [ "$STEP" = all ]; then
  mkdir -p "$APPS"
  for tier in $TIERS; do
    # shellcheck disable=SC2086
    (cd "$SOURCE/example" && flutter build apk --profile --target-platform "${AUDIT_ARCH:-android-arm64}" \
      -t "$TARGET" \
      --dart-define=GALLERY_GLASS="$tier" --dart-define=AUDIT_RUNS="$RUNS" \
      --dart-define=AUDIT_OUT="$DEVICE_DIR" $DEFINES | tail -2)
    cp "$SOURCE/example/build/app/outputs/flutter-apk/app-profile.apk" "$APPS/$tier$SUFFIX.apk"
  done
fi

thermal() {
  adb shell dumpsys thermalservice | grep -E 'Thermal Status|VIRTUAL-SKIN|mName=battery' | tr -s '\t ' ' '
}

skin() {
  adb shell dumpsys thermalservice | grep 'Temperature{.*mName=VIRTUAL-SKIN' | tail -1 | sed -E 's/.*mValue=([0-9]+).*/\1/'
}

if [ "$STEP" = run ] || [ "$STEP" = all ]; then
  mkdir -p "$OUT" "$SHOTS"
  for tier in $TIERS; do
    name=$tier$SUFFIX
    info=$OUT/$name.device.txt
    adb install -r "$APPS/$name.apk" >/dev/null
    adb shell am force-stop "$PKG"
    if [ -n "${AUDIT_COOL_C:-}" ]; then
      until [ "$(skin)" -lt "$AUDIT_COOL_C" ]; do sleep 15; done
    fi
    adb shell am force-stop "$PKG"
    if [ "${AUDIT_COLD:-0}" = 1 ]; then adb shell pm clear "$PKG" >/dev/null; fi
    adb shell rm -rf "$DEVICE_DIR/report.json"
    {
      echo "apk: $name.apk  commit: $(git -C "$SOURCE" rev-parse --short HEAD)  date: $(date)"
      echo "thermal before:"
      thermal
    } >"$info"
    adb logcat -c
    sampler=
    if [ "${AUDIT_GPUFREQ:-0}" = 1 ]; then
      adb shell 'while true; do cat /sys/class/misc/mali0/device/cur_freq; sleep 0.5; done' \
        >"$OUT/$name.gpufreq.txt" 2>/dev/null &
      sampler=$!
    fi
    tracer=
    if [ "${AUDIT_GPUWORK:-0}" = 1 ]; then
      adb shell 'cd /sys/kernel/tracing && echo 0 > tracing_on && echo mono > trace_clock &&
        echo 8192 > buffer_size_kb && echo > trace &&
        echo 1 > events/power/gpu_work_period/enable &&
        echo 1 > events/power/gpu_frequency/enable && echo 1 > tracing_on'
      adb shell cat /sys/kernel/tracing/trace_pipe >"$OUT/$name.gpuwork.txt" 2>/dev/null &
      tracer=$!
    fi
    adb shell am start -W -n "$PKG/.MainActivity" | grep -E 'TotalTime|WaitTime' >>"$info"
    sleep 30
    i=0
    until adb shell ls "$DEVICE_DIR/report.json" >/dev/null 2>&1; do
      i=$((i + 1))
      if [ $i -gt 120 ]; then echo "no report for $name"; exit 1; fi
      sleep 10
    done
    sleep 2
    if [ -n "$tracer" ]; then
      adb shell 'cd /sys/kernel/tracing && echo 0 > tracing_on &&
        echo 0 > events/power/gpu_work_period/enable &&
        echo 0 > events/power/gpu_frequency/enable && echo boot > trace_clock &&
        echo > trace'
      kill "$tracer" 2>/dev/null || true
      adb shell pm list packages -U "$PKG" >>"$info"
    fi
    if [ -n "$sampler" ]; then
      kill "$sampler" 2>/dev/null || true
      echo "gpu cur_freq kHz histogram (samples):" >>"$info"
      sort -n "$OUT/$name.gpufreq.txt" | uniq -c >>"$info"
    fi
    rm -f "$OUT/$name.json"
    adb pull "$DEVICE_DIR/report.json" "$OUT/$name.json" >/dev/null
    {
      echo "thermal after:"
      thermal
      echo "logcat (impeller, gpu, errors):"
      adb logcat -d | grep -E ' [IWEF] flutter |Impeller|GLES|E vulkan' | head -40
    } >>"$info"
    rm -rf "$SHOTS/$name"
    adb pull "$DEVICE_DIR" "$SHOTS/$name" >/dev/null 2>&1 || true
    adb shell am force-stop "$PKG"
    echo "$name done"
  done
  python3 "$ROOT/tool/ios_reference/perf/summarize.py" "$OUT"
fi
