#!/usr/bin/env bash
# ============================================================================
# push-fly-registry.sh
# ============================================================================
# Re-tags a keen-backend image from GHCR and pushes it to Fly's private
# registry so the provisioning service can reference it when creating
# per-user Machines.
#
# Usage:
#   ./push-fly-registry.sh <version>
#
# Example:
#   ./push-fly-registry.sh 0.8.0
#
# Prerequisites:
#   - Docker daemon running
#   - Authenticated to GHCR: echo $GITHUB_TOKEN | docker login ghcr.io -u <user> --password-stdin
#   - Authenticated to Fly registry: fly auth docker
#   - The GHCR image ghcr.io/saputello2/keen-backend:<version> must exist
#   - The Fly app "keen-backend-images" must exist (one-time: fly apps create keen-backend-images)
#
# The provisioning service references images as:
#   registry.fly.io/keen-backend-images:<tag>
# ============================================================================

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: push-fly-registry.sh <version>" >&2
  exit 1
fi

VERSION="$1"
GHCR_IMAGE="ghcr.io/saputello2/keen-backend:${VERSION}"
FLY_IMAGE="registry.fly.io/keen-backend-images:${VERSION}"
FLY_LATEST="registry.fly.io/keen-backend-images:latest"

echo "=== Push keen-backend ${VERSION} to Fly registry ==="
echo ""
echo "  Source: ${GHCR_IMAGE}"
echo "  Target: ${FLY_IMAGE}"
echo "         ${FLY_LATEST}"
echo ""

# 1. Pull from GHCR
#
# `--platform linux/amd64` is required: the GHCR image is built by
# publish-image.yml for linux/amd64 only (Fly Machines run x86_64), so
# the manifest list contains no arm64 entry. Without the flag, `docker
# pull` on an Apple Silicon host fails with
#   "no matching manifest for linux/arm64/v8 in the manifest list entries".
echo "Step 1/3: Pulling from GHCR (linux/amd64)..."
docker pull --platform linux/amd64 "${GHCR_IMAGE}"

# 2. Re-tag for Fly registry
echo "Step 2/3: Tagging for Fly registry..."
docker tag "${GHCR_IMAGE}" "${FLY_IMAGE}"
docker tag "${GHCR_IMAGE}" "${FLY_LATEST}"

# 3. Push to Fly registry
echo "Step 3/3: Pushing to Fly registry..."
docker push "${FLY_IMAGE}"
docker push "${FLY_LATEST}"

echo ""
echo "=== Done ==="
echo "  ${FLY_IMAGE} is now available to Fly Machines."
echo "  ${FLY_LATEST} updated."
