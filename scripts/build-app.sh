#!/bin/zsh
# Builds MeetingNoter.app into ./dist (no Xcode needed, Command Line Tools are enough).
set -euo pipefail

PROJECT_DIR="${0:a:h:h}"
APP_NAME="MeetingNoter"
DIST="$PROJECT_DIR/dist"
APP="$DIST/$APP_NAME.app"

cd "$PROJECT_DIR"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

if [[ ! -f "Resources/AppIcon.icns" ]]; then
  swift scripts/make-icon.swift
fi
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
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
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
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
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

echo "Done: $APP"
