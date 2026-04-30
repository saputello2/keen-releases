#!/usr/bin/env bash
# ============================================================================
# publish-release.sh
# ============================================================================
# Multi-step release pipeline for Keen. Each step is a separate invocation:
#
#   Step A — Create GitHub Release (client artifacts only)
#     publish-release.sh <version> [release-notes] \
#       [--arm64-bundle <dir>] [--x64-bundle <dir>]
#
#   Step B — Push image to Fly registry (for managed hosting provisioning)
#     publish-release.sh --push-fly-registry <version>
#
#   Step C — Publish client update manifest (latest.json)
#     publish-release.sh --publish-manifest <version>
#
# The intended multi-step flow is: push the image BEFORE publishing the
# client manifest, so clients never see an update pointing at an image
# that managed hosting can't yet provision. Step B keeps managed hosting
# able to roll new versions onto user machines. (The script does not
# currently *enforce* this ordering — `--publish-manifest` will run
# regardless of whether the image is in the registry — so treat the
# sequence as a recommended runbook, not a guard.)
#
# (The previous Step B "Deploy backend to Fly.io (keen-dev-trial)" path
# was retired along with the keen-dev-trial Fly app. Managed-hosting
# machines are provisioned by `keen-provisioning` via Fly's Machines
# API directly, not via `fly deploy` against a fly.toml.)
#
# Expects the renamed updater artifacts produced by
# keen-frontend/scripts/rename-updater-artifacts.sh:
#   Keen_${VERSION}_aarch64.app.tar.gz  (+ .sig)
#   Keen_${VERSION}_x64.app.tar.gz       (+ .sig)
# plus DMGs (already version + arch named by Tauri):
#   Keen_${VERSION}_aarch64.dmg
#   Keen_${VERSION}_x64.dmg
#
# Defaults (matching dual-architecture-builds.md):
#   arm64 bundle dir: keen-frontend/src-tauri/target/release/bundle
#   x64   bundle dir: keen-frontend/src-tauri/target/x86_64-apple-darwin/release/bundle
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GH_REPO="saputello2/keen-releases"

usage() {
  cat >&2 <<'USAGE'
Usage:
  Step A — Create GitHub Release:
    publish-release.sh <version> [release-notes] \
      [--arm64-bundle <dir>] [--x64-bundle <dir>]

  Step B — Push image to Fly registry (managed hosting):
    publish-release.sh --push-fly-registry <version>

  Step C — Publish client manifest:
    publish-release.sh --publish-manifest <version>
USAGE
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

# ── Route to the correct step ──
case "$1" in
  --push-fly-registry)
    # ── Step B2: Push image to Fly registry for managed hosting ──
    shift
    if [[ $# -lt 1 ]]; then
      echo "Usage: publish-release.sh --push-fly-registry <version>" >&2
      exit 1
    fi
    VERSION="$1"

    echo "=== Step B2: Push keen-backend ${VERSION} to Fly registry ==="
    echo ""

    if [[ ! -x "$SCRIPT_DIR/push-fly-registry.sh" ]]; then
      echo "ERROR: push-fly-registry.sh not found at $SCRIPT_DIR/push-fly-registry.sh" >&2
      exit 1
    fi

    "$SCRIPT_DIR/push-fly-registry.sh" "$VERSION"
    exit $?
    ;;

  --publish-manifest)
    # ── Step C: Publish latest.json ──
    shift
    if [[ $# -lt 1 ]]; then
      echo "Usage: publish-release.sh --publish-manifest <version>" >&2
      exit 1
    fi
    VERSION="$1"

    echo "=== Step C: Publish client manifest for ${VERSION} ==="
    echo ""

    # Verify the GitHub Release exists
    if ! gh release view "v${VERSION}" --repo "$GH_REPO" > /dev/null 2>&1; then
      echo "ERROR: GitHub Release v${VERSION} not found in ${GH_REPO}." >&2
      echo "Run Step A first: publish-release.sh ${VERSION}" >&2
      exit 1
    fi

    # Download .sig files from the release to read signatures
    TMPDIR_SIGS=$(mktemp -d)
    trap 'rm -rf "$TMPDIR_SIGS"' EXIT

    echo "Downloading signatures from GitHub Release v${VERSION}..."
    gh release download "v${VERSION}" \
      --repo "$GH_REPO" \
      --pattern "*.sig" \
      --dir "$TMPDIR_SIGS"

    ARM64_SIG_FILE="${TMPDIR_SIGS}/Keen_${VERSION}_aarch64.app.tar.gz.sig"
    X64_SIG_FILE="${TMPDIR_SIGS}/Keen_${VERSION}_x64.app.tar.gz.sig"

    if [[ ! -f "$ARM64_SIG_FILE" ]] || [[ ! -f "$X64_SIG_FILE" ]]; then
      echo "ERROR: Could not find both .sig files in the release." >&2
      echo "  Expected: Keen_${VERSION}_aarch64.app.tar.gz.sig" >&2
      echo "  Expected: Keen_${VERSION}_x64.app.tar.gz.sig" >&2
      ls -la "$TMPDIR_SIGS" >&2
      exit 1
    fi

    ARM64_SIGNATURE=$(cat "$ARM64_SIG_FILE")
    X64_SIGNATURE=$(cat "$X64_SIG_FILE")

    RELEASE_BASE="https://github.com/${GH_REPO}/releases/download/v${VERSION}"
    ARM64_URL="${RELEASE_BASE}/Keen_${VERSION}_aarch64.app.tar.gz"
    X64_URL="${RELEASE_BASE}/Keen_${VERSION}_x64.app.tar.gz"

    # Fetch release notes from the GH release
    NOTES=$(gh release view "v${VERSION}" --repo "$GH_REPO" --json body -q .body 2>/dev/null || echo "Release v${VERSION}")
    if [[ -z "$NOTES" ]]; then
      NOTES="Release v${VERSION}"
    fi

    PUB_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    echo ""
    echo "About to update latest.json and push to main:"
    echo "  Version:  ${VERSION}"
    echo "  arm64 URL: ${ARM64_URL}"
    echo "  x64 URL:   ${X64_URL}"
    echo ""
    read -r -p "Proceed? (y/N) " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
      echo "Aborted."
      exit 1
    fi

    # Build latest.json via jq so the notes (which contain newlines, quotes,
    # backticks, and Unicode) are correctly JSON-escaped. Direct heredoc
    # interpolation produces invalid JSON as soon as $NOTES contains any
    # character that needs escaping, which silently breaks every client's
    # update check.
    if ! command -v jq >/dev/null 2>&1; then
      echo "ERROR: jq is required to build latest.json. Install it (brew install jq)." >&2
      exit 1
    fi
    jq -n \
      --arg version "$VERSION" \
      --arg notes "$NOTES" \
      --arg pub_date "$PUB_DATE" \
      --arg arm64_sig "$ARM64_SIGNATURE" \
      --arg arm64_url "$ARM64_URL" \
      --arg x64_sig "$X64_SIGNATURE" \
      --arg x64_url "$X64_URL" \
      '{
        version: $version,
        notes: $notes,
        pub_date: $pub_date,
        platforms: {
          "darwin-aarch64": { signature: $arm64_sig, url: $arm64_url },
          "darwin-x86_64":  { signature: $x64_sig,   url: $x64_url }
        }
      }' > "${REPO_DIR}/latest.json"

    # Sanity-check that the generated file actually parses.
    if ! jq empty "${REPO_DIR}/latest.json" >/dev/null 2>&1; then
      echo "ERROR: Generated latest.json is not valid JSON." >&2
      exit 1
    fi

    cd "$REPO_DIR"
    git add latest.json
    git commit -m "release: v${VERSION}"
    git push origin main

    echo ""
    echo "=== Manifest published ==="
    echo "  Manifest: https://raw.githubusercontent.com/${GH_REPO}/main/latest.json"
    echo "  Clients will now see v${VERSION} as an available update."
    exit 0
    ;;

  --help|-h)
    usage
    ;;

  --*)
    echo "ERROR: Unknown flag: $1" >&2
    usage
    ;;
esac

# ── Step A: Create GitHub Release ──
VERSION="$1"
shift

NOTES="Release v${VERSION}"
if [[ $# -gt 0 && "$1" != --* ]]; then
  NOTES="$1"
  shift
fi

FRONTEND_DIR="$HOME/Developer/keen/keen-frontend"

# arm64 bundle candidates: default build writes to target/release/bundle;
# `--target aarch64-apple-darwin` writes to the triple-qualified path.
# Pick whichever actually contains the version+arch-named updater tarball.
ARM64_CANDIDATES=(
  "$FRONTEND_DIR/src-tauri/target/release/bundle"
  "$FRONTEND_DIR/src-tauri/target/aarch64-apple-darwin/release/bundle"
)
ARM64_BUNDLE=""
X64_BUNDLE="$FRONTEND_DIR/src-tauri/target/x86_64-apple-darwin/release/bundle"

# Optional explicit overrides (handled before auto-detect).
ARM64_OVERRIDE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arm64-bundle)
      ARM64_OVERRIDE="${2:?--arm64-bundle requires a path}"
      shift 2
      ;;
    --x64-bundle)
      X64_BUNDLE="${2:?--x64-bundle requires a path}"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown flag: $1" >&2
      usage
      ;;
  esac
done

if [[ -n "$ARM64_OVERRIDE" ]]; then
  ARM64_BUNDLE="$ARM64_OVERRIDE"
else
  for p in "${ARM64_CANDIDATES[@]}"; do
    if [[ -f "$p/macos/Keen_${VERSION}_aarch64.app.tar.gz" ]]; then
      ARM64_BUNDLE="$p"
      break
    fi
  done
  # Fall back to the default path so the missing-artifact error downstream
  # has a sensible path to report.
  [[ -z "$ARM64_BUNDLE" ]] && ARM64_BUNDLE="${ARM64_CANDIDATES[0]}"
fi

echo "=== Step A: Create GitHub Release v${VERSION} ==="
echo ""

ARM64_TAR="${ARM64_BUNDLE}/macos/Keen_${VERSION}_aarch64.app.tar.gz"
ARM64_SIG="${ARM64_BUNDLE}/macos/Keen_${VERSION}_aarch64.app.tar.gz.sig"
ARM64_DMG="${ARM64_BUNDLE}/dmg/Keen_${VERSION}_aarch64.dmg"

X64_TAR="${X64_BUNDLE}/macos/Keen_${VERSION}_x64.app.tar.gz"
X64_SIG="${X64_BUNDLE}/macos/Keen_${VERSION}_x64.app.tar.gz.sig"
X64_DMG="${X64_BUNDLE}/dmg/Keen_${VERSION}_x64.dmg"

MISSING=()
for f in "$ARM64_TAR" "$ARM64_SIG" "$ARM64_DMG" "$X64_TAR" "$X64_SIG" "$X64_DMG"; do
  if [[ ! -f "$f" ]]; then
    MISSING+=("$f")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "ERROR: Missing artifact(s):" >&2
  for f in "${MISSING[@]}"; do
    echo "  - $f" >&2
  done
  echo "" >&2
  echo "Expected workflow:" >&2
  echo "  1. Build arm64:  cd keen-frontend && npm run tauri build" >&2
  echo "  2. Rename arm64: ./scripts/rename-updater-artifacts.sh aarch64 ${VERSION}" >&2
  echo "  3. Build x64:    TARGET_ARCH=x86_64 npm run tauri build -- \\" >&2
  echo "                     --target x86_64-apple-darwin \\" >&2
  echo "                     --config src-tauri/tauri.conf.x86_64-patch.json" >&2
  echo "  4. Rename x64:   ./scripts/rename-updater-artifacts.sh x86_64 ${VERSION}" >&2
  exit 1
fi

echo "Creating GitHub Release v${VERSION} with arm64 + x86_64 artifacts..."
gh release create "v${VERSION}" \
  "$ARM64_TAR" \
  "$ARM64_SIG" \
  "$ARM64_DMG" \
  "$X64_TAR" \
  "$X64_SIG" \
  "$X64_DMG" \
  --repo "$GH_REPO" \
  --title "v${VERSION}" \
  --notes "$NOTES"

echo ""
echo "=== GitHub Release created ==="
echo "  Release: https://github.com/${GH_REPO}/releases/tag/v${VERSION}"
echo ""
echo "Next steps:"
echo "  1. Verify the release artifacts look correct"
echo "  2. Push the image to Fly registry (for managed hosting):"
echo "       ./publish-release.sh --push-fly-registry ${VERSION}"
echo "  3. After verifying /version on a managed-hosting machine, publish"
echo "     the client manifest:"
echo "       ./publish-release.sh --publish-manifest ${VERSION}"
