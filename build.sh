#!/bin/sh
# Builds build/MacDoats.app (ad-hoc signed).
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/MacDoats.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/MacDoats "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources"
cp design/logo/kit/export/MacDoats.icns "$APP/Contents/Resources/"
# Version lives in Info.plist (CFBundleShortVersionString); build number = commit count.
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 0)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
codesign --force -s - "$APP"
echo "$APP"
