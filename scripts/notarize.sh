#!/bin/zsh
# Submits dist/MeetingNoter.dmg to Apple for notarization and staples the ticket.
# Requires a Developer ID build (scripts/build-app.sh picks that identity automatically
# once the certificate exists) and notarytool credentials.
#
# One-time credential setup — stores an app-specific password in the keychain:
#   xcrun notarytool store-credentials meeting-noter \
#       --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
set -euo pipefail

PROJECT_DIR="${0:a:h:h}"
APP="$PROJECT_DIR/dist/MeetingNoter.app"
DMG="$PROJECT_DIR/dist/MeetingNoter.dmg"
PROFILE="${NOTARY_PROFILE:-meeting-noter}"

[[ -f "$DMG" ]] || { echo "error: $DMG not found — run scripts/make-dmg.sh first" >&2; exit 1; }

# Notarization rejects anything not signed with Developer ID under Hardened Runtime,
# so fail early with a clear message rather than after a slow round trip to Apple.
AUTHORITY="$(codesign -dvvv "$APP" 2>&1 | grep '^Authority=' | head -1 | cut -d= -f2-)"
if [[ "$AUTHORITY" != Developer\ ID* ]]; then
  echo "error: app is signed by '$AUTHORITY', not a Developer ID certificate." >&2
  echo "       Notarization requires Developer ID + Hardened Runtime." >&2
  exit 1
fi

echo "Submitting $DMG to Apple (this usually takes a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "Stapling the ticket…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo
echo "Gatekeeper assessment:"
spctl --assess --type open --context context:primary-signature -vv "$DMG" 2>&1 || true

echo
echo "Notarized: $DMG"
echo "Users can now open the app with a normal double-click — no right-click needed."
