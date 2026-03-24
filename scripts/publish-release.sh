#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: publish-release.sh <version> [release-notes]}"
NOTES="${2:-Release v${VERSION}}"
BUNDLE_DIR="$HOME/Developer/keen/keen-frontend/src-tauri/target/release/bundle"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

TAR_GZ="${BUNDLE_DIR}/macos/Keen.app.tar.gz"
SIG_FILE="${BUNDLE_DIR}/macos/Keen.app.tar.gz.sig"
DMG_FILE="${BUNDLE_DIR}/dmg/Keen_${VERSION}_aarch64.dmg"

for f in "$TAR_GZ" "$SIG_FILE" "$DMG_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Missing artifact: $f"
    echo "Run 'npm run tauri build' in keen-frontend first."
    exit 1
  fi
done

SIGNATURE=$(cat "$SIG_FILE")
PUB_DATE=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
DOWNLOAD_URL="https://github.com/saputello2/keen-releases/releases/download/v${VERSION}/Keen.app.tar.gz"

echo "Creating GitHub Release v${VERSION}..."
gh release create "v${VERSION}" \
  "$TAR_GZ" \
  "$SIG_FILE" \
  "$DMG_FILE" \
  --repo saputello2/keen-releases \
  --title "v${VERSION}" \
  --notes "$NOTES"

echo "Updating latest.json..."
cat > "${REPO_DIR}/latest.json" <<EOF
{
  "version": "${VERSION}",
  "notes": "${NOTES}",
  "pub_date": "${PUB_DATE}",
  "platforms": {
    "darwin-aarch64": {
      "signature": "${SIGNATURE}",
      "url": "${DOWNLOAD_URL}"
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
