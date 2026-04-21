#!/usr/bin/env bash
# ============================================================================
# publish-release.sh
# ============================================================================
# Creates a GitHub Release with macOS arm64 + x86_64 artifacts, then updates
# latest.json with signatures and URLs for both platforms.
#
# Expects the renamed updater artifacts produced by
# keen-frontend/scripts/rename-updater-artifacts.sh:
#   Keen_${VERSION}_aarch64.app.tar.gz  (+ .sig)
#   Keen_${VERSION}_x64.app.tar.gz       (+ .sig)
# plus DMGs (already version + arch named by Tauri):
#   Keen_${VERSION}_aarch64.dmg
#   Keen_${VERSION}_x64.dmg
#
# Usage:
#   publish-release.sh <version> [release-notes] \
#     [--arm64-bundle <arm64-bundle-dir>] \
#     [--x64-bundle   <x64-bundle-dir>]
#
# Defaults (matching dual-architecture-builds.md):
#   arm64 bundle dir: keen-frontend/src-tauri/target/release/bundle
#   x64   bundle dir: keen-frontend/src-tauri/target/x86_64-apple-darwin/release/bundle
# ============================================================================

set -euo pipefail

# ── Parse positional args ──
if [[ $# -lt 1 ]]; then
  echo "Usage: publish-release.sh <version> [release-notes] [--arm64-bundle <dir>] [--x64-bundle <dir>]" >&2
  exit 1
fi

VERSION="$1"
shift

NOTES="Release v${VERSION}"
if [[ $# -gt 0 && "$1" != --* ]]; then
  NOTES="$1"
  shift
fi

# ── Defaults for bundle roots ──
FRONTEND_DIR="$HOME/Developer/keen/keen-frontend"
ARM64_BUNDLE="$FRONTEND_DIR/src-tauri/target/release/bundle"
X64_BUNDLE="$FRONTEND_DIR/src-tauri/target/x86_64-apple-darwin/release/bundle"

# ── Parse --arm64-bundle / --x64-bundle flags ──
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arm64-bundle)
      ARM64_BUNDLE="${2:?--arm64-bundle requires a path}"
      shift 2
      ;;
    --x64-bundle)
      X64_BUNDLE="${2:?--x64-bundle requires a path}"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ── Artifact paths ──
ARM64_TAR="${ARM64_BUNDLE}/macos/Keen_${VERSION}_aarch64.app.tar.gz"
ARM64_SIG="${ARM64_BUNDLE}/macos/Keen_${VERSION}_aarch64.app.tar.gz.sig"
ARM64_DMG="${ARM64_BUNDLE}/dmg/Keen_${VERSION}_aarch64.dmg"

X64_TAR="${X64_BUNDLE}/macos/Keen_${VERSION}_x64.app.tar.gz"
X64_SIG="${X64_BUNDLE}/macos/Keen_${VERSION}_x64.app.tar.gz.sig"
X64_DMG="${X64_BUNDLE}/dmg/Keen_${VERSION}_x64.dmg"

# ── Validate all 6 artifacts exist ──
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

# ── Read signatures ──
ARM64_SIGNATURE=$(cat "$ARM64_SIG")
X64_SIGNATURE=$(cat "$X64_SIG")

PUB_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
RELEASE_BASE="https://github.com/saputello2/keen-releases/releases/download/v${VERSION}"
ARM64_URL="${RELEASE_BASE}/Keen_${VERSION}_aarch64.app.tar.gz"
X64_URL="${RELEASE_BASE}/Keen_${VERSION}_x64.app.tar.gz"

# ── Create GitHub Release with all 6 artifacts ──
echo "Creating GitHub Release v${VERSION} with arm64 + x86_64 artifacts..."
gh release create "v${VERSION}" \
  "$ARM64_TAR" \
  "$ARM64_SIG" \
  "$ARM64_DMG" \
  "$X64_TAR" \
  "$X64_SIG" \
  "$X64_DMG" \
  --repo saputello2/keen-releases \
  --title "v${VERSION}" \
  --notes "$NOTES"

# ── Update latest.json ──
echo "Updating latest.json..."
cat > "${REPO_DIR}/latest.json" <<EOF
{
  "version": "${VERSION}",
  "notes": "${NOTES}",
  "pub_date": "${PUB_DATE}",
  "platforms": {
    "darwin-aarch64": {
      "signature": "${ARM64_SIGNATURE}",
      "url": "${ARM64_URL}"
    },
    "darwin-x86_64": {
      "signature": "${X64_SIGNATURE}",
      "url": "${X64_URL}"
    }
  }
}
EOF

cd "$REPO_DIR"
git add latest.json
git commit -m "release: v${VERSION}"
git push origin main

echo ""
echo "Done! Published v${VERSION}"
echo "  GitHub Release: https://github.com/saputello2/keen-releases/releases/tag/v${VERSION}"
echo "  Manifest:       https://raw.githubusercontent.com/saputello2/keen-releases/main/latest.json"
