#!/bin/bash
# One iteration of the pull-and-maybe-restart logic.
# Exit 0 if up-to-date or successfully updated; non-zero on failure.
set -euo pipefail

# Serialize so the loop and the API can't clobber each other
mkdir -p /tmp/continuous-pull
exec 200>/tmp/continuous-pull/pull.lock
if ! flock -n 200; then
    echo "Another pull is already in progress, skipping"
    exit 0
fi

cd /app
BRANCH=$(git rev-parse --abbrev-ref HEAD)

if ! git fetch --quiet origin "$BRANCH" 2>&1; then
    echo "Warning: git fetch failed"
    exit 1
fi

OLD_HEAD=$(git rev-parse HEAD)
NEW_HEAD=$(git rev-parse "origin/$BRANCH")

if [ "$OLD_HEAD" = "$NEW_HEAD" ]; then
    echo "Already up to date at ${OLD_HEAD:0:8}"
    exit 0
fi

echo "=== Changes detected: ${OLD_HEAD:0:8} -> ${NEW_HEAD:0:8} ==="
echo "Changed files:"
git diff --name-only "$OLD_HEAD" "$NEW_HEAD"

# Fast-forward to remote, discarding any local changes
git reset --hard --quiet "origin/$BRANCH"
git clean -fdq

# Update saved watched app's supervisord config
cp /app/keboola-config/supervisord/services/*.conf /tmp/continuous-pull/watched-services/

# Restart the app process
echo "Restarting app..."
supervisorctl restart app || echo "Warning: supervisorctl restart failed"

echo "=== Update complete ==="
