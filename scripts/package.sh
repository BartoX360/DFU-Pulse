#!/bin/sh
# Builds a Release copy of DFU Pulse signed with the Developer ID certificate,
# wraps it in a DMG, has Apple notarize it and staples the ticket.
#
# Needs, once: the "Developer ID Application" certificate in the keychain, and
#   xcrun notarytool store-credentials dfupulse --apple-id … --team-id 6LKS98VG4F
#
# scripts/package.sh            build build/DFU-Pulse-x.y.z.dmg
# scripts/package.sh --publish  also create the GitHub release vx.y.z
set -eu
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
PROFILE=${NOTARY_PROFILE:-dfupulse}
BUILD=build/release
DMG="build/DFU-Pulse-$VERSION.dmg"

command -v xcodegen >/dev/null && xcodegen generate
rm -rf "$BUILD" "$DMG"
xcodebuild -project DFUPulse.xcodeproj -scheme DFUPulse -configuration Release \
    -derivedDataPath "$BUILD/derived" build >/dev/null

APP="$BUILD/derived/Build/Products/Release/DFU Pulse.app"
codesign --verify --deep --strict "$APP"

STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "DFU Pulse" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
codesign --sign "Developer ID Application" --timestamp "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature "$DMG"
shasum -a 256 "$DMG"

if [ "${1:-}" = "--publish" ]; then
    gh release create "v$VERSION" "$DMG" --generate-notes
fi
