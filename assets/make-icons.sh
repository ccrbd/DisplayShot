#!/usr/bin/env bash
# Regenerates every icon artifact from assets/make-icons.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=assets/build
swift assets/make-icons.swift "$BUILD"
iconutil -c icns "$BUILD/DisplayShot.iconset" -o macos/Resources/AppIcon.icns
python3 assets/make-ico.py windows/DisplayShot/Assets/DisplayShot.ico \
  "$BUILD"/png/icon-16.png "$BUILD"/png/icon-24.png "$BUILD"/png/icon-32.png \
  "$BUILD"/png/icon-48.png "$BUILD"/png/icon-64.png "$BUILD"/png/icon-256.png
python3 assets/make-ico.py assets/favicon.ico \
  "$BUILD"/png/favicon-16.png "$BUILD"/png/favicon-32.png "$BUILD"/png/favicon-48.png
cp "$BUILD"/png/favicon-32.png assets/favicon-32.png
cp "$BUILD"/png/favicon-180.png assets/apple-touch-icon.png
cp "$BUILD"/png/icon-256.png assets/icon-256.png
echo "done"
