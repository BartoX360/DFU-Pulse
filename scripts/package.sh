#!/bin/sh
# Builds a Release copy of DFU Pulse signed with the Developer ID certificate,
# wraps it in a DMG, has Apple notarize it and staples the ticket.
#
# Needs the "Developer ID Application" certificate in the keychain, and either
#   xcrun notarytool store-credentials dfupulse --apple-id … --team-id 6LKS98VG4F
# or, as in GitHub Actions, NOTARY_APPLE_ID and NOTARY_PASSWORD in the environment.
# Updates are signed with the Sparkle EdDSA key: from the keychain (account
# fr.bartox.DFUPulse), or SPARKLE_PRIVATE_KEY in the environment.
#
# scripts/package.sh            build build/DFU-Pulse-x.y.z.dmg
# scripts/package.sh --publish  also create the GitHub release vx.y.z, with the
#                               DMG and the appcast.xml Sparkle reads
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
IDENTITY="Developer ID Application"

# Sparkle ships its helpers ad-hoc signed: notarization needs them signed
# with our certificate, inside out, then the app itself again.
sign() { codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign "$APP"
codesign --verify --deep --strict "$APP"

STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "DFU Pulse" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
codesign --sign "$IDENTITY" --timestamp "$DMG"

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

# The appcast Sparkle reads, served from the latest release.
TOOLS=$(dirname "$(find "$BUILD/derived/SourcePackages/artifacts" -name sign_update -path '*/bin/*' | head -1)")
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    SIGNATURE=$(printf %s "$SPARKLE_PRIVATE_KEY" | "$TOOLS/sign_update" --ed-key-file - -p "$DMG")
else
    SIGNATURE=$("$TOOLS/sign_update" --account fr.bartox.DFUPulse -p "$DMG")
fi
BUILD_NUMBER=$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' project.yml)

# Release notes from CHANGELOG.md, this version first: the update window
# shows the last few, the GitHub release only this one.
notes() {
    awk -v v="$VERSION" -v n="$1" '
        /^## / { if ($2 == v) on = 1; if (on && ++count > n) exit }
        on && NF' CHANGELOG.md
}
NOTES_HTML=$(notes 5 | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' | awk '
    /^## / { if (open) print "</ul>"; print "<h3>" $2 "</h3><ul>"; open = 1; next }
    /^- / { sub(/^- /, ""); print "<li>" $0 "</li>" }
    END { if (open) print "</ul>" }')
if [ -z "$NOTES_HTML" ]; then
    echo "warning: no entry for $VERSION in CHANGELOG.md, the update window will show no notes" >&2
    DESCRIPTION=""
else
    DESCRIPTION="<description><![CDATA[$NOTES_HTML]]></description>"
fi
PAGE="https://github.com/BartoX360/DFU-Pulse/releases/tag/v$VERSION"
cat > build/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>DFU Pulse</title>
    <item>
      <title>DFU Pulse $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      $DESCRIPTION
      <sparkle:fullReleaseNotesLink>$PAGE</sparkle:fullReleaseNotesLink>
      <enclosure url="https://github.com/BartoX360/DFU-Pulse/releases/download/v$VERSION/DFU-Pulse-$VERSION.dmg"
                 length="$(stat -f %z "$DMG")" type="application/octet-stream"
                 sparkle:edSignature="$SIGNATURE"/>
    </item>
  </channel>
</rss>
XML

if [ "${1:-}" = "--publish" ]; then
    NOTES=$(notes 1 | sed 1d)
    if [ -n "$NOTES" ]; then set -- --notes "$NOTES"; else set -- --generate-notes; fi
    gh release create "v$VERSION" "$DMG" build/appcast.xml --title "DFU Pulse $VERSION" "$@"
fi
