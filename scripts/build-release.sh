#!/bin/bash
# Builds Menu Bar for Grenton for distribution without a paid Apple Developer account:
# Release configuration, universal binary, ad-hoc signature (no notarization).
# Usage: scripts/build-release.sh <version> [build-number]
# Output: dist/MenuBarForGrenton-<version>.zip
set -euo pipefail

VERSION="${1:?usage: scripts/build-release.sh <version> [build-number]}"
BUILD_NUMBER="${2:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/release"
APP="$DERIVED/Build/Products/Release/Menu Bar for Grenton.app"
ZIP="$ROOT/dist/MenuBarForGrenton-$VERSION.zip"

rm -rf "$DERIVED"
# Package versions come only from Package.resolved, as tested locally.
# "-" is an ad-hoc signature: the sandbox entitlements still apply, but no
# team is needed. Base entitlements (get-task-allow) stay out of the release.
xcodebuild build \
    -project "$ROOT/MenuBarForGrenton.xcodeproj" \
    -scheme MenuBarForGrenton \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED" \
    -onlyUsePackageVersionsFromResolvedFile \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

codesign --verify --deep --strict "$APP"
mkdir -p "$ROOT/dist"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "$ZIP"
