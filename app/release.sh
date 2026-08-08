#!/bin/bash
# Cuts a release: builds Tether, stamps the version, zips the bundle, publishes a GitHub
# release, and prints the sha256 the Homebrew cask needs.
#
#   ./app/release.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:-}
[ -n "$VERSION" ] || { echo "usage: release.sh <version>   e.g. release.sh 1.0.0" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.0.0" >&2; exit 1; }

./build.sh

APP=build/Tether.app
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$APP/Contents/Info.plist"
# Editing Info.plist invalidates the signature, so sign after stamping, not before.
codesign --force --sign - "$APP"

ZIP="build/Tether-$VERSION.zip"
rm -f "$ZIP"
# ditto, not zip: it preserves the bundle's symlinks and resource forks.
ditto -c -k --keepParent "$APP" "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

gh release create "v$VERSION" "$ZIP" \
  --title "Tether $VERSION" \
  --notes "Install with:

    brew tap abhijit424515/dynamight
    brew install --cask --no-quarantine tether

The \`--no-quarantine\` flag is required: Tether is ad-hoc signed rather than
notarized, and Gatekeeper blocks unnotarized apps that carry the quarantine
attribute Homebrew would otherwise set."

echo
echo "released v$VERSION"
echo "sha256 $SHA"
echo
echo "Update Casks/tether.rb in the tap with that version and sha256."
