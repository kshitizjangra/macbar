#!/usr/bin/env bash
# Build and launch MacBar.app (needs Xcode Command Line Tools for swiftc).
set -euo pipefail
cd "$(dirname "$0")"
APP="$HOME/Applications/MacBar.app"
pkill -x MacBar 2>/dev/null || true
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$HOME/.local/bin"
cp bin/mcpclean "$APP/Contents/Resources/mcpclean"
cp bin/mcpclean "$HOME/.local/bin/mcpclean"
chmod +x "$APP/Contents/Resources/mcpclean" "$HOME/.local/bin/mcpclean"
cp Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
swiftc -O src/MenuBar.swift -o "$APP/Contents/MacOS/MacBar"
codesign -s - --force "$APP"
touch "$APP"
open "$APP"
echo "MacBar running."
