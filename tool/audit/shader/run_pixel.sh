#!/bin/sh
# The shader harness on the Pixel 6a, Vulkan or the forced GLES backend.
#
#   tool/audit/shader/run_pixel.sh <label> [vulkan|gles] [parity|bench]
#
#   SHADER_REV=<rev>      the commit to build (default HEAD), checked out as a
#                         git worktree in /tmp/morph-perf/src/<rev>-<backend>, so
#                         other agents' uncommitted edits stay out of the build
#   AUDIT_STEP=build|run|all   as in audit_android.sh; only run needs the phone
#   SHADER_DEFINES="..."  extra --dart-define flags (SHADER_CASES, SHADER_COPIES)
#
# GLES is forced the way the passport does it: the worktree's manifest gets
# io.flutter.embedding.android.ImpellerBackend=opengles. Results: the report
# and PNGs in /tmp/morph-perf/shader/<label>-<backend>-<mode>, the report also
# in tool/ios_reference/perf/<date>-shader-<label>-<backend>-<mode>/;
# tool/audit/shader/parity.py reads both. The run step expects the Pixel
# lock (/tmp/morph-native/pixel.lock) to be held by the caller.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
LABEL=${1:?label}
BACKEND=${2:-vulkan}
MODE=${3:-parity}
REV=$(git -C "$ROOT" rev-parse --short "${SHADER_REV:-HEAD}")
SRC=/tmp/morph-perf/src/$REV-$BACKEND
if [ ! -d "$SRC" ]; then
  git -C "$ROOT" worktree add --detach "$SRC" "$REV" >/dev/null
  if [ "$BACKEND" = gles ]; then
    python3 - "$SRC/example/android/app/src/main/AndroidManifest.xml" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
anchor = '        <!-- Don\'t delete the meta-data below.'
extra = ('        <meta-data\n'
         '            android:name="io.flutter.embedding.android.ImpellerBackend"\n'
         '            android:value="opengles" />\n')
open(path, 'w').write(text.replace(anchor, extra + anchor, 1))
PY
  fi
fi
DEFINES=${SHADER_DEFINES:-}
if [ "$MODE" = bench ]; then DEFINES="$DEFINES --dart-define=SHADER_BENCH=true"; fi
NAME=$LABEL-$BACKEND-$MODE
AUDIT_SOURCE=$SRC \
AUDIT_TARGET=integration_test/shader_parity_test.dart \
AUDIT_REPORT=shader \
AUDIT_TIERS=liquid \
AUDIT_RUNS=1 \
AUDIT_SUFFIX=-$REV-$BACKEND-$MODE \
AUDIT_DEFINES="$DEFINES" \
AUDIT_LABEL=shader-$NAME \
AUDIT_SHOTS=/tmp/morph-perf/shader/$NAME \
  "$ROOT/tool/ios_reference/perf/audit_android.sh"
SHOT=/tmp/morph-perf/shader/$NAME/liquid-$REV-$BACKEND-$MODE
if [ -f "$SHOT/report.json" ]; then
  python3 "$ROOT/tool/audit/shader/parity.py" show "$SHOT"
fi
