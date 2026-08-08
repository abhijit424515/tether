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

# The artwork's 9-unit strokes on a 460-unit canvas come out 0.3px wide at 16px, which
# antialiases to near-white — the small Finder icon looked washed out while Quick Look,
# rendering the 512px slice, stayed blue. Thicken the stroke for the small slices so every
# size keeps at least MIN_INK pixels of solid colour. Large slices keep the original 9.
MIN_INK=1.6
render() { # size, output
  local width
  width=$(awk -v s="$1" -v ink="$MIN_INK" 'BEGIN { w = ink * 460 / s; print (w > 9 ? int(w + 0.5) : 9) }')
  sed "s/stroke-width=\"9\"/stroke-width=\"$width\"/" icon-app.svg |
    rsvg-convert -w "$1" -h "$1" -o "$2"
}

for size in 16 32 128 256 512; do
  render "$size" "$SET/icon_${size}x${size}.png"
  render "$((size * 2))" "$SET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$SET" -o Resources/Tether.icns
rm -rf "$(dirname "$SET")"

echo "wrote Resources/MenuBarIcon.png, MenuBarIcon@2x.png and Tether.icns"
