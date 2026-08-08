#!/bin/bash
# Builds AudioPriority.app. No Xcode project — swiftc plus a hand-made bundle.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/AudioPriority.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library AudioPriority.swift Reorder.swift -o "$APP/Contents/MacOS/AudioPriority"
cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature. Enough for Login Items to work locally; not enough to distribute
# to other people's Macs without them right-click > Open past Gatekeeper.
codesign --force --sign - "$APP"

echo "built $PWD/$APP"
