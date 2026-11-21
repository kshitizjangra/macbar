#!/usr/bin/env bash
# Rebuild assets/AppIcon.icns from the drawing in make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d)
swiftc -O tools/make-icon.swift -o "$T/mk"
"$T/mk" assets/AppIcon.png
IS="$T/AppIcon.iconset"; mkdir -p "$IS"
for s in 16 32 128 256 512; do
  sips -z $s $s assets/AppIcon.png --out "$IS/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) assets/AppIcon.png --out "$IS/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$IS" -o assets/AppIcon.icns
rm -rf "$T"
echo "assets/AppIcon.icns ready"
