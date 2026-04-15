#!/bin/bash
set -euo pipefail

# shellcheck disable=SC1091
[ -f /tmp/continuous-pull/config.env ] && . /tmp/continuous-pull/config.env

# Always do one pull immediately so the first-pull setup runs at boot,
# even when automatic pulling is disabled.
echo "Running initial pull..."
bash /tmp/continuous-pull/scripts/pull_once.sh || true

if [ -z "${PULL_PERIOD:-}" ]; then
    echo "Automatic pull disabled (pullPeriod not configured)"
    exec sleep infinity
fi

echo "Starting continuous pull loop (interval: ${PULL_PERIOD}s)..."

while true; do
    sleep "$PULL_PERIOD"
    bash /tmp/continuous-pull/scripts/pull_once.sh || true
done
