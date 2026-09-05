#!/usr/bin/env bash
# Builds DisplayShot.app with SwiftPM only (no Xcode required).
#   ARCHS="arm64"          -> Apple Silicon build (default)
#   ARCHS="arm64 x86_64"   -> universal binary
# Output: macos/dist/DisplayShot.app and macos/dist/DisplayShot-macOS-<arch>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=${ARCHS:-arm64}
VERSION=$(tr -d '[:space:]' < ../VERSION 2>/dev/null || echo 0.1.0)
FLAGS=(-c release)
for a in $ARCHS; do FLAGS+=(--arch "$a"); done

swift build "${FLAGS[@]}" --product DisplayShot
BIN="$(swift build "${FLAGS[@]}" --product DisplayShot --show-bin-path)/DisplayShot"

APP=dist/DisplayShot.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DisplayShot"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature (no Developer ID needed). Screen Recording permission is tied to this
# signature, so macOS asks again after the binary changes.
codesign --force --sign - --identifier com.ccrbd.DisplayShot --timestamp=none "$APP"

TAG=$(echo "$ARCHS" | tr ' ' '-')
(cd dist && rm -f "DisplayShot-macOS-$TAG.zip" && ditto -c -k --keepParent DisplayShot.app "DisplayShot-macOS-$TAG.zip")
echo "Built $APP (version $VERSION, $ARCHS)"
