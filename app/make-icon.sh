#!/bin/bash
# Regenerates the menu bar icon PNGs from icon-menubar.svg. Needs `brew install librsvg`.
# The PNGs are committed, so building Tether does not need this script.
set -euo pipefail
cd "$(dirname "$0")"

# 14pt, not the 18pt the menu bar allows: the artwork is a solid band of strokes with no
# internal whitespace, so drawn at full height it reads heavier than the system's icons and
# touches the top and bottom edges. The menu bar centres it, which supplies the gap.
HEIGHT=14

mkdir -p Resources
rsvg-convert icon-menubar.svg -h "$HEIGHT" -o Resources/MenuBarIcon.png
rsvg-convert icon-menubar.svg -h "$((HEIGHT * 2))" -o Resources/MenuBarIcon@2x.png
echo "wrote Resources/MenuBarIcon.png and Resources/MenuBarIcon@2x.png"
