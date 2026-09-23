#!/usr/bin/env bash
# Uploads the notarized DMG from macos/dist to the GitHub release for the current VERSION.
# Run after `macos/scripts/build-app.sh && macos/scripts/make-dmg.sh` on a machine with the certificate.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(tr -d '[:space:]' < VERSION)
DMG="macos/dist/DisplayShot-$VERSION.dmg"
[ -f "$DMG" ] || { echo "$DMG not found; run macos/scripts/make-dmg.sh first" >&2; exit 1; }
xcrun stapler validate "$DMG" >/dev/null || { echo "$DMG is not notarized/stapled; refusing to publish" >&2; exit 1; }
gh release upload "v$VERSION" "$DMG" --clobber
echo "Uploaded $DMG to release v$VERSION"
gh release view "v$VERSION" --json assets -q '.assets[].name'
