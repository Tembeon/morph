#!/bin/sh
# Energy of the glass audit on an Android phone: every launch of an audit APK
# under a Perfetto trace of the ODPM power rails, the CPU frequency, idle and
# scheduling tracks and the thermal zones (energy_android.cfg), launches of
# the variants interleaved, each from a cooled start. energy.py splits the
# rails by the report's scene windows.
#
#   energy_android.sh <out dir> <order> <apk dir>
#
#   <order>      the launches, variant names separated by spaces, e.g.
#                "off on on off off on on off" (ABBA); each <apk dir>/<name>.apk
#   ENERGY_COOL_C=37   wait before every launch until VIRTUAL-SKIN reads below
#   ENERGY_REPORT=glass   the report directory name of the audit target
#   AUDIT_SERIAL=<adb serial>   default: the owner's Pixel 6a
#
# Per launch <name>-<i>: the trace (.pftrace), the audit report (.json) and
# the device notes (.device.txt: thermal before and after, battery, launch).
# Expects the Pixel lock (/tmp/morph-native/pixel.lock) to be held.
set -eu
export ANDROID_SERIAL=${AUDIT_SERIAL:-26221JEGR12737}
PKG=dev.tembeon.morph_example
OUT=$1
ORDER=$2
APKS=$3
COOL=${ENERGY_COOL_C:-37}
REPORT=${ENERGY_REPORT:-glass}
DEVICE_DIR=/sdcard/Android/data/$PKG/files/$REPORT
CFG=$(dirname "$0")/energy_android.cfg
mkdir -p "$OUT"
pid=

stop_recorder() {
  case "$pid" in ''|*[!0-9]*) return ;; esac
  if [ "$pid" -gt 1 ]; then adb shell kill -TERM "$pid" 2>/dev/null || true; fi
}
trap stop_recorder EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

skin() {
  adb shell dumpsys thermalservice | grep 'Temperature{.*mName=VIRTUAL-SKIN' | tail -1 | sed -E 's/.*mValue=([0-9.]+).*/\1/'
}

notes() {
  echo "skin: $(skin)"
  adb shell dumpsys thermalservice | grep -E 'Thermal Status' | head -1
  adb shell dumpsys battery | grep -E 'AC powered|USB powered|status|level|temperature'
}

adb push "$CFG" /data/local/tmp/energy.cfg >/dev/null
i=0
for name in $ORDER; do
  i=$((i + 1))
  run=$name-$i
  info=$OUT/$run.device.txt
  adb install -r "$APKS/$name.apk" >/dev/null
  adb shell am force-stop "$PKG"
  adb shell rm -rf "$DEVICE_DIR/report.json"
  until [ "$(skin | cut -d. -f1)" -lt "$COOL" ]; do sleep 20; done
  sleep 10
  {
    echo "run: $run  apk: $name.apk  date: $(date)"
    echo "before:"
    notes
  } >"$info"
  adb shell rm -f /data/misc/perfetto-traces/energy.pftrace
  pid=$(adb shell "cat /data/local/tmp/energy.cfg | perfetto --txt -c - -o /data/misc/perfetto-traces/energy.pftrace --background" | tr -d '\r' | tail -1)
  sleep 3
  adb shell am start -W -n "$PKG/.MainActivity" | grep -E 'TotalTime' >>"$info"
  sleep 30
  n=0
  until adb shell ls "$DEVICE_DIR/report.json" >/dev/null 2>&1; do
    n=$((n + 1))
    if [ $n -gt 90 ]; then echo "no report for $run"; exit 1; fi
    sleep 10
  done
  sleep 2
  adb shell kill -TERM "$pid" || true
  while adb shell kill -0 "$pid" 2>/dev/null; do sleep 1; done
  pid=
  {
    echo "after:"
    notes
  } >>"$info"
  adb pull /data/misc/perfetto-traces/energy.pftrace "$OUT/$run.pftrace" >/dev/null
  adb pull "$DEVICE_DIR/report.json" "$OUT/$run.json" >/dev/null
  adb shell am force-stop "$PKG"
  echo "$run done: $(grep skin "$info" | tr '\n' ' ')"
done
