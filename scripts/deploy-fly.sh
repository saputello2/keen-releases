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
# Runs pg_dump over TCP with password auth using the POSTGRES_PASSWORD env
# var that fly-entrypoint.sh already has injected into the container
# (from the Fly secret of the same name).
#
# Why password-auth and not peer auth:
#   fly-entrypoint.sh hardens pg_hba.conf to scram-sha-256 for ALL
#   connections — including the local unix socket. Peer auth is not
#   available on this image. The canonical way to authenticate is with
#   the Fly secret that the entrypoint used to set the postgres role's
#   password at initdb time.
#
# PGPASSWORD is read by libpq automatically. POSTGRES_HOST/PORT/USER/DB
# are set by Dockerfile.fly, so pg_dump picks them up with no flags.
#
# The `>` redirect is at the bash level (root-owned shell), so the dump
# file is written into /data/backups by root — avoiding needing a user
# switch.
#
# Retains last 5 backups; older ones are pruned.
echo "Step 1/3: Creating pre-deploy backup..."
flyctl ssh console --app "$APP" -C "bash -c '
  set -e
  if [ -z \"\${POSTGRES_PASSWORD:-}\" ]; then
    echo \"ERROR: POSTGRES_PASSWORD env var is not set inside the container.\" >&2
    echo \"  Ensure it is configured as a Fly secret (fly secrets list --app $APP).\" >&2
    exit 1
  fi
  mkdir -p /data/backups
  PGPASSWORD=\"\$POSTGRES_PASSWORD\" pg_dump -U postgres -Fc knowledge_explorer > /data/backups/${BACKUP_NAME}
  echo \"Backup created: /data/backups/${BACKUP_NAME}\"
  echo \"Pruning old backups (keeping last 5)...\"
  ls -1t /data/backups/pre-deploy-*.dump | tail -n +6 | xargs -r rm -f
  echo \"Remaining backups:\"
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
echo "       'bash -c \"PGPASSWORD=\\\$POSTGRES_PASSWORD pg_restore -U postgres -c -d knowledge_explorer /data/backups/${BACKUP_NAME}\"'" >&2
exit 1
