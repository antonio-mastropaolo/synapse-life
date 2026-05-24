#!/usr/bin/env bash
#
# scripts/release-ios.sh
#
# Archives the iOS Synapse build, exports an App Store .ipa, and
# uploads it to App Store Connect / TestFlight using `altool`.
#
# Credentials are taken from the environment so no secrets are stored
# in the repo. The user generates an API key in App Store Connect
# (Users and Access -> Keys -> App Store Connect API), downloads the
# .p8, and exports:
#
#   export ASC_API_KEY_ID="<10-char Key ID>"
#   export ASC_API_ISSUER="<UUID Issuer ID>"
#   export ASC_API_KEY_PATH="$HOME/.appstoreconnect/AuthKey_${ASC_API_KEY_ID}.p8"
#
# `altool` reads the key from one of a small set of well-known
# locations; we point at `~/private_keys/` for cross-platform sanity.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BUILD_DIR="${REPO_ROOT}/build"
ARCHIVE_PATH="${BUILD_DIR}/SynapseLifeiOS.xcarchive"
EXPORT_PATH="${BUILD_DIR}/iOS-export"
EXPORT_OPTIONS="${REPO_ROOT}/apps/Synapse-iOS/ExportOptions.plist"

: "${ASC_API_KEY_ID:?ASC_API_KEY_ID env var is required}"
: "${ASC_API_ISSUER:?ASC_API_ISSUER env var is required}"

mkdir -p "$BUILD_DIR"

echo "[1/3] xcodebuild archive — SynapseLifeiOS"
xcodebuild \
    -project SynapseLife.xcodeproj \
    -scheme SynapseLifeiOS \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    archive

echo "[2/3] xcodebuild -exportArchive -> $EXPORT_PATH"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_PATH"

IPA_PATH="$(find "$EXPORT_PATH" -name '*.ipa' -maxdepth 2 -print -quit)"
if [ -z "${IPA_PATH:-}" ]; then
    echo "no .ipa found under $EXPORT_PATH" >&2
    exit 1
fi

echo "[3/3] altool --upload-app — $IPA_PATH"
xcrun altool --upload-app \
    -f "$IPA_PATH" \
    --type ios \
    --apiKey "$ASC_API_KEY_ID" \
    --apiIssuer "$ASC_API_ISSUER"

echo "Done. Uploaded: $IPA_PATH"
