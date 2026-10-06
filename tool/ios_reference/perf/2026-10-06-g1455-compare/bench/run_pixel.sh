#!/bin/sh
# One launch of the comparison bench on the Pixel 6a with the kernel's GPU
# work periods traced (the AUDIT_GPUWORK=1 branch of audit_android.sh).
#
#   run_pixel.sh <apk> <out dir> <name>
#
# Expects the Pixel lock (/tmp/morph-native/pixel.lock) to be held.
set -eu
export ANDROID_SERIAL=${AUDIT_SERIAL:-26221JEGR12737}
PKG=dev.tembeon.g1455_bench
APK=$1
OUT=$2
name=$3
COOL=${AUDIT_COOL_C:-38}
DEVICE_DIR=/sdcard/Android/data/$PKG/files/compare
mkdir -p "$OUT"
info=$OUT/$name.device.txt

skin() {
  adb shell dumpsys thermalservice | grep 'Temperature{.*mName=VIRTUAL-SKIN' | tail -1 | sed -E 's/.*mValue=([0-9]+).*/\1/'
}

adb install -r "$APK" >/dev/null
adb shell am force-stop "$PKG"
until [ "$(skin)" -lt "$COOL" ]; do sleep 15; done
adb shell rm -rf "$DEVICE_DIR"
{
  echo "apk: $APK  date: $(date)"
  echo "skin before: $(skin)"
  adb shell dumpsys thermalservice | grep -E 'Thermal Status' | head -1
} >"$info"
adb logcat -c
adb shell 'cd /sys/kernel/tracing && echo 0 > tracing_on && echo mono > trace_clock &&
  echo 8192 > buffer_size_kb && echo > trace &&
  echo 1 > events/power/gpu_work_period/enable &&
  echo 1 > events/power/gpu_frequency/enable && echo 1 > tracing_on'
adb shell cat /sys/kernel/tracing/trace_pipe >"$OUT/$name.gpuwork.txt" 2>/dev/null &
tracer=$!
adb shell am start -W -n "$PKG/.MainActivity" | grep -E 'TotalTime|WaitTime' >>"$info"
sleep 30
i=0
until adb shell ls "$DEVICE_DIR/report.json" >/dev/null 2>&1; do
  i=$((i + 1))
  if [ $i -gt 120 ]; then echo "no report for $name"; kill "$tracer" 2>/dev/null || true; exit 1; fi
  sleep 10
done
sleep 2
adb shell 'cd /sys/kernel/tracing && echo 0 > tracing_on &&
  echo 0 > events/power/gpu_work_period/enable &&
  echo 0 > events/power/gpu_frequency/enable && echo boot > trace_clock &&
  echo > trace'
kill "$tracer" 2>/dev/null || true
adb shell pm list packages -U "$PKG" >>"$info"
adb pull "$DEVICE_DIR/report.json" "$OUT/$name.json" >/dev/null
mkdir -p "$OUT/shots-$name"
adb pull "$DEVICE_DIR" "$OUT/shots-$name" >/dev/null 2>&1 || true
{
  echo "skin after: $(skin)"
  adb shell dumpsys thermalservice | grep -E 'Thermal Status' | head -1
  echo "logcat (impeller, errors):"
  adb logcat -d | grep -E ' [IWEF] flutter |Impeller|E vulkan' | head -40
} >>"$info"
adb shell am force-stop "$PKG"
echo "$name done"
