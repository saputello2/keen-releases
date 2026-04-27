# keen-releases

Update manifest and release artifacts for [Keen](https://thekeen.app) — the Knowledge Explorer Everyone Needs.

This repository serves a single purpose: it hosts the [`latest.json`](./latest.json) update manifest consumed by Keen's built-in auto-updater (Tauri updater plugin), alongside the signed release artifacts attached to [GitHub Releases](../../releases). Binaries (`.dmg`, `.tar.gz`, `.sig`) are attached to releases — never committed to the repo.

If you are looking to download Keen, get it from the [Keen website](https://thekeen.app). If you are looking to verify a release artifact, the [Verifying a release manually](#verifying-a-release-manually) section below has everything you need.

## How auto-updates work

Update checks are **always user-initiated**. There is no automatic startup or background poll. The three entry points inside Keen are:

1. **macOS app menu** → "Keen" → "Check for Updates…"
2. **System tray menu** → "Check for Updates…"
3. **Settings → Updates** → "Check for Updates" button

Selecting any of them runs the same flow:

```
Keen.app fetches latest.json
  → compares manifest version to installed version
  → if newer, prompts the user
  → downloads .tar.gz from the matching GitHub Release
  → verifies Ed25519 signature against the public key embedded in the app
  → replaces the app on disk and relaunches
```

The signature check happens **before** the new bundle is written to disk. An artifact whose signature does not verify is rejected and never executed.

## `latest.json` format

```json
{
  "version": "0.10.0",
  "notes": "## What's New\n\n- Feature X\n- Bug fix Y",
  "pub_date": "2026-04-25T00:00:00.000Z",
  "platforms": {
    "darwin-aarch64": {
      "signature": "<contents of Keen_0.10.0_aarch64.app.tar.gz.sig>",
      "url": "https://github.com/saputello2/keen-releases/releases/download/v0.10.0/Keen_0.10.0_aarch64.app.tar.gz"
    },
    "darwin-x86_64": {
      "signature": "<contents of Keen_0.10.0_x64.app.tar.gz.sig>",
      "url": "https://github.com/saputello2/keen-releases/releases/download/v0.10.0/Keen_0.10.0_x64.app.tar.gz"
    }
  }
}
```

| Field | Description |
|---|---|
| `version` | Semver version string (must match the version baked into the shipped Keen.app) |
| `notes` | Markdown release notes shown in the update dialog |
| `pub_date` | ISO 8601 publication date |
| `platforms.darwin-aarch64.signature` | Base64-encoded contents of the arm64 `.sig` file (Tauri/minisign Ed25519 format) |
| `platforms.darwin-aarch64.url` | Download URL for the arm64 `.tar.gz` updater artifact |
| `platforms.darwin-x86_64.signature` | Base64-encoded contents of the x86_64 `.sig` file (Tauri/minisign Ed25519 format) |
| `platforms.darwin-x86_64.url` | Download URL for the x86_64 `.tar.gz` updater artifact |

> The plain-text form of each `.sig` file is also attached directly to the GitHub Release alongside the `.tar.gz` payloads, which is what the [manual verification](#verifying-a-release-manually) flow uses. The base64-wrapped copy in `latest.json` is what the in-app updater consumes; the two are kept identical by the release pipeline.

The Tauri updater automatically selects the platform key matching the client's
architecture, so a single `latest.json` serves both Apple Silicon and Intel Macs.

A CI workflow (`.github/workflows/validate-manifest.yml`) gates every change to
`latest.json` on: valid JSON, semver `version`, ISO 8601 `pub_date`, non-empty
`signature` blocks for every advertised platform, and reachable artifact URLs.
Manifests that fail the gate cannot be merged to `main`, which is what the
updater fetches.

### Updater artifact naming

Each release on GitHub contains, per architecture:

| Artifact | Purpose |
|---|---|
| `Keen_<version>_aarch64.app.tar.gz` | Updater payload, Apple Silicon |
| `Keen_<version>_aarch64.app.tar.gz.sig` | Ed25519 signature over the tar.gz, Apple Silicon |
| `Keen_<version>_x64.app.tar.gz` | Updater payload, Intel |
| `Keen_<version>_x64.app.tar.gz.sig` | Ed25519 signature over the tar.gz, Intel |
| `Keen_<version>_aarch64.dmg` | Standalone installer, Apple Silicon |
| `Keen_<version>_x64.dmg` | Standalone installer, Intel |

The DMGs are independent installers — they are **not** consumed by the updater
and do not have a `.sig` file (Apple Developer ID signing covers them).

## Verifying a release manually

Every release artifact in this repository is signed with the same Tauri/minisign
Ed25519 keypair. The **public** half of that keypair is published below and is
also embedded into the Keen.app binary at build time, so the updater verifies
every download against it before applying.

You can reproduce that verification from a shell, without running Keen, using
[`minisign`](https://jedisct1.github.io/minisign/) (`brew install minisign`).

### Public key

```
untrusted comment: minisign public key: 99BC37E2890FE289
RWSJ4g+J4je8mdZOVjwK/6WQqZ3fIQB4JTBzTiZCPOq5kFOWliG2o2cH
```

This is what every Keen.app trusts. If the value baked into your installed app
does not match (Tauri stores it under `bundle.updater.pubkey` in the Tauri
config that ships inside the bundle), do not run that build and please report
it.

### Steps

```bash
VERSION=0.10.0
ARCH=aarch64   # or x64

# 1. Download the artifact and its signature
gh release download "v$VERSION" \
  --repo saputello2/keen-releases \
  --pattern "Keen_${VERSION}_${ARCH}.app.tar.gz*"

# 2. Save the public key to a local file
cat > keen-updater.pub <<'EOF'
untrusted comment: minisign public key: 99BC37E2890FE289
RWSJ4g+J4je8mdZOVjwK/6WQqZ3fIQB4JTBzTiZCPOq5kFOWliG2o2cH
EOF

# 3. Verify the signature
minisign -V \
  -p keen-updater.pub \
  -m "Keen_${VERSION}_${ARCH}.app.tar.gz" \
  -x "Keen_${VERSION}_${ARCH}.app.tar.gz.sig"
```

A successful verification prints `Signature and comment signature verified`. A
tampered or substituted artifact will fail with a non-zero exit code; **do not
run it**.

If you want to verify the same `.sig` content the auto-updater consumed, the
raw text of the `.sig` file is also embedded verbatim in
[`latest.json`](./latest.json) under `platforms.darwin-<arch>.signature`. The
two sources are kept identical by the release pipeline.

## Security model

- Update artifacts are signed with an Ed25519 keypair (Tauri/minisign format).
- The public half is published in this README and baked into every Keen.app at build time. The private half lives offline on a single signing host and is never present in CI or any deployed environment.
- The Tauri updater verifies the signature **before** writing the new bundle to disk; an artifact whose signature does not verify is rejected and discarded.
- Compromise of GitHub (this repo, the GitHub Actions runners, or `latest.json`) is therefore not sufficient to ship a malicious update — an attacker would also need the private signing key, which is held outside that trust boundary.
- Code signing and notarization are additionally enforced by Apple Developer ID; macOS Gatekeeper checks both before the bundle is allowed to launch.

## Platform support

| Platform | Architecture | Status |
|---|---|---|
| macOS | aarch64 (Apple Silicon) | Supported |
| macOS | x86_64 (Intel) | Supported (macOS 13+ practical minimum) |
| Windows | x86_64 | Not yet |
| Linux | x86_64 | Not yet |
