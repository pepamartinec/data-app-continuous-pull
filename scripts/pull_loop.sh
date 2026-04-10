#!/bin/bash
set -euo pipefail

echo "Starting continuous pull loop..."

while true; do
    sleep 1

    cd /app

    # Capture current HEAD
    OLD_HEAD=$(git rev-parse HEAD)

    # Fetch remote changes, continue on failure
    if ! git fetch origin 2>&1; then
        echo "Warning: git fetch failed, will retry..."
        continue
    fi

    # Reset to remote, discarding any local changes
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    git reset --hard "origin/$BRANCH"
    git clean -fd

    NEW_HEAD=$(git rev-parse HEAD)

    if [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
        echo "=== Changes detected: ${OLD_HEAD:0:8} -> ${NEW_HEAD:0:8} ==="
        echo "Changed files:"
        git diff --name-only "$OLD_HEAD" "$NEW_HEAD"

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
    fi
done
