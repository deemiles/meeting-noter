#!/bin/zsh
# Builds MeetingNoter.app into ./dist (no Xcode needed, Command Line Tools are enough).
set -euo pipefail

PROJECT_DIR="${0:a:h:h}"
APP_NAME="MeetingNoter"
DIST="$PROJECT_DIR/dist"
APP="$DIST/$APP_NAME.app"

# Marketing version and build number. CFBundleVersion must increase on every release —
# Sparkle compares it to decide whether an update is available.
VERSION="${VERSION:-1.0}"
BUILD="${BUILD:-1}"

# Signing identity. A stable certificate keeps the app's designated requirement constant,
# so macOS Screen Recording permission survives rebuilds and auto-updates. Falling back to
# ad-hoc ("-") still builds, but every update will reset the user's permissions.
if [[ -z "${IDENTITY:-}" ]]; then
  # A Developer ID certificate means notarized, warning-free distribution; prefer it.
  # `|| true`: grep exits 1 when no Developer ID exists yet, and set -e would abort.
  DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null |
    grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
  if [[ -n "$DEVELOPER_ID" ]]; then
    IDENTITY="$DEVELOPER_ID"
  else
    IDENTITY="Meeting Noter"
  fi
fi
if ! security find-identity -v 2>/dev/null | grep -q "$IDENTITY" && \
   ! security find-identity 2>/dev/null | grep -q "$IDENTITY"; then
  echo "warning: signing identity '$IDENTITY' not found, falling back to ad-hoc" >&2
  IDENTITY="-"
fi

APPCAST_URL="${APPCAST_URL:-https://deemiles.github.io/meeting-noter/appcast.xml}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-q1MfGUxoJqNETTbZrkb7WXg+Jjf13XrAHimAL2i6KKs=}"

cd "$PROJECT_DIR"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# SPM links Sparkle via @rpath but only bakes in @loader_path, which points at Contents/MacOS.
# Point the loader at the embedded framework. Must happen before signing — it rewrites the binary.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true

if [[ ! -f "Resources/AppIcon.icns" ]]; then
  swift scripts/make-icon.swift
fi
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Bundled whisper-cli: statically linked, no Homebrew needed on the user's machine.
# Rebuild it with scripts/build-whisper.sh.
if [[ ! -x "Resources/bin/whisper-cli" ]]; then
  echo "error: Resources/bin/whisper-cli missing — run ./scripts/build-whisper.sh" >&2
  exit 1
fi
cp "Resources/bin/whisper-cli" "$APP/Contents/Resources/whisper-cli"
chmod +x "$APP/Contents/Resources/whisper-cli"

# Sparkle ships as an XCFramework through SPM; the SPM CLI does not embed it for us.
SPARKLE_FRAMEWORK="$(find .build/artifacts -type d -name 'Sparkle.framework' -path '*macos-arm64_x86_64*' | head -1)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "error: Sparkle.framework not found — run 'swift package resolve' first" >&2
  exit 1
fi
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>MeetingNoter</string>
	<key>CFBundleDisplayName</key>
	<string>Meeting Noter</string>
	<key>CFBundleIdentifier</key>
	<string>com.dmytro.meetingnoter</string>
	<key>CFBundleExecutable</key>
	<string>MeetingNoter</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$VERSION</string>
	<key>CFBundleVersion</key>
	<string>$BUILD</string>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSMicrophoneUsageDescription</key>
	<string>Meeting Noter records your voice during calls to produce a transcript.</string>
	<key>SUFeedURL</key>
	<string>$APPCAST_URL</string>
	<key>SUPublicEDKey</key>
	<string>$SPARKLE_PUBLIC_KEY</string>
	<key>SUEnableAutomaticChecks</key>
	<true/>
</dict>
</plist>
PLIST

# Hardened Runtime is required for notarization but breaks a self-signed setup
# (library validation refuses to load Sparkle), so it is enabled only for Developer ID.
SIGN_FLAGS=(--force --sign "$IDENTITY")
APP_SIGN_FLAGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" == Developer\ ID* ]]; then
  SIGN_FLAGS+=(--options runtime --timestamp)
  APP_SIGN_FLAGS+=(--options runtime --timestamp --entitlements "$PROJECT_DIR/Resources/MeetingNoter.entitlements")
fi

# Sign inside-out, following Sparkle's documented order. Never use --deep here.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -e "$SPARKLE/Versions/B/XPCServices/Installer.xpc" ]]; then
  codesign "${SIGN_FLAGS[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
fi
if [[ -e "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" ]]; then
  codesign "${SIGN_FLAGS[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
fi
if [[ -e "$SPARKLE/Versions/B/Autoupdate" ]]; then
  codesign "${SIGN_FLAGS[@]}" "$SPARKLE/Versions/B/Autoupdate"
fi
if [[ -e "$SPARKLE/Versions/B/Updater.app" ]]; then
  codesign "${SIGN_FLAGS[@]}" "$SPARKLE/Versions/B/Updater.app"
fi
codesign "${SIGN_FLAGS[@]}" "$SPARKLE"

codesign "${SIGN_FLAGS[@]}" "$APP/Contents/Resources/whisper-cli"
codesign "${APP_SIGN_FLAGS[@]}" "$APP"

echo "Done: $APP  ($VERSION build $BUILD, signed by '$IDENTITY')"
if [[ "$IDENTITY" == Developer\ ID* ]]; then
  echo "Hardened Runtime on — ready for ./scripts/notarize.sh"
fi
