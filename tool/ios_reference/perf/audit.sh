#!/bin/sh
# Frame timings of the glass audit on the iPhone, per glass tier.
#
#   AUDIT_STEP=build|run|all      build the profile apps, run them on the phone, or both (all)
#   AUDIT_TIERS="liquid frosted flat"
#   AUDIT_RUNS=5                  timed repeats of every scene inside one launch
#   AUDIT_LABEL=baseline          names the result directory <date>-<label>
#   AUDIT_APPS=<dir>              where the built apps are kept between the steps
#   AUDIT_SHOTS=<dir>             where the screenshots are pulled (not committed)
#   AUDIT_UDID=<udid>             default: the owner's iPhone 16 Pro
#   AUDIT_SOURCE=<checkout>       the tree to build (a git worktree at a fixed commit keeps
#                                 other agents' uncommitted edits out of the numbers)
#   AUDIT_TARGET=<test file>      default integration_test/glass_audit_test.dart; the density
#                                 audit is integration_test/glass_density_test.dart
#   AUDIT_REPORT=<tmp dir>        the app's report directory, default tmp/glass (the density
#                                 audit writes tmp/glass_density)
#
# The run step expects the phone lock (spec/README.md) to be held by the caller.
# Results: tool/ios_reference/perf/<date>-<label>/<tier>.json; summarize.py prints them.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SOURCE=${AUDIT_SOURCE:-$ROOT}
UDID=${AUDIT_UDID:-00008140-001039D01442801C}
BUNDLE=dev.tembeon.morphExample
STEP=${AUDIT_STEP:-all}
TIERS=${AUDIT_TIERS:-liquid frosted flat}
RUNS=${AUDIT_RUNS:-5}
LABEL=${AUDIT_LABEL:-run}
TARGET=${AUDIT_TARGET:-integration_test/glass_audit_test.dart}
REPORT=${AUDIT_REPORT:-tmp/glass}
APPS=${AUDIT_APPS:-/tmp/morph-perf/apps}
SHOTS=${AUDIT_SHOTS:-/tmp/morph-perf/shots/$LABEL}
OUT=$ROOT/tool/ios_reference/perf/$(date +%F)-$LABEL

if [ "$STEP" = build ] || [ "$STEP" = all ]; then
  mkdir -p "$APPS"
  for tier in $TIERS; do
    (cd "$SOURCE/example" && flutter build ios --profile \
      -t "$TARGET" \
      --dart-define=GALLERY_GLASS="$tier" --dart-define=AUDIT_RUNS="$RUNS" | tail -2)
    rm -rf "$APPS/$tier.app"
    cp -R "$SOURCE/example/build/ios/iphoneos/Runner.app" "$APPS/$tier.app"
  done
fi

if [ "$STEP" = run ] || [ "$STEP" = all ]; then
  mkdir -p "$OUT" "$SHOTS"
  for tier in $TIERS; do
    xcrun devicectl device install app --device "$UDID" "$APPS/$tier.app" >/dev/null
    xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE" >/dev/null
    sleep 30
    rm -f "$OUT/$tier.json"
    i=0
    until xcrun devicectl device copy from --device "$UDID" --domain-type appDataContainer \
      --domain-identifier "$BUNDLE" --source "$REPORT/report.json" \
      --destination "$OUT/$tier.json" >/dev/null 2>&1; do
      i=$((i + 1))
      if [ $i -gt 120 ]; then echo "no report for $tier"; exit 1; fi
      sleep 10
    done
    rm -rf "$SHOTS/$tier"
    xcrun devicectl device copy from --device "$UDID" --domain-type appDataContainer \
      --domain-identifier "$BUNDLE" --source "$REPORT" \
      --destination "$SHOTS/$tier" >/dev/null 2>&1 || true
    echo "$tier done"
  done
  python3 "$ROOT/tool/ios_reference/perf/summarize.py" "$OUT"
fi
