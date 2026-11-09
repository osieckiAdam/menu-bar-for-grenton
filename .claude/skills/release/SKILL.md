---
name: release
description: Publish a new version of Menu Bar for Grenton as a GitHub release. Use when the user asks to release, publish, ship or tag a version, or "wydaj wersję".
---

# Releasing Menu Bar for Grenton

Releases are ad-hoc signed and not notarized (no paid Apple Developer
account, by the owner's choice). Pushing a `vX.Y.Z` tag runs
`.github/workflows/release.yml`, which builds with `scripts/build-release.sh`
and attaches `MenuBarForGrenton-X.Y.Z.zip`, its `.sha256` and a build
provenance attestation to a GitHub release with generated notes. The app's
version comes from the tag. The workflow refuses tags that are not
`vX.Y.Z` or not on `main`.

## Steps

1. **Pick the version.** Look at the last tag (`git tag --sort=-v:refname | head -1`)
   and the commits since it (`git log <last-tag>..HEAD --oneline`). Propose a
   semver bump: patch for fixes, minor for features. Confirm with the user
   unless they already gave a version.
2. **Make sure everything is committed and pushed to `main`.** The script
   refuses a dirty tree or a `main` that differs from `origin/main`.
3. **Run** `scripts/release.sh X.Y.Z`. It runs the tests and a local release
   build, pushes the tag, waits for the workflow and verifies the uploaded
   zip (signature, version, SHA-256, `gh attestation verify`). It needs the network, `gh` logged in, and
   takes a few minutes. Run it outside the Bash sandbox, since it writes
   build products and talks to GitHub.
4. **Report** the release URL the script prints.

## When the workflow fails

- Read the failure: `gh run view <id> --log-failed`.
- **The runner's Xcode is older than the local one.** `macos-26` had Xcode 26.6
  (Swift 6.3.3) when the local Xcode was 27.1, so a build that passes locally
  can fail in CI. In v0.1.0, swift-frontend crashed on x86_64 when a
  `@MainActor @Sendable` function value was passed as a `Binding` setter;
  a closure literal fixed it. Check the Xcode version in the "Select Xcode"
  step first.
- **Never move or force-push a tag.** Fix the problem on `main`, then
  release the next patch version. A tag without a release can be deleted
  (`git push origin :refs/tags/vX.Y.Z && git tag -d vX.Y.Z`), but only after
  asking the user.

## Notes

- Releases are immutable and `v*` tags are protected by a ruleset (if those
  repo settings are on): a published release cannot be changed, only
  followed by a new version.
- Actions in the workflow are pinned to commit SHAs; Dependabot opens PRs to
  update them. Review and merge those like any other change.
- `build-release.sh` builds with `-onlyUsePackageVersionsFromResolvedFile`:
  after bumping `grenton-core-swift` in `project.yml`, resolve packages in
  Xcode and commit the updated `Package.resolved`, or CI will fail.

- The repository is `osieckiAdam/menu-bar-for-grenton`.
- Building only: `scripts/build-release.sh X.Y.Z` writes `dist/MenuBarForGrenton-X.Y.Z.zip`.
- User-facing install instructions (Gatekeeper, "Open Anyway") live in
  README → Installation; update them if the release format changes.
