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

# Artifact names are lowercase; Tether with a capital T is for branding only.
ZIP="build/tether-$VERSION.zip"
rm -f "$ZIP"
# ditto, not zip: it preserves the bundle's symlinks and resource forks.
ditto -c -k --keepParent "$APP" "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

gh release create "v$VERSION" "$ZIP" \
  --title "tether $VERSION" \
  --notes "$(cat <<NOTES
## Install

\`\`\`sh
brew install --cask abhijit424515/dynamight/tether
\`\`\`

No flag needed. Earlier notes mentioned \`--no-quarantine\`; that option was
removed in Homebrew 6, so the cask clears the quarantine attribute itself in a
postflight step instead.

## What you are trusting

tether is ad-hoc signed, not notarized by Apple. Gatekeeper only inspects files
carrying the quarantine attribute, so clearing it is what lets the app launch —
which means you are trusting this source rather than Apple's notary service.
Every build script is in the repository if you would rather build it yourself:

\`\`\`sh
git clone https://github.com/abhijit424515/tether.git
cd tether && ./app/install.sh
\`\`\`

## Notes

- Requires macOS 13 (Ventura) or later.
- The Microphone tab shows a live input level, so macOS asks for microphone
  permission the first time you open that tab. Nothing is recorded, and the mic
  is opened only while that tab is on screen.
- Turn on **Open at Login** in the panel to start it with your Mac.
NOTES
)"

echo
echo "released v$VERSION"
echo "sha256 $SHA"
echo
echo "Update Casks/tether.rb in the tap with that version and sha256."
