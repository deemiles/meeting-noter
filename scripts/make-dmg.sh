#!/bin/zsh
# Packages dist/MeetingNoter.app into a distributable .dmg and signs it for Sparkle.
set -euo pipefail

PROJECT_DIR="${0:a:h:h}"
APP_NAME="MeetingNoter"
APP="$PROJECT_DIR/dist/$APP_NAME.app"
VERSION="${VERSION:-$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)}"
DMG="$PROJECT_DIR/dist/$APP_NAME.dmg"   # stable name: the download link on the site points here
STAGING="$(mktemp -d)"

[[ -d "$APP" ]] || { echo "error: $APP not found — run scripts/build-app.sh first" >&2; exit 1; }

trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# A .background folder would let us set a custom Finder layout; keeping it plain
# avoids requiring Finder automation permissions on the build machine.
rm -f "$DMG"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  -quiet \
  "$DMG"

echo "Built: $DMG ($(du -h "$DMG" | cut -f1))"

# Sparkle needs an EdDSA signature and the file length for the appcast entry.
SIGN_UPDATE="$(find "$PROJECT_DIR/.build/artifacts" -name sign_update -type f | head -1)"
if [[ -n "$SIGN_UPDATE" ]]; then
  echo "Appcast signature:"
  "$SIGN_UPDATE" "$DMG"
else
  echo "note: sign_update not found — run 'swift package resolve' to sign the update" >&2
fi
