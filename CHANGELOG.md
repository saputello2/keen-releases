# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Scope of this CHANGELOG.** `keen-releases` ships two distinct artifacts:
>
> 1. The **per-version GitHub Release pages** (`v0.X.Y` tags) — those carry
>    the user-visible release notes for the desktop app. Those notes live on
>    the GitHub Releases UI and inside `latest.json`'s `notes` field. **They
>    do NOT belong in this CHANGELOG.**
> 2. The **release-pipeline tooling** itself (`scripts/publish-release.sh`,
>    `scripts/push-fly-registry.sh`, `.github/workflows/validate-manifest.yml`,
>    `latest.json` schema changes, runbook updates). Changes to that pipeline
>    DO belong in this CHANGELOG, because they affect every future release
>    and aren't versioned per-tag.
>
> When unsure: ask "would a future release author / operator need to know
> this?" If yes → CHANGELOG. If it's just "what changed in 0.12.4 for end
> users" → GitHub Release notes only.

## [Unreleased]

### Added

- **`publish-release.sh` now auto-consumes the `.release-notes-<version>.md` authoring convention, so real user-facing notes flow into `latest.json` without a manual copy step** (`scripts/publish-release.sh` Step A + `--publish-manifest`; `.gitignore`). The operator has been authoring per-release notes into `keen-releases/.release-notes-<version>.md` (present for 0.20.0 / 0.21.0 / 0.22.0 / 0.22.1) but nothing in the pipeline read them, so they never reached the manifest. Both Step A (create GitHub Release) and `--publish-manifest` (write `latest.json`) now resolve notes by precedence: explicit `--notes "<string>"` / positional arg → `--notes-file <path>` → `.release-notes-<version>.md` (auto) → the GitHub Release body → placeholder-guard abort. Added `--notes-file` / `--notes` overrides to `--publish-manifest` for the cases where the convention file isn't used. The `.release-notes-*.md` files are now git-ignored (this repo is public; the published copy lives on the GitHub Release page + `latest.json`, so the drafts stay local scratch).

### Fixed

- **`publish-release.sh --publish-manifest` now refuses to ship placeholder / empty release notes into `latest.json`, closing the 0.21.0 / 0.22.1 leak where the in-app updater showed build-pipeline instructions to end users** (`scripts/publish-release.sh` new `notes_are_placeholder` guard). `latest.json`'s `notes` field is rendered verbatim in the desktop updater dialog, and `--publish-manifest` fetched it straight from the GitHub Release body. The keen-frontend CI `publish-draft` job seeds every draft release body with an operator placeholder (`"Draft release built by keen-frontend release workflow. Operator: review artifacts, then run Step B … Step C …"`); when the operator promoted the draft to public without editing that body, the placeholder flowed verbatim into `latest.json` — so 0.21.0 and 0.22.1 users literally saw `publish-release.sh --push-fly-registry` / `--publish-manifest` operator instructions as the release note. The guard aborts (with a fix-it message pointing at the release-body edit URL, `--notes-file`, and `--notes`) when the resolved notes are empty, equal the trivial `Release vX.Y.Z` default, or still contain the CI placeholder marker (`<!-- keen:release-notes-placeholder -->`) or the legacy operator text. Pairs with the keen-frontend `release.yml` change that swaps the draft body from operator instructions to a detectable placeholder (operator steps moved to the workflow run's job summary).

### Changed

- **`publish-release.sh` — retire misleading `--push-fly-registry` as the managed-hosting path.** Step B is now `--publish-manifest` (desktop `latest.json` only). `--push-fly-registry` errors by default with pointers to `managed-backend-release` (GHCR → `sign-and-publish-manifest` → `KEEN_IMAGE_TAG` → `flyctl machine update`); the legacy `push-fly-registry.sh` docker mirror requires `KEEN_ALLOW_LEGACY_FLY_REGISTRY_PUSH=1`. Post–Step A "Next steps" no longer sends operators at a local Docker daemon for Fly releases. `copilot-instructions.md` table aligned to the same step letters.
