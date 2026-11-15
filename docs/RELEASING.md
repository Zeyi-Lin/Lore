# Releasing Lore

Lore ships as a macOS app bundle inside a DMG attached to a GitHub release, and the app updates itself by reading that release feed. Every release therefore has to be **discoverable, newer, and installable**: a semver tag, a bundle whose `CFBundleShortVersionString` matches the tag, and a DMG asset named the way the updater expects. This document is the contract between the release pipeline and the in-app updater, written so that a human or a coding agent can cut a release without guessing.

| Property | Value |
| --- | --- |
| Repository | `Zeyi-Lin/Lore` (`https://github.com/Zeyi-Lin/Lore`) |
| Version source | `Sources/Lore/Version.swift` → `LoreVersion.current` (currently `1.2.0`) |
| Version consumers | `Info.plist` → `CFBundleShortVersionString`; Settings → About; in-app updater |
| App bundle | `dist/Lore.app`, bundle id `studio.lore.library` |
| Release asset | `dist/Lore-vX.Y.Z.dmg`, uploaded as `Lore-vX.Y.Z.dmg` |
| Current release | `v1.2.0`, asset `Lore-v1.2.0.dmg` |
| Updater feed | `https://api.github.com/repos/Zeyi-Lin/Lore/releases/latest` |
| Download URL shape | `https://github.com/Zeyi-Lin/Lore/releases/download/vX.Y.Z/Lore-vX.Y.Z.dmg` |
| Packaging script | `scripts/package-release.sh` — builds and packages, never publishes |
| Build script | `scripts/build-app.sh release` — stamps the version, ad-hoc signs the bundle |

All commands below run from the repository root.

---

## One version, one line

The app version is declared exactly once:

```swift
// Sources/Lore/Version.swift
enum LoreVersion {
    static let current = "1.2.0"   // ← the only line to bump for a release
    // ...
}
```

Everything else derives from it:

| Consumer | Where the number comes from | What a bump changes |
| --- | --- | --- |
| `CFBundleShortVersionString` | `scripts/build-app.sh` extracts the literal with `sed` and stamps it into `dist/Lore.app/Contents/Info.plist` | The packaged bundle version (Finder *Get Info*, app menu) |
| Settings → About | `LoreVersion.installed` reads `Bundle.main`'s `CFBundleShortVersionString`, falling back to `current` for a bare `swift run` | The number users see, e.g. `Lore 1.2.0` |
| In-app updater | `SemanticVersion(tag)` is compared against `LoreVersion.installed` | Which releases are offered as updates |
| `CFBundleVersion` | Not from this line — `git rev-list --count HEAD` at build time | A monotonic build counter; never the marketing version |

`scripts/build-app.sh` and `scripts/package-release.sh` read the version with the same command, so the bundle and the DMG name cannot drift:

```bash
VERSION="$(sed -n 's/.*static let current = "\([0-9][0-9.]*\)".*/\1/p' Sources/Lore/Version.swift | head -1)"
```

**Never hard-code the version anywhere else** — not in a SwiftUI view, not as a second `Info.plist` field, not in a CI or shell script, not as a literal DMG name. If a second copy exists, Settings → About and the updater will disagree with the bundle, and users will be offered an update that installs an older (or identical) build.

> The Agent API has its own implementation version (`LoreAgentKit.version`, `/health`'s `version` field, and the footer in `docs/AGENT_API.md`). It is deliberately **not** derived from `LoreVersion.current`: bump it separately, only when the Agent API implementation version changes.

---

## Release checklist

### 0. Pre-flight (one minute)

```bash
cd "$(git rev-parse --show-toplevel)"   # repository root
git status --short                      # should be clean before you start
gh auth status                          # a token that can create releases
git tag --sort=-v:refname | head -3     # current release tags
gh release list --limit 3               # current published releases
```

If `gh` is missing: `brew install gh && gh auth login`.

### 1. Choose the version

Use semver and make it **strictly greater** than the latest published tag:

- **patch** (`1.2.0` → `1.2.1`) — fixes, packaging only
- **minor** (`1.2.0` → `1.3.0`) — new features, backwards compatible
- **major** (`1.2.0` → `2.0.0`) — breaking changes

### 2. Bump the one line

Edit `Sources/Lore/Version.swift` (currently line 11 in the `LoreVersion` enum; search for `static let current` if the file has moved):

```swift
static let current = "1.2.0"   →   static let current = "X.Y.Z"
```

That is the whole bump. Do not edit `dist/Lore.app/Contents/Info.plist` by hand — `scripts/build-app.sh` regenerates it on every build. User-facing documentation (README, `docs/`) belongs with the feature pull requests, not with this commit.

### 3. Package

```bash
./scripts/package-release.sh              # swift build (release), then the DMG
./scripts/package-release.sh --no-build   # reuse an existing dist/Lore.app
```

The script:

1. extracts the version with the `sed` command above and rejects anything that is not `X.Y.Z`;
2. runs `./scripts/build-app.sh release` (with `--no-build`: skips this and reuses `dist/Lore.app`);
3. checks `dist/Lore.app`'s `CFBundleShortVersionString` equals `X.Y.Z` and `CFBundleIdentifier` equals `studio.lore.library`, so a stale bundle is never shipped;
4. rebuilds `.build/dmg-stage` with `Lore.app` at the root, an `Applications → /Applications` symlink, and the Finder background in `.background/`;
5. creates a writable UDRW image, mounts it, and runs `scripts/dmg-layout.applescript` to set the 640×586 window centered on the active display, background picture, icon positions, and hidden toolbar/status bar;
6. converts the laid-out image to `dist/Lore-vX.Y.Z.dmg` with `hdiutil` (`-format UDZO`, volume name `Lore X.Y.Z`);
7. prints the DMG path, human-readable size, and SHA-256.

Expected tail of the output:

```text
Packaged Lore X.Y.Z
  DMG      dist/Lore-vX.Y.Z.dmg
  Size     ...
  Volume   Lore X.Y.Z
  SHA-256  ...
```

Keep the SHA-256 for the release notes. The script never tags, pushes, or uploads — publishing is a separate, deliberate step.

The installer window is a static design: `scripts/dmg-background.png` (1280×1120 at 144 DPI, shown as 640×560 points) carries the headline, dotted drag path, and the three first-launch Gatekeeper steps. Icon positions live in `scripts/dmg-layout.applescript`; keep them aligned with the background if you move things. Regenerate the background after editing `scripts/make-dmg-background.py`:

```bash
python3 scripts/make-dmg-background.py   # requires Pillow
```

Finder Automation is needed for the layout. If it is unavailable, the script prints a warning and still produces a valid DMG with a plain Finder window; the app and updater contract are unaffected.

> `CFBundleVersion` is the git commit count at build time, so rebuilding the same version produces different bytes. Upload the artifact you built and record *its* SHA-256; do not rebuild between packaging and publishing.

### 4. Smoke-test the artifact (recommended)

```bash
hdiutil attach -nobrowse -readonly "dist/Lore-vX.Y.Z.dmg"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "/Volumes/Lore X.Y.Z/Lore.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "/Volumes/Lore X.Y.Z/Lore.app/Contents/Info.plist"
open "/Volumes/Lore X.Y.Z/Lore.app"   # optional: launch, then check Settings → About
hdiutil detach "/Volumes/Lore X.Y.Z"
shasum -a 256 "dist/Lore-vX.Y.Z.dmg"
```

The two `PlistBuddy` lines must print `X.Y.Z` (no `v`) and `studio.lore.library`.

### 5. Commit the bump

```bash
git add Sources/Lore/Version.swift
git commit -m "Bump to X.Y.Z"
```

The tagged commit must contain exactly the `Version.swift` that was packaged. Code changes and documentation belong in earlier commits.

### 6. Tag and push

```bash
git tag -a "vX.Y.Z" -m "Lore X.Y.Z"
git push origin main
git push origin "vX.Y.Z"
```

The tag is `v` followed by the exact three-component version. The updater parses `tag_name` as semver and compares it with `LoreVersion.installed`.

### 7. Write the release notes

Create `/tmp/release-notes.md` (or use `--notes "…"`). It is shown on the release page and included in the feed JSON the updater reads. Markdown, English or Chinese — either is fine. Include:

- what changed, grouped by area;
- the SHA-256 printed by `scripts/package-release.sh` for users who prefer a manual download;
- `git log --oneline "$PREV".."vX.Y.Z"` output if you want a complete list.

### 8. Publish the release

```bash
gh release create "vX.Y.Z" "dist/Lore-vX.Y.Z.dmg" \
  --verify-tag \
  --title "Lore X.Y.Z" \
  --notes-file /tmp/release-notes.md
```

- `gh` uses the local file's basename as the asset name. Keep it exactly `Lore-vX.Y.Z.dmg`; renaming the file renames the asset, and agent tooling that follows this document will look for the conventional name.
- Do **not** pass `--draft` or `--prerelease` for a normal release. `releases/latest` ignores both, so the updater would not see the release.
- `--verify-tag` fails the command if the tag was never pushed, which prevents a release whose tag points at nothing.
- Add `--repo Zeyi-Lin/Lore` if you run `gh` from outside the clone.

### 9. Verify

```bash
gh release view "vX.Y.Z" --json tagName,isDraft,isPrerelease,assets \
  --jq '{tag: .tagName, draft: .isDraft, prerelease: .isPrerelease, assets: [.assets[].name]}'

curl -fsSL "https://api.github.com/repos/Zeyi-Lin/Lore/releases/latest" \
  | jq '{tag: .tag_name, draft, prerelease, assets: [.assets[].name]}'
```

Expect `"draft": false`, `"prerelease": false`, and exactly `["Lore-vX.Y.Z.dmg"]` — the same payload the app will read. (Both commands use `jq`; install it with `brew install jq`, or drop the `--jq`/`| jq` part.)

End-to-end update check, from an installed **previous** release:

1. Launch the previous release and open **Settings → About**.
2. Click **Check for Updates**; the new release should appear with its title and an **Install Update** button; **Release Notes** opens the release page.
3. Install once to confirm download, mount, validation, replacement, and relaunch.

For an offline update smoke test without a real previous install, see [Testing an update locally](#testing-an-update-locally).

Also confirm the public artifact byte-for-byte:

```bash
curl -fL -o "/tmp/Lore-vX.Y.Z.dmg" \
  "https://github.com/Zeyi-Lin/Lore/releases/download/vX.Y.Z/Lore-vX.Y.Z.dmg"
shasum -a 256 "/tmp/Lore-vX.Y.Z.dmg"   # must equal the packaging output
```

---

## Updater contract

### What the app does

- **Settings → About** shows `LoreVersion.installed` — rendered as `LoreVersion.display`, e.g. `Lore 1.2.0` — which is the bundle version, falling back to the compiled constant for bare `swift run` builds.
- **Launch auto-check** runs at most once every 24 hours (the timestamp is persisted), is silent on failure, and does not cache a failed attempt, so the next launch retries. There is no polling loop and no background process that checks at intervals.
- **Manual check** — Settings → About → *Check for Updates*, or the app menu's *Check for Updates…* — fetches on demand and surfaces the failure reason.
- A check performs a single `GET https://api.github.com/repos/Zeyi-Lin/Lore/releases/latest`, decodes `tag_name`, `name`, `body`, `html_url`, and `assets`, and compares the tag as semver with the installed version.
- If the latest tag is **strictly newer**, the app offers the release title with **Install Update** and **Release Notes** (opens the GitHub page). Equal or older versions report *You're up to date*.
- **Install Update** downloads the release's DMG asset over HTTPS, mounts it **read-only**, validates the `Lore.app` inside the image (bundle id and version, see below), copies the app to a staging location, then swaps it in **after the app quits**, clears `com.apple.quarantine` on the installed bundle, and relaunches. Install-time failures are surfaced in Settings, and the swap helper logs to `~/Library/Logs/Lore/update.log`.
- **Dev builds not inside a `.app`** (for example `swift run Lore`) can check for updates but cannot self-install — there is no bundle to replace; use a packaged `dist/Lore.app` to test the install path.

### Required release shape

Every future release must satisfy all of these; a release that breaks one is invisible to the updater or gets rejected at install time.

| Requirement | Why it matters |
| --- | --- |
| Tag `vX.Y.Z` — three numeric components, no pre-release suffix for normal releases | The updater parses `tag_name` as semver; a malformed tag (e.g. `latest`, `release-1.2`) fails the check with “Unexpected release payload” instead of silently comparing as zero |
| Newest **non-draft, non-prerelease** release | `releases/latest` excludes drafts and pre-releases; a draft release is simply not seen |
| Exactly one `.dmg` asset named `Lore-vX.Y.Z.dmg` | The updater downloads the release's DMG asset; the conventional name keeps humans, this document, and agent tooling in agreement |
| DMG contains `Lore.app` at the root and an `/Applications` symlink | The updater mounts the image and expects `Lore.app` at the root; the symlink keeps drag-to-install working for humans |
| App's `CFBundleShortVersionString` equals `X.Y.Z` (no leading `v`) | The installer validates this after mounting and refuses a mismatch, so a mis-packaged DMG can never masquerade as the new version |
| App's `CFBundleIdentifier` is `studio.lore.library` | The installer refuses to replace the app with a foreign bundle |
| Ad-hoc signed bundle (current distribution) | The app must launch after install; there is no Developer ID or notarization in this pipeline |

`scripts/package-release.sh` produces exactly this shape and cross-checks the two version fields before writing the DMG.

> The feed helper (`UpdateRelease.installerAsset`) also accepts a `.zip` asset as a fallback when no DMG is attached, but Lore releases ship a DMG: keep exactly one `.dmg` per release so the choice is unambiguous, and let `scripts/package-release.sh` name it.

### Failure modes

| Symptom in the app or release page | Likely cause | Fix |
| --- | --- | --- |
| “Up to date” but GitHub shows a newer release | Release is a **draft** or **pre-release**, so `releases/latest` still returns the older one | Publish it (`gh release edit "vX.Y.Z" --draft=false --prerelease=false`) or re-release without `--draft` / `--prerelease`; verify with `gh release view` |
| No **Install Update** button (the button opens the release page instead), or “This release doesn't include an installer.” | Release has no `.dmg` (or no `.zip`) asset — upload missing/failed | Attach `dist/Lore-vX.Y.Z.dmg` to the release; verify `assets[].name` via the API |
| “The downloaded app doesn't match this release.” | The DMG's `CFBundleShortVersionString` or bundle id does not match the feed | Rebuild and repackage from the same commit, then upload the corrected asset; never edit `Info.plist` by hand |
| “GitHub is rate limiting checks.” (or `HTTP 403`/`429`) | Unauthenticated GitHub API rate limit (60 requests/hour per IP) | Wait, then check again manually. The launch check consumes at most one request per 24 h; only repeated manual testing hits the cap. The app never ships a token |
| “Unexpected release payload: tag_name … is not a version” | Tag is not semver (`latest`, `v1`, `release-1.2`) | Re-release with tag `vX.Y.Z`; the tag is part of the contract |
| `GitHub returned HTTP 404` | No published release, or the repository/API path changed | Confirm `https://api.github.com/repos/Zeyi-Lin/Lore/releases/latest` returns a release |
| Gatekeeper blocks the first launch | Ad-hoc signed, not notarized (expected) | Right-click **Open**, or approve in **System Settings → Privacy & Security**. Updater-installed copies have quarantine cleared already |
| Update installs but About still shows the old number | The DMG carried an old `CFBundleShortVersionString` (stale `--no-build` bundle) | Repackage without `--no-build`, re-upload the asset, then install again |

---

## Testing an update locally

The updater reads a few environment overrides for smoke tests. None is a user-facing feature; all are read from the environment of the launched process.

- `LORE_VERSION_OVERRIDE` — pretend the running app is an older version, without rebuilding (`LoreVersion.installed`).
- `LORE_UPDATE_FEED` — point the feed at a local JSON file (a path or `file://` URL) containing the same payload as the GitHub API, to exercise the check and update-notes flow offline.
- `LORE_UPDATE_DISABLE=1` — skip the automatic launch check while testing other things (a manual check still works).

```bash
# Pretend to be 1.0.0 so the current release is offered; use a local feed fixture.
LORE_VERSION_OVERRIDE=1.0.0 \
LORE_UPDATE_FEED="file:///tmp/latest.json" \
  dist/Lore.app/Contents/MacOS/Lore
```

A minimal feed fixture looks like a GitHub release payload:

```json
{
  "tag_name": "v1.2.0",
  "name": "Lore v1.2.0",
  "body": "Release notes shown on the release page.",
  "html_url": "https://github.com/Zeyi-Lin/Lore/releases/tag/v1.2.0",
  "published_at": "2026-11-15T07:21:19Z",
  "assets": [
    {
      "name": "Lore-v1.2.0.dmg",
      "browser_download_url": "https://github.com/Zeyi-Lin/Lore/releases/download/v1.2.0/Lore-v1.2.0.dmg",
      "size": 6946762
    }
  ]
}
```

The feed and version comparison logic is covered by unit tests (requires a toolchain that ships the `xctest` runner, e.g. full Xcode):

```bash
swift test --filter UpdateFeedTests
```

The full install path can be exercised offline too: when `LORE_UPDATE_FEED` points at a local file, the fixture's `browser_download_url` may be a local `file://` DMG, so check → download → mount → validate → swap → relaunch runs without GitHub. Use a packaged app (`dist/Lore.app`) and a fixture whose tag matches the DMG's `CFBundleShortVersionString`; `LORE_VERSION_OVERRIDE` supplies the older "installed" version. Local asset paths are rejected for real HTTPS feeds.

When launching through `open` (which does not forward shell environment variables), the same switches can be set as defaults instead — `lore.debugUpdateFeed`, `lore.debugDisableUpdateCheck`, and `lore.debugAutoInstallUpdate` (runs the install path without clicking). Delete those keys when finished.

---

## Security notes

- **Ad-hoc signed, not notarized.** Distribution is `codesign --force --deep --sign -` (see `scripts/build-app.sh`); there is no Developer ID and no notarization. The first launch shows the standard Gatekeeper warning. The updater therefore cannot rely on Apple code signing to authenticate a release — it validates the bundle identity and version itself, and the root of trust is the GitHub repository/account plus HTTPS.
- **HTTPS-only, GitHub hosts only.** The release feed is `https://api.github.com`, and an installer asset must be `https:` on `github.com`, `objects.githubusercontent.com`, or another `*.githubusercontent.com` host. Local `file:` assets are accepted only when the feed itself is a local smoke-test fixture (`LORE_UPDATE_FEED`). No third-party mirrors or arbitrary URLs are followed — widening this allowlist is a security change, because the download URL comes from a remote JSON payload.
- **Validate before replacing.** The installer mounts the DMG read-only, checks the bundle at the image root, checks `CFBundleIdentifier` (`studio.lore.library`) and `CFBundleShortVersionString` against the tag, and only then stages a copy. Nothing is executed from the mounted image, and the running bundle is never overwritten in place.
- **Swap after quit.** The user clicks Install Update, the app quits, and a tiny shell helper moves the old bundle aside, copies the staged app into place, clears its quarantine flag, removes the old bundle, and reopens Lore — restoring the previous bundle if the copy fails. A failed swap never leaves a half-installed app.
- **Quarantine handling.** A downloaded DMG carries `com.apple.quarantine`, which would otherwise block the freshly installed app. The install helper clears the flag on the installed bundle before reopening it — the equivalent of `xattr -dr com.apple.quarantine /Applications/Lore.app`. It does not disable Gatekeeper globally and does not affect other apps.
- **No credentials in the app.** Update checks are unauthenticated public GitHub API requests; never embed a personal access token in the app or in scripts that run on users' machines.
- **No downgrades.** Only strictly newer semver versions are installed. Rolling back bad software is a new release (see below), not an update to an older tag.
- **Dev builds cannot self-install.** A process not running from inside a `.app` has no bundle to replace; it may check for updates, but installation requires the packaged app.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `Could not read LoreVersion.current from Sources/Lore/Version.swift` | The `static let current = "X.Y.Z"` line was reformatted or moved | Restore exactly `static let current = "<three-part version>"`; both scripts match that shape with `sed` |
| `Refusing to package: version 'X.Y' is not X.Y.Z` | The version literal is not three numeric components | Use `X.Y.Z`; the updater and DMG naming require it |
| `Version mismatch: Sources/Lore/Version.swift says X.Y.Z but dist/Lore.app says …` | `--no-build` reused a bundle from an earlier version | Run `./scripts/package-release.sh` without `--no-build` |
| `Missing dist/Lore.app` | Nothing has been built yet | Run `./scripts/package-release.sh` (builds by default) or `./scripts/build-app.sh release` first |
| `Refusing to package: bundle id is '…'` | The bundle was built by an old/foreign `build-app.sh` | Rebuild with `./scripts/build-app.sh release`; the id must be `studio.lore.library` |
| `Volume 'Lore X.Y.Z' is already mounted; detach it before packaging.` | A previous build of the same version is still mounted | `hdiutil detach "/Volumes/Lore X.Y.Z"`, close its Finder window, rerun |
| DMG opens with a plain white Finder window | Finder Automation was denied, or `scripts/dmg-background.png` is missing | Allow the terminal/agent under **System Settings → Privacy & Security → Automation → Finder**, or regenerate the background; rerun the package script |
| `warning: Finder layout failed; shipping a plain DMG window` | Same as above; the image is still valid but not guided | Fix Automation, rerun, and re-upload the asset only before publishing |
| `hdiutil: create failed - Resource busy` (or similar) | A previous `Lore X.Y.Z` volume, stale helper image, or the output DMG is open/mounted | `hdiutil info` to list mounted images, `hdiutil detach "/Volumes/Lore X.Y.Z"`, close Finder windows on it, rerun |
| `gh: command not found` or `HTTP 401` from `gh` | GitHub CLI missing or not authenticated | `brew install gh`, then `gh auth login` |
| `gh release create` fails with `--verify-tag` | Tag was not pushed (or is misspelled) | `git push origin "vX.Y.Z"`; confirm with `git tag -l "vX.Y.Z"` |
| `tag already exists` while tagging | The tag (or release) was created by an earlier attempt | `git tag -l "vX.Y.Z"` / `gh release view "vX.Y.Z"`; if the tag is wrong and nothing has been published, delete it locally and remotely and retag |
| Updater reports “up to date” after a successful release | Release is draft/prerelease, installed version equals the tag, or the launch check is still inside its 24 h window | Verify with `gh release view`; run **Check for Updates** manually |
| Update check fails with “GitHub is rate limiting checks.” | Unauthenticated API rate limit (HTTP 403/429) | Wait and retry manually; the hourly limit resets |
| “The downloaded app doesn't match this release.” | DMG app version/bundle id don't match the feed/tag | Re-download from the release page, check the two `PlistBuddy` values, repackage and re-upload if the asset itself is wrong |
| “Lore can't replace itself at this location.” | The app's parent folder is not writable (e.g. running from the DMG or a locked location) | Move `Lore.app` to `/Applications` and retry; the mounted installer is opened for a manual drag-install |
| Update installs but the app doesn't reopen, or the old app is restored | The swap helper failed; it restores the previous bundle instead of leaving a broken install | Read `~/Library/Logs/Lore/update.log`, then retry or reinstall from the release page |

---

## Rollback

The updater only moves **forward**: it installs a release only when the tag is strictly newer than the installed version, and there is no automatic downgrade path. Plan rollbacks accordingly.

**Preferred: ship the fix forward.** Bump to the next patch version (`X.Y.(Z+1)`), package, and release it. This is the only rollback that reaches users who already installed the broken build.

**Hide a broken release from new users.** Drafting or deleting the release makes `releases/latest` fall back to the previous published release, so fresh installs stop being offered the broken build — but users who already updated stay on it and must wait for the fix-forward release.

```bash
gh release edit "vX.Y.Z" --draft          # hides it from releases/latest
gh release delete "vX.Y.Z" --yes --cleanup-tag   # removes release and tag (destructive)
```

**Correct an asset on the same release.** If only the DMG is wrong and the release is otherwise good:

```bash
./scripts/package-release.sh
gh release upload "vX.Y.Z" "dist/Lore-vX.Y.Z.dmg" --clobber
```

Anyone who downloaded the old bytes still has the old file, so record the new SHA-256 in the release notes and prefer a fix-forward version when users may already have installed it.

**Manual fallback for users.** Install the previous good release by downloading its DMG and dragging `Lore.app` to `/Applications`:

```bash
gh release download "v1.1.0" --pattern "Lore-v1.1.0.dmg" --dir /tmp
open "/tmp/Lore-v1.1.0.dmg"
```

Note that the next update check will still offer the newest published version; there is no way to pin a user to an older release.

**Git tags are append-only.** Do not move a tag after it has been published — `releases/latest` and the updater compare tags, and a moved tag makes already-installed builds and the feed disagree. If a release was never published, deleting and retagging is fine.

---

## For an AI agent publishing the next release

This section is the copy-paste version of the checklist. **The only file you edit is `Sources/Lore/Version.swift`, and the only line is `static let current = "X.Y.Z"`.** Do not edit `Info.plist`, SwiftUI views, `README*`, or any other version copy.

Rules:

- Start from a clean tree except your intended edit; never package uncommitted feature work by accident.
- Never use `--draft` or `--prerelease` for a release users should receive.
- Never rename `Lore-vX.Y.Z.dmg`, and never move tags after publishing.
- If any command fails, stop and report it; do not publish a partial release.
- Do not commit the DMG (`dist/` and `.build/` are gitignored) or release notes.

```bash
# From the repository root. The ONLY edit: Sources/Lore/Version.swift
# (currently line 11) → static let current = "X.Y.Z"
cd "$(git rev-parse --show-toplevel)"
git status --short                        # should be clean before the bump

# 1. Bump exactly one line in Sources/Lore/Version.swift: replace the quoted
#    version with X.Y.Z (no other file, no other copy of the number).

# 2. Package. Prints the DMG path, size, and SHA-256; publishes nothing.
./scripts/package-release.sh

# 3. Commit the bump and tag that commit.
VERSION="$(sed -n 's/.*static let current = "\([0-9][0-9.]*\)".*/\1/p' Sources/Lore/Version.swift | head -1)"
echo "Releasing Lore $VERSION"
git add Sources/Lore/Version.swift
git commit -m "Bump to $VERSION"
git tag -a "v$VERSION" -m "Lore $VERSION"
git push origin main
git push origin "v$VERSION"

# 4. Release notes (markdown; shown on the release page). Replace /tmp/release-notes.md
#    with curated notes if you have them; the generated log is valid as a fallback.
PREV="$(git describe --tags --abbrev=0 "v$VERSION^")"
git log --oneline "$PREV".."v$VERSION" > /tmp/release-notes.md

# 5. Publish the DMG as the release asset. Keep the file name exactly
#    Lore-v$VERSION.dmg and do not add --draft or --prerelease.
gh release create "v$VERSION" "dist/Lore-v$VERSION.dmg" \
  --verify-tag \
  --title "Lore $VERSION" \
  --notes-file /tmp/release-notes.md

# 6. Verify the payload the app will read.
gh release view "v$VERSION" --json tagName,isDraft,isPrerelease,assets \
  --jq '{tag: .tagName, draft: .isDraft, prerelease: .isPrerelease, assets: [.assets[].name]}'
curl -fsSL "https://api.github.com/repos/Zeyi-Lin/Lore/releases/latest" \
  | jq '{tag: .tag_name, draft, prerelease, assets: [.assets[].name]}'
```

Acceptance: the final `curl` reports `"tag": "v$VERSION"`, `"draft": false`, `"prerelease": false`, and `"assets": ["Lore-v$VERSION.dmg"]`. Report the tag, asset name, DMG size, and SHA-256 when done.
