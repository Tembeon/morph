#!/bin/sh
# Reduce Motion pass on the device: the representative gesture of every motion family,
# replayed with Settings > Accessibility > Motion > Reduce Motion ON (the OWNER switches
# it; no agent automates Settings). Every capture's start row carries rm / rmXfade / rt
# (UIAccessibility flags), so a file recorded with the switch in the wrong position is
# detectable: check `"rm":true` before analysing.
#
#   RM_STEP=all|settings|lens|controls|menu|ctx|sheet|zoom|bars|alert|search|date|page
#   RM_OUT=recordings/device-rm (default)
#
# The test bodies are the existing ones (same gestures as the normal-motion fixtures, so a
# file pairs with its fixture of the same name); PROBE_ONLY picks the representative subset.
# Builds once (device.sh's xcodegen + build-for-testing), then test-without-building per
# class. Take the device lock first (/tmp/morph-native/device.lock, see spec/README.md).
set -eu
cd "$(dirname "$0")"
UDID=${PROBE_UDID:-00008140-001039D01442801C}
TEAM=${PROBE_TEAM:-83S63575XD}
OUT=${RM_OUT:-recordings/device-rm}
STEP=${RM_STEP:-all}
DERIVED=build/device-derived

if [ "${PROBE_SKIP_BUILD:-0}" != 1 ]; then
  /opt/homebrew/bin/xcodegen generate --spec project.yml --quiet
  xcodebuild -project Probe.xcodeproj -scheme Probe -configuration Release -destination "id=$UDID" \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" build-for-testing | tail -2
fi

run() { # run <Class/test> <comma separated capture names> [extra env assignments...]
  t=$1; only=$2; shift 2
  echo "== $t ($only)"
  env TEST_RUNNER_PROBE_ONLY="$only" TEST_RUNNER_PROBE_STEP_HZ="${PROBE_STEP_HZ:-}" "$@" \
    xcodebuild -project Probe.xcodeproj -scheme Probe -configuration Release -destination "id=$UDID" \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" \
    test-without-building -resultBundlePath "$OUT/xcresult/$(echo "$t" | tr '/' '-').xcresult" \
    -only-testing:"ProbeUITests/$t" 2>&1 | grep -E "Test Case|error|PROBE synth failed" || true
}

mkdir -p "$OUT/xcresult"
rm -rf "$OUT"/xcresult/*.xcresult
want() { [ "$STEP" = all ] || [ "$STEP" = "$1" ]; }

want settings && run StatesUITests/testSettingsDump rm-settings-on TEST_RUNNER_PROBE_RMTAG=on
want lens && run ProbeUITests/testLens "segmented-seg3-taps,segmented-seg5-dragslow-from-selected,tabbar4-taps"
want lens && run ProbeUITests/testRecapLens "tabbar4-scrub-mid,tabbar4-tap-selected,segmented-seg3-tap-selected"
want controls && run ProbeUITests/testControls "switch-off-tap,switch-off-hold800,switch-off-drag-right50,slider-w300-hold800-thumb,slider-w300-drag-slow,slider-w300-fling,button-glass-120x44-hold800,button-glass-44x44-hold800,button-prominent-120x44-hold800,button-glass-120x44-drag-off-back"
want menu && run ProbeUITests/testMenu "center3-tap,center3-dismiss,center3-select,navbar3-dismiss"
want ctx && run Widgets2UITests/testW2Ctx "ctx-hold-release,ctx-hold-select"
want sheet && run Widgets2UITests/testW2Sheet "sheet-present-tap,sheet-drag-up-slow,sheet-flick-down,sheet-grab-tap"
want zoom && run SheetNavUITests/testSNZoom "zoom-tap-open-dim,zoom-drag-dismiss"
want zoom && run SheetNavUITests/testSNPush "push-zoom-back,push-zoom-edge"
want zoom && run SheetNavUITests/testSNBack "back-hold-open"
want bars && run BarsUITests/testBars "bars-push-auto,bars-edge-commit,bars-back-tap,bars-toolbar-auto,bars-scroll-auto"
want alert && run ExtrasUITests/testX3Device "alert-press,alert-tap,ash-tap-out"
want search && run ExtrasUITests/testX3Device "search-tap,search-tab,search-tabauto"
want date && run ExtrasUITests/testX3Timing "tm-date-oc-1500" TEST_RUNNER_PROBE_GAPS=1.5
want page && run Widgets2UITests/testW2Page "pc-tap-right,pc-scrub"

xcrun devicectl device copy from --device "$UDID" --domain-type appDataContainer \
  --domain-identifier dev.tembeon.morph.probe --source Documents --destination "$OUT" >/dev/null
echo "pulled into $OUT; files recorded with Reduce Motion ON:"
grep -l '"rm":true' "$OUT"/rec-*.jsonl 2>/dev/null | wc -l
