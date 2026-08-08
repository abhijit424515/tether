#!/bin/bash
# Regenerates both icons from the SVGs. Needs `brew install librsvg`.
# The rendered files are committed, so building Tether does not need this script.
#
#   menu bar  <- icon-menubar.svg   flat black template, macOS recolours it
#   app icon  <- icon-app.svg       the original blue gradient, shown in Finder and the Dock
set -euo pipefail
cd "$(dirname "$0")"

# 14pt, not the 18pt the menu bar allows: the artwork is a solid band of strokes with no
# internal whitespace, so drawn at full height it reads heavier than the system's icons and
# touches the top and bottom edges. The menu bar centres it, which supplies the gap.
HEIGHT=14

mkdir -p Resources
rsvg-convert icon-menubar.svg -h "$HEIGHT" -o Resources/MenuBarIcon.png
rsvg-convert icon-menubar.svg -h "$((HEIGHT * 2))" -o Resources/MenuBarIcon@2x.png

# .icns wants a specific set of filenames; iconutil rejects the folder otherwise.
SET=$(mktemp -d)/Tether.iconset
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  rsvg-convert icon-app.svg -w "$size" -h "$size" -o "$SET/icon_${size}x${size}.png"
  rsvg-convert icon-app.svg -w "$((size * 2))" -h "$((size * 2))" -o "$SET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$SET" -o Resources/Tether.icns
rm -rf "$(dirname "$SET")"

echo "wrote Resources/MenuBarIcon.png, MenuBarIcon@2x.png and Tether.icns"
