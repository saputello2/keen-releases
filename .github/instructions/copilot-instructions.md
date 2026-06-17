---
name: 'Keen Releases Codebase Instructions'
description: 'Overview of the release manifest, artifact pipeline, and auto-updater for the Keen desktop app'
applyTo: 'keen-releases/**'
---

# Keen Releases Codebase Instructions

## Purpose

Release manifest and artifact host for the Keen desktop app's **Tauri auto-updater**. Binaries (`.dmg`, `.tar.gz`, `.sig`) are attached to GitHub Releases — never committed. The only tracked data file is `latest.json`.

## Repository Layout

```
keen-releases/
├── latest.json                          # Tauri updater manifest (the core artifact)
├── scripts/
│   ├── publish-release.sh               # Multi-step release pipeline orchestrator
│   └── push-fly-registry.sh             # Re-tag GHCR → Fly private registry (legacy)
├── .github/workflows/
│   └── validate-manifest.yml            # CI gate — validates latest.json on PR/push
├── docs/                                # Git-ignored — internal runbook (not public)
└── README.md                            # Public docs: update flow, verification, security
```

No `package.json`, build tools, or test framework — this is a pure manifest + scripts repo.

## `latest.json` Schema

The Tauri updater checks this file to determine if an update is available. The updater selects the platform key matching the client architecture.

```json
{
  "version": "0.11.0",
  "notes": "Release notes (shown in update dialog)",
  "pub_date": "2026-04-27T12:49:22.000Z",
  "platforms": {
    "darwin-aarch64": {
      "signature": "<base64 Ed25519 .sig contents>",
      "url": "https://github.com/saputello2/keen-releases/releases/download/v0.11.0/Keen_0.11.0_aarch64.app.tar.gz"
    },
    "darwin-x86_64": {
      "signature": "<base64 Ed25519 .sig contents>",
      "url": "https://github.com/saputello2/keen-releases/releases/download/v0.11.0/Keen_0.11.0_x64.app.tar.gz"
    }
  }
}
```

Only macOS is supported currently (darwin-aarch64, darwin-x86_64).

## Release Pipeline (`scripts/publish-release.sh`)

Three modes, run in sequence for a full release:

| Step | Command | What it does |
|---|---|---|
| **A** | `publish-release.sh <version> [notes]` | Creates GitHub Release with 6 artifacts (2 `.tar.gz`, 2 `.sig`, 2 `.dmg`). Auto-detects arm64 bundle path. |
| Step | Command | What it does |
|---|---|---|
| **A** | `publish-release.sh <version> [notes]` | Creates GitHub Release with 6 artifacts (2 `.tar.gz`, 2 `.sig`, 2 `.dmg`). Auto-detects arm64 bundle path. |
| **B** | `publish-release.sh --publish-manifest <version>` | Downloads `.sig` files from GH Release, builds `latest.json` via `jq`, commits and pushes to `main` |
| **(legacy)** | `publish-release.sh --push-fly-registry <version>` | **Retired** — errors unless `KEEN_ALLOW_LEGACY_FLY_REGISTRY_PUSH=1`. Legacy docker mirror; not used by managed hosting. |

**Managed hosting (Fly Machines)** — separate pipeline; see `managed-backend-release` skill:
GHCR (CI) → `sign-and-publish-manifest` → `KEEN_IMAGE_TAG` → `flyctl machine update`.

**Artifact naming convention** (from `keen-frontend` Tauri build output):
- `Keen_<VERSION>_aarch64.app.tar.gz` + `.sig` (updater payload + signature)
- `Keen_<VERSION>_x64.app.tar.gz` + `.sig`
- `Keen_<VERSION>_aarch64.dmg` + `Keen_<VERSION>_x64.dmg` (manual download)

## Version Bumping (Step 0)

Before building, update 3 files in `keen-frontend/` in lockstep:
- `src-tauri/tauri.conf.json` → `"version"`
- `src-tauri/Cargo.toml` → `[package].version`
- `package.json` → `"version"`

## CI Validation (`validate-manifest.yml`)

Runs on push to `main` and PRs when `latest.json` changes. Five checks:

1. Required JSON fields (`version`, `notes`, `pub_date`, `platforms`)
2. Semver format (`^[0-9]+\.[0-9]+\.[0-9]+$`)
3. ISO 8601 date validation
4. Non-empty signatures per platform
5. Reachable artifact URLs (HEAD request)

## Security

- **Ed25519 signing** via Tauri/minisign — private key at `~/.tauri/keen-updater.key`, set via `TAURI_SIGNING_PRIVATE_KEY` env var during builds
- **Apple Developer ID** notarization for `.dmg` and `.app` bundles
- **Public key** (for manual verification with `minisign -V`):
  ```
  RWSJ4g+J4je8mdZOVjwK/6WQqZ3fIQB4JTBzTiZCPOq5kFOWliG2o2cH
  ```


## Rollback Procedures

- **Client rollback**: `git revert HEAD` on `latest.json`, push to `main`
- **Managed-hosting image rollback**: `flyctl machine update <id> --image ghcr.io/saputello2/keen-backend:<prev-version> -a keen-<subdomain>` per affected machine (see `keen-frontend/docs/runbooks/managed-hosting-infrastructure-setup.md` → "Rolling out a backend-only patch")
- **Database restore**: `pg_restore` from a backup on the per-user Fly volume

## Conventions

- **Commit messages**: `release: v<version>` for manifest updates, conventional commits for tooling
- **No test files** — CI validates the manifest schema only
- **`docs/` is git-ignored** — operator-facing runbook lives there locally, never pushed (repo is public)
