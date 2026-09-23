#!/usr/bin/env bash
# Packages macos/dist/DisplayShot.app into a signed (and, when credentials exist, notarized) DMG.
#
#   ./scripts/build-app.sh && ./scripts/make-dmg.sh
#
#   NOTARY_PROFILE=DisplayShot   keychain profile created once with
#                                  xcrun notarytool store-credentials DisplayShot \
#                                    --apple-id you@example.com --team-id TEAMID --password app-specific-password
#                                When the profile exists the DMG is notarized and stapled, so other
#                                Macs open it without the "unidentified developer" warning.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=dist/DisplayShot.app
[ -d "$APP" ] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }
VERSION=$(tr -d '[:space:]' < ../VERSION 2>/dev/null || echo 0.1.0)
DMG="dist/DisplayShot-$VERSION.dmg"
NOTARY_PROFILE=${NOTARY_PROFILE:-DisplayShot}

SIGN_IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)}
[ -n "$SIGN_IDENTITY" ] || { echo "No Developer ID Application certificate in the keychain" >&2; exit 1; }

# The app must already carry a Developer ID signature (build-app.sh does this when the cert exists).
codesign --verify --strict "$APP"
# (grep without -q so the pipeline drains; with pipefail an early grep exit would fail it.)
if ! codesign -dvv "$APP" 2>&1 | grep "Authority=Developer ID Application" >/dev/null; then
  echo "$APP is not signed with Developer ID; re-run build-app.sh with the certificate installed" >&2
  exit 1
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "DisplayShot" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
echo "Created and signed $DMG"

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Notarizing with keychain profile '$NOTARY_PROFILE' (this takes a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  echo "Notarized and stapled."
else
  echo "Not notarized: no keychain profile '$NOTARY_PROFILE'. Recipients will need right-click → Open once."
  echo "Create it with: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id <team> --password <app-specific-password>"
fi

echo "--- Gatekeeper assessment:"
spctl --assess --type open --context context:primary-signature -v "$DMG" 2>&1 || true
