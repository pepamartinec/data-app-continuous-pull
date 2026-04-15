#!/bin/bash
set -euo pipefail

# shellcheck disable=SC1091
[ -f /tmp/continuous-pull/config.env ] && . /tmp/continuous-pull/config.env

if [ -z "${PULL_PERIOD:-}" ]; then
    echo "Automatic pull disabled (pullPeriod not configured)"
    # Stay alive so supervisord doesn't keep respawning us
    exec sleep infinity
fi

echo "Starting continuous pull loop (interval: ${PULL_PERIOD}s)..."

while true; do
    sleep "$PULL_PERIOD"
    bash /tmp/continuous-pull/scripts/pull_once.sh || true
done
