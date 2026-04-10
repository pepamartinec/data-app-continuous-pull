#!/bin/bash
set -euo pipefail

WATCHED_DIR=/app/watched

# Parse the watched app's supervisord config for the command
CMD=$(python3 /app/scripts/parse_command.py "$WATCHED_DIR")

echo "Starting watched app: $CMD"
cd "$WATCHED_DIR"
# shellcheck disable=SC2086
exec $CMD
