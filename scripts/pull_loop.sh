#!/bin/bash
set -euo pipefail

POLL_INTERVAL="${PULL_LOOP_INTERVAL:-10}"

echo "Starting continuous pull loop (interval: ${POLL_INTERVAL}s)..."

cd /app
BRANCH=$(git rev-parse --abbrev-ref HEAD)

while true; do
    sleep "$POLL_INTERVAL"

    # Fetch remote changes quietly, continue on failure
    if ! git fetch --quiet origin "$BRANCH" 2>&1; then
        echo "Warning: git fetch failed, will retry..."
        continue
    fi

    OLD_HEAD=$(git rev-parse HEAD)
    NEW_HEAD=$(git rev-parse "origin/$BRANCH")

    # No change on remote -> stay quiet, do nothing
    if [ "$OLD_HEAD" = "$NEW_HEAD" ]; then
        continue
    fi

    echo "=== Changes detected: ${OLD_HEAD:0:8} -> ${NEW_HEAD:0:8} ==="
    echo "Changed files:"
    git diff --name-only "$OLD_HEAD" "$NEW_HEAD"

    # Fast-forward to remote, discarding any local changes
    git reset --hard --quiet "origin/$BRANCH"
    git clean -fdq

    # Update saved watched app's supervisord config
    cp /app/keboola-config/supervisord/services/*.conf /tmp/continuous-pull/watched-services/

    # Re-run the watched app's setup
    echo "Running watched app setup..."
    if [ -f /app/keboola-config/setup.sh ]; then
        bash /app/keboola-config/setup.sh || echo "Warning: watched app setup failed"
    fi

    # Restart the app process
    echo "Restarting app..."
    supervisorctl restart app || echo "Warning: supervisorctl restart failed"

    echo "=== Update complete ==="
done
