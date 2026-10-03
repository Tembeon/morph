#!/bin/sh
# Copies the probe's recordings from the booted simulator into recordings/.
set -eu
cd "$(dirname "$0")"
DATA=$(xcrun simctl get_app_container "${PROBE_DEVICE:-booted}" dev.tembeon.morph.probe data)
OUTDIR=${PROBE_OUT:-recordings}
mkdir -p "$OUTDIR"
cp "$DATA"/Documents/* "$OUTDIR"/
ls -la "$OUTDIR"
