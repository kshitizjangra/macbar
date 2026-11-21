#!/usr/bin/env bash
# Build MacBar and package dist/MacBar.dmg (drag to Applications) and dist/MacBar.zip.
# Apple Silicon, ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
APP="$HOME/Applications/MacBar.app"
mkdir -p dist
rm -f dist/MacBar.zip dist/MacBar.dmg
ditto -c -k --keepParent "$APP" dist/MacBar.zip

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/MacBar.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MacBar" -srcfolder "$STAGE" -ov -format UDZO dist/MacBar.dmg >/dev/null
rm -rf "$STAGE"
echo "dist/MacBar.dmg $(du -h dist/MacBar.dmg | cut -f1), dist/MacBar.zip $(du -h dist/MacBar.zip | cut -f1)"
