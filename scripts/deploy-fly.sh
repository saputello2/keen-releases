#!/usr/bin/env bash
# ============================================================================
# deploy-fly.sh
# ============================================================================
# Deploys a tagged keen-backend Docker image to a Fly.io app with a pre-deploy
# Postgres backup and post-deploy version verification.
#
# Usage:
#   ./deploy-fly.sh <version> <app-name>
#
# Example:
#   ./deploy-fly.sh 0.8.0 keen-dev-trial
#
# Prerequisites:
#   - flyctl authenticated (`fly auth login`)
#   - GHCR image ghcr.io/saputello2/keen-backend:<version> already pushed
#   - /data/backups/ directory exists on the Fly volume (created by
#     fly-entrypoint.sh on first boot)
# ============================================================================

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: deploy-fly.sh <version> <app-name>" >&2
  exit 1
fi

VERSION="$1"
APP="$2"
IMAGE="ghcr.io/saputello2/keen-backend:${VERSION}"
BACKUP_NAME="pre-deploy-$(date -u +%Y%m%dT%H%M%SZ)-v${VERSION}.dump"

echo "=== Deploy keen-backend ${VERSION} to ${APP} ==="
echo ""

# ── 1. Pre-deploy Postgres backup ──
# Runs pg_dump as the postgres OS user over the local socket (peer auth)
# to avoid scram-sha-256 password prompts over TCP.
# Retains last 5 backups; older ones are pruned.
echo "Step 1/3: Creating pre-deploy backup..."
flyctl ssh console --app "$APP" -C "bash -c '
  mkdir -p /data/backups &&
  su postgres -c \"pg_dump -Fc knowledge_explorer\" > /data/backups/${BACKUP_NAME} &&
  echo \"Backup created: /data/backups/${BACKUP_NAME}\" &&
  echo \"Pruning old backups (keeping last 5)...\" &&
  ls -1t /data/backups/pre-deploy-*.dump | tail -n +6 | xargs -r rm -f &&
  echo \"Remaining backups:\" &&
  ls -1t /data/backups/pre-deploy-*.dump
'"
echo ""

# ── 2. Rolling deploy with the new image ──
echo "Step 2/3: Deploying ${IMAGE}..."
flyctl deploy --app "$APP" \
  --image "$IMAGE" \
  --strategy rolling \
  --wait-timeout 300
echo ""

# ── 3. Post-deploy version verification ──
echo "Step 3/3: Verifying /version reports ${VERSION}..."
URL="https://${APP}.fly.dev/version"
for i in {1..10}; do
  REPORTED=$(curl -sf "$URL" | jq -r .version 2>/dev/null || echo "")
  if [[ "$REPORTED" == "$VERSION" ]]; then
    echo ""
    echo "=== Deploy successful ==="
    echo "  App:     ${APP}"
    echo "  Version: ${VERSION}"
    echo "  Backup:  /data/backups/${BACKUP_NAME}"
    echo ""
    echo "Next step: verify the app is working, then publish the client manifest:"
    echo "  ./publish-release.sh --publish-manifest ${VERSION}"
    exit 0
  fi
  echo "  Attempt ${i}/10: got '${REPORTED}', expected '${VERSION}'. Retrying in 3s..."
  sleep 3
done

echo "" >&2
echo "ERROR: ${APP} did not report version ${VERSION} within 30s" >&2
echo "" >&2
echo "Reported version: ${REPORTED:-<empty>}" >&2
echo "Expected version: ${VERSION}" >&2
echo "" >&2
echo "To roll back:" >&2
echo "  1. Image: flyctl releases list --app ${APP}" >&2
echo "           flyctl releases rollback <prev-release-id> --app ${APP}" >&2
echo "" >&2
echo "  2. If migrations ran, restore the database:" >&2
echo "     flyctl ssh console --app ${APP} -C \\" >&2
echo "       \"su postgres -c 'pg_restore -c -d knowledge_explorer /data/backups/${BACKUP_NAME}'\"" >&2
exit 1
