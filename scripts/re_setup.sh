#!/bin/bash
# Re-run the watched app's setup.sh and restart the app.
set -euo pipefail

# Serialize against pulls so we don't clobber files mid-reset
mkdir -p /tmp/continuous-pull
exec 200>/tmp/continuous-pull/pull.lock
if ! flock -n 200; then
    echo "A pull/setup is already in progress, aborting"
    exit 1
fi

if [ ! -f /app/keboola-config/setup.sh ]; then
    echo "No /app/keboola-config/setup.sh found, nothing to do"
    exit 0
fi

echo "Running watched app setup..."
bash /app/keboola-config/setup.sh

# Refresh saved watched app's supervisord config (in case setup changed it)
cp /app/keboola-config/supervisord/services/*.conf /tmp/continuous-pull/watched-services/

echo "Restarting app..."
supervisorctl -s unix:///tmp/supervisor.sock restart app \
    || echo "Warning: supervisorctl restart failed"

echo "=== Re-setup complete ==="
