#!/bin/sh
# Captures the UIKit reference motion on a REAL device through XCUITest.
#
#   PROBE_PLAN=lens|controls|menu|sliderends|slidervideo|dragtiming|recaplens|recapcontrols|recapmenu|refs|tablook|tabglowdrag|merge|mergedyn|bars|all
#                                      (default all)  which test family to run
#   PROBE_RESULT=<path.xcresult>       keep the result bundle (refs: screenshots are attachments;
#                                      export with xcrun xcresulttool export attachments)
#   PROBE_ONLY=a,b                     only these capture names (rec-<name>.jsonl)
#   PROBE_UDID=<udid>                  device (default: the owner's iPhone 16 Pro)
#   PROBE_TEAM=<team id>               signing team for automatic signing (default 83S63575XD, the owner's own team)
#   PROBE_OUT=<dir>                    where Documents is pulled to (default recordings/device-<plan>)
#   PROBE_SKIP_BUILD=1                 reuse the last build (test-without-building)
#   PROBE_STEP_HZ=<hz>                 point rate of synthesized drag paths (see ProbeUITests)
#
# Steps: xcodegen -> xcodebuild build-for-testing (automatic signing,
# -allowProvisioningUpdates) -> test-without-building on the device -> pull the app's
# Documents with devicectl. The device must be unlocked, trusted, in developer mode, with
# Settings > Developer > Enable UI Automation on.
set -eu
cd "$(dirname "$0")"
UDID=${PROBE_UDID:-00008140-001039D01442801C}
PLAN=${PROBE_PLAN:-all}
export PROBE_TEAM=${PROBE_TEAM:-83S63575XD}
OUT=${PROBE_OUT:-recordings/device-$PLAN}
DERIVED=build/device-derived

/opt/homebrew/bin/xcodegen generate --spec project.yml --quiet

if [ "${PROBE_SKIP_BUILD:-0}" != 1 ]; then
  xcodebuild -project Probe.xcodeproj -scheme Probe -configuration Release \
    -destination "id=$UDID" -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates DEVELOPMENT_TEAM="$PROBE_TEAM" \
    build-for-testing | tail -5
fi

case "$PLAN" in
  lens) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testLens" ;;
  controls) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testControls" ;;
  menu) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testMenu" ;;
  dragtiming) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testDragTiming" ;;
  recaplens) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testRecapLens" ;;
  slidervideo) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testSliderVideo" ;;
  sliderends) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testSliderEnds" ;;
  recapcontrols) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testRecapControls" ;;
  recapmenu) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testRecapMenu" ;;
  refs) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testReferences" ;;
  merge) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testMerge" ;;
  mergedyn) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testMergeDyn" ;;
  tablook) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testTabLook" ;;
  tabglowdrag) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testTabGlowDrag" ;;
  bars) ONLY_TESTS="-only-testing:ProbeUITests/BarsUITests/testBars" ;;
  *) ONLY_TESTS="-only-testing:ProbeUITests/ProbeUITests/testLens -only-testing:ProbeUITests/ProbeUITests/testControls -only-testing:ProbeUITests/ProbeUITests/testMenu" ;;
esac

RESULT_ARGS=""
if [ -n "${PROBE_RESULT:-}" ]; then rm -rf "$PROBE_RESULT"; RESULT_ARGS="-resultBundlePath $PROBE_RESULT"; fi

# xcodebuild forwards TEST_RUNNER_<NAME> into the test runner as <NAME>.
TEST_RUNNER_PROBE_ONLY="${PROBE_ONLY:-}" TEST_RUNNER_PROBE_SPACINGS="${PROBE_SPACINGS:-0,10,20,40,80}" TEST_RUNNER_PROBE_STEP_HZ="${PROBE_STEP_HZ:-}" xcodebuild -project Probe.xcodeproj -scheme Probe \
  -configuration Release -destination "id=$UDID" -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$PROBE_TEAM" \
  test-without-building $RESULT_ARGS $ONLY_TESTS 2>&1 | grep -E "PROBE|Test Case|error|failed|passed|TEST" || true

mkdir -p "$OUT"
xcrun devicectl device copy from --device "$UDID" --domain-type appDataContainer \
  --domain-identifier dev.tembeon.morph.probe --source Documents --destination "$OUT" >/dev/null
ls -la "$OUT" | head -60
