#!/bin/bash
# Builds Tether and installs it where Spotlight, Raycast and Launchpad look for apps.
# Running it from the repo's build directory works, but nothing indexes build output.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

# /Applications when this account can write it, otherwise the per-user equivalent.
# Both are indexed; ~/Applications just never needs an admin prompt.
DEST=/Applications
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

pkill -f "Tether.app/Contents/MacOS/Tether" 2>/dev/null || true
rm -rf "$DEST/Tether.app"
cp -R build/Tether.app "$DEST/Tether.app"

# Launch Services caches the old bundle for a moment after the copy, so `open` can fail
# with -600 on the first try. Nudge it, then retry rather than failing the install.
touch "$DEST/Tether.app"
open "$DEST/Tether.app" 2>/dev/null || { sleep 2; open "$DEST/Tether.app"; }
echo "installed $DEST/Tether.app"
