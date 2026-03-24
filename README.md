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
│   └── publish-release.sh     # Build manifest + create GitHub Release
└── README.md
```

## latest.json Format

```json
{
  "version": "0.7.0",
  "notes": "## What's New\n\n- Feature X\n- Bug fix Y",
  "pub_date": "2026-03-24T00:00:00.000Z",
  "platforms": {
    "darwin-aarch64": {
      "signature": "<contents of Keen.app.tar.gz.sig>",
      "url": "https://github.com/saputello2/keen-releases/releases/download/v0.7.0/Keen.app.tar.gz"
    }
  }
}
```

| Field | Description |
|---|---|
| `version` | Semver version string (must match `tauri.conf.json`) |
| `notes` | Markdown release notes shown in the update dialog |
| `pub_date` | ISO 8601 publication date |
| `platforms.darwin-aarch64.signature` | Raw text content of the `.sig` file (Ed25519) |
| `platforms.darwin-aarch64.url` | Download URL for the `.tar.gz` update artifact |

## Publishing a Release

### Prerequisites

- Tauri signing key at `~/.tauri/keen-updater.key`
- Apple Developer ID certificate in Keychain
- `gh` CLI authenticated (`gh auth status`)

### Steps

```bash
# 1. Build the signed + notarized release from keen-frontend
cd ~/Developer/keen/keen-frontend
export TAURI_SIGNING_PRIVATE_KEY=$(cat ~/.tauri/keen-updater.key)
npm run tauri build

# 2. Run the publish script
cd ~/Developer/keen/keen-releases
./scripts/publish-release.sh 0.7.0 "## What's New\n\n- License gate\n- Auto-updater"
```

Or manually:

```bash
VERSION=0.7.0
BUNDLE=~/Developer/keen/keen-frontend/src-tauri/target/release/bundle

# Create GitHub Release with artifacts
gh release create "v${VERSION}" \
  "${BUNDLE}/macos/Keen.app.tar.gz" \
  "${BUNDLE}/macos/Keen.app.tar.gz.sig" \
  "${BUNDLE}/dmg/Keen_${VERSION}_aarch64.dmg" \
  --title "v${VERSION}" \
  --notes "Release notes here"

# Update latest.json with new version, signature, and URL
# then commit and push
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
| macOS | x86_64 (Intel) | Planned |
| Windows | x86_64 | Not yet |
| Linux | x86_64 | Not yet |
