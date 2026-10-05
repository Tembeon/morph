#!/bin/sh
# The shader harness on the iPhone 16 Pro (Metal).
#
#   tool/audit/shader/run_iphone.sh <label> [parity|bench]
#
#   SHADER_REV=<rev>      the commit to build (default HEAD), checked out as a
#                         git worktree in /tmp/morph-perf/src/<rev>-metal
#   AUDIT_STEP=build|run|all   as in audit.sh; only run needs the phone
#   SHADER_DEFINES="..."  extra --dart-define flags (SHADER_CASES, SHADER_COPIES)
#
# Results: the report and PNGs in /tmp/morph-perf/shader/<label>-metal-<mode>;
# tool/audit/shader/parity.py reads them. The run step expects the phone lock
# (/tmp/morph-native/device.lock, spec/README.md) to be held by the caller.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
LABEL=${1:?label}
MODE=${2:-parity}
REV=$(git -C "$ROOT" rev-parse --short "${SHADER_REV:-HEAD}")
SRC=/tmp/morph-perf/src/$REV-metal
if [ ! -d "$SRC" ]; then
  git -C "$ROOT" worktree add --detach "$SRC" "$REV" >/dev/null
fi
# The harness itself (cases, runner, bench) always comes from the main tree,
# so an older commit is measured by today's harness; its frozen baseline
# stays the commit's own.
cp -R "$ROOT/example/integration_test/support" "$SRC/example/integration_test/"
cp "$ROOT/example/integration_test/shader_parity_test.dart" "$SRC/example/integration_test/"
DEFINES=${SHADER_DEFINES:-}
if [ "$MODE" = bench ]; then DEFINES="$DEFINES --dart-define=SHADER_BENCH=true"; fi
NAME=$LABEL-metal-$MODE
AUDIT_SOURCE=$SRC \
AUDIT_TARGET=integration_test/shader_parity_test.dart \
AUDIT_REPORT=tmp/shader \
AUDIT_TIERS=liquid \
AUDIT_RUNS=1 \
AUDIT_DEFINES="$DEFINES" \
AUDIT_APPS=/tmp/morph-perf/apps/shader-$REV-$MODE \
AUDIT_LABEL=shader-$NAME \
AUDIT_SHOTS=/tmp/morph-perf/shader/$NAME \
  "$ROOT/tool/ios_reference/perf/audit.sh"
SHOT=/tmp/morph-perf/shader/$NAME/liquid
if [ -f "$SHOT/report.json" ]; then
  python3 "$ROOT/tool/audit/shader/parity.py" show "$SHOT"
fi
