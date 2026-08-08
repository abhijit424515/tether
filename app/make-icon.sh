#!/bin/bash
# Regenerates the menu bar icon PNGs from icon-menubar.svg. Needs `brew install librsvg`.
# The PNGs are committed, so building Tether does not need this script.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p Resources
rsvg-convert icon-menubar.svg -h 18 -o Resources/MenuBarIcon.png
rsvg-convert icon-menubar.svg -h 36 -o Resources/MenuBarIcon@2x.png
echo "wrote Resources/MenuBarIcon.png and Resources/MenuBarIcon@2x.png"
