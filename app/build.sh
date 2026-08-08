#!/bin/bash
# Builds Tether.app. No Xcode project — swiftc plus a hand-made bundle.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Tether.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library Tether.swift Reorder.swift InputMeter.swift -o "$APP/Contents/MacOS/Tether"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/*.png Resources/Tether.icns "$APP/Contents/Resources/"

# Ad-hoc signature. Enough for Login Items to work locally; not enough to distribute
# to other people's Macs without them right-click > Open past Gatekeeper.
codesign --force --sign - "$APP"

echo "built $PWD/$APP"
