#!/bin/bash
# Rebuilds Resources/Pitatto.icns from Resources/icon.svg.
#
# Not part of `make app`: the .icns is committed, so a build needs nothing but
# Swift. This is for when the artwork changes, and it needs rsvg-convert
# (`brew install librsvg`) — a dependency worth asking for once a year rather
# than on every build.
set -euo pipefail

cd "$(dirname "$0")/.."

command -v rsvg-convert >/dev/null || {
	echo "rsvg-convert not found: brew install librsvg" >&2
	exit 1
}

SET="$(mktemp -d)/Pitatto.iconset"
mkdir -p "$SET"

# The ten files iconutil expects. A missing one is dropped silently, and the
# size it covers then falls back to a scaled neighbour.
render() { rsvg-convert -w "$1" -h "$1" Resources/icon.svg -o "$SET/$2"; }
render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil --convert icns "$SET" --output Resources/Pitatto.icns
rm -rf "$(dirname "$SET")"
echo "built Resources/Pitatto.icns"
