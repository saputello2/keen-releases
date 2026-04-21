# keen-releases

Update manifest and release artifacts for [Keen](https://thekeen.app) — the Knowledge Explorer Everyone Needs.

This repo hosts the `latest.json` manifest consumed by Keen's built-in auto-updater (Tauri updater plugin). Binary artifacts (`.dmg`, `.tar.gz`, `.sig`) are attached to [GitHub Releases](../../releases), not committed to the repository.

## How It Works

```
Keen.app → checks latest.json → compares versions → downloads .tar.gz → verifies Ed25519 signature → installs
```

1. On startup (8s delay) and via Settings > Updates, Keen fetches `latest.json` from this repo
2. If a newer version is available, the user is prompted to download and install
3. The `.tar.gz` update artifact is downloaded from the GitHub Release
4. The Ed25519 signature is verified against the public key baked into the app
5. The app is replaced and relaunched

## Repository Structure

```
keen-releases/
├── latest.json                # Update manifest (Tauri updater format)
├── scripts/
│   └── publish-release.sh     # Build manifest + create GitHub Release (dual-arch)
└── README.md
```

Related tooling in the sibling `keen-frontend` repo:

```
keen-frontend/scripts/
└── rename-updater-artifacts.sh  # Renames Keen.app.tar.gz → Keen_${VERSION}_${ARCH}.app.tar.gz
```

## latest.json Format

```json
{
  "version": "0.8.0",
  "notes": "## What's New\n\n- Feature X\n- Bug fix Y",
  "pub_date": "2026-04-01T00:00:00.000Z",
  "platforms": {
    "darwin-aarch64": {
      "signature": "<contents of Keen_0.8.0_aarch64.app.tar.gz.sig>",
      "url": "https://github.com/saputello2/keen-releases/releases/download/v0.8.0/Keen_0.8.0_aarch64.app.tar.gz"
    },
    "darwin-x86_64": {
      "signature": "<contents of Keen_0.8.0_x64.app.tar.gz.sig>",
      "url": "https://github.com/saputello2/keen-releases/releases/download/v0.8.0/Keen_0.8.0_x64.app.tar.gz"
    }
  }
}
```

| Field | Description |
|---|---|
| `version` | Semver version string (must match `tauri.conf.json`) |
| `notes` | Markdown release notes shown in the update dialog |
| `pub_date` | ISO 8601 publication date |
| `platforms.darwin-aarch64.signature` | Raw text content of the arm64 `.sig` file (Ed25519) |
| `platforms.darwin-aarch64.url` | Download URL for the arm64 `.tar.gz` updater artifact |
| `platforms.darwin-x86_64.signature` | Raw text content of the x86_64 `.sig` file (Ed25519) |
| `platforms.darwin-x86_64.url` | Download URL for the x86_64 `.tar.gz` updater artifact |

The Tauri updater automatically selects the platform key matching the client's
architecture, so a single `latest.json` serves both Apple Silicon and Intel Macs.

### Artifact naming

Tauri v2 emits the updater artifact as a literal `Keen.app.tar.gz` (no version,
no arch) at different paths per target. Before uploading to a GitHub Release,
rename each one in place with `scripts/rename-updater-artifacts.sh` in the
sibling `keen-frontend` repo so the arm64 and x86_64 artifacts don't collide:

| Arch | Source | Renamed to |
|---|---|---|
| arm64 | `src-tauri/target/release/bundle/macos/Keen.app.tar.gz` | `Keen_${VERSION}_aarch64.app.tar.gz` |
| x86_64 | `src-tauri/target/x86_64-apple-darwin/release/bundle/macos/Keen.app.tar.gz` | `Keen_${VERSION}_x64.app.tar.gz` |

DMG artifacts are already version + arch qualified by Tauri
(`Keen_${VERSION}_aarch64.dmg`, `Keen_${VERSION}_x64.dmg`) — no rename needed.

## Publishing a Release

### Prerequisites

- Tauri signing key at `~/.tauri/keen-updater.key`
- Apple Developer ID certificate in Keychain
- `gh` CLI authenticated (`gh auth status`)

### Steps

See `docs/build/dual-architecture-builds.md` in the sibling `keen-frontend` repo
for the full arm64 and x86_64 build procedures.

```bash
VERSION=0.8.0
cd ~/Developer/keen/keen-frontend
export TAURI_SIGNING_PRIVATE_KEY=$(cat ~/.tauri/keen-updater.key)

# 1. Build arm64 (Apple Silicon) — native
npm run tauri build
./scripts/rename-updater-artifacts.sh aarch64 "$VERSION"

# 2. Build x86_64 (Intel) — cross-compiled
TARGET_ARCH=x86_64 npm run tauri build -- \
  --target x86_64-apple-darwin \
  --config src-tauri/tauri.conf.x86_64-patch.json
./scripts/rename-updater-artifacts.sh x86_64 "$VERSION"

# 3. Publish both architectures in a single GitHub Release
cd ~/Developer/keen/keen-releases
./scripts/publish-release.sh "$VERSION" "## What's New\n\n- Intel support"
```

The publish script uploads all 6 artifacts (2 updater tarballs, 2 signatures,
2 DMGs) to the GitHub Release and writes `latest.json` with entries for both
`darwin-aarch64` and `darwin-x86_64`.

Or manually, skipping the script:

```bash
VERSION=0.8.0
ARM64_BUNDLE=~/Developer/keen/keen-frontend/src-tauri/target/release/bundle
X64_BUNDLE=~/Developer/keen/keen-frontend/src-tauri/target/x86_64-apple-darwin/release/bundle

gh release create "v${VERSION}" \
  "${ARM64_BUNDLE}/macos/Keen_${VERSION}_aarch64.app.tar.gz" \
  "${ARM64_BUNDLE}/macos/Keen_${VERSION}_aarch64.app.tar.gz.sig" \
  "${ARM64_BUNDLE}/dmg/Keen_${VERSION}_aarch64.dmg" \
  "${X64_BUNDLE}/macos/Keen_${VERSION}_x64.app.tar.gz" \
  "${X64_BUNDLE}/macos/Keen_${VERSION}_x64.app.tar.gz.sig" \
  "${X64_BUNDLE}/dmg/Keen_${VERSION}_x64.dmg" \
  --title "v${VERSION}" \
  --notes "Release notes here"

# Update latest.json with both platform entries (signatures + URLs),
# then commit and push.
```

### Updating latest.json

The `publish-release.sh` script automates this, but the key steps are:

1. Read the `.sig` file contents
2. Update `version`, `pub_date`, `signature`, and `url` in `latest.json`
3. Commit and push to `main`

The Tauri updater fetches `latest.json` from:
```
https://raw.githubusercontent.com/saputello2/keen-releases/main/latest.json
```

## Security

- All update artifacts are signed with an Ed25519 key pair
- The public key is embedded in the app binary at build time
- The app verifies the signature before applying any update
- Code signing and notarization are handled by Apple Developer ID

## Platform Support

| Platform | Architecture | Status |
|---|---|---|
| macOS | aarch64 (Apple Silicon) | Supported |
| macOS | x86_64 (Intel) | Supported (macOS 13+ practical minimum) |
| Windows | x86_64 | Not yet |
| Linux | x86_64 | Not yet |
