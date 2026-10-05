#!/bin/sh
# One atrace capture of an audit APK built with the TraceSystrace meta-data
# (io.flutter.embedding.android.TraceSystrace = true in the example's manifest,
# a local patch): Flutter's trace events of the whole run as text, then
# atrace_slices.py sums them per thread.
#
#   trace_android.sh <apk> <out.txt> [report dir name, default glass]
#
# Expects the Pixel lock to be held. The capture buffer is 64 MB; keep the
# traced run short (AUDIT_SCENES, AUDIT_RUNS=2, AUDIT_SHOTS=false).
set -eu
export ANDROID_SERIAL=${AUDIT_SERIAL:-26221JEGR12737}
PKG=dev.tembeon.morph_example
APK=$1
OUT=$2
REPORT=${3:-glass}
DEVICE_DIR=/sdcard/Android/data/$PKG/files/$REPORT
adb install -r "$APK" >/dev/null
adb shell am force-stop "$PKG"
adb shell rm -rf "$DEVICE_DIR/report.json"
adb shell atrace --async_start -c -b 65536 -a "$PKG" gfx view freq >/dev/null
adb shell am start -W -n "$PKG/.MainActivity" >/dev/null
i=0
until adb shell ls "$DEVICE_DIR/report.json" >/dev/null 2>&1; do
  i=$((i + 1))
  if [ $i -gt 120 ]; then echo "no report"; exit 1; fi
  sleep 5
done
adb shell atrace --async_stop > "$OUT"
adb pull "$DEVICE_DIR/report.json" "${OUT%.txt}.json" >/dev/null
adb shell am force-stop "$PKG"
python3 "$(dirname "$0")/atrace_slices.py" "$OUT" "" 30 | head -150
