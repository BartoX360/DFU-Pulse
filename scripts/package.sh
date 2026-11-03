#!/bin/sh
# Builds a Release copy of DFU Pulse signed with the Developer ID certificate,
# wraps it in a DMG, has Apple notarize it and staples the ticket.
#
# Needs the "Developer ID Application" certificate in the keychain, and either
#   xcrun notarytool store-credentials dfupulse --apple-id … --team-id 6LKS98VG4F
# or, as in GitHub Actions, NOTARY_APPLE_ID and NOTARY_PASSWORD in the environment.
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

# Runs a notarytool command with whichever credentials are available.
notary() {
    if [ -n "${NOTARY_APPLE_ID:-}" ]; then
        xcrun notarytool "$@" --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id 6LKS98VG4F
    else
        xcrun notarytool "$@" --keychain-profile "$PROFILE"
    fi
}

# notarytool exits 0 even when Apple rejects the file: read the verdict.
RESULT=$(notary submit "$DMG" --wait --output-format json)
echo "$RESULT"
if ! echo "$RESULT" | grep -q '"status":"Accepted"'; then
    ID=$(echo "$RESULT" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
    echo "Notarization failed:" >&2
    notary log "$ID" >&2
    exit 1
fi
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature "$DMG"
shasum -a 256 "$DMG"

if [ "${1:-}" = "--publish" ]; then
    gh release create "v$VERSION" "$DMG" --title "DFU Pulse $VERSION" --generate-notes
fi
