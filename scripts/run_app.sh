#!/bin/bash
set -euo pipefail

# Parse the watched app's supervisord config for the command
CMD=$(python3 /tmp/continuous-pull/scripts/parse_command.py /tmp/continuous-pull/watched-services)

echo "Starting watched app: $CMD"
cd /app
# shellcheck disable=SC2086
exec $CMD
