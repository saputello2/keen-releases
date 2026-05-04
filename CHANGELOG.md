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
