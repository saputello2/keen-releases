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
│   ├── publish-release.sh     # Multi-step release pipeline (release → deploy → registry → manifest)
│   ├── deploy-fly.sh          # Pre-deploy backup + rolling Fly.io deploy
│   └── push-fly-registry.sh   # Re-tag GHCR image → Fly private registry (for managed hosting)
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

The release pipeline is a **multi-step flow** that enforces backend deployment
before the client manifest goes live. This ensures clients never see an update
pointing at a not-yet-deployed backend.

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

# 3. Step A — Create GitHub Release (artifacts only, no manifest update)
cd ~/Developer/keen/keen-releases
./scripts/publish-release.sh "$VERSION" "## What's New\n\n- Feature X"

# 4. Verify the release artifacts look correct on GitHub

# 5. Step B — Deploy backend to Fly.io (pre-deploy backup + rolling deploy)
./scripts/publish-release.sh --deploy-fly "$VERSION" keen-dev-trial

# 6. Verify /version reports the new version

# 7. Step B2 — Push image to Fly registry (for managed hosting provisioning)
./scripts/publish-release.sh --push-fly-registry "$VERSION"

# 8. Step C — Publish client manifest (writes latest.json, commits, pushes)
./scripts/publish-release.sh --publish-manifest "$VERSION"
```

**Step A** uploads all 6 artifacts (2 updater tarballs, 2 signatures, 2 DMGs) to
the GitHub Release but does **not** update `latest.json`. Clients don't see the
update yet.

**Step B** calls `deploy-fly.sh`, which takes a pre-deploy `pg_dump` backup on the
Fly volume, performs a rolling deploy with the tagged GHCR image, and verifies
`/version` reports the expected version.

**Step B2** calls `push-fly-registry.sh`, which pulls the image from GHCR, retags
it for `registry.fly.io/keen-backend-images`, and pushes it to Fly's private
registry. This is required for managed hosting — the provisioning service creates
per-user Machines that pull from this registry (Fly cannot pull from private GHCR).

**Step C** downloads the `.sig` files from the GitHub Release, writes `latest.json`
with both platform entries, and pushes to `main`. A confirmation prompt prevents
accidental publishes. After this step, clients see the update.

### Backend image on GHCR

The `keen-backend` repo has a GitHub Actions workflow (`publish-image.yml`) that
builds and pushes a Docker image to GHCR on every `v*` tag push:

```
ghcr.io/saputello2/keen-backend:<version>   (e.g. 0.8.0)
ghcr.io/saputello2/keen-backend:latest
```

Tag the backend repo before running Step B:

```bash
cd ~/Developer/keen/keen-backend
git tag v${VERSION}
git push origin v${VERSION}
# Wait for the GitHub Actions workflow to complete
```

The Tauri updater fetches `latest.json` from:
```
https://raw.githubusercontent.com/saputello2/keen-releases/main/latest.json
```

## Rollback

### Client rollback

Revert `latest.json` to the previous version, commit, and push:

```bash
git revert HEAD   # if the last commit was the manifest update
git push origin main
```

Clients that haven't updated yet will no longer see the new version. Clients that
already updated are unaffected — the Tauri updater does not support downgrades.

### Fly.io image rollback

```bash
APP=keen-dev-trial

# List recent releases to find the previous release ID
flyctl releases list --app "$APP"

# Roll back to the previous image
flyctl releases rollback <prev-release-id> --app "$APP"
```

This swaps the container image but **does not touch the database**. If the
release included migrations that have already run, you also need to restore the
database (see below).

### Fly.io database restore

The `deploy-fly.sh` script takes a `pg_dump` backup before every deploy, stored
at `/data/backups/pre-deploy-<timestamp>-v<version>.dump` on the Fly volume.

To restore after a failed migration:

```bash
APP=keen-dev-trial
BACKUP=pre-deploy-20260421T120000Z-v0.8.0.dump

# 1. Roll back the image first (see above)
flyctl releases rollback <prev-release-id> --app "$APP"

# 2. Restore the database from the pre-deploy backup
flyctl ssh console --app "$APP" -C \
  'bash -c "PGPASSWORD=\$POSTGRES_PASSWORD pg_restore -U postgres -c -d knowledge_explorer /data/backups/'"${BACKUP}"'"'
```

Only the last 5 backups are retained; older ones are pruned automatically.

### Additive-only migration policy

Migrations **must** be additive: new columns, new tables, new indexes. The
following changes are non-additive and require a two-release buffer:

- `DROP COLUMN` / `DROP TABLE`
- `ALTER COLUMN ... TYPE` (column type changes)
- Adding `NOT NULL` without a `DEFAULT` on existing columns

**Two-release buffer**: release N makes the change backward-compatible (e.g. add
a new nullable column); release N+1 drops the old column after clients have
upgraded. This ensures `flyctl releases rollback` (image-only, no DB rollback)
remains safe for any single-version rollback.

A CI check (`migration-additive-check.yml` in `keen-backend`) scans PR diffs of
`src/migrations/*.sql` for these patterns and fails unless the line includes a
`-- @non-additive-ack: <version>` comment.

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
