#!/usr/bin/env bash
#
# scripts/release-macos.sh
#
# Archives, exports, notarises, and staples the macOS Synnapse build for
# distribution outside the Mac App Store (Developer ID + notarization).
# Intended to be invoked from the repo root.
#
# One-time setup the user does on their laptop (not the agent):
#
#   xcrun notarytool store-credentials synnapse-notarytool \
#       --apple-id "<your-apple-id>" \
#       --team-id "<YOUR_TEAM_ID>" \
#       --password "<app-specific-password>"
#
# After that one-time setup, this script is a single command. The
# `notarytool` step blocks until Apple finishes notarisation (typically
# 1-5 minutes); `stapler` then attaches the notarisation ticket so the
# app launches without a network round-trip.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="${REPO_ROOT}/build"
ARCHIVE_PATH="${BUILD_DIR}/SynnapseMac.xcarchive"
EXPORT_PATH="${BUILD_DIR}/macOS-export"
EXPORT_OPTIONS="${REPO_ROOT}/apps/Synnapse-macOS/ExportOptions.plist"
NOTARY_PROFILE="${NOTARY_PROFILE:-synnapse-notarytool}"

mkdir -p "$BUILD_DIR"

echo "[1/4] xcodebuild archive — SynnapseMac"
xcodebuild \
    -project Synnapse.xcodeproj \
    -scheme SynnapseMac \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    archive

echo "[2/4] xcodebuild -exportArchive -> $EXPORT_PATH"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_PATH"

APP_PATH="${EXPORT_PATH}/SynnapseMac.app"
ZIP_PATH="${EXPORT_PATH}/SynnapseMac.app.zip"

if [ ! -d "$APP_PATH" ]; then
    echo "expected exported app at $APP_PATH — exiting" >&2
    exit 1
fi

echo "[3/4] ditto + notarytool submit"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" \
    --wait \
    --keychain-profile "$NOTARY_PROFILE"

echo "[4/4] stapler staple"
xcrun stapler staple "$APP_PATH"

echo "Done. Notarised .app is at: $APP_PATH"
