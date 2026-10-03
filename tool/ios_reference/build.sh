#!/bin/sh
# Builds the UIKit reference probe for the iOS simulator and installs it on the
# booted device. Run a scene with:
#   SIMCTL_CHILD_PROBE_SCENE=tabbar3 xcrun simctl launch --terminate-running-process booted dev.tembeon.morph.probe
# PROBE_DEVICE=<udid> targets one simulator when several are booted.
# Recordings land in the app's Documents as rec-<scene>.jsonl (see pull.sh).
set -eu
cd "$(dirname "$0")"
OUT=build/Probe.app
mkdir -p "$OUT"
cp Info.plist "$OUT/Info.plist"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator swiftc -parse-as-library \
  -target arm64-apple-ios26.0-simulator -sdk "$SDK" -O \
  Sources/*.swift -o "$OUT/Probe"
codesign -f -s - "$OUT" >/dev/null 2>&1
xcrun simctl install "${PROBE_DEVICE:-booted}" "$OUT"
