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

# Apply any supervisord config changes the setup may have introduced, then
# restart all watched programs. `reread && update` handles adds/removes;
# the explicit stop/start ensures long-running processes pick up new binaries
# or rebuilt artifacts even when their supervisord entry is unchanged.
echo "Applying supervisord config changes..."
supervisorctl -s unix:///tmp/supervisor.sock reread \
    || echo "Warning: supervisorctl reread failed"
supervisorctl -s unix:///tmp/supervisor.sock update \
    || echo "Warning: supervisorctl update failed"

# Restart every watched program (everything except our pull-loop/pull-api).
# `update` only touches programs whose config changed; re_setup is invoked
# precisely because build output / dependencies changed, so we want a
# forced restart of the app processes.
WATCHED=$(supervisorctl -s unix:///tmp/supervisor.sock status \
    | awk '{print $1}' \
    | grep -vxE '(pull-loop|pull-api)' || true)
if [ -n "$WATCHED" ]; then
    # shellcheck disable=SC2086
    supervisorctl -s unix:///tmp/supervisor.sock restart $WATCHED \
        || echo "Warning: supervisorctl restart failed"
fi

# Best-effort nginx reload in case the watched setup.sh produced new nginx files
if nginx -t 2>&1; then
    nginx -s reload 2>&1 || echo "Warning: nginx reload failed"
else
    echo "Warning: nginx -t rejected config, skipping reload"
fi

echo "=== Re-setup complete ==="
