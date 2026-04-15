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

FIRST_PULL_FLAG=/tmp/continuous-pull/.first-pull-done

cd /app
BRANCH=$(git rev-parse --abbrev-ref HEAD)

if ! git fetch --quiet origin "$BRANCH" 2>&1; then
    echo "Warning: git fetch failed"
    exit 1
fi

OLD_HEAD=$(git rev-parse HEAD)
NEW_HEAD=$(git rev-parse "origin/$BRANCH")

CHANGED=0
if [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
    CHANGED=1
    echo "=== Changes detected: ${OLD_HEAD:0:8} -> ${NEW_HEAD:0:8} ==="
    echo "Changed files:"
    git diff --name-only "$OLD_HEAD" "$NEW_HEAD"

    # Fast-forward to remote, discarding any local changes
    git reset --hard --quiet "origin/$BRANCH"
    git clean -fdq

    # Update saved watched app's supervisord config
    cp /app/keboola-config/supervisord/services/*.conf /tmp/continuous-pull/watched-services/
else
    echo "Already up to date at ${OLD_HEAD:0:8}"
fi

# First pull of the container's lifetime runs watched setup automatically
if [ ! -f "$FIRST_PULL_FLAG" ]; then
    if [ -f /app/keboola-config/setup.sh ]; then
        echo "First pull - running watched app setup..."
        bash /app/keboola-config/setup.sh || echo "Warning: watched app setup failed"
    fi
    touch "$FIRST_PULL_FLAG"
    CHANGED=1
fi

if [ "$CHANGED" = "1" ]; then
    echo "Restarting app..."
    supervisorctl -s unix:///tmp/supervisor.sock restart app \
        || echo "Warning: supervisorctl restart failed"
    echo "=== Update complete ==="
fi
