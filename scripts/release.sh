#!/bin/bash
# Publishes a release: checks the repo, runs the tests and a local release
# build, pushes the tag, waits for the Release workflow and verifies the
# zip it uploaded (signature, version, SHA-256, provenance).
# Usage: scripts/release.sh <version>   e.g. scripts/release.sh 0.2.0
set -euo pipefail

VERSION="${1:?usage: scripts/release.sh <version>}"
TAG="v$VERSION"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Menu Bar for Grenton"
cd "$ROOT"

die() { echo "release: $*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z, got '$VERSION'"
[[ "$(git branch --show-current)" == main ]] || die "not on main"
[[ -z "$(git status --porcelain)" ]] || die "working tree is not clean"
git fetch -q origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "main is not in sync with origin/main"
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || die "tag $TAG already exists"

echo "==> Tests"
xcodebuild test -project MenuBarForGrenton.xcodeproj -scheme MenuBarForGrenton -destination 'platform=macOS' -quiet

# The local Xcode can be newer than the one on the runner, so this does not
# guarantee the CI build passes; it catches everything else before tagging.
echo "==> Local release build"
scripts/build-release.sh "$VERSION" >/dev/null

echo "==> Tag $TAG"
git tag "$TAG"
git push -q origin "$TAG"

echo "==> Release workflow"
RUN_ID=""
for _ in $(seq 1 12); do
    RUN_ID="$(gh run list --workflow release.yml --branch "$TAG" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
    [[ -n "$RUN_ID" ]] && break
    sleep 5
done
[[ -n "$RUN_ID" ]] || die "no workflow run started for $TAG"
gh run watch "$RUN_ID" --exit-status --interval 20 >/dev/null \
    || die "workflow failed: gh run view $RUN_ID --log-failed"

echo "==> Verify download"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
gh release download "$TAG" --dir "$TMP"
ditto -x -k "$TMP/MenuBarForGrenton-$VERSION.zip" "$TMP/app"
codesign --verify --deep --strict "$TMP/app/$APP_NAME.app"
SHIPPED="$(plutil -extract CFBundleShortVersionString raw "$TMP/app/$APP_NAME.app/Contents/Info.plist")"
[[ "$SHIPPED" == "$VERSION" ]] || die "release reports version $SHIPPED, expected $VERSION"
(cd "$TMP" && shasum -a 256 -c "MenuBarForGrenton-$VERSION.zip.sha256" >/dev/null) || die "SHA-256 does not match"
gh attestation verify "$TMP/MenuBarForGrenton-$VERSION.zip" --repo osieckiAdam/menu-bar-for-grenton >/dev/null \
    || die "build provenance attestation does not verify"

gh release view "$TAG" --json url --jq .url
