#!/bin/sh
# Builds a Release copy of DFU Pulse and wraps it in a DMG.
# The app is ad-hoc signed: no paid Apple developer account is involved.
set -eu
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
BUILD=build/release
DMG="build/DFU-Pulse-$VERSION.dmg"

command -v xcodegen >/dev/null && xcodegen generate
rm -rf "$BUILD" "$DMG"
xcodebuild -project DFUPulse.xcodeproj -scheme DFUPulse -configuration Release \
    -derivedDataPath "$BUILD/derived" build >/dev/null

STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$BUILD/derived/Build/Products/Release/DFU Pulse.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
codesign --force --deep --sign - "$STAGE/DFU Pulse.app"
hdiutil create -volname "DFU Pulse" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
shasum -a 256 "$DMG"
