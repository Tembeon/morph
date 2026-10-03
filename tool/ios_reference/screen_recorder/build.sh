#!/bin/sh
# Builds MorphRecorder.app (records the wired iPhone's screen; needs the
# camera permission granted to it once). Usage after building:
#   : > log.txt; open -W build/MorphRecorder.app --args "$PWD/log.txt" /abs/out.mov 8
set -eu
cd "$(dirname "$0")"
mkdir -p build/MorphRecorder.app/Contents/MacOS
cp Info.plist build/MorphRecorder.app/Contents/Info.plist
swiftc -O main.swift -o build/MorphRecorder.app/Contents/MacOS/MorphRecorder
codesign -f -s - build/MorphRecorder.app >/dev/null 2>&1
