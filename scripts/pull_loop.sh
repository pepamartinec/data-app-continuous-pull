#!/bin/bash
set -euo pipefail

POLL_INTERVAL="${PULL_LOOP_INTERVAL:-10}"

echo "Starting continuous pull loop (interval: ${POLL_INTERVAL}s)..."

while true; do
    sleep "$POLL_INTERVAL"
    bash /tmp/continuous-pull/scripts/pull_once.sh || true
done
