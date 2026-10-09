#!/bin/bash
# build.sh OUT_DIR NAME ARCH(arm|arm64) [--dart-define=...]
# Builds the navigation stage bench as a profile APK at OUT_DIR/NAME.apk with
# the beta SDK (FLUTTER, default ~/.local/share/flutter-beta/bin/flutter).
# Fails when a shader does not compile for every backend (SkSL included).
set -e
OUT=$1; NAME=$2; ARCH=$3; shift 3
FLUTTER=${FLUTTER:-$HOME/.local/share/flutter-beta/bin/flutter}
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
LOG=$(mktemp)
mkdir -p "$OUT"
cd "$ROOT/example"
"$FLUTTER" build apk --profile --target-platform android-$ARCH -t lib/perf/navigation_stage_bench.dart \
  --dart-define=AUDIT_OUT=/sdcard/Android/data/dev.tembeon.morph_example/files/stage-bench \
  --dart-define=NAV_SAMPLE_MS=1500 --dart-define=NAV_WARM_MS=500 "$@" 2>&1 | tee "$LOG" | grep -E "Built|rror" || true
! grep -q "SkSL Error\|rror:" "$LOG"
cp build/app/outputs/flutter-apk/app-profile.apk "$OUT/$NAME.apk"
