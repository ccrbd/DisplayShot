#!/usr/bin/env bash
# Builds DisplayShot.app with SwiftPM only (no Xcode required).
#   ARCHS="arm64"            -> Apple Silicon build (default)
#   ARCHS="arm64 x86_64"     -> universal binary
#   SIGN_IDENTITY="..."      -> codesign identity; defaults to the first "Developer ID Application"
#                               certificate in the keychain, else ad-hoc.
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

SIGN_IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)}
if [ -n "$SIGN_IDENTITY" ]; then
  # Developer ID + hardened runtime + secure timestamp: what notarization and Gatekeeper expect.
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
    --identifier com.ccrbd.DisplayShot "$APP"
  echo "Signed with: $SIGN_IDENTITY"
else
  # Ad-hoc: runs locally; Screen Recording permission is tied to this signature and re-asks after rebuilds.
  codesign --force --sign - --identifier com.ccrbd.DisplayShot --timestamp=none "$APP"
  echo "Signed ad-hoc (no Developer ID certificate found)"
fi
codesign --verify --strict --deep "$APP"

TAG=$(echo "$ARCHS" | tr ' ' '-')
(cd dist && rm -f "DisplayShot-macOS-$TAG.zip" && ditto -c -k --keepParent DisplayShot.app "DisplayShot-macOS-$TAG.zip")
echo "Built $APP (version $VERSION, $ARCHS)"
