#!/usr/bin/env bash
# Build MacBar and package dist/MacBar.zip (Apple Silicon, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
mkdir -p dist
rm -f dist/MacBar.zip
ditto -c -k --keepParent "$HOME/Applications/MacBar.app" dist/MacBar.zip
echo "dist/MacBar.zip ready: $(du -h dist/MacBar.zip | cut -f1)"
