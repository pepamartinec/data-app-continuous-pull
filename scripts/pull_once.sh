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

# shellcheck disable=SC1091
[ -f /tmp/continuous-pull/config.env ] && . /tmp/continuous-pull/config.env

cd /app
BRANCH=$(git rev-parse --abbrev-ref HEAD)

if ! git fetch --quiet origin "$BRANCH" 2>&1; then
    echo "Warning: git fetch failed"
    exit 1
fi

OLD_HEAD=$(git rev-parse HEAD)
NEW_HEAD=$(git rev-parse "origin/$BRANCH")

CHANGED=0
NGINX_CHANGED=0
if [ "$OLD_HEAD" != "$NEW_HEAD" ]; then
    CHANGED=1
    echo "=== Changes detected: ${OLD_HEAD:0:8} -> ${NEW_HEAD:0:8} ==="
    echo "Changed files:"
    git diff --name-only "$OLD_HEAD" "$NEW_HEAD"

    # Did any nginx config change? (decide before we reset so we can compare paths)
    if git diff --name-only "$OLD_HEAD" "$NEW_HEAD" \
        | grep -qE '^keboola-config/nginx/'; then
        NGINX_CHANGED=1
    fi

    # Fast-forward to remote, discarding any local changes
    git reset --hard --quiet "origin/$BRANCH"
    git clean -fdq
fi

# First pull of the container's lifetime runs watched setup automatically
if [ ! -f "$FIRST_PULL_FLAG" ]; then
    if [ -f /app/keboola-config/setup.sh ]; then
        echo "First pull - running watched app setup..."
        bash /app/keboola-config/setup.sh || echo "Warning: watched app setup failed"
    fi
    touch "$FIRST_PULL_FLAG"
    CHANGED=1
# On subsequent pulls, re-run setup if autoReSetup is enabled and code changed
elif [ "$CHANGED" = "1" ] && [ -n "${AUTO_RE_SETUP:-}" ]; then
    if [ -f /app/keboola-config/setup.sh ]; then
        echo "Auto re-setup: running watched app setup..."
        bash /app/keboola-config/setup.sh || echo "Warning: watched app setup failed"
    fi
fi

if [ "$CHANGED" = "1" ]; then
    # reread picks up [program:*] changes (added, removed, modified) from the
    # supervisord services dir; update applies them -- adding new programs,
    # stopping removed ones, and restarting changed ones. Previously this was a
    # hard-coded `restart app`, which silently ignored every user program after
    # the first and broke multi-process apps.
    echo "Applying supervisord config changes..."
    supervisorctl -s unix:///tmp/supervisor.sock reread \
        || echo "Warning: supervisorctl reread failed"
    supervisorctl -s unix:///tmp/supervisor.sock update \
        || echo "Warning: supervisorctl update failed"

    # `update` only restarts programs whose supervisord config changed. For
    # pure source-code pushes (e.g. edit app.py, commit, push) supervisord sees
    # no config change and wouldn't restart anything, so we'd serve stale code
    # until the next config edit. Explicitly restart every watched program --
    # i.e. everything except our own pull-loop and pull-api -- to mirror the
    # old single-program `restart app` behavior.
    WATCHED=$(supervisorctl -s unix:///tmp/supervisor.sock status \
        | awk '{print $1}' \
        | grep -vxE '(pull-loop|pull-api)' || true)
    if [ -n "$WATCHED" ]; then
        # shellcheck disable=SC2086
        supervisorctl -s unix:///tmp/supervisor.sock restart $WATCHED \
            || echo "Warning: supervisorctl restart failed"
    fi

    # If the user's nginx config (conf.d/, sites/) changed, reload nginx so
    # new location blocks take effect without a container restart. Best-effort:
    # if nginx is not managed by the wrapper we just log and carry on.
    if [ "$NGINX_CHANGED" = "1" ]; then
        echo "Nginx config changed - validating and reloading..."
        if nginx -t 2>&1; then
            nginx -s reload 2>&1 \
                || echo "Warning: nginx reload failed (container restart may be needed)"
        else
            echo "Warning: nginx -t rejected new config, NOT reloading -- previous config stays in effect"
        fi
    fi

    echo "=== Update complete ==="
fi
